#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const flutterDir = path.join(root, 'packages/flutter/lib');
const iosDir = path.join(root, 'packages/ios/Sources/Napaxi');

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(fullPath));
    else out.push(fullPath);
  }
  return out;
}

function rel(file) {
  return path.relative(root, file);
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function hasWord(haystack, word) {
  return new RegExp(`\\b${escapeRegex(word)}\\b`).test(haystack);
}

function addByFile(map, item, label) {
  if (!map[item.file]) map[item.file] = [];
  map[item.file].push(`${label}:${item.owner ? `${item.owner}.` : ''}${item.name}:${item.line}`);
}

const dartFiles = walk(flutterDir)
  .filter((file) => file.endsWith('.dart') && !file.includes('/generated/'));
const generatedBridgeFiles = walk(path.join(flutterDir, 'generated/bridge'))
  .filter((file) => file.endsWith('.dart'));
const swiftText = walk(iosDir)
  .filter((file) => file.endsWith('.swift'))
  .map((file) => fs.readFileSync(file, 'utf8'))
  .join('\n');
const swiftPublicFunctions = new Set(
  [...swiftText.matchAll(/\bpublic\s+(?:static\s+)?func\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/g)]
    .map((match) => match[1])
);
const swiftTopLevelPublicFunctions = new Set();

const publicTypes = [];
const publicMethods = [];
const publicMembers = [];
const topLevel = [];
const enumValues = [];
const namedConstructors = [];
const generatedBridgeFunctions = [];

for (const file of dartFiles) {
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split(/\n/);
  let currentType = null;
  let depth = 0;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const trimmed = line.trim();
    const lineNo = index + 1;
    const topDepth = depth;

    // `@visibleForTesting` members are test-only surface, not part of the
    // shipped cross-adapter API, so native adapters need no counterpart. Detect
    // the annotation on the immediately preceding non-empty line and suppress
    // recording the symbol it decorates (without disturbing brace tracking).
    let annotationCursor = index - 1;
    while (annotationCursor >= 0 && lines[annotationCursor].trim() === '') {
      annotationCursor -= 1;
    }
    const visibleForTesting =
      annotationCursor >= 0 &&
      lines[annotationCursor].trim().startsWith('@visibleForTesting');

    const typeMatch = line.match(/^(?:abstract\s+)?(?:base\s+|final\s+|sealed\s+)?(?:class|enum|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (typeMatch && !typeMatch[1].startsWith('_')) {
      currentType = typeMatch[1];
      if (!visibleForTesting) {
        publicTypes.push({ name: currentType, file: rel(file), line: lineNo });
      }
    } else if (topDepth === 0) {
      currentType = null;
    }

    if (topDepth === 0) {
      let match = trimmed.match(/^(?:const|final|var)\s+(?:[A-Za-z_][A-Za-z0-9_<>?, ]+\s+)?([a-zA-Z_][A-Za-z0-9_]*)\s*=/);
      if (match && !match[1].startsWith('_')) {
        topLevel.push({ name: match[1], file: rel(file), line: lineNo });
      }
      match = trimmed.match(/^(?:Future<[^>]+>|Future<void>|void|bool|int|double|String|Map<[^>]+>|List<[^>]+>|[A-Za-z_][A-Za-z0-9_<>?, ]+)\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/);
      if (match && !match[1].startsWith('_') && !['if', 'for', 'while', 'switch'].includes(match[1])) {
        topLevel.push({ name: match[1], file: rel(file), line: lineNo });
      }
    }

    if (currentType && !visibleForTesting) {
      const methodMatch = line.match(/^\s{2}(?:(?:static|factory)\s+)?(?:Future<[^>]+>|Future<void>|Future<bool>|Future<String>|Stream<[^>]+>|[A-Za-z_][A-Za-z0-9_<>?, ]*|void|bool|int|double|String|Map<[^>]+>|List<[^>]+>)\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/);
      if (methodMatch && !methodMatch[1].startsWith('_') && methodMatch[1] !== currentType) {
        publicMethods.push({ owner: currentType, name: methodMatch[1], file: rel(file), line: lineNo });
      }

      const memberMatch = line.match(/^\s{2}(?:static\s+)?(?:const\s+|final\s+|late\s+final\s+)?(?:[A-Za-z_][A-Za-z0-9_<>?, ]*|bool|int|double|String|Object\?|Map<[^>]+>|List<[^>]+>|Set<[^>]+>)\s+(?:get\s+)?([a-zA-Z_][A-Za-z0-9_]*)\s*(?:=>|=|;|\{)/);
      if (memberMatch) {
        const name = memberMatch[1];
        if (!name.startsWith('_') && !['fromJson', 'fromMap', 'values'].includes(name) && name !== currentType) {
          publicMembers.push({ owner: currentType, name, file: rel(file), line: lineNo });
        }
      }
    }

    const enumMatch = line.match(/^enum\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{/);
    if (enumMatch) {
      const owner = enumMatch[1];
      let cursor = index + 1;
      while (cursor < lines.length && !lines[cursor].includes(';') && !lines[cursor].includes('}')) {
        for (const part of lines[cursor].split(',')) {
          const valueMatch = part.trim().match(/^([a-zA-Z_][A-Za-z0-9_]*)\s*(?:\(|$)/);
          if (valueMatch) {
            enumValues.push({ owner, name: valueMatch[1], file: rel(file), line: cursor + 1 });
          }
        }
        cursor += 1;
      }
    }

    const classMatch = line.match(/^(?:abstract\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (classMatch) {
      const owner = classMatch[1];
      const ctorRegex = new RegExp(`^\\s{2}(?:const\\s+|factory\\s+)?${owner}\\.([a-zA-Z_][A-Za-z0-9_]*)\\s*\\(`);
      let cursor = index + 1;
      let classDepth = 0;
      for (; cursor < lines.length; cursor += 1) {
        const ctorMatch = lines[cursor].match(ctorRegex);
        if (ctorMatch && !ctorMatch[1].startsWith('_')) {
          namedConstructors.push({ owner, name: ctorMatch[1], file: rel(file), line: cursor + 1 });
        }
        for (const char of lines[cursor]) {
          if (char === '{') classDepth += 1;
          else if (char === '}') classDepth -= 1;
        }
        if (classDepth < 0) break;
      }
    }

    for (const char of line) {
      if (char === '{') depth += 1;
      else if (char === '}') depth = Math.max(0, depth - 1);
    }
  }
}

for (const file of walk(iosDir).filter((item) => item.endsWith('.swift'))) {
  const lines = fs.readFileSync(file, 'utf8').split(/\n/);
  let depth = 0;
  for (const line of lines) {
    const topDepth = depth;
    const match = line.match(/^public\s+func\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/);
    if (topDepth === 0 && match) swiftTopLevelPublicFunctions.add(match[1]);
    for (const char of line) {
      if (char === '{') depth += 1;
      else if (char === '}') depth = Math.max(0, depth - 1);
    }
  }
}


for (const file of generatedBridgeFiles) {
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split(/\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const match = line.match(/^(?:Future<[^>]+>|Stream<[^>]+>|String|bool|int|void|PlatformInt64)\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/);
    if (match && !match[1].startsWith('_')) {
      generatedBridgeFunctions.push({ name: match[1], file: rel(file), line: index + 1 });
    }
  }
}

const methodFalsePositives = new Set(['Function', 'jsonEncode', 'base64Encode']);
const memberFalsePositives = new Set(['eventAttrs', 'operator', 'hashCode']);
// Flutter-internal engine infrastructure, NOT part of the cross-adapter API
// surface: `EngineCore` is the state machine extracted from NapaxiEngine (a
// `part of` the engine library). Native adapters keep that logic inside their
// own engine classes, so there is no Swift/Kotlin counterpart by design.
// Excluded from parity like the name false-positives above (its named
// constructors are excluded via `owner` below).
const typeFalsePositives = new Set(['EngineCore']);

function missing(items, ignoredNames = new Set()) {
  return items.filter((item) => !ignoredNames.has(item.name) && !hasWord(swiftText, item.name));
}

function missingPublicFunctions(items) {
  return items.filter((item) => !swiftPublicFunctions.has(item.name));
}

const missingByFile = {};
for (const item of missing(publicTypes, typeFalsePositives)) addByFile(missingByFile, item, 'type');
for (const item of missing(topLevel)) addByFile(missingByFile, item, 'top');
for (const item of missing(publicMethods, methodFalsePositives)) addByFile(missingByFile, item, 'method');
for (const item of missing(publicMembers, memberFalsePositives)) addByFile(missingByFile, item, 'member');
for (const item of missing(enumValues)) addByFile(missingByFile, item, 'enum');
for (const item of missing(namedConstructors).filter((item) => !typeFalsePositives.has(item.owner))) addByFile(missingByFile, item, 'ctor');
for (const item of missingPublicFunctions(generatedBridgeFunctions)) addByFile(missingByFile, item, 'bridge');

const ignored = {
  methodFalsePositives: publicMethods.filter((item) => methodFalsePositives.has(item.name)).length,
  memberFalsePositives: publicMembers.filter((item) => memberFalsePositives.has(item.name)).length,
};

const summary = {
  publicTypes: publicTypes.length,
  topLevel: topLevel.length,
  publicMethods: publicMethods.length,
  publicMembers: publicMembers.length,
  enumValues: enumValues.length,
  namedConstructors: namedConstructors.length,
  generatedBridgeFunctions: generatedBridgeFunctions.length,
  swiftPublicFunctions: swiftPublicFunctions.size,
  generatedBridgeTopLevelFunctions: generatedBridgeFunctions.filter((item) => swiftTopLevelPublicFunctions.has(item.name)).length,
  generatedBridgeTopLevelMissing: generatedBridgeFunctions.filter((item) => !swiftTopLevelPublicFunctions.has(item.name)).length,
  missingPublicSurface: Object.values(missingByFile).reduce((total, entries) => total + entries.length, 0),
  ignored,
};

console.log(`iOS/Flutter parity audit: ${JSON.stringify(summary)}`);

const MISSING_PUBLIC_SURFACE_BASELINE = 227;

if (summary.missingPublicSurface > MISSING_PUBLIC_SURFACE_BASELINE) {
  console.error('Missing Swift counterparts for Flutter public surface:');
  for (const [file, entries] of Object.entries(missingByFile)) {
    console.error(`  ${file}`);
    for (const entry of entries) console.error(`    - ${entry}`);
  }
  console.error(`missingPublicSurface=${summary.missingPublicSurface} exceeds baseline ${MISSING_PUBLIC_SURFACE_BASELINE}. Add Swift parity or update the baseline with review justification.`);
  process.exit(1);
}

if (summary.missingPublicSurface < MISSING_PUBLIC_SURFACE_BASELINE) {
  console.log(`missingPublicSurface=${summary.missingPublicSurface} is below baseline ${MISSING_PUBLIC_SURFACE_BASELINE}; raise MISSING_PUBLIC_SURFACE_BASELINE to lock in the improvement.`);
} else if (summary.missingPublicSurface > 0) {
  console.log(`missingPublicSurface=${summary.missingPublicSurface} matches the checked-in baseline.`);
}

console.log('iOS/Flutter parity audit passed.');
