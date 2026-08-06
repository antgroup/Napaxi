# Mobile Capabilities

Mobile capabilities are compiled SDK contracts owned by core and carried by
adapters. They cover LLM providers, built-in tools, platform tools, MCP
surfaces, host custom tools, media features, background services, and future
policy gates.

V1 capabilities are not runtime native plugins. They are discovered from the
core registry, made available by platform/host declarations, and enabled by
runtime config or explicit selection.

## Capability Model

Each capability definition has:

- `id`: stable SDK ID such as `napaxi.llm.openai` or
  `napaxi.platform_tool.open_url`.
- `kind`: `llm_provider`, `tool`, `platform_tool`, `mcp`, `policy`,
  `service`, or `agent_engine`.
- `version`: contract version.
- `platforms`: supported platforms, or `all`.
- `config_schema`: adapter-neutral JSON schema for capability config.
- `risk`: `low`, `medium`, `high`, or `critical`.
- `requirements`: host permissions, network, approval, workspace, or sandbox
  requirements.
- `default_enabled`: whether the capability is enabled when available.
- `activation`: `always`, `config`, `host`, or `policy`.

State is split deliberately:

- Registered: core contains the capability definition.
- Available: the current platform and host profile can carry it.
- Enabled: config/selection allows it to participate in runtime execution.

## Scenario Packs

Scenario packs are capability-backed runtime postures. They let one Napaxi SDK
installation expose different scene behavior without downloading arbitrary
native runtime code. A pack describes:

- `id`: stable SDK scene ID such as `napaxi.scenario.general` or
  `napaxi.scenario.mobile_development`.
- Required, recommended, and optional capabilities.
- Expected execution planes: core, host bridge, platform provider, or remote
  workspace.
- UI surfaces and memory scopes the host can use to shape its experience.
- UI contributions such as `repo_workbench` and `environment`, which let a
  host show scene-specific project and environment workspaces without exposing
  those surfaces in unrelated scenarios.
- Activation posture: manual, intent-routed, or host-policy controlled.

Core ships two V1 anchor packs:

| Scenario | Purpose | Default state |
| --- | --- | --- |
| `napaxi.scenario.general` | The current general mobile assistant posture: chat, memory, files, skills, web fetch/search, and normal host-carried tools. | Available and enabled when the default core capabilities are enabled. |
| `napaxi.scenario.mobile_development` | A privileged mobile developer workbench posture: project context, git/build/test tools, approval UI, audit timeline, and richer workbench surfaces. | Registered but unavailable until the host declares and enables workbench, git, shell, and approval-policy capabilities. |

Installed scenario packs are manifest-only extensions. Core persists them under
`<files_dir>/napaxi/scenarios/packs.json`, merges them with built-in packs at
query time, and exposes the merged set through the same core/bridge/adapter
APIs. Installed packs may declare capability requirements, execution planes, UI
surfaces, memory scopes, and activation posture, but they cannot replace or
remove built-in scenario IDs.

Installing a scenario pack normalizes the manifest, adds
`napaxi.service.scenario_registry` when omitted, and returns warnings for
unknown capability IDs instead of silently admitting behavior. This lets hosts
stage future or custom host-carried capabilities while still showing users the
gap.

Resolving a scenario returns an activation plan rather than mutating runtime
state. The plan tells the host which capabilities should be added to its
profile, which capabilities should be enabled in selection, and which remote,
host, or policy contracts must be made visible to users. This keeps scene
installation auditable: installing a developer pack can propose remote shell
and git capabilities, but admission still goes through the core capability and
policy chain.

V1 scenario packs are compiled SDK contracts plus adapter/host declarations and
installed manifests. They are not a native plugin market. Downloaded
skill/workflow packs may map to scenario requirements later, but executing new
native code still requires a host-provided capability boundary.

### Scenario-Scoped Git

`napaxi.tool.git` is a host-carried capability used by the mobile development
scenario. Installing or declaring the provider makes Git available in the host
profile; switching to a scene that enables `napaxi.tool.git` plus a configured
Git settings contribution makes admitted Git tools such as `git_clone`,
`git_status`, and `git_diff` visible to the runtime. Switching back to the
general scene removes those Git descriptors because the selection no longer
enables the capability.

The first Flutter demo provider executes Git through the host process when a
`git` executable is present and keeps repositories under an app-owned
`git_repos` workspace. Phone-native repository cloning should be supplied
by a dedicated host provider, such as libgit2/JGit or a remote workspace bridge,
rather than making Git a default global capability.

## Adding A Capability

1. Add the definition and mapping in `crates/core/src/capabilities/`.
2. Implement reusable behavior in the owning core domain module, feature crate,
   or existing tool/provider runtime.
3. Expose adapter-facing operations through `crates/core/src/api/`.
4. Add bridge functions in `packages/api_bridge/` only as thin calls into
   `napaxi_core::api`.
5. Add Flutter models/wrappers under `packages/flutter/lib/` if host apps need
   a public SDK surface.
6. Update this document and architecture docs when the capability adds a new
   kind, state rule, risk policy, or host requirement.

Demo apps consume public SDK APIs only. They may show or validate capability
behavior, but they must not own reusable capability contracts or runtime
policy.

## Platform Tools

Platform tools are host-carried capabilities. Core owns the tool names,
parameter schemas, risk levels, and permission requirements. The Flutter
adapter may execute tools such as contacts, calendar, camera, location, audio,
notifications, URL handling, device info, clipboard, phone, alarms, and APK
install, but those tools are exposed only when the host declares support.

Use a host profile to describe support, for example:

```json
{
  "platform": "ios",
  "supported_capabilities": ["napaxi.platform_tool.*"],
  "disabled_capabilities": ["napaxi.platform_tool.install_apk"]
}
```

## Memory Tools

Workspace memory and recall tools are covered by `napaxi.tool.memory`. This
includes curated memory reads/writes, `memory_search`, and `session_recall`.
Recall results are historical context returned on demand; they are not injected
into the default system prompt.

## Browser Control

Persistent in-app browser operation is carried by `napaxi.tool.browser`. It is a
host-carried high-risk tool capability: core owns the `browser_*` tool names,
schemas, admission mapping, and risk classification, while the adapter owns the
visible WebView session, login surface, user approval UI, and storage clearing.

V1 uses one app-isolated browser session. `browser_open` reuses the current
page when the URL already matches, and `browser_snapshot`, `browser_click`,
`browser_type`, `browser_scroll`, `browser_wait`, `browser_back`, and
`browser_close` continue operating on the same session. Hosts must keep the
browser visible for login and high-risk operations, redact password-like fields
from snapshots, and require user approval for form submission, payment,
purchase, send/post, delete, file upload, permission, and similar mutating
flows.

## Agent App Actions

Connected app or backend actions use one generic host-carried capability:
`napaxi.tool.agent_app_action`. Core owns the capability definition, action
proposal schema, result schema, persistence lifecycle, and admission checks.
Specific provider actions are runtime package data selected by `provider_id`;
they are not Agent definitions, dynamic native plugins, or global custom host
tools. Protocol-v2 `agent_id` fields remain wire-compatibility identities only.

Hosts declare and enable the capability only when they provide an Agent App
action dispatcher. Action tool names are reserved with the `app_action_`
prefix so descriptor and invocation admission map them to
`napaxi.tool.agent_app_action` instead of `napaxi.tool.custom_host`.

Package/proposal/result APIs live under `api::agent_app` and the Flutter
`AgentAppApi`. See `docs/agent-app-actions.md` for the runtime flow
and SDK integration contract.

Each registered package also has host-owned automatic-invocation state. The
state defaults to disabled and can only be changed through
`set_agent_app_auto_invoke`; Provider manifest input cannot enable it. Without
an explicit `@{provider:...}` selection, Core exposes actions only from packages
whose automatic-invocation state is enabled. Explicit selections and actual
action dispatches update host-owned `last_used_at` and `use_count` metadata for
adapter UI ranking. Action execution still passes descriptor/invocation
admission and Provider-side confirmation unchanged.

Generated Android Agent Apps may additionally expose the trusted runtime
diagnostics control endpoint described in `docs/agent-provider-protocol.md`.
This is provider/adapter lifecycle infrastructure, not a Core capability or an
Agent App action: it is absent from model descriptors and can only be read by
the bound Host through explicit management UI. It carries bounded crash/ANR
reports and structured runtime logs; debug-level collection is an explicit
user-controlled Provider setting.

## Channel Capabilities

IM channel ingress and egress use the host-carried service capability
`napaxi.channel.im`; device/peripheral channel ingress and egress use
`napaxi.channel.device`. Core owns the registration shape, route metadata,
stable capability ids, durable inbound envelopes, outbound delivery leasing,
channel-agent routing, stable sessions, history, ask-human continuation, and
policy gates. Adapters and host apps own provider SDKs, webhooks, sockets,
pairing/login flows, Bluetooth/audio transports, app permissions, background
constraints, and final reply delivery.

V1 channel records remain file-backed under `napaxi/channels.json` and preserve
the existing `list_channels`, `register_channel`, and `unregister_channel`
public APIs. New registrations may include `surface_kind`, `endpoint_kind`,
`modalities`, and `transport` so IM channels can be represented without
blocking future device/peripheral channels. IM adapters such as QQ Bot, WeChat,
and Feishu can use the shared `submit_inbound`, `take_inbound`,
`enqueue_outbound`, `reply_inbound`, `lease_outbound`, `ack_outbound`, and
`fail_outbound` contract. Official first-party channels may add shared sans-IO
protocol kits in core for payload mapping, normalization, gateway/webhook state,
and fallback classification; live transports, credentials, SDK callbacks, and
background lifecycle remain in provider implementations. The Flutter SDK exposes
`NapaxiChannelProviderHost` for provider lifecycle, `NapaxiChannelAgentBridge` for
agent/session/HITL routing, `QqBotChannelProvider` as the first-party QQBot IM
provider, and `BluetoothHeadsetChannelProvider` as the first Bluetooth
audio-device channel provider. The audio-device provider accepts host/STT
transcripts and can route outbound replies to a host TTS sink; Flutter Android
ships the first platform implementation using Android microphone permission,
speech recognition, best-effort Bluetooth communication routing, and TTS
playback. These live Bluetooth/audio responsibilities still stay in
adapter/host code rather than Rust core. Host UI should treat device channels
as agent-bound input/output sources: setup binds the device channel to an
agent, while chat surfaces only expose connected device inputs for the current
agent and pass through the same channel-agent route/session runtime.
Android/iOS expose the same provider-host contract plus shared channel-agent
route/status APIs and QQBot sans-IO protocol helpers; they do not ship a live
QQBot transport shell in v1. Demo apps should only store credentials, present
setup/status UI, and call SDK APIs.

See `docs/channel-capabilities.md` for the channel contract and first-phase IM
design.

## Agent Engines

Agent engines are core-owned runtime loop capabilities. The default
`napaxi.agent_engine.napaxi_core` capability keeps the existing Napaxi tool loop
enabled when no Agent definition selects another engine.

`napaxi.agent_engine.codex` is the core-owned Codex app-server engine. The
capability and adapter API are visible across Flutter, Android, and iOS. Mobile
runtime implementations start `codex app-server` inside a bundled Linux sandbox
PTY: Android uses the PRoot backend, while iOS uses the
`napaxi.platform.ios_qemu` backend backed by Napaxi-owned rootfs preparation and
vendored lower-level QEMU C/static libraries. Both backends share the baked
Alpine rootfs artifact name (`alpine-rootfs.bin`), the app-server JSON-RPC
session owner, Codex event mapping to Napaxi `ChatEvent`s, and persisted Napaxi
session to Codex native thread mapping. On iOS the capability is available only
when the QEMU runtime is linked, the rootfs resource is packaged, and the host
enables the required capabilities; otherwise core/adapters report the explicit
not-ready or disabled state. Other platforms return
`napaxi.agent_engine.codex is unsupported on this platform` until they provide a
compatible sandbox runner.

The selected main `LlmConfig` is the only supported source for Codex model and
credential configuration. Hosts call `syncCodexAgentEngineModel` after the main
model is persisted and `clearCodexAgentEngineModelConfig` when it is removed.
On Android, core validates the provider and writes `config.toml` plus
`auth.json` atomically into the Linux sandbox. OpenAI and OpenAI-compatible
providers use the Responses wire API required by current Codex releases.
Anthropic, Gemini, and other incompatible protocols are rejected. Every Codex
turn repeats this sync from the turn's `config_json`, invalidates stale native
thread mappings when the configuration fingerprint changes, and refuses to run
if the model config is missing or invalid. The deprecated raw TOML API is
retained only for source compatibility and must not be used by host
applications. If a host must route only the sandboxed Codex CLI through a
network proxy, it may put `http_proxy`, `https_proxy`, `all_proxy`, or
`no_proxy` under the Codex agent definition's `engine_config.network_env`; core
validates those values, exports them only for `codex app-server`, and includes
them in the Codex runtime fingerprint so idle sessions restart when the network
route changes. This proxy path is Codex-engine scoped and does not mutate the
Rust-native Napaxi provider configuration.

Codex turns reuse the normal Napaxi prompt and attachment preparation path before
they enter app-server. The compiled `napaxi_core` runtime instructions are sent
as Codex app-server `developerInstructions` when a native Codex thread is started
or resumed, so SDK policies for workspace use, shell/file behavior, skills,
media handling, response language, and host guidance stay aligned with the
default engine path without replacing the Rust tool loop. Attachment bytes are
persisted into the workspace under `/workspace/attachments/<thread>/...`; image
attachments with workspace sandbox paths are forwarded as Codex app-server
`localImage` input items, and all attachments are summarized in the text input
with filename, MIME type, kind, and workspace path when available. Host-local
picker paths are not passed as `localImage` values because the app-server process
can only read sandbox-visible workspace files. Non-image file attachments
continue to be exposed as workspace paths and metadata for Codex to inspect with
its sandbox tools. The Android integration strict live probe requires the model
response to reflect both a text-file sentinel and a PNG image sentinel before it
accepts the attachment path as validated. This does not change the default
`napaxi_core` engine attachment/history path.

Codex app-server threads also receive Napaxi's currently admitted tool
descriptors through the app-server experimental `dynamicTools` field on
`thread/start`. These descriptors are derived from the same capability profile,
selection, tool registry, and internal handler preflight used by the Rust tool
loop. When Codex sends an `item/tool/call` request, core executes it through the
Napaxi tool broker / internal tool-loop path with the same invocation admission,
policy, workspace context, redaction, and result sanitization used by
`napaxi_core`. On mobile platforms, core includes the shared platform-tool
descriptors in this preflight only when a host tool bridge is registered, then
dispatches calls back through that bridge with workspace context so Android/iOS
permission, file-resolution, and user-confirmation handling stays in the SDK
adapter. Platform and device tools such as URL opening, camera, media library,
clipboard, browser, Git, and host custom tools remain available only when the
host declares and enables their capabilities and still require any host-side
permission or user-confirmation UI. Dynamic tools are advertised only
when a new native Codex thread is started; existing resumed app-server threads
continue with the tools they were started with, and configuration or dynamic-tool
fingerprint changes clear the thread mapping before a new thread is opened.
Approval, extra-permission, MCP elicitation, current-time, and unsupported
app-server JSON-RPC requests are answered deterministically at the Codex bridge
boundary so a mobile turn is not left waiting on a Codex-side approval channel;
user-input requests remain routed through Napaxi's ask-human continuation path.

`CodexAgentEngineConfigResult` reports `success`, `providerAvailable`,
`modelUsable`, `errorCode`, `error`, `model`, and `configChanged`. Stable errors
are `missing_main_model`, `missing_api_key`, `missing_base_url`,
`unsupported_provider`, `model_not_available`, `model_check_failed`,
`config_write_failed`, and `unsupported_platform`. Model-list checks are a host
preflight: an explicit missing model, authentication error, timeout, or server
failure blocks Codex; endpoints that return `404`, `405`, or `501` for model
listing fall back to core's local protocol validation.

Codex conversation recovery uses the same core-owned app-server boundary as
turn execution. On Android, `listCodexAgentEngineThreads` calls `thread/list`,
`readCodexAgentEngineThread` resumes or reads the native thread and maps its
items to SDK `ChatMessage` values, `bindCodexAgentEngineThread` associates a
recovered native thread with an SDK session before the next turn, and
`deleteCodexAgentEngineThread` forwards deletes to Codex `thread/delete` so
removed conversations do not reappear on the next native history restore. This
retains the working native history behavior without restoring the removed
developer workbench configuration or Flutter-owned Codex PTY runtime. Other platforms
return `unsupported_platform` through the same typed result. History-specific
failures use `history_query_failed` and `missing_native_thread`.
Flutter dispatches these potentially blocking app-server history operations on
the FRB worker pool so startup restoration never blocks the UI isolate.

Hosts may declare `napaxi.agent_engine.external_host` when they carry an
external agent loop executor. The external executor owns turn planning and
model interaction, but it must call back through the Napaxi ToolBroker for tool
listing and tool calls. Tool descriptor admission, invocation admission, shell
policy, workspace scope, approval, rate limiting, output sanitization, run
evidence, and emitted `ChatEvent` mapping remain core-controlled. The `codex`
alias no longer routes to `external_host`; only `external_host` does.

The core-owned internal JSON protocol has three stable operations:
`tools/list` returns the current Agent's admitted tool descriptors,
`tools/call` invokes one admitted tool through the existing policy and evidence
path, and `run/event` normalizes host-reported events such as `thinking`,
`response_delta`, `tool_call`, `tool_result`, `error`, and `completed` into
Napaxi `ChatEvent` values. External engines may report tool-call arguments as
JSON objects; core stringifies those fields before mapping them to the existing
`ChatEvent` wire shape.

`AgentDefinition` selects an engine with `engine_id`, `engine_profile_id`, and
`engine_config`. `provider` and `model` continue to configure the built-in
Napaxi LLM loop; external engines do not depend on those fields except when the
host executor chooses to read them from the turn request.

Flutter v1 can register a host-carried `AgentEngineExecutor` for true external
engines such as demo CLI integrations. Android and iOS v1 expose the stable wire
models and explicit unsupported state for host executors. Selecting
`external_host` or `codex` without the declared and enabled capability is
rejected by core capability admission; selecting `codex` on a platform without a
compatible bundled sandbox runner returns the platform unsupported error above.

## LLM And Media Capabilities

LLM providers route through provider capabilities. Built-in routes include
OpenAI-compatible, OpenAI, Anthropic, and Gemini. GLM and NearAI remain
compatible aliases routed through the OpenAI-compatible provider path.

Media tools are tool capabilities backed by provider config slots. Existing
`capability_configs` keys such as `imageAnalysis` and `imageGeneration` remain
compatible and map to `napaxi.tool.image_analysis` and
`napaxi.tool.image_generation`.

### Stream Resilience

Core owns LLM transport fault tolerance; adapters do not retry turns. LLM HTTP
clients are process-shared with a connect timeout and connection reuse. A stream
that stops delivering bytes for 60s is treated as stalled and reconnected rather
than hanging the turn. Streaming and non-streaming calls retry transient
failures (connection drops, decode errors, stalls, `429`/`5xx`) with exponential
backoff plus jitter, honoring a `Retry-After` header when present. When a stream
drops after partial output, core emits a `stream_reset` `ChatEvent` so adapters
discard the aborted attempt's partial assistant content before the reconnected
stream resumes; no session history is written for the aborted attempt.

## Context Engine

`napaxi.service.context_engine` is a low-risk service capability enabled through
LLM config. Core owns automatic long-session compaction, stores summary state
under engine files, injects summaries through prompt sections, and exposes
manual compact/status operations through the common session API. Adapters
should configure it with `context_engine`; they should not rewrite session
history or own a separate compression pipeline. Flutter, Android, and iOS
configuration selections may also persist a selection-level `context_engine`;
hosts should apply it to the active profile so one global context policy follows
model switches. Profile-level context settings remain readable for migration.

`napaxi.workspace.project` owns the project placement API. `SessionKey` remains an
immutable conversation identity; its single display project and runtime
workspace are stored independently in libsql. A normal move uses the target
project's default workspace, while `keep_current` supports Codex-style moves
where the conversation is displayed in project B but keeps running in workspace
A. The runtime workspace is snapshotted before each turn and cannot change
during an active turn. Project files are listed through the same core workspace
record used by tools, so the Files surface cannot accidentally browse another
project's root. See [Project session workspaces](project-session-workspaces.md).

## Shell Command Safety

Shell command admission is core-owned and follows a three-step model: the SDK
provides the mechanism, the host selects the policy through LLM config
(`shell_security.approval_mode`). It is configured, not toggled — the wire field
is a snake_case enum that maps to a fixed posture.

1. **Hard gate** — destructive and data-exfiltration commands (`rm -rf /`,
   `mkfs`, raw block-device access, fork bombs, piping fetched content into a
   shell, netcat exfiltration) are rejected in *every* mode, including
   `trusted_allow`. The gate operates on a token stream, so quoted or heredoc
   text is treated as data (e.g. `echo "rm -rf /"` is not a hit) and spacing
   variants (`rm  -rf /`) are still caught.
2. **Known-safe allow-list** — read-only commands run automatically regardless
   of mode, with per-argument validation ported from codex: a command name is
   only safe when its arguments cannot write, delete, or execute. `find` is safe
   but `find / -delete` is not; `git status` is safe but `git -C /other status`
   and `git push --force` are not; `sed -n 1,5p` is safe but `sed -i` is not.
3. **Approval posture** — everything that is neither hard-gated nor known-safe
   is decided by `ShellApprovalMode`:

| Mode | Wire value | Non-safe command fate |
| --- | --- | --- |
| Read-only only | `read_only_only` | Prompt host approval; reject if no bridge. Strictest. |
| On request (SDK default) | `on_request` | Prompt host approval; reject if no bridge. Closest to historical behavior. |
| Trusted allow | `trusted_allow` | Run directly once it clears the hard gate, no prompt. |
| Custom | `custom` | Deferred to a host-registered policy hook after the hard gate. |

"Dangerous but legitimate" commands (`sudo`, `git push -f`, `kill -9`) are *not*
hard-gated — they are simply not known-safe, so the mode decides their fate.
Under `on_request` they prompt; under `trusted_allow` they run.

The `Prompt` decision is resolved in the shell tool layer through the existing
approval bridge (`request_host_tool_execution`); it never enters the binary
`CapabilityAdmissionDecision { Allow, Deny }` enum, so capability admission is
unchanged. The napaxi demo selects `trusted_allow`: its sandboxed workspace is
the blast radius, so only the hard gate is effectively in play and no approval
interaction is introduced. The SDK default stays `on_request` so open-source
hosts get a conservative posture.

Android, iOS, and Flutter adapters expose `ShellSecurityConfig` /
`ShellApprovalMode` on the LLM config with the same snake_case wire values and
an `on_request` fallback for unknown values. This fallback is important for
forward compatibility: if a future SDK version introduces a new
`ShellApprovalMode` variant, older Android/iOS adapter builds that do not
recognize the value will default to `on_request`, ensuring the host is always
prompted before potentially dangerous commands run rather than silently
allowing or blocking them.

## Automation

`napaxi.service.automation` is a host-carried service capability for mobile
scheduled and proactive Agent work. Core owns the durable job model, next-wake
calculation, run state, run audit log, retry/backoff state, and the execution
contract for `systemEvent` and `agentTurn` payloads.

Automation state is stored under the engine files dir:

- `napaxi/automation/jobs.json`
- `napaxi/automation/runs/<job_id>.jsonl`

V1 triggers are one-shot timestamps, local-time schedules, fixed intervals,
manual runs, and host events. Local-time schedules use `localTime` with
`hour`, `minute`, an IANA `timezone`, and optional ISO `daysOfWeek` values
(`1` = Monday, `7` = Sunday). V1 does not implement server webhooks, desktop
Gateway cron, arbitrary script cron, or full cron expressions. Android/iOS
adapters and host apps are responsible for real system wakeup, permission
prompts, user-visible notifications, and platform scheduling APIs. iOS
execution remains best-effort unless a host-controlled foreground handoff or
push path wakes the app.

Mobile scheduling is host-carried rather than runtime-resident. Core calculates
the next durable wake through `getNextAutomationWake`; the adapter registers
that wake with the platform, records native wake delivery in a small pending
wake queue, then calls `recordAutomationWake` when an engine is available.
This avoids assuming the SDK process is always alive. Android uses a framework
alarm bridge for the next wake and persists delivered wakes until Dart drains
them. Hosts should call the scheduler sync path on app start, resume, and after
automation job CRUD so missed wakes are caught up and the next wake is
re-armed.
One-shot trigger `timezone` is provenance for the user's local scheduling
intent; automation turns may use it as a `userTimezone` fallback when the host
config does not set one, but trigger execution is still keyed by `atMs`.

Automation Agent turns run through the normal core session runtime. Isolated
automation sessions use the `automation` channel type by default, while
high-risk tools such as shell, HTTP mutation, and Agent App actions are disabled
unless the job policy explicitly allows them.

## Mobile A2A

`napaxi.a2a.deeplink` remains the host-carried deep-link fallback for pairing,
manual handoff, and result links. `napaxi.a2a.local` is the local peer service
capability for real device-to-device Agent collaboration over host-provided
nearby transports such as LAN WebSocket/TCP, Wi-Fi hotspot, mDNS/Bonjour/NSD,
and future BLE discovery.

`napaxi.tool.a2a` is the separate model-facing A2A tool capability. Hosts should
enable it only while a nearby transport is running and trusted peers can be
resolved. A2A chat tools such as `a2a_list_agents` and `a2a_send_message` must
not fall back to the broad `napaxi.tool.custom_host` gate; turning Nearby off
should remove both the tool descriptors and the A2A runtime guidance from the
model request.

Core owns the peer/session/message/task ledger, delivery state, nonce and
idempotency checks, user-confirmation semantics, and remote task safety gates.
Adapters own discovery, local-network/Bluetooth permissions, socket lifecycle,
foreground/background constraints, and UI. Local transports should move
`A2APeerMessage` JSON and then call the common A2A API to record inbound
messages; they must not mark work as delivered, accepted, running, or complete
from transport text alone.

When a saved peer has a shared secret, core wraps outbound peer message payloads
in an AES-256-GCM v1 encrypted payload envelope, signs the encrypted message
with HMAC-SHA256, verifies signed inbound messages, and decrypts them before
writing task evidence into the ledger. The encryption envelope binds message
identity fields as AEAD additional data. Unsigned messages remain accepted only
as untrusted input that requires user confirmation; invalid signatures or
undecryptable payloads are recorded as failed delivery records.

Flutter exposes the local transport through the A2A API: status, start, stop,
discover, send, and a broadcast event stream for peer discovery and inbound
messages. Android v1 implements LAN discovery with Android NSD service type
`_napaxi-a2a._tcp.` and sends `A2APeerMessage` JSON over TCP newline-delimited
frames (`lan_tcp_jsonl`). iOS v1 implements the same service type with Bonjour
`NetService` discovery and Network.framework TCP JSON-lines transport.
Host iOS apps must declare `NSLocalNetworkUsageDescription` and include
`_napaxi-a2a._tcp` in `NSBonjourServices`; otherwise iOS may block local peer
discovery or service publication.

Pairing proves peer identity and trust; it does not prove current reachability.
Adapters must treat discovered endpoints as short-lived leases bound to the
current transport window. Before a model-facing A2A tool sends work, the host
must refresh discovery, match the advertised `peerId`/public key against the
trusted peer record, and use only a verified endpoint from that refresh. If no
verified endpoint exists, the tool should return a structured reachability
diagnostic such as `a2a_no_verified_channel`; it must not reuse a stale IP or
let the model infer that the remote app, Wi-Fi, hotspot, or OS permission is the
cause.

The transport registry should stay open-ended: LAN TCP/Bonjour/NSD is the first
shipping transport, BLE can provide discovery or low-bandwidth exchange, and a
host-provided/xChannel relay can bridge devices when the local network is
isolated. All transports feed the same peer/session/message ledger and must
produce verified endpoint evidence before delivery is reported.

The demo requires explicit user confirmation before treating a discovered
local peer as paired. Advertised peer identity is public and is used only for
discovery and a short identity fingerprint; it is not treated as secret key
material. A trusted local pairing requires both devices to exchange a
user-visible pairing secret out of band, for example via `/a2a status` and
`/a2a pair <peer> <secret>` in the Flutter demo. The demo derives the core
shared secret from both peer identities and both local pairing secrets, then
persists the trusted peer in core so task, progress, and result payloads can be
encrypted, signed, and verified. Future work can replace the manual secret
exchange with signed peer cards, QR codes, or platform key agreement.

Local A2A runtime state is stored under the engine files dir in
`agent_runtime/a2a/`, including `peers.json`, `sessions/`, `messages/`,
`deliveries/`, and `tasks/`.

## Policy Gates

Security and policy capabilities are core gates. Tool descriptor admission,
tool invocation admission, provider admission, and future model switching must
pass through the core policy chain. Host approval UI can participate in a
policy decision, but the SDK must not create an alternate path that bypasses
core policy.

## Verification

For capability changes:

- Add Rust tests for registry definitions, host profile status, legacy config
  compatibility, and policy admission.
- Add tool/provider regression tests for affected execution paths.
- Add Dart model/API tests when public Flutter models change.
- Run `./tools/scripts/build.sh check-boundary` for core or bridge changes.
- Run focused Flutter tests first, then full `cd packages/flutter &&
  flutter analyze --no-fatal-infos && flutter test` before broad SDK handoff.
