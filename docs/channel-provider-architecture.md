# Channel Provider Architecture

Napaxi channel providers are host-owned adapters that connect external message
or device surfaces to the core channel queue. They align with Agent Provider
security boundaries, but they are not Agent actions: a channel provider owns a
long-lived ingress/outbox loop, while an Agent Provider owns proposal/result
handoff for app actions.

## Roles

- Core owns channel registration, durable inbound envelopes, outbound leasing,
  inbound ack/fail/release, channel-agent routes, stable session identity,
  ask-human continuation, outbound reply enqueueing, capability policy, provider
  contracts, and official first-party sans-IO protocol kits.
- API bridges expose `napaxi_core::api` to SDK adapters without owning provider
  behavior.
- SDK adapters own provider lifecycle hooks, registration helpers, polling,
  dispatch from the Napaxi outbox to provider delivery code, background/permission
  glue, and thin wrappers that start the core channel-agent pump.
- Provider implementations own platform credentials, connection state,
  platform-specific identifiers, media upload/download, live transport retries,
  UI/login flows, and risk controls.

## Provider Contract

A provider declares a manifest:

```json
{
  "provider_id": "napaxi.qqbot.provider",
  "channel_name": "qqbot",
  "display_name": "QQBot",
  "account_id": "bot-a",
  "surface_kind": "im",
  "endpoint_kinds": ["direct", "group", "room"],
  "modalities": ["text", "image", "audio", "file"],
  "content_formats": ["plain_text", "markdown"],
  "transport": "websocket",
  "auth_requirements": ["qq_open_platform_app_credentials"],
  "background_requirements": ["websocket_gateway"]
}
```

The host registers the manifest, then providers use `submitInbound` for
external events. The provider host leases outbound messages and calls provider
delivery code; success maps to `ackOutbound`, failure maps to `failOutbound`.
`content_formats` declares display formats the provider can attempt for
outbound text. Providers that receive an unsupported format must preserve the
message body and send it as `plain_text`; they should not parse Markdown or
infer rich text from characters such as `**`.

`napaxi_core::api::channel_agent` is the reusable layer that turns any
registered channel into an agent conversation. It leases normalized inbound
envelopes, resolves a `ChannelAgentRoute`, creates or reuses the stable session,
streams the agent run, wraps stream/tool/reasoning events as
`ChannelAgentEvent`, queues outbound replies, handles `asking_human` by sending
the question back through the same channel, and resumes the run when the user
replies. Flutter's `NapaxiChannelAgentBridge` only starts that pump, reconnects
providers, keeps Android background service alive, and adapts events to UI.

## Official Protocol Kits

Officially supported channels may add a platform-independent protocol kit under
`crates/core` and expose it through `napaxi_core::api`. These kits are not live
providers. They are sans-IO helpers that take JSON/state/events and return
payloads, normalized envelopes, or actions for the provider transport to
execute.

Suitable core-owned protocol decisions include:

- outbound payload builders and content-format mapping;
- peer/thread to endpoint routing;
- inbound event normalization and de-duplication keys;
- gateway or webhook state reducers;
- signature, replay, and timestamp validation helpers;
- fallback, retry, and error classification.

The kit must be pinned by shared fixtures, and every SDK adapter that supports
that official channel should call the kit instead of re-implementing those
rules. Live I/O remains outside core: sockets, HTTP clients bound to app
lifecycle, Bluetooth, vendor SDK callbacks, secure storage, QR/login UI,
background services, and host network policy.

Flutter calls official protocol kits through FRB generated helpers. Android and
iOS call the same pure helpers through the C API dispatch namespace, for example
`channel_qqbot.build_outbound_payload` and `channel_qqbot.gateway_step`.

## External Provider Extension Standard

External developers extend channels by implementing the SDK provider contract,
not by modifying `crates`. A provider package or host app must:

- declare a stable manifest with channel name, provider id, account id, surface
  kind, endpoint kinds, modalities, content formats, transport kind, and
  background/auth requirements;
- register the provider through the SDK adapter's provider host;
- normalize platform events into `ChannelInboundMessage` and submit them through
  the provider context;
- lease outbound messages from the Napaxi outbox and deliver them through the
  platform transport;
- return delivery receipts or failures with provider-specific diagnostics;
- report status without mutating core session, route, history, HITL, or policy
  rules.

External providers may implement private protocol mapping in their own package.
They must still preserve the core channel envelope and let
`napaxi_core::api::channel_agent` own routing, sessions, history, ask-human,
stream events, and outbound queue state. If the common envelope cannot represent
a provider's required behavior, add a typed core contract first, then expose it
through the SDK adapters; do not smuggle reusable behavior through demo code or
adapter-only JSON fields.

## Relationship To Agent Provider

Agent Provider remains the contract for app-owned actions:

- install/action handoff
- proposal validation
- provider confirmation
- action result return

Channel Provider uses the same trust principle, but a different runtime shape:

- install or host configuration establishes provider trust
- provider events enter through channel ingress
- outbound delivery is leased from the channel outbox
- background support is explicit in the provider manifest

Android external provider apps can reuse Agent Provider installation trust
metadata for package/signature binding. iOS external providers should use
foreground URL or Universal Link setup unless a platform extension provides an
approved background path.

## SDK QQBot Provider

The Flutter SDK currently includes `QqBotChannelProvider`, a first-party
convenience `qqbot` provider that follows the official QQ Bot adapter path while
delegating protocol decisions to the core QQBot kit:

- `/channel qqbot setup` stores QQBot AppID/AppSecret in host secure storage.
- `/channel qqbot connect` gets an AccessToken, opens the QQ Gateway
  WebSocket, identifies, heartbeats, and maps QQ message events into Napaxi
  channel ingress.
- `/channel qqbot status` shows provider state, the registered channel record,
  Gateway session state, and delivery counters.
- Outbound Napaxi channel messages are leased by the provider host and delivered
  through QQ OpenAPI send endpoints.
- `format = "markdown"` for direct/group outbound maps to QQBot
  `msg_type = 2` with `markdown.content`. Room/channel sends remain plain text
  unless a future QQ capability declaration explicitly enables Markdown there.
  Clear 4xx Markdown capability/format errors fall back to `msg_type = 0`
  plain text and include `markdown_fallback: true` in the delivery receipt.

The Flutter demo only supplies UI and secure-storage glue. SDK consumers can use
the provider directly:

```dart
final provider = QqBotChannelProvider(
  const QqBotChannelCredentials(
    appId: '...',
    appSecret: '...',
    agentId: 'napaxi',
  ),
);
await engine.channelProviders.registerProvider(provider, autoPump: true);
engine.channelAgents.registerRoute(
  NapaxiChannelAgentRoute.channelDefault(
    channelName: QqBotChannelProvider.channelName,
    channelAccountId: provider.credentials.appId,
    sessionAccountId: 'default',
    agentId: provider.credentials.agentId,
  ),
);

final bridge = NapaxiChannelAgentBridge(
  engine: engine,
  channelName: QqBotChannelProvider.channelName,
  accountId: 'default',
  channelAccountId: provider.credentials.appId,
  agentId: provider.credentials.agentId,
  isProviderConnected: () => provider.status().connected,
);
bridge.start();
```

Android and iOS currently expose the shared provider-host contract and the
QQBot sans-IO protocol helpers, but do not ship a live QQBot transport shell in
v1. A native QQBot transport should follow the same pattern as the Flutter
provider: hold sockets/timers/tokens in adapter code and delegate protocol
payload, gateway, normalization, endpoint, and fallback decisions to core.

The slash command namespace is intentionally generic. Future WeChat, Feishu, or
device providers should add provider implementations under the same
`/channel <provider> <action>` control surface instead of introducing
provider-specific command roots. If a provider graduates from demo/convenience
code to an official first-party channel, its shared protocol decisions should
move into a core sans-IO kit while its live transport remains in provider code.

## SDK Bluetooth Device Provider Family

Bluetooth is modeled as a device discovery and transport family, not as a
single universal channel. The Flutter SDK currently includes
`BluetoothHeadsetChannelProvider`, a first-party device-channel provider shell
for headset/audio-device style voice interaction. It standardizes how host
audio code plugs into Napaxi, and the Flutter Android adapter now provides the
first official platform-audio implementation for push-to-talk input and TTS
output:

- The manifest uses `surface_kind = "device"`, `endpoint_kind = "device"`,
  `modalities = ["audio", "text", "control", "presence"]`, and capability
  `napaxi.channel.device`.
- Host/STT code submits completed utterances through
  `submitVoiceTranscript`, which normalizes the message as
  `voice_transcript_final` channel ingress.
- SDK consumers can use
  `BluetoothHeadsetChannelProvider.withPlatformAudio(...)` on Flutter Android.
  That wires the provider to Android microphone permission, `SpeechRecognizer`
  capture, best-effort Bluetooth communication routing while listening, and
  `TextToSpeech` reply playback.
- Core `channel_agent` resolves the configured route, creates or reuses the
  stable session for the headset device, records history, handles ask-human,
  and queues outbound replies exactly like IM channels.
- Provider outbound delivery strips Markdown for speech and either calls the
  host `BluetoothHeadsetSpeechSink` or acknowledges with a host-visible receipt
  when no TTS sink is configured.
- The Flutter Android adapter exposes a thin `BluetoothHeadsetDeviceDiscovery`
  helper for setup UI. It lists already paired Bluetooth devices with
  `device_kind`, `profiles`, `capabilities`, `recommended_channel_kinds`,
  `confidence`, and optional warnings. Headsets, speakers, and connected unknown
  audio-profile devices can be offered to the audio channel. Phones, computers,
  car audio, control devices, sensors, and unknown non-audio devices are kept as
  "other devices" and are not attached to the audio channel by default.
- Android Bluetooth permissions, SCO/session routing, microphone capture,
  platform speech recognition, native TTS, notification controls, and
  foreground-service lifecycles remain in adapter/host transport code.

Demo usage stays on the generic Channel settings surface:

1. Add a Bluetooth Devices channel and choose a paired audio device.
2. Bind it to an agent.
3. Connect the channel.
4. In that agent's chat screen, use the headset voice-input button next to the
   composer to run the full path:
   Android speech capture -> normalized channel inbound -> core channel-agent
   run -> outbound lease -> Android TTS playback.

The settings card may keep a management/test action, but the normal user path
is agent-scoped: only connected device channels bound to the current agent are
offered in the chat composer. If several devices are bound to the same agent,
the composer opens a small device picker; devices bound to other agents are not
used for the current conversation.

Host apps may replace the default platform audio implementation with their own
wake-word capture, custom STT, or custom TTS sink while continuing to use the
same provider manifest, inbound envelope, route configuration, and
channel-agent bridge.

## Extension Path

New channels should implement the same provider interface:

- IM: QQ, WeChat, Feishu, Slack, Telegram.
- Device: Bluetooth audio device, car kit, sensor, wearable.
- App/system: local notification bridge, clipboard listener, share extension.

Core changes are only needed when the shared channel envelope or official
protocol kit contract is insufficient. Platform-specific live transport belongs
in provider packages or host apps. Official, cross-adapter protocol decisions
belong in core as sans-IO helpers; third-party providers can keep private
protocol mapping in their own packages as long as they submit/lease the standard
Napaxi channel envelope.

Provider implementations own platform I/O: auth/login, gateway/webhook/socket
lifecycle, media transport, live retries, and outbound send endpoints. The SDK
`NapaxiChannelProviderHost` is reused unchanged for provider lifecycle and
outbound delivery; `crates/core/src/channel_agent/` is reused unchanged for
agent routing, session history, stream events, ask-human, and outbound replies.
