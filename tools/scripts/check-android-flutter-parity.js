#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const flutterDir = path.join(root, 'packages/flutter/lib');
const androidDir = path.join(root, 'packages/android/src/main/kotlin/com/napaxi/android');
const providerModels = path.join(root, 'packages/agent_provider/android/src/main/kotlin/agent/provider/sdk/Models.kt');

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function rel(file) {
  return path.relative(root, file);
}

function existing(files) {
  return files.filter((file) => fs.existsSync(file));
}

function classBody(text, className) {
  const match = text.match(new RegExp(`(?:class|enum|abstract class)\\s+${className}\\b`));
  if (!match) return '';
  let depth = 0;
  let bodyStart = -1;
  for (let index = match.index; index < text.length; index += 1) {
    const char = text[index];
    if (char === '{') {
      if (depth === 0 && bodyStart < 0) bodyStart = index + 1;
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0 && bodyStart >= 0) return text.slice(bodyStart, index);
    }
  }
  return '';
}

function kotlinBody(text, className) {
  const match = text.match(new RegExp(`(?:class|data class|object|enum class|fun interface)\\s+${className}\\b`));
  if (!match) return '';
  let depth = 0;
  let bodyStart = -1;
  for (let index = match.index; index < text.length; index += 1) {
    const char = text[index];
    if (char === '{') {
      if (depth === 0 && bodyStart < 0) bodyStart = index + 1;
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0 && bodyStart >= 0) return text.slice(bodyStart, index);
    }
  }
  return '';
}

function dartMethods(file, className) {
  const body = classBody(read(file), className);
  const methods = [];
  for (const line of body.split(/\n/)) {
    if (!/^  \w/.test(line)) continue;
    const match = line.match(
      /^\s{2}(?:static\s+)?(?:Future(?:<[A-Za-z0-9_<>, ?]+>)?|Stream<[A-Za-z0-9_<>, ?]+>|List<[A-Za-z0-9_<>, ?]+>|Map<[A-Za-z0-9_<>, ?]+>|[A-Z][A-Za-z0-9_<>?, ]*|void|bool|int|double|String)\s+(\w+)\s*\(/,
    );
    if (match && !match[1].startsWith('_') && match[1] !== className) methods.push(match[1]);
  }
  return [...new Set(methods)].sort();
}

function kotlinMethods(fileText, className) {
  const body = kotlinBody(fileText, className);
  const methods = [];
  for (const match of body.matchAll(/^\s+(?:public\s+)?(?:suspend\s+)?fun\s+(\w+)\s*\(/gm)) {
    if (!match[1].startsWith('_')) methods.push(match[1]);
  }
  return [...new Set(methods)].sort();
}

function exportedFlutterFiles() {
  const entry = read(path.join(flutterDir, 'napaxi_flutter.dart'));
  return [...entry.matchAll(/export '([^']+)'/g)]
    .map((match) => path.join(flutterDir, match[1]))
    .filter((file) => fs.existsSync(file));
}

function flutterTypes(files) {
  const types = [];
  for (const file of files) {
    const text = read(file);
    for (const match of text.matchAll(/^(?:abstract\s+)?(?:base\s+|final\s+|sealed\s+)?(?:class|enum|typedef)\s+(\w+)\b/gm)) {
      if (!match[1].startsWith('_')) types.push({ name: match[1], file });
    }
  }
  return types;
}

function flutterModelHelpers(files) {
  const helpers = [];
  for (const file of files) {
    const text = read(file);
    for (const match of text.matchAll(/^class\s+(\w+)\b/gm)) {
      const name = match[1];
      const body = classBody(text, name);
      if (/factory\s+\w+\.fromMap\s*\(/.test(body)) {
        helpers.push({ name, helper: 'fromMap', file });
      }
      if (/factory\s+\w+\.fromJson\s*\(/.test(body)) {
        helpers.push({ name, helper: 'fromJson', file });
      }
    }
  }
  return helpers;
}

// Cross-platform enum parity is about the WIRE VALUE, not the identifier:
// Dart writes `toolObserved('tool_observed')` while Kotlin writes
// `ToolObserved("tool_observed")` — the shared contract is the string literal.
// Extract the wire-value string from each Dart enhanced-enum entry so we can
// confirm Android carries the same value, regardless of identifier casing.
function flutterEnumWireValues(files) {
  const values = [];
  for (const file of files) {
    const text = read(file);
    const lines = text.split(/\n/);
    let owner = null;
    let depth = 0;
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const enumMatch = line.match(/^enum\s+([A-Za-z_]\w*)\s*\{/);
      if (enumMatch) {
        owner = enumMatch[1];
        depth = 0;
      }
      if (owner) {
        for (const char of line) {
          if (char === '{') depth += 1;
          else if (char === '}') {
            depth -= 1;
            if (depth <= 0) owner = null;
          }
        }
      }
      if (!owner) continue;
      // Enhanced-enum entry carrying a string wire value, e.g.
      //   toolObserved('tool_observed'),
      const valueMatch = line.match(/^\s{2}[a-zA-Z_]\w*\(\s*['"]([^'"]+)['"]/);
      if (valueMatch) {
        values.push({ owner, value: valueMatch[1], file: rel(file), line: index + 1 });
      }
    }
  }
  return values;
}

function dartApiClasses() {
  const apiDir = path.join(flutterDir, 'api');
  const files = fs.readdirSync(apiDir)
    .filter((file) => file.endsWith('.dart'))
    .map((file) => path.join(apiDir, file));
  const classes = {};
  for (const file of files) {
    const text = read(file);
    for (const match of text.matchAll(/^class\s+(\w+)\b/gm)) {
      classes[match[1]] = { file, methods: dartMethods(file, match[1]) };
    }
  }
  return classes;
}

function stringSetFromDartSwitch(file, className, methodName) {
  const body = classBody(read(file), className);
  const methodStart = body.indexOf(`${methodName}(`);
  const source = methodStart >= 0 ? body.slice(methodStart) : body;
  return new Set([
    ...[...source.matchAll(/case '([^']+)'/g)].map((match) => match[1]),
    ...[...source.matchAll(/'([^']+)'\s*=>/g)].map((match) => match[1]),
  ]);
}

function stringSetFromKotlinSet(text, setName) {
  const match = text.match(new RegExp(`${setName}\\s*(?::[^=]+)?=\\s*setOf\\(([\\s\\S]*?)\\)`, 'm'));
  if (!match) return new Set();
  return new Set([...match[1].matchAll(/"([^"]+)"/g)].map((item) => item[1]));
}

function browserToolNamesFromFlutter(file) {
  return new Set([...read(file).matchAll(/'(browser_[^']+)'\s*=>/g)].map((match) => match[1]));
}

function reportMissing(label, missing) {
  if (missing.length === 0) return;
  console.error(label);
  for (const item of missing) console.error(`  - ${item}`);
}

const flutterFiles = exportedFlutterFiles();
const androidText = existing([
  'AgentProviders.kt',
  'Apis.kt',
  'Background.kt',
  'ConfigStore.kt',
  'NapaxiEngine.kt',
  'Models.kt',
  'PlatformContext.kt',
  'PlatformTools.kt',
  'ProviderProtocolAliases.kt',
  'Tooling.kt',
].map((file) => path.join(androidDir, file)))
  .concat(existing([providerModels]))
  .map(read)
  .join('\n');

const nativeAliases = {
  IosAgentProviderActionExecutor: 'AndroidAgentProviderActionExecutor',
  NapaxiBrowserBackend: 'NapaxiBrowserController',
  NapaxiBrowserSurface: 'AndroidBrowserToolHost',
  BrowserBackendCapabilities: 'BrowserToolProvider',
  NapaxiBrowserScreenshot: 'NapaxiBrowserController',
  NapaxiBrowserSnapshot: 'NapaxiBrowserController',
  BrowserViewportMode: 'NapaxiBrowserController',
  BrowserScreenshotMode: 'NapaxiBrowserController',
  BackgroundPermissionStatus: 'NapaxiBackgroundPermissions',
};

const missingTypes = [];
for (const type of flutterTypes(flutterFiles)) {
  const target = nativeAliases[type.name] || type.name;
  const hasType = new RegExp(`(?:class|data class|enum class|interface|fun interface|object|typealias)\\s+${target}\\b`).test(androidText);
  if (!hasType) missingTypes.push(`${type.name} (${rel(type.file)}) -> ${target}`);
}

const missingHelpers = [];
for (const item of flutterModelHelpers(flutterFiles)) {
  const target = nativeAliases[item.name] || item.name;
  if (!new RegExp(`(?:class|data class|typealias)\\s+${target}\\b`).test(androidText)) continue;
  if (!new RegExp(`${item.helper}\\s*\\([^)]*\\)\\s*:\\s*${target}\\b`).test(androidText)) {
    missingHelpers.push(`${item.name}.${item.helper} (${rel(item.file)})`);
  }
}

const engineFile = path.join(flutterDir, 'engine.dart');
const androidEngineFile = path.join(androidDir, 'NapaxiEngine.kt');
const flutterEngineMethods = dartMethods(engineFile, 'NapaxiEngine');
const androidEngineMethods = kotlinMethods(read(androidEngineFile), 'NapaxiEngine');
const engineNativeDifferences = new Set([
  'initialize',
  'shutdown',
  'attachBackgroundController',
  'detachBackgroundController',
  'setDefaultBrowserController',
  'clearDefaultBrowserController',
  'streamChat',
]);
const missingEngineMethods = flutterEngineMethods
  .filter((method) => !engineNativeDifferences.has(method) && !androidEngineMethods.includes(method));

const dartApis = dartApiClasses();
const androidApisText = read(path.join(androidDir, 'Apis.kt')) + '\n' + read(path.join(androidDir, 'AgentProviders.kt')) + '\n' + read(path.join(androidDir, 'Background.kt'));
const apiClassMap = {
  AgentApi: 'AgentApi',
  AgentAppApi: 'AgentAppApi',
  AgentProviderInstallApi: 'AgentProviderInstallApi',
  AgentProviderTriggerApi: 'AgentProviderTriggerApi',
  AutomationApi: 'AutomationApi',
  BackgroundApi: 'BackgroundApi',
  CapabilityApi: 'CapabilityApi',
  ChatApi: 'ChatApi',
  GroupApi: 'GroupApi',
  SessionApi: 'SessionApi',
  SessionRunApi: 'SessionRunApi',
  SkillApi: 'SkillApi',
  ToolApi: 'ToolApi',
  WorkspaceApi: 'WorkspaceApi',
};
const missingApiMethods = [];
for (const [dartClass, kotlinClass] of Object.entries(apiClassMap)) {
  const flutterMethods = dartApis[dartClass]?.methods || [];
  const androidMethods = kotlinMethods(androidApisText, kotlinClass);
  for (const method of flutterMethods) {
    if (!androidMethods.includes(method)) missingApiMethods.push(`${dartClass}.${method} -> ${kotlinClass}`);
  }
}

const platformFlutter = stringSetFromDartSwitch(
  path.join(flutterDir, 'platform_tools/capability_host.dart'),
  'FlutterCapabilityHost',
  'execute',
);
const platformAndroid = stringSetFromKotlinSet(read(path.join(androidDir, 'PlatformTools.kt')), 'TOOL_NAMES');
const missingPlatformTools = [...platformFlutter].filter((name) => !platformAndroid.has(name));

const browserFlutter = browserToolNamesFromFlutter(path.join(flutterDir, 'browser_controller.dart'));
const browserAndroid = stringSetFromKotlinSet(read(path.join(androidDir, 'Tooling.kt')), 'fallbackToolNames');
const missingBrowserTools = [...browserFlutter].filter((name) => !browserAndroid.has(name));

// Enum wire-value parity: every string value a Flutter enum serializes to must
// appear somewhere in the Android source. Catches a renamed/added/removed enum
// value that the name-only type check would miss. Compared by wire string, so
// Dart camelCase vs Kotlin PascalCase identifiers do not cause false positives.
const enumValueAllowList = new Set([
  // Add deliberate Flutter-only enum values here (with a reason) if a value is
  // intentionally not represented on Android.
]);
const missingEnumValues = flutterEnumWireValues(flutterFiles)
  .filter((item) => !enumValueAllowList.has(item.value))
  .filter((item) => !androidText.includes(`"${item.value}"`))
  .map((item) => `${item.owner}.${item.value} (${item.file}:${item.line})`);

const summary = {
  flutterExportedFiles: flutterFiles.length,
  flutterExportedTypes: flutterTypes(flutterFiles).length,
  flutterEngineMethods: flutterEngineMethods.length,
  androidEngineMethods: androidEngineMethods.length,
  flutterApiClasses: Object.keys(apiClassMap).length,
  platformTools: platformFlutter.size,
  browserTools: browserFlutter.size,
  missingTypes: missingTypes.length,
  missingHelpers: missingHelpers.length,
  missingEngineMethods: missingEngineMethods.length,
  missingApiMethods: missingApiMethods.length,
  missingPlatformTools: missingPlatformTools.length,
  missingBrowserTools: missingBrowserTools.length,
  missingEnumValues: missingEnumValues.length,
};

console.log(`Android/Flutter parity audit: ${JSON.stringify(summary)}`);

const baseline = {
  missingTypes: 53,
  missingHelpers: 5,
  missingEngineMethods: 0,
  missingApiMethods: 0,
  missingPlatformTools: 1,
  missingBrowserTools: 0,
  missingEnumValues: 0,
};

const missingBuckets = [
  ['missingTypes', 'Missing Android public type counterparts:', missingTypes],
  ['missingHelpers', 'Missing Android model helper counterparts:', missingHelpers],
  ['missingEngineMethods', 'Missing Android NapaxiEngine methods:', missingEngineMethods],
  ['missingApiMethods', 'Missing Android API facade methods:', missingApiMethods],
  ['missingPlatformTools', 'Missing Android platform tools:', missingPlatformTools],
  ['missingBrowserTools', 'Missing Android browser tools:', missingBrowserTools],
  ['missingEnumValues', 'Missing Android enum wire values:', missingEnumValues],
];

let failed = false;
for (const [key, label, items] of missingBuckets) {
  const limit = baseline[key];
  if (items.length > limit) {
    reportMissing(label, items);
    console.error(`${key}=${items.length} exceeds baseline ${limit}. Add Android parity or update the baseline with review justification.`);
    failed = true;
  } else if (items.length < limit) {
    console.log(`${key}=${items.length} is below baseline ${limit}; raise the checked-in baseline to ${items.length} to lock in the improvement.`);
  } else if (items.length > 0) {
    console.log(`${key}=${items.length} matches the checked-in baseline.`);
  }
}

if (failed) {
  process.exit(1);
}

console.log('Android/Flutter parity audit passed.');
