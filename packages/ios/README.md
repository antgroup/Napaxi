# Napaxi iOS SDK

`packages/ios` is the native Swift Package for host-side iOS integration. It
uses the same Rust core API as `packages/flutter` through the stable C ABI in
`packages/api_bridge/include/napaxi_api_bridge.h`.
The package currently declares iOS 16 as its minimum iOS deployment target
because the vendored iSHCore runtime assets are device slices built for that
deployment floor.

Before opening the package in Xcode, build and compile-check the native iOS
package:

```sh
./tools/scripts/build.sh fast check-ios-native
```

That command prepares the local SwiftPM binary target at
`packages/ios/Frameworks/napaxi_api_bridge.xcframework` and runs an iPhoneOS
SwiftPM build of the Swift SDK, C iSH target, and Rust bridge together. Use
`./tools/scripts/build.sh fast ios-all` when you only need to regenerate the
Flutter and native iOS xcframeworks without the SwiftPM compile check.
The Swift SDK exposes typed engine lifecycle helpers plus a raw JSON API escape
hatch for the complete core surface. Stable Flutter-exported models are
available as Codable Swift models that preserve the full JSON object, so newer
core fields remain source-compatible while high-traffic models can grow typed
properties over time.
Flutter-style JSON codec helpers such as `decodeJsonValue(...)`,
`decodeJsonObject(...)`, `decodeJsonArray(...)`, `asJsonObject(...)`,
`decodeJsonObjectList(...)`, `jsonErrorMessage(...)`, and
`throwIfJsonError(...)` are available for porting adapter code that works
directly with raw core payloads.

`NapaxiEngine` also exposes lightweight API facades such as `chat`, `sessions`,
`agents`, `agentApp`, `automation`, `workspace`, `fileBridge`, `mcp`, and
`groups`. These map to the same core JSON methods as the Flutter SDK.
For host code ported from Flutter generated bridge calls, Swift also keeps
raw function-name aliases such as `sendMessage(...)`, `mcpAddServer(...)`,
`listSessionRuns(...)`, `getAgentAppPackage(...)`,
`platformToolDescriptorsJson()`, and `browserToolDescriptorsJson()`. Prefer
the typed facades for new Swift code, but the aliases preserve the same raw JSON
handoff points used by Flutter.
`agentApps` remains available as a Swift plural alias, while `agentApp` mirrors
Flutter's public facade name. `ensureAgent()` mirrors Flutter and delegates to
the Swift-native `ensureAgentReady()`. `NapaxiEngine.create(...)` initializes
the core file bridge so `engine.fileBridge` is ready after engine creation,
matching Flutter's create-time setup. MCP defaults to the Flutter-compatible
`default` account and can be rebound with `mcpForAccount(...)`. Its
server/tool/action/OAuth models have typed accessors, Flutter-style
`fromMap(...)` / `fromJson(...)` / `fromJsonString(...)` / `toMap()` helpers,
and `...JSON` raw escape hatches for host-specific fields. Swift also exposes
Flutter-shaped MCP aliases such as `activate(...)`, `deactivate(...)`, and
`startOAuth(..., redirectUri:, usePkce:)` alongside the native `activateServer`
/ `deactivateServer` labels.

Platform context resolution is available through `NapaxiPlatformContextResolver`,
mirroring Flutter's resolver output with `platform`, `files_dir`,
capability profile/selection, and skill-readiness metadata. The resolved
context exposes both Swift `platformContextJSON` and Flutter
`platformContextJson` spellings.

Top-level Flutter compatibility aliases such as `defaultMaxTokens`,
`LlmConfig`, `LlmCapabilityConfig`, `ScenePromptConfig`,
`ContextEngineConfig`, `napaxiDesktopUserAgent`, `AgentAppActionExecutor`, and
the deprecated `McAgentAppActionExecutor` are available alongside the
Swift-native `Napaxi...` names. The small Flutter-style `log(tag, message)`
helper and Android-only `NapaxiApkInstaller` aliases are also present for source
migration; APK installation returns an explicit unsupported result on iOS.
`ContextEngineConfig` includes Flutter's compaction strategy, optional
compaction model, and compaction timeout fields so LLM config JSON round-trips
without dropping long-session tuning.
The package also exports a broader Flutter migration alias layer for primary
SDK symbols such as `NapaxiEngine`, `ChatApi`, `SessionKey`, `ChatEvent`,
Flutter chat event names like `RunCompletedEvent` and `ResponseEvent`,
`AgentHandle`, `WorkspaceFile`, `SkillInfo`, `McpServerInfo`,
`BackgroundConfig`, and `NapaxiConfigStore`, all backed by the Swift-native
`Napaxi...` implementations.

Capability APIs expose Flutter-compatible typed models for definitions,
statuses, profiles, and selections. `NapaxiCapabilitySelection` preserves the
`config` map used by Flutter capability selection JSON, capability models expose
Flutter-style `fromJson(...)`, `toJson()`, and `toJsonString()` helpers where
they match the Dart surface, and raw JSON access is still available through the
`...JSON` methods, including the Flutter-shaped `listStatusesJSON(...)` alias.
Public
`decodeCapabilityDefinitions(...)` and `decodeCapabilityStatuses(...)` helpers
mirror Flutter's tolerant raw JSON decoders.

Agent APIs expose Flutter-compatible typed handles, definitions, tool filters,
and available-tool metadata. `engine.agents` is engine-backed for default config
sends and exposes Flutter-shaped positional `send(agent, session, message, ...)`
overloads, while `engine.agentDefinitions` mirrors the Flutter
CRUD/import/create facade with `...JSON` raw escape hatches.

Automation APIs also expose Flutter-compatible typed models for triggers,
payloads, policies, jobs, runs, and wake records. The Swift models accept both
Flutter camelCase JSON and core snake_case JSON, expose Flutter-style
`fromJson(...)` / `toJson()` map helpers, and the raw `...JSON` methods remain
available for forward-compatible fields. Automation payloads and runs expose
both Swift `sessionKeyJSON` and Flutter `sessionKeyJson` spellings.
`engine.automation` offers both
Swift-style short names such as `createJob(...)` and Flutter facade names such
as `createAutomationJob(...)`, `getNextAutomationWake()`, and
`recordAutomationWake(...)`. Public `decodeJsonObjectOrNull(...)`,
`decodeAutomationJobs(...)`, and `decodeAutomationRuns(...)` helpers mirror the
Flutter raw JSON decoders.

Agent App APIs expose Flutter-compatible typed accessors and constructors for
packages, action manifests, install bindings, action proposals, action results,
action records, action requests, and install results while preserving unknown
JSON fields. `engine.agentApps` mirrors Flutter's package/proposal/result
facade with typed methods plus `...JSON` raw escape hatches. Public
`decodeAgentAppPackages(...)` and `decodeAgentAppActionRecords(...)` helpers
mirror Flutter's raw JSON list decoders. Positional Agent App helpers such as
`getPackage(_:)`, `deletePackage(_:)`, and `getProposal(_:)` are also available
for code moving from Flutter's facade. Hosts that want Flutter's typed
`AgentAppActionExecutor.execute(_:)` shape can pass
`typedAgentAppActionExecutor` to `NapaxiEngine.create(...)`; the SDK adapts it
to the core JSON dispatch protocol internally.

Browser tool hosting exposes Flutter-compatible viewport/screenshot modes,
backend capability JSON, screenshot metadata, snapshot JSON, and browser tool
request/result helpers. Native hosts provide the actual web view behavior by
implementing `NapaxiBrowserToolExecutor` or `NapaxiBrowserController`; the SDK
keeps the same `browser_*` tool names, snapshot payload shape, and default
mutation approval policy as Flutter. `NapaxiBrowserToolHost` and its
Flutter-compatible alias `FlutterBrowserToolHost` mirror Flutter's standalone
browser host facade for `canHandle(...)` and `execute(...)`. Use
`browserMutationPolicy: .allowAll` only for hosts that intentionally bypass
high-risk click and submit approval.
Flutter-style browser type aliases such as `BrowserMutationPolicy`,
`BrowserViewportMode`, `BrowserScreenshotMode`, `BrowserBackendCapabilities`,
`NapaxiBrowserBackend`, `NapaxiBrowserSnapshot`, and
`NapaxiBrowserToolResult` are also available for host code that wants names
close to the Flutter SDK. Browser capability, screenshot, and snapshot models
also expose Flutter-style `toJson()` helpers. Browser controllers expose
Flutter-named convenience entrypoints such as `executeTool(...)`,
`latestSnapshot`, and `notifyBackendStateChanged()` alongside Swift-native
protocol names. Browser backends also include Flutter-spelled
`loadUrl(...)` and `currentUrl()` aliases over Swift's `loadURL(...)` and
`currentURL()`. WebKit browser snapshots include Flutter-compatible viewport
text blocks, overlay candidates, diagnostics, action hints, and listener-aware
clickability metadata.
`NapaxiWebKitBrowserController` also surfaces Flutter-style controller state
such as `url`, `title`, `loading`, `progress`, `hasPage`, `browserMode`,
`userAgent`, `pageChangeToken`, `buildWebView()`, and `buildWidget()`. SwiftUI
hosts can use `NapaxiBrowserSurface(controller:)` or provide a placeholder view,
mirroring Flutter's `NapaxiBrowserSurface` wrapper around the shared browser
controller.

Agent APIs are available through `engine.agents` / `engine.agentDefinitions`
and through Flutter-style direct engine helpers such as `getOrCreateAgent(...)`,
`listAgents()`, `deleteAgent(...)`, `agentSend(...)`,
`createAgentDefinition(...)`, `importAgentMd(...)`, `listAvailableTools()`, and
`createAgentFromDefinition(...)`. Agent definition models include Flutter-style
`fromMap(...)`, `fromJson(...)`, `toMap()`, and `toJson()` helpers, while
available tool metadata exposes `ToolInfo.fromMap(...)`.

Session models expose Flutter-style `fromJson(...)`, `fromMap(...)`, `toJson()`,
and `toMap()` helpers where they match the Dart surface, including chat
attachments, tool calls, history pages, context status, and nested token budget
models. Tool-call arguments accept both object maps and JSON object strings like
Flutter.

Group APIs are available through `engine.groups` and through Flutter-style
direct engine helpers such as `createGroup(...)`, `listGroups()`,
`renameGroup(...)`, `updateGroupMembers(...)`, `sendToGroup(...)`,
`sendToGroupAgent(...)`, `exportGroupState()`, and `importGroupState(...)`.
The `engine.groups` facade also provides positional Flutter migration overloads
such as `create(_:_:)`, `rename(_:_:)`, `updateMembers(_:_:)`, `send(_:_:)`,
`sendToAgent(_:_:_:_:)`, and `importState(_:)`.

Skill APIs expose Flutter-compatible typed accessors for installed skills,
status reports, status entries, requirements, OpenClaw metadata, usage records,
curator summaries, support-file reads, command dispatch/resolution/run results,
source reports, refresh results, snapshots, secret requirements, remediation
actions/runs, install inputs/results, and catalog search/list/detail results.
`NapaxiSkillInstallInput` exposes both `installPayloadJSON()` and Flutter's
`toInstallPayloadJson()` spelling.
`engine.skills` mirrors the core-backed Flutter skill facade with typed methods
plus `...JSON` raw escape hatches. Flutter-shaped helpers such as
`recordSourceChanged(...)`, `updateConfig(...)`, `pin(...)`, `readSupportFile(...)`,
`searchCatalog(...)`, and `runConsolidationReview(...)` are available from the
skill facade. `NapaxiEngine` also exposes Flutter-style direct skill helpers such as
`listSkills(...)`, `getSkillStatus(...)`, `runSkillCommand(...)`,
`listSkillSources(...)`, `listSkillSnapshots(...)`,
`listSkillSecretRequirements(...)`, `requestSkillRemediation(...)`,
`listSkillRemediationRuns(...)`, `installSkill(...)`, `reloadSkills(...)`,
`pinSkill(...)`, `readSkillSupportFile(...)`, `searchCatalog(...)`, and
`installFromCatalog(...)`. Direct `NapaxiEngine.listCatalogPackages(...)`
mirrors Flutter's 50-item engine default, while
`engine.skills.listCatalogPackages(...)` mirrors Flutter's 24-item `SkillApi`
facade default. Both paths use the same ClawHub request shape and 1...100 clamp
range, returning a typed `NapaxiCatalogPackagePage`.

Evolution APIs expose Flutter-compatible typed run statuses, review run
records, diagnostics, and skill-consolidation review results. Pending
apply/reject responses remain raw JSON dictionaries because Flutter exposes
them as maps.

Custom tool execution supports both the Swift-native `NapaxiToolExecutor`
protocol and Flutter-style `McToolExecutor`. Hosts can pass `mcToolExecutor:`
to `NapaxiEngine.create(...)`; the SDK adapts it through
`NapaxiToolExecutorAdapter` while preserving the same `(toolName, paramsJson) ->
result JSON` contract Flutter exposes.

Workspace APIs expose Flutter-compatible typed accessors for files, directory
entries, memory search results, recalled sessions/snippets, recall index stats,
journal days, journal turns, and workspace path constants. Workspace models
include Flutter-style `fromMap(...)`, `fromJson(...)`, and `toMap()` helpers
where they match the Dart surface. `engine.workspace` mirrors the Flutter
workspace facade with default account/agent values, typed file/memory/journal
methods, the Flutter-shaped `search(...)` memory helper, engine-backed recall
config, positional migration overloads for `writeFile(_:_:)`,
`appendFile(_:_:)`, and `listFiles(_:)`, and `...JSON` raw escape hatches.
`NapaxiEngine`
also exposes Flutter-style direct workspace helpers such as
`readWorkspaceFile(...)`, `writeWorkspaceFile(...)`, `searchMemory(...)`,
`recallSessions(...)`, `listJournalDays(...)`, `getSystemPrompt(...)`, and
`reseedWorkspace(...)`; `writeWorkspaceFile(_:_:)` and
`appendWorkspaceFile(_:_:)` accept Flutter's positional content argument.
Direct workspace helpers default to Flutter's blank
engine workspace agent scope, while `engine.workspace` defaults to the `napaxi`
agent like Flutter's `WorkspaceApi`.

File bridge APIs expose the same sandbox/real path mapping, scoped workspace
mapping, workspace browsing, workspace size, and attachment metadata operations
as Flutter. Common path helpers such as `sandboxToReal(...)`,
`realToSandbox(...)`, `resolveFile(...)`, `sandboxToRealPath(...)`,
`realToSandboxPath(...)`,
scoped variants, `workspaceDirPath(...)`, `rootfsDirPath()`, and
`skillsDirPath()` return typed Swift strings so hosts do not need to unwrap raw
JSON for standard file bridge workflows. Raw path mapping remains available
through `sandboxToRealJSON(...)` and `realToSandboxJSON(...)`.
`NapaxiFileBridgeAPI.instance`, `isInitialized`, and `requireInstance()` mirror
Flutter's singleton-style file bridge access after `NapaxiEngine.create(...)`;
`filesDir` is retained on the facade for hosts that need the original app
storage root.
`ResolvedFile` and `WorkspaceFileInfo` expose Flutter-style `fromMap(...)` and
`toMap()` helpers for advanced file bridge payloads.
Flutter generated bridge names are also available where Swift's facade uses
shorter labels: `initFileBridge()`, `initFileBridgeScoped(...)`,
`deleteSandboxFile(...)`, `deleteSandboxFileScoped(...)`,
`listWorkspaceFilesystem(...)`, `listWorkspaceFilesystemScoped(...)`, and the
`saveMessageAttachments(threadId:userMsgIndex:attachmentsJson:)` overload.
`NapaxiFileBridge` is a migration alias for the Swift file bridge facade.
`McAttachment` mirrors Flutter's attachment payload map through
`toMap(sandboxPath:)`, supports `Data` construction, and serializes batches with
the same `data_base64` field used by Flutter.

Platform tool hosting includes `NapaxiDefaultPlatformToolExecutor` plus
Flutter-compatible names such as `FlutterCapabilityHost`,
`FlutterMobileCapabilityHost`, `PlatformToolExecutor`, `CapabilityContext`, and
`MobileCapabilityContext`. The context helper
mirrors Flutter's workspace/rootfs/skills path resolution and attachment result
JSON helpers for native tool implementations, including both Swift `...JSON`
and Flutter `...Json` spellings. `FlutterCapabilityHost`
also exposes Flutter-style `canHandle(...)` and `execute(..., paramsJSON,
workspaceFilesDir:)` helpers that return JSON strings, while the Swift-native
`NapaxiPlatformToolExecutor.executePlatformTool(...)` remains available for
typed host integrations.
`PlatformToolProvider` mirrors Flutter's standalone helper for
`isSupported`, `platformToolNames`, `isMobilePlatformTool(...)`, and
`getToolDefinitions()`, so hosts can inspect the mobile tool surface without
building an engine facade first. Flutter's per-tool helper names such as
`UrlTool`, `PhoneTool`, `ClipboardTool`, `DeviceInfoTool`, `LocationTool`,
`NotificationTool`, `ContactsTool`, `CalendarTool`, `CameraTool`, `AudioTool`,
`AlarmTool`, and `InstallAppTool` are available as thin Swift facades over the
same native executor. `NotificationTool.ensureInit()` is available as an
iOS no-op initialization hook for Flutter-shaped shared code.

Group APIs expose Flutter-compatible typed accessors for group metadata,
messages, message types, membership updates, state import/export, and group
send results. `GroupInfo`, `GroupMessage`, and `GroupMessageType` include
Flutter-style `fromMap(...)`, `fromJson(...)`, `toMap()`, and `fromString(...)`
helpers where they match the Dart model surface. `engine.groups` is
engine-backed for default config sends, while explicit-config methods and
`...JSON` raw escape hatches remain available for advanced hosts.

Flutter-style config profile persistence is available through
`NapaxiConfigStore`, `NapaxiConfigProfile`, and `NapaxiConfigSelection`. Profile
metadata is stored separately from API keys; the default store uses
`UserDefaults` for profile JSON and Keychain for secrets when Security is
available, while tests or hosts can inject custom stores. Config profile and
selection models expose Flutter-shaped `toMap()`, `fromMap(...)`, and
`init(map:)` helpers for hosts that persist or migrate profile JSON directly.
`NapaxiConfig` mirrors
Flutter's `LlmConfig` fields for system prompts, token/tool limits, model
allowlists, image/video/audio models, per-capability provider configs, scene
prompt config, context engine config, and optional `userTimezone` IANA timezone
for user-local date intent, while still preserving unknown JSON fields through
`extra`. Runtime storage, wire values, and timestamps remain UTC/epoch based;
hosts set `userTimezone` explicitly when they want local-time prompt context.
`LlmConfig.fromJson(...)` / `toJson()` and the
Flutter-style `fromMap(...)` / `toMap()` helpers on `ScenePromptConfig`,
`ContextEngineConfig`, and `LlmCapabilityConfig` are available for hosts that
share configuration payloads with Flutter.

Session APIs are available through `engine.sessions` and the Flutter-style
direct engine helpers `createSession(...)`, `listSessions(...)`,
`deleteSession(...)`, `clearSession(...)`, `getHistory(...)`,
`getHistoryPage(...)`, `compactContext(...)`, and `contextStatus(...)`.
`NapaxiEngine.getHistoryPage(...)` mirrors Flutter's direct engine default of
80 messages, while `engine.sessions.historyPage(...)` mirrors the 50-message
`SessionApi` facade default. The session facade also exposes positional
Flutter-style overloads such as `history(_:)`, `historyPage(_:)`,
`contextStatus(_:)`, and `answerHumanRequest(_:_:)`.
`NapaxiEngine.send(...)`, `sendStream(...)`, `sendToSession(...)`,
`sendToSessionStream(...)`, and the `ChatApi` facade accept Swift `Int`
`maxIterations` values like Flutter's `int`, converting safely at the native
bridge boundary. Direct engine session sends also support Flutter's positional
`sendToSession(session, message, ...)` and `sendToSessionStream(session,
message, ...)` migration shape.
Session sends expose Flutter-style local run state through `activeSessionRuns`,
`activeSessionRun(...)`, `hasActiveSessionRun(...)`, and `sessionRunUpdates`.
`SessionRunInfo.copyWith(...)` mirrors Flutter's update helper, including clear
flags for human requests and errors.
The Swift SDK updates this state from streamed chat events, including tool
progress, HITL waits, local cancellation, errors, and completion. Late stream
events after `cancelSession(...)` keep the run cancelled instead of reactivating
stale local state. Persisted session run APIs also expose Flutter-compatible
typed records, statuses, verification values, and evidence through
`engine.sessionRuns`, with list/get/active typed methods plus raw JSON escape
hatches. Session run stable strings expose Flutter-style `wireName` and
`fromWire(...)` helpers. The public `decodeSessionRunRecords(...)` helper mirrors Flutter's
tolerant raw JSON decoder for host/debug workflows.
`NapaxiChatEvent.fromMap(...)`, `fromJsonString(...)`, and `toMap()` mirror
Flutter's event factory helpers while retaining Swift's raw-backed event model.

Evolution APIs are available through `engine.evolution` and the Flutter-style
direct engine helpers `listPendingEvolution()`, `applyPendingEvolution(...)`,
`rejectPendingEvolution(...)`, `listEvolutionRuns(...)`,
`listEvolutionDiagnostics()`, and `runSkillConsolidationReview(...)`.

Background execution exposes Flutter-style config, action events, and a
controller through `engine.background` / `engine.backgroundController`. iOS does
not have an Android foreground service equivalent, so `backgroundController`
stays nil without a host, matching Flutter's non-Android behavior. Apps that
provide their own wake or notification policy can implement
`NapaxiBackgroundHost`; with a host, starting a configured controller uses that
host policy. `NapaxiBackgroundConfig.toMap()` mirrors Flutter's
MethodChannel payload shape, and `jsonValue()` uses the same flattened config
map. `wakeLockTimeout` is available as a Flutter-shaped seconds value alongside
Swift's `wakeLockTimeoutMilliseconds`. Streamed sends automatically start the configured
background host, update notifications for tool/HITL/error events, and stop on
completion like the Flutter adapter. `NapaxiBackgroundPermissions` mirrors
Flutter's non-Android defaults (`isSupported == false`, notification permission
checks return true, `isBackgroundExecutionSupported()` and background execution
return false) and can delegate checks to a host policy through
`NapaxiBackgroundPermissionHost`.

Agent Provider integrations use `engine.agentProviders` for the Flutter-style
facade and `engine.agentProviderHost` for lower-level URL handling. The facade
can request provider installs, register returned Agent packages with core,
consume launch-intent installs, validate and accept pending triggers, and
delegate provider actions through `NapaxiAgentProviderActionExecutor`. Flutter
names such as `AgentProviderInstallApi`, `AgentProviderTriggerApi`,
`IosAgentProviderActionExecutor`, `AndroidAgentProviderActionExecutor`, and
`agentProviderRequestToJson(...)` are available as migration aliases/helpers.
Agent app packages, manifests, install bindings, proposals, results, records,
and action requests expose Flutter-shaped map helpers for moving host payloads
between Swift and Dart-style integration code.
Provider descriptors, install requests/results, and trigger requests expose
Flutter-style `fromMap(...)`, `toJson()`, and `toJsonString()` helpers where the
Dart models do.
Typed package methods (`requestInstall`, `installFromLaunchIntent`,
`requestInstallPackage`, `installPackageFromLaunchIntent`,
`validateTriggerPackage`, and `consumePendingTrigger`) mirror Flutter's
package-oriented provider facade while raw JSON hooks remain available through
`requestInstallJSON` and `installFromLaunchIntentJSON`. The host
parses provider discovery URLs, generates protocol-v2 install requests, builds
install and action handoff URLs, consumes trigger callbacks, and attaches the
iOS install binding fields expected by core (`ios_bundle_id`, `ios_team_id`,
`host_bundle_id`, `host_team_id`, and `host_callback_scheme`). Trigger
acceptance validates protocol v2, expiry, replay, installed package/provider
matching, host binding, and `hmac-sha256-v1` signatures.

If shell support is needed, prepare the local iSH assets before building:

```sh
./tools/scripts/prepare_ios_ish_spm.sh
```

The native package expects `Sources/Napaxi/Resources/alpine-rootfs.tar.gz` plus
the vendored iSH headers and static libraries under `Vendor/iSHCore`. The
`check-ios-native` gate validates those assets before compiling the package.

Default iOS platform tools cover URL, phone/SMS handoff, clipboard, device
info, location, notifications, contacts, calendar events, camera capture,
and audio recording. Android-only or system-restricted tools such as
`install_apk` and `set_alarm` return an explicit unavailable error on iOS.
For Flutter public API parity, `NapaxiApkInstaller.isSupported` is always false
on iOS and `installApk(...)` returns a failed `NapaxiApkInstallResult`. The
result model exposes Flutter-style `fromMap(...)` and `toMap()` helpers for
shared host code.

Host tool requests use the same core dispatch tool names as Flutter. Implement
`NapaxiStructuredToolApprovalHandler` to receive `__napaxi_approval__` requests
with request id, tool name, description, parameters JSON, and `allowAlways`,
then return `approved`, `always`, and an optional message. The legacy boolean
`NapaxiToolApprovalHandler` is still accepted as a compatibility fallback.
Flutter names `McToolApprovalRequest`, `McToolApprovalResponse`, and
`McToolApprovalHandler` mirror Flutter's structured host approval types,
including decoded parameters, `parametersJson`, and the same approval response
JSON shape. Hosts
can pass a Flutter-shaped async approval closure through
`NapaxiEngine.create(..., mcToolApprovalHandler:)`; the SDK adapts it into the
core policy chain.
Custom host tools can be registered with Flutter-compatible
`NapaxiCustomToolDefinition` / `CustomToolDef` values through either
`engine.updateCustomTools(...)` or `engine.tools.updateCustomTools(...)`; the
model exposes Flutter-style `fromJson(...)`, `toJson()`, and `toJsonString()`
helpers, and the raw JSON escape hatch remains available as
`updateCustomToolsJSON(...)`. Flutter's `startToolRequestListener()` and
`engine.tools.startRequestListener()` are available as idempotent migration
hooks; Swift registers the host tool router during `NapaxiEngine.create(...)`.
`engine.tools.mobilePlatformToolDefinitions()` and
`engine.tools.browserToolDefinitions()` decode the same descriptor arrays that
Flutter's platform/browser providers expose, with raw descriptor APIs retained
for forward-compatible fields.
The standalone `BrowserToolProvider` also exposes Flutter-style
`isBrowserTool(...)`, `getToolDefinitions()`, and `capabilityId`; it recognizes
the same current `browser_*` tool names rather than any arbitrary prefix.

Channel bridge access is available through `engine.channels`. The raw
`list()`, `register(configJSON:)`, and `unregister(channelName:)` methods match
the core C API, while `registerChannel(configJSON:)` and
`unregisterChannel(...)` mirror Flutter's generated boolean channel bridge.
