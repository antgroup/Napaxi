#!/usr/bin/env node
// Executable manifest-action-handler alignment checks for Provider Apps.
// For every Provider App manifest (assets/agent-app.json) this verifies the
// manifest is internally consistent and that the app source registers exactly
// the actions the manifest declares, so a drifted template fails the build
// instead of surfacing as handler_not_found or a silently missing action at
// run time on the phone.

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const examplesDir = path.join(root, 'examples/provider_app');
const fail = (message) => {
  console.error(`[ERROR] ${message}`);
  process.exit(1);
};
const info = (message) => console.log(`[INFO] ${message}`);

function listProviderApps() {
  return fs.readdirSync(examplesDir)
    .map((name) => path.join(examplesDir, name))
    .filter((fullPath) => fs.statSync(fullPath).isDirectory())
    .map((fullPath) => ({ name: path.basename(fullPath), dir: fullPath }))
    .filter(app =>
      fs.existsSync(path.join(app.dir, 'app/src/main/assets', 'agent-app.json')));
}

function readManifest(app) {
  const file = path.join(app.dir, 'app/src/main/assets/agent-app.json');
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`${app.name}: invalid agent-app.json JSON: ${error.message}`);
  }
  if (!Array.isArray(manifest.actions) || manifest.actions.length === 0) {
    fail(`${app.name}: manifest.actions must be a non-empty array`);
  }
  if (typeof manifest.provider_id !== 'string' || !manifest.provider_id) {
    fail(`${app.name}: manifest.provider_id must be a non-empty string`);
  }
  return { file, manifest };
}

// Mirrors the runtime contract checks in AgentProviderLite.validatePackage:
// contract_version >= 2 must declare structured action parameter schemas.
function checkContractVersion(app, manifest) {
  const contractVersion = manifest.contract_version === undefined
    ? 1 : manifest.contract_version;
  if (!Number.isInteger(contractVersion) || contractVersion < 1) {
    fail(`${app.name}: contract_version must be an integer >= 1`);
  }
  if (contractVersion >= 2) {
    for (const action of manifest.actions) {
      if (action.parameters === undefined || action.parameters === null) {
        fail(`${app.name}: contract_version >= 2 requires action ${action.action_id} to declare parameters`);
      }
      if (action.parameters.type !== 'object') {
        fail(`${app.name}: action ${action.action_id} parameters.type must be "object"`);
      }
      // Workitem §4/§8: a "manifest only declares id+json string" was the
      // root failure mode for TradeJournal. The build must reject a v2
      // manifest that lets a UI/drive agent call an action with no
      // discoverable result schema, since the host cannot otherwise tell
      // "succeeded with empty {}" from "succeeded with a real record".
      if (action.result_schema === undefined || action.result_schema === null) {
        fail(`${app.name}: contract_version >= 2 requires action ${action.action_id} to declare result_schema`);
      }
      if (action.result_schema.type !== 'object') {
        fail(`${app.name}: action ${action.action_id} result_schema.type must be "object"`);
      }
      if (Object.keys(action.result_schema).length === 0) {
        fail(`${app.name}: action ${action.action_id} result_schema must be a non-empty object`);
      }
      // Workitem §6: a missing display_name lets the UI silently swallow
      // the action. Refuse the manifest rather than render an empty chip.
      if (typeof action.display_name !== 'string' || !action.display_name.trim()) {
        fail(`${app.name}: action ${action.action_id} must declare a non-empty display_name`);
      }
    }
  }
}

function declaredActionIds(app, manifest) {
  const seen = new Set();
  for (const action of manifest.actions) {
    const actionId = typeof action.action_id === 'string'
      ? action.action_id.trim() : '';
    if (!actionId) fail(`${app.name}: every action must declare a non-empty action_id`);
    if (seen.has(actionId)) fail(`${app.name}: duplicate declared action ${actionId}`);
    if (typeof action.tool_name !== 'string' || !action.tool_name.trim()) {
      fail(`${app.name}: action ${actionId} must declare a non-empty tool_name`);
    }
    seen.add(actionId);
  }
  return seen;
}

// Mirrors the generated-app idiom:
//   new AgentProviderActionRegistry().register("note.create", ...).
function registeredHandlerActionIds(app) {
  const sourceDirs = ['java', 'kotlin'].map((lang) =>
    path.join(app.dir, 'app/src/main', lang)).filter((dir) => fs.existsSync(dir));
  if (sourceDirs.length === 0) {
    fail(`${app.name}: no app/src/main Java or Kotlin sources found`);
  }
  const registered = new Set();
  for (const dir of sourceDirs) {
    for (const file of fs.readdirSync(dir, { recursive: true })) {
      if (!file.endsWith('.java') && !file.endsWith('.kt')) continue;
      const text = fs.readFileSync(path.join(dir, file), 'utf8');
      for (const match of text.matchAll(/\.register\(\s*"([^"]+)"/g)) {
        registered.add(match[1].trim());
      }
    }
  }
  return registered;
}

// APK build hygiene: the `android-apk-build` skill forbids project-local
// `build.sh` and guarantees the only final APK is build/<APP_NAME>.apk. These
// checks run against the same sample sources used for manifest alignment, so
// a regenerated demo with an untracked build helper or stray intermediate
// APK cannot accidentally pass CI.
function checkApkBuildHygiene(app) {
  const buildSh = path.join(app.dir, 'build.sh');
  if (fs.existsSync(buildSh)) {
    fail(`${app.name}: project-local build.sh is forbidden; the android-apk-build skill owns the build pipeline via its bundled scripts/build_apk.sh`);
  }
  // App build outputs are not committed; this only flags leftover APKs that
  // were accidentally checked in under app/build/.
  const appBuild = path.join(app.dir, 'app/build');
  if (fs.existsSync(appBuild)) {
    const strayApks = fs.readdirSync(appBuild).filter((name) => name.endsWith('.apk'));
    if (strayApks.length > 1) {
      fail(`${app.name}: app/build/ contains ${strayApks.length} *.apk files; the build skill must leave exactly one final APK`);
    }
  }
}

// If a Provider app's fixture project is expected to have a build-skill
// artifact registry, require it. Older sample projects may legitimately lack
// one until rebuilt; only the committed fixture that mentions artifact.json
// in its README/spec opts in here.
function checkArtifactManifestWhenExpected(app) {
  const expectedMarker = path.join(app.dir, '.napaxi-expects-artifact-json');
  if (!fs.existsSync(expectedMarker)) {
    return;
  }
  const artifact = path.join(app.dir, '.mobile/artifact.json');
  if (!fs.existsSync(artifact)) {
    fail(`${app.name}: marked as expected to ship an .mobile/artifact.json sample but the file is missing`);
  }
}

try {
  const apps = listProviderApps();
  if (apps.length === 0) fail('No Provider App manifests found under examples/provider_app');
  for (const app of apps) {
    const { file, manifest } = readManifest(app);
    checkContractVersion(app, manifest);
    const declared = declaredActionIds(app, manifest);
    const registered = registeredHandlerActionIds(app);
    const missingHandlers = [...declared].filter((id) => !registered.has(id));
    const undeclared = [...registered].filter((id) => !declared.has(id));
    if (missingHandlers.length) {
      fail(`${app.name} (${path.relative(root, file)}): manifest actions without a registered handler: ${missingHandlers.join(', ')}`);
    }
    if (undeclared.length) {
      fail(`${app.name} (${path.relative(root, file)}): registered handlers missing from manifest: ${undeclared.join(', ')}`);
    }
    info(`${app.name}: ${declared.size} declared actions match ${registered.size} registered handlers`);
    checkApkBuildHygiene(app);
    checkArtifactManifestWhenExpected(app);
  }
  console.log('[INFO] Manifest-action alignment checks passed');
} catch (error) {
  fail(error.message);
}
