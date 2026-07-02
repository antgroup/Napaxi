#!/usr/bin/env node
// Executable SDK API contract checks. This intentionally uses JSON for the
// first contract vertical slice so it can run without package installation.

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const fail = (message) => {
  console.error(`[ERROR] ${message}`);
  process.exit(1);
};
const info = (message) => console.log(`[INFO] ${message}`);
const readText = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');
const readJson = (relativePath) => JSON.parse(readText(relativePath));
const exists = (relativePath) => fs.existsSync(path.join(root, relativePath));
const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

function requireIncludes(file, needle, label = needle) {
  const text = readText(file);
  if (!text.includes(needle)) {
    fail(`${file} must contain ${label}`);
  }
}

function requireRegex(file, regex, label = String(regex)) {
  const text = readText(file);
  if (!regex.test(text)) {
    fail(`${file} must match ${label}`);
  }
}

function requireArray(value, label) {
  if (!Array.isArray(value) || value.length === 0) {
    fail(`${label} must be a non-empty array`);
  }
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function ensureStringArray(value, label) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string' || item.length === 0)) {
    fail(`${label} must be an array of non-empty strings`);
  }
}

function validateType(value, type, label, models) {
  if (type.startsWith('array<') && type.endsWith('>')) {
    if (!Array.isArray(value)) {
      fail(`${label} must be ${type}`);
    }
    const itemType = type.slice('array<'.length, -1);
    value.forEach((item, index) => validateType(item, itemType, `${label}[${index}]`, models));
    return;
  }

  if (models[type]) {
    validateModelValue(type, value, models, label);
    return;
  }

  switch (type) {
    case 'string':
      if (typeof value !== 'string') fail(`${label} must be string`);
      return;
    case 'boolean':
      if (typeof value !== 'boolean') fail(`${label} must be boolean`);
      return;
    case 'number':
      if (typeof value !== 'number' || Number.isNaN(value)) fail(`${label} must be number`);
      return;
    case 'integer':
      if (!Number.isInteger(value)) fail(`${label} must be integer`);
      return;
    case 'date':
      if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail(`${label} must be date string YYYY-MM-DD`);
      return;
    case 'datetime':
      if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) fail(`${label} must be parseable datetime string`);
      return;
    default:
      fail(`${label} uses unknown contract field type ${type}`);
  }
}

function validateRequiredFields(modelName, value, model, models, label) {
  const required = model.required ?? [];
  ensureStringArray(required, `${modelName}.required`);

  for (const key of required) {
    if (!hasOwn(value, key)) {
      fail(`${label} missing required field ${key}`);
    }
    validateType(value[key], model.fields[key], `${label}.${key}`, models);
  }

  const requiredAny = model.requiredAny ?? [];
  if (!Array.isArray(requiredAny)) {
    fail(`${modelName}.requiredAny must be an array of alias groups`);
  }
  requiredAny.forEach((aliases, index) => {
    ensureStringArray(aliases, `${modelName}.requiredAny[${index}]`);
    const present = aliases.filter((key) => hasOwn(value, key));
    if (present.length === 0) {
      fail(`${label} must contain one of required aliases: ${aliases.join(', ')}`);
    }
    for (const key of aliases) {
      if (!model.fields[key]) fail(`${modelName}.fields missing required alias ${key}`);
    }
    for (const key of present) {
      validateType(value[key], model.fields[key], `${label}.${key}`, models);
    }
  });
}

function validateModelValue(modelName, value, models, label = modelName) {
  if (!isObject(value)) {
    fail(`${label} must be object for model ${modelName}`);
  }
  const model = models[modelName];
  if (!model) fail(`Unknown model ${modelName}`);
  if (model.unknownFields !== 'preserve') {
    fail(`${modelName}.unknownFields must be preserve`);
  }
  if (!isObject(model.fields)) {
    fail(`${modelName}.fields must define typed fields`);
  }

  validateRequiredFields(modelName, value, model, models, label);

  for (const key of model.optional ?? []) {
    if (!model.fields[key]) fail(`${modelName}.fields missing optional field ${key}`);
    if (hasOwn(value, key)) {
      validateType(value[key], model.fields[key], `${label}.${key}`, models);
    }
  }

  const requiredAnyFields = (model.requiredAny ?? []).flat();
  const allowedFields = new Set([...(model.required ?? []), ...requiredAnyFields, ...(model.optional ?? [])]);
  const unknownFields = Object.keys(value).filter((key) => !allowedFields.has(key));
  if (model.unknownFields === 'preserve' && unknownFields.length === 0) {
    fail(`${label} fixture must include at least one unknown field to exercise preserve semantics`);
  }
}

function validateEnvelopeFixture(relativePath) {
  const value = readJson(relativePath);
  if (typeof value.ok !== 'boolean') {
    fail(`${relativePath} must contain boolean ok`);
  }
  if (value.ok) {
    if (!hasOwn(value, 'data')) {
      fail(`${relativePath} success envelope must contain data`);
    }
    return;
  }
  if (!isObject(value.error)) {
    fail(`${relativePath} error envelope must contain error object`);
  }
  if (typeof value.error.code !== 'string' || value.error.code.length === 0) {
    fail(`${relativePath} error envelope must contain error.code`);
  }
  if (typeof value.error.message !== 'string' || value.error.message.length === 0) {
    fail(`${relativePath} error envelope must contain error.message`);
  }
}

function validateResponseShape(response, binding, value, models, label) {
  if (!isObject(response)) fail(`${label} response must be object`);

  if (binding.model) {
    if (response.model !== binding.model) {
      fail(`${label} binding model ${binding.model} must match response.model ${response.model}`);
    }
    validateModelValue(binding.model, value, models, label);
    return;
  }

  if (binding.items) {
    if (response.envelopeField !== binding.envelopeField || response.items !== binding.items) {
      fail(`${label} binding ${binding.envelopeField}:${binding.items} must match response shape`);
    }
    requireArray(value[binding.envelopeField], `${label}.${binding.envelopeField}`);
    value[binding.envelopeField].forEach((item, index) => {
      validateModelValue(binding.items, item, models, `${label}.${binding.envelopeField}[${index}]`);
    });
    return;
  }

  fail(`${label} binding must define model or items`);
}

function validateWorkspaceFixtureBinding(binding, contract, methodsByName) {
  const fixturePath = `packages/api_contract/${binding.path}`;
  if (!exists(fixturePath)) {
    fail(`Missing workspace fixture ${fixturePath}`);
  }

  if (binding.envelope) {
    validateEnvelopeFixture(fixturePath);
    return;
  }

  const value = readJson(fixturePath);
  if (binding.composites) {
    requireArray(binding.composites, `${binding.path}.composites`);
    for (const composite of binding.composites) {
      requireArray(composite.responseOf, `${binding.path}.${composite.envelopeField}.responseOf`);
      for (const methodName of composite.responseOf) {
        const method = methodsByName.get(methodName);
        if (!method) fail(`${binding.path} references unknown method ${methodName}`);
        validateResponseShape(method.response, composite, value, contract.models, `${fixturePath}:${methodName}`);
      }
    }
    return;
  }

  const targets = binding.responseOf ?? [];
  requireArray(targets, `${binding.path}.responseOf`);
  for (const methodName of targets) {
    const method = methodsByName.get(methodName);
    if (!method) fail(`${binding.path} references unknown method ${methodName}`);
    validateResponseShape(method.response, binding, value, contract.models, `${fixturePath}:${methodName}`);
  }
}


function validateFixtureCoverage(contract, contractPath) {
  requireArray(contract.fixtureCoverage, `${contractPath}.fixtureCoverage`);

  const fixtureSet = new Set(contract.fixtures);
  const coverageByPath = new Map();
  for (const entry of contract.fixtureCoverage) {
    if (!isObject(entry)) {
      fail(`${contractPath}.fixtureCoverage entries must be objects`);
    }
    if (typeof entry.path !== 'string' || entry.path.length === 0) {
      fail(`${contractPath}.fixtureCoverage entry must define path`);
    }
    if (!fixtureSet.has(entry.path)) {
      fail(`${contractPath}.fixtureCoverage ${entry.path} must be listed in fixtures`);
    }
    if (coverageByPath.has(entry.path)) {
      fail(`${contractPath}.fixtureCoverage has duplicate entry for ${entry.path}`);
    }
    requireArray(entry.consumers, `${contractPath}.fixtureCoverage.${entry.path}.consumers`);

    for (const consumer of entry.consumers) {
      if (!isObject(consumer)) {
        fail(`${contractPath}.fixtureCoverage.${entry.path}.consumers entries must be objects`);
      }
      if (typeof consumer.package !== 'string' || consumer.package.length === 0) {
        fail(`${contractPath}.fixtureCoverage.${entry.path} consumer must define package`);
      }
      if (typeof consumer.test !== 'string' || consumer.test.length === 0) {
        fail(`${contractPath}.fixtureCoverage.${entry.path} consumer must define test`);
      }
      if (consumer.test.startsWith('packages/api_contract/')) {
        fail(`${contractPath}.fixtureCoverage.${entry.path} consumer must be outside api_contract self-checks`);
      }
      if (!exists(consumer.test)) {
        fail(`${contractPath}.fixtureCoverage.${entry.path} consumer test missing: ${consumer.test}`);
      }
      const testText = readText(consumer.test);
      const marker = `contract-fixture: ${entry.path}`;
      if (!testText.includes(marker)) {
        fail(`${consumer.test} must declare fixture coverage marker: ${marker}`);
      }
    }
    coverageByPath.set(entry.path, entry);
  }

  for (const fixture of contract.fixtures) {
    if (!coverageByPath.has(fixture)) {
      fail(`${contractPath} fixture ${fixture} must have fixtureCoverage consumers`);
    }
  }
}

function validateWorkspaceContract() {
  const contractPath = 'packages/api_contract/workspace.json';
  if (!exists(contractPath)) {
    fail(`Missing ${contractPath}`);
  }
  const contract = readJson(contractPath);
  if (contract.namespace !== 'workspace') {
    fail(`${contractPath} namespace must be workspace`);
  }
  if (contract.version !== 1) {
    fail(`${contractPath} version must be 1`);
  }
  if (contract.resultEnvelope !== 'packages/api_contract/errors.yaml#result_envelope') {
    fail(`${contractPath} must point at the standard result envelope`);
  }
  requireArray(contract.methods, `${contractPath}.methods`);

  const methodNames = new Set();
  const methodsByName = new Map();
  const dispatchText = readText('packages/api_bridge/c_api/dispatch.rs');
  const flutterText = readText('packages/flutter/lib/api/workspace_api.dart');
  const iosText = readText('packages/ios/Sources/Napaxi/CoreAPIs.swift');
  const androidText = readText('packages/android/src/main/kotlin/com/napaxi/android/Apis.kt');

  for (const method of contract.methods) {
    if (!method.name || methodNames.has(method.name)) {
      fail(`${contractPath} has missing or duplicate method name: ${method.name}`);
    }
    methodNames.add(method.name);
    methodsByName.set(method.name, method);
    if (method.status !== 'stable') {
      fail(`workspace.${method.name} must be stable for this vertical slice`);
    }
    if (method.bridge?.namespace !== 'workspace' || method.bridge?.method !== method.name) {
      fail(`workspace.${method.name} bridge mapping must use namespace workspace and matching method name`);
    }
    for (const adapter of ['flutter', 'ios', 'android']) {
      if (!method[adapter]) {
        fail(`workspace.${method.name} missing ${adapter} adapter mapping`);
      }
    }
    if (!method.request || !Array.isArray(method.request.required)) {
      fail(`workspace.${method.name} must define request.required`);
    }
    if (!isObject(method.response)) {
      fail(`workspace.${method.name} must define response`);
    }

    const dispatchPattern = `("workspace", "${method.name}")`;
    if (!dispatchText.includes(dispatchPattern)) {
      fail(`packages/api_bridge/c_api/dispatch.rs missing ${dispatchPattern}`);
    }
    if (!flutterText.includes(`${method.flutter.facade}(`)) {
      fail(`Flutter WorkspaceApi missing facade ${method.flutter.facade}`);
    }
    if (!iosText.includes(`func ${method.ios.facade}`)) {
      fail(`iOS NapaxiWorkspaceAPI missing facade ${method.ios.facade}`);
    }
    if (method.ios.raw && !iosText.includes(`func ${method.ios.raw}`)) {
      fail(`iOS NapaxiWorkspaceAPI missing raw method ${method.ios.raw}`);
    }
    if (!androidText.includes(`fun ${method.android.facade}`)) {
      fail(`Android WorkspaceApi missing facade ${method.android.facade}`);
    }
    if (!androidText.includes(`"${method.android.bridgeKey}"`)) {
      fail(`Android WorkspaceApi missing bridge key ${method.android.bridgeKey}`);
    }
  }

  const requiredMethods = [
    'read_file',
    'write_file',
    'append_file',
    'delete_file',
    'list_files',
    'search_memory',
    'recall_sessions',
    'rebuild_recall_index',
    'recall_index_stats',
    'list_journal_days',
    'read_journal_day',
    'system_prompt',
    'reseed',
  ];
  for (const name of requiredMethods) {
    if (!methodNames.has(name)) {
      fail(`${contractPath} missing required workspace method ${name}`);
    }
  }

  const models = contract.models ?? {};
  for (const modelName of [
    'WorkspaceFile',
    'WorkspaceEntry',
    'MemorySearchResult',
    'MemoryRecallSnippet',
    'MemoryRecallSession',
    'RecallIndexStats',
    'JournalDay',
    'JournalTurnRecord',
  ]) {
    const model = models[modelName];
    if (!model) {
      fail(`${contractPath} missing model ${modelName}`);
    }
    if (model.unknownFields !== 'preserve') {
      fail(`${contractPath} model ${modelName} must preserve unknown fields`);
    }
    if (!isObject(model.fields)) {
      fail(`${contractPath} model ${modelName} must declare typed fields`);
    }
    ensureStringArray(model.required ?? [], `${modelName}.required`);
    ensureStringArray(model.optional ?? [], `${modelName}.optional`);
    const requiredAnyFields = (model.requiredAny ?? []).flat();
    for (const field of [...(model.required ?? []), ...requiredAnyFields, ...(model.optional ?? [])]) {
      if (!model.fields[field]) {
        fail(`${contractPath} model ${modelName} missing field type for ${field}`);
      }
    }
  }

  requireArray(contract.fixtures, `${contractPath}.fixtures`);
  requireArray(contract.fixtureBindings, `${contractPath}.fixtureBindings`);
  const bindingPaths = new Set(contract.fixtureBindings.map((binding) => binding.path));
  for (const fixture of contract.fixtures) {
    if (!bindingPaths.has(fixture)) {
      fail(`${contractPath} fixture ${fixture} must have a fixtureBinding`);
    }
  }
  for (const binding of contract.fixtureBindings) {
    if (!contract.fixtures.includes(binding.path)) {
      fail(`${contractPath} fixtureBinding ${binding.path} must be listed in fixtures`);
    }
    validateWorkspaceFixtureBinding(binding, contract, methodsByName);
  }
  validateFixtureCoverage(contract, contractPath);

  // Check model symbols exist in all adapters. The contract does not require
  // generated code yet, but it gates accidental removal or naming drift.
  const dartModels = readText('packages/flutter/lib/models/workspace.dart');
  const swiftModels = readText('packages/ios/Sources/Napaxi/WorkspaceModels.swift');
  const kotlinModels = readText('packages/android/src/main/kotlin/com/napaxi/android/Models.kt');
  const modelSymbols = [
    ['WorkspaceFile', 'NapaxiWorkspaceFile'],
    ['WorkspaceEntry', 'NapaxiWorkspaceEntry'],
    ['MemorySearchResult', 'NapaxiMemorySearchResult'],
    ['MemoryRecallSnippet', 'NapaxiMemoryRecallSnippet'],
    ['MemoryRecallSession', 'NapaxiMemoryRecallSession'],
    ['RecallIndexStats', 'NapaxiRecallIndexStats'],
    ['JournalDay', 'NapaxiJournalDay'],
    ['JournalTurnRecord', 'NapaxiJournalTurnRecord'],
  ];
  for (const [dartKotlin, swift] of modelSymbols) {
    if (!dartModels.includes(`class ${dartKotlin}`)) {
      fail(`Dart workspace model missing ${dartKotlin}`);
    }
    if (!kotlinModels.includes(`class ${dartKotlin}`)) {
      fail(`Kotlin workspace model missing ${dartKotlin}`);
    }
    if (!swiftModels.includes(swift)) {
      fail(`Swift workspace model missing ${swift}`);
    }
  }
}

function validateContractIndex() {
  requireIncludes('packages/api_contract/README.md', 'workspace.json', 'workspace contract entry');
  requireIncludes('packages/api_contract/methods.yaml', 'workspace:', 'workspace namespace');
  requireIncludes('packages/api_contract/capability_matrix.yaml', 'workspace_memory:', 'workspace capability');
  requireIncludes('packages/api_contract/errors.yaml', 'result_envelope:', 'standard result envelope');
  requireRegex('packages/api_contract/errors.yaml', /invalid_argument:/, 'invalid_argument error code');
}

info('Checking executable SDK API contract');
validateContractIndex();
validateWorkspaceContract();
info('SDK API contract checks passed');
