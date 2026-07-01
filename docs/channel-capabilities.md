# Channel Capabilities

Napaxi channels are host-carried interaction surfaces that can deliver user
input into the agent runtime and route agent output back to the correct
surface. V1 supports IM channels and the first device/peripheral channel shape,
with Bluetooth device support implemented first as a host-audio provider contract
that can accept completed speech transcripts and deliver agent replies to a
host TTS sink.

This design borrows the durable parts of OpenClaw's channel model: deterministic
host routing, per-account channel instances, session isolation, pairing or
allowlist safety, and stable reply routes. Napaxi does not adopt OpenClaw's
desktop Gateway/runtime-plugin shape. The mobile SDK core owns the channel
runtime, provider contract, policy, route metadata, session identity, and
official first-party sans-IO protocol kits. SDK adapter packages expose those
rules through thin host/lifecycle wrappers. Provider implementations, whether
first-party or external, own platform connections, credentials, permissions,
transport lifecycles, and UI.

## V1 Scope

V1 implements the SDK contract for channel registration, durable message
ingress, durable outbound delivery leasing, and core-owned channel-to-agent
routing. IM providers and device providers use the same queue, route, session,
history, ask-human, and outbound contract.

In scope:

- Register, list, and unregister channel records through the existing channel
  API.
- Define the provider extension contract external channel implementations must
  use: manifest registration, normalized inbound submit, outbound lease/delivery,
  status, receipts, and capability declarations.
- Represent IM channels as the host-carried service capability
  `napaxi.channel.im`, and device/peripheral channels as
  `napaxi.channel.device`.
- Store typed route metadata: channel surface kind, endpoint kind, supported
  modalities, supported content formats, transport kind, and capability id.
- Accept normalized inbound messages from host/platform adapters.
- Lease inbound messages and acknowledge, fail, or release them.
- Queue outbound messages and let adapters lease, acknowledge, or fail delivery.
- Reply to an inbound message by reusing its channel/account/peer/thread route.
- Configure `ChannelAgentRoute` entries that map channel/account/peer/thread to
  a target `agent_id` and `session_account_id`.
- Run `streamChannelAgentPump`, which resolves routes, creates stable sessions,
  streams agent events, handles ask-human, records history, and queues outbound
  replies.
- Keep the existing session key shape: `channel_type`, `account_id`,
  `thread_id`.
- Provide official, shared, sans-IO protocol kits for first-party channels when
  cross-adapter behavior must remain identical, such as QQBot payload mapping,
  gateway state machines, inbound normalization, and fallback classification.
- Let adapters register IM channels such as Telegram, WhatsApp, Slack, Discord,
  WeChat, Feishu, SMS, and host-private IM bridges.
- Let adapters register device channels such as Bluetooth audio devices,
  wearables, car head units, sensor buttons, and local A2A peripheral surfaces.
- Provide a Flutter SDK Bluetooth audio-device provider that declares a
  `device` channel, accepts host/STT transcripts, and routes outbound replies to
  an optional host TTS sink. Flutter Android additionally ships the first
  platform-audio wrapper for microphone permission, one-shot speech capture,
  best-effort Bluetooth communication routing, and TTS playback.
- Provide a Flutter Android setup helper that can list already paired Bluetooth
  devices, classify them by kind/profile/capability, and only default suitable
  audio devices into the current audio channel. This is a convenience picker
  over OS state, not a Bluetooth transport.

Out of scope for V1:

- Live IM provider transports inside Rust core, such as provider-owned
  WebSockets, QR/login UI, vendor SDK callbacks, secure-storage access,
  Bluetooth sessions, foreground services, or platform-specific webhook servers.
- Runtime plugin downloads or a channel marketplace.
- Server/webhook/tunnel managers inside the mobile SDK runtime.
- Bluetooth scanning, pairing, connection management, live SCO/session routing,
  native speech recognition, native TTS engines, car/wearable vendor SDKs, and
  foreground-service implementations inside Rust core.
- Model-chosen cross-channel delivery.

## OpenClaw-Compatible IM Adapter Pattern

OpenClaw's QQ, WeChat, and Feishu integrations share one important boundary:
the Gateway/core is channel-agnostic, while channel adapters own platform
runtime details.

- QQ Bot uses the official QQ Bot API WebSocket gateway. The plugin owns AppID
  and AppSecret setup, token cache, account-isolated sockets, C2C/group/guild
  target grammar, media upload, voice/STT/TTS shaping, and platform echo-loop
  handling.
- OpenClaw's WeChat path uses an external Tencent Weixin/iLink plugin with QR
  login. Napaxi does not ship a first-party WeChat provider in V1; a future
  provider must still enter through the same normalized channel contract.
- Feishu/Lark uses bot credentials and defaults to WebSocket/persistent
  connection mode, with optional webhook mode. The adapter owns app credentials,
  event subscriptions, group mention policy evidence, interactive-card
  streaming, and account-specific config.

Napaxi supports the same integration style by making the SDK contract explicit:
providers register their channel, submit normalized inbound envelopes, and
lease outbound messages to send through their native transport. For official
channels, platform-independent protocol decisions can live in `crates/core` as
sans-IO kits exposed through `napaxi_core::api`; for external channels, the
provider can implement its own protocol mapping while still using the same
provider contract. Core never stores platform secrets directly unless the host
places them in its own channel config, and core never starts provider
WebSockets or QR login flows.

Flutter, Android, and iOS hosts can use the SDK `ChannelProviderHost` contract as
the reusable adapter lifecycle layer. A provider declares a manifest, starts
with a channel provider context, submits inbound messages, and implements
outbound delivery. `napaxi_core::api::channel_agent` is the reusable runtime from
normalized channel ingress to agent sessions, stream events, outbound replies,
history, and ask-human continuation; Flutter `NapaxiChannelAgentBridge` is a thin
provider-lifecycle wrapper over that core pump. Android and iOS expose
non-streaming `channelAgents` route/status APIs and intentionally report the
stream pump wrapper as unavailable in v1. The Flutter SDK currently includes
the first-party convenience `QqBotChannelProvider`, which stores
credentials in the host app, connects to QQBot AccessToken/Gateway/OpenAPI
surfaces, maps message events into Napaxi ingress, and leases outbound messages
for QQ delivery. The Flutter demo only provides setup/status UI over these SDK
APIs. See
[`channel-provider-architecture.md`](channel-provider-architecture.md).

## Core Concepts

`ChannelSurfaceKind` describes the broad interaction surface:

- `im`: user/account/chat surfaces such as DMs, groups, rooms, and threads.
- `device`: paired peripherals or local devices.
- `app`: host app surfaces such as in-app chat, notification taps, or widgets.
- `system`: OS or automation-originated ingress.
- `custom`: host-defined surfaces that still use the common contract.

`ChannelEndpointKind` describes the route endpoint:

- `direct`: one sender or peer.
- `group`: multi-person conversation with mention/access policy.
- `room`: shared room/channel where background context may be observed.
- `thread`: sub-thread under a parent conversation.
- `broadcast`: fan-out target controlled by the host.
- `device`: local device or peripheral endpoint.
- `custom`: host-defined endpoint.

`ChannelModality` describes payload shape:

- `text`, `audio`, `image`, `file`, `control`, `sensor`, `presence`.

`ChannelContentFormat` describes how text should be presented:

- `plain_text`: default for host-authored sends and unsupported providers.
- `markdown`: model/provider-authored rich text that the platform may render.

IM channels normally use `surface_kind = "im"` and start with `text`; media
support is declared as additional modalities. Device channels use the same
fields; for example a headset can be `surface_kind = "device"`,
`endpoint_kind = "device"`, and `modalities = ["audio", "text", "control",
"presence"]`.

## Registration Shape

The existing public API accepts arbitrary JSON and remains backwards
compatible:

```json
{
  "name": "telegram",
  "type": "telegram"
}
```

New channel-aware hosts should include route metadata:

```json
{
  "name": "work-telegram",
  "type": "telegram",
  "surface_kind": "im",
  "account_id": "work",
  "endpoint_kind": "direct",
  "modalities": ["text", "image", "file"],
  "content_formats": ["plain_text", "markdown"],
  "transport": "bot_api",
  "config": {
    "allow_from": ["tg:123456"]
  }
}
```

Core persists the original config and projects stable metadata into the channel
record:

- `name`
- `type`
- `surface_kind`
- `endpoint_kind`
- `modalities`
- `content_formats`
- `transport`
- `capability_id`
- `registered_at`
- `updated_at`

Known IM `type` values infer `surface_kind = "im"` when the host omits the
field. Custom IM bridges should set `surface_kind` explicitly.

Recommended first-party IM names:

- `qqbot`: QQ Bot API adapter, available as Flutter SDK
  `QqBotChannelProvider`.

Future first-party or host-provided IM names should use stable provider ids
such as `feishu`, `lark`, `wechat`, or host-specific reverse-domain names.

## Ingress Contract

Platform adapters submit inbound messages with `submitInbound` /
`channel.submit_inbound`:

```json
{
  "channel_name": "feishu",
  "account_id": "main",
  "platform_message_id": "om_123",
  "peer": {
    "kind": "group",
    "id": "oc_group",
    "display_name": "Ops"
  },
  "sender": {
    "id": "ou_user",
    "display_name": "Alice",
    "is_bot": false
  },
  "thread_id": "om_root",
  "text": "ship status?",
  "media": [
    {
      "kind": "image",
      "uri": "file:///adapter/cache/image.png",
      "mime_type": "image/png"
    }
  ],
  "raw": {
    "provider_event_type": "im.message.receive_v1"
  }
}
```

The response is an accepted receipt:

```json
{
  "accepted": true,
  "id": "in_1781160000000000_1",
  "duplicate": false
}
```

`platform_message_id` is the idempotency key within
`channel_name/account_id/peer`. Re-delivery of the same platform event returns
the original Napaxi id with `duplicate = true`.

Host runtimes can take inbound work with `takeInbound(channelName, limit)`.
Taking marks matching `queued` items as `leased`. After processing, the host
calls `ackInbound(inboundId)`. If processing fails permanently, call
`failInbound(inboundId, error)`; if the host needs another worker to retry,
call `releaseInbound(inboundId)`.

## Channel-Agent Runtime

Provider adapters do not decide which agent receives a message. They submit
normalized ingress only. Core resolves the route with this precedence:

1. Exact peer/thread route.
2. Channel default route.
3. Bridge default agent.

The default session policy is `stable_by_peer_or_thread`. Core builds a stable
UUID v5-style thread id from `channel_name`, `session_account_id`, `agent_id`,
`channel_account_id`, peer kind, and `thread_id` or `peer_id`/`sender_id`. That
means one QQ direct chat or group lands in the same Napaxi session across app
restarts, while different agents/accounts/channels stay isolated.

The user-visible history message stores only display text. The model-facing
input includes channel, peer, sender, and platform message context so the agent
can reason about where the request came from without polluting the session list
with raw platform ids.

When a turn emits `asking_human`, core records a pending mapping from
`request_id` to the session and original channel route, sends the question back
through the same channel, and acknowledges the original inbound. A later inbound
from the same stable session is treated as the human answer and passed to
`answer_human_request`; the original run then continues and its final response
is queued back to the answer message's route.

## Outbound Contract

Hosts enqueue outbound delivery with `enqueueOutbound` /
`channel.enqueue_outbound`, or use `replyInbound(inboundId, reply)` to reuse
the original inbound route:

```json
{
  "channel_name": "qqbot",
  "account_id": "bot-a",
  "peer": {
    "kind": "direct",
    "id": "openid-a"
  },
  "reply_to_message_id": "msg_123",
  "thread_id": "topic_1",
  "text": "green",
  "format": "plain_text",
  "media": []
}
```

`format` defaults to `plain_text` when omitted. Core channel-agent replies and
ask-human questions use `markdown` so model output keeps formatting until the
provider decides whether the platform supports it. Error/fallback system
messages use `plain_text`.

Provider fallback is platform-owned. A provider that cannot render `markdown`
must send a safe plain-text body instead of interpreting Markdown itself. The
QQBot provider maps direct/group Markdown to the official QQBot Markdown send
shape (`msg_type = 2` with `markdown.content`) and falls back to plain text only
for clear 4xx format/capability errors.

Adapters call `leaseOutbound(channelName, accountId, limit)`, deliver the
leased messages through their native platform API, then call:

- `ackOutbound(outboundId, receipt)` after native send succeeds.
- `failOutbound(outboundId, error)` after native send fails.

Outbound messages carry `status` values `queued`, `leased`, `sent`, and
`failed`. Adapters should only send `queued` messages they leased themselves.

## Capability Contract

`napaxi.channel.im` and `napaxi.channel.device` are `service` capabilities with
`activation = "host"` and `default_enabled = false`.

Hosts must declare and enable the matching capability before exposing real
ingress or egress:

```json
{
  "platform": "android",
  "supported_capabilities": ["napaxi.channel.im", "napaxi.channel.device"]
}
```

```json
{
  "enabled_capabilities": ["napaxi.channel.im", "napaxi.channel.device"]
}
```

Required host responsibilities:

- `host_channel_adapter`: host owns provider SDKs, webhooks, sockets, QR login,
  app permissions, and background constraints.
- `channel_identity_policy`: host supplies stable sender/account/endpoint ids
  and honors pairing or allowlists.
- `reply_route_dispatcher`: host can deliver core-approved output to the
  recorded route.
- `host_device_channel_adapter`: for device channels, host owns Bluetooth,
  microphone, speaker/TTS, foreground-service, and user-visible device state
  handling.

Core responsibilities:

- Store channel registrations.
- Store normalized inbound envelopes and outbound delivery records durably.
- Preserve route metadata and timestamps.
- Preserve idempotency and reply-to route metadata.
- Keep channel ids stable for sessions and audit.
- Gate future channel ingress through capability and policy hooks.
- Route agent output deterministically from session metadata instead of asking
  the model to choose a provider.

## Session And Routing

V1 keeps the existing mobile session key:

```json
{
  "channel_type": "telegram",
  "account_id": "work",
  "thread_id": "..."
}
```

For IM, adapters should derive:

- `channel_type` from the provider or host-private channel type.
- `account_id` from the channel account instance.
- `thread_id` from the direct peer, group, room, thread, or a core-created
  session id when the host cannot expose a stable external id.

Direct messages may share one user-facing session in simple single-user hosts,
but multi-user hosts should isolate by channel/account/peer. Group and room
traffic should default to isolated sessions and explicit mention or activation
policy.

Future work may add first-class route records such as `last_channel`,
`last_account_id`, `last_endpoint_id`, and `last_transport` so a session can be
re-docked to another linked channel without changing transcript history.

## Peripheral Extension Point

Device and peripheral channels use the same provider contract as IM channels.
V1 includes the SDK Bluetooth audio-device provider shell and core
`napaxi.channel.device` capability. Native Bluetooth/audio transports remain
adapter or host implementations; the Flutter Android adapter provides the first
SDK-owned implementation for the Bluetooth audio-device path.

Examples:

```json
{
  "name": "daily-headset",
  "type": "bluetooth_headset",
  "surface_kind": "device",
  "endpoint_kind": "device",
  "modalities": ["audio", "text", "control", "presence"],
  "content_formats": ["plain_text", "markdown"],
  "transport": "bluetooth_headset_host_audio"
}
```

```json
{
  "name": "car-display",
  "type": "car_head_unit",
  "surface_kind": "device",
  "endpoint_kind": "device",
  "modalities": ["text", "audio", "control"],
  "transport": "android_auto"
}
```

Peripheral adapters must remain host-carried because Android/iOS own Bluetooth,
microphone, nearby-device, notification, CarPlay/Android Auto, and background
execution constraints. Core should receive normalized events and return
approved replies or actions.

## Open Questions

- Whether to promote `channel` from a `service` capability to its own
  `CapabilityKind` after V1.
- Whether inbound leases should gain timeout/requeue semantics once background
  execution and retry policy are finalized.
- How much route state should live in session records versus channel records.
- Which pairing policy is the mobile default for real IM providers:
  `pairing`, `allowlist`, or host-controlled policy.

## References

- OpenClaw Gateway architecture:
  https://docs.openclaw.ai/concepts/architecture
- OpenClaw channel routing:
  https://docs.openclaw.ai/channels/channel-routing
- OpenClaw session management:
  https://docs.openclaw.ai/concepts/session
- OpenClaw channel docking:
  https://docs.openclaw.ai/concepts/channel-docking
