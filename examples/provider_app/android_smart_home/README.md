# Smart Home Provider Demo

A virtual smart-home dashboard (lights + a Yeelight Cube 20×5 pixel matrix) that
demonstrates the **two distinct ways an Android app integrates with napaxi**.
Most apps only need one of them; this demo shows both side by side so the
boundary is clear.

## Two integration modes

| | Local embedded SDK | Provider protocol |
|---|---|---|
| Dependency | `com.napaxi:android` (`NapaxiEngine`) | `agent.provider:android_agent_provider` |
| Who runs the agent | this app, in-process | an **external** napaxi host app |
| Entry point | `SmartHomeAgentRuntime` | `SmartHomePackage` + `AgentInstallActivity` + `AgentActionActivity` |
| What it does | configures an LLM, registers light tools, runs the chat loop locally | exposes app-owned actions to a host that creates auditable `ActionProposal`s |
| Trigger | the in-app assistant panel | host install/handoff intents, or background triggers |

### Local embedded SDK

`SmartHomeAgentRuntime` creates a `NapaxiEngine`, registers the light tools, and
collects `sendToSessionFlow()` into a single `HomeAgentResponse`. The outcome
type is driven by **what actually happened** in the turn (a real tool result →
`LOCAL_ACTION`; plain text → `STATUS`; error → `CLARIFICATION`).

There is **no keyword routing**. Every user message goes to the local engine.
When a request is beyond local light control (cross-device automation, devices
this app doesn't expose, or judgement that needs a broader agent), the model
itself calls the `request_napaxi_collaboration` tool. Only then does the UI offer
a **"交给 Napaxi"** button that hands the context off through the provider
protocol below.

### Provider protocol

When an external napaxi host is connected (via `AgentInstallActivity`), the host
can send `ActionProposal`s to `AgentActionActivity`, which validates the trusted
proposal, optionally confirms with the user, executes it, and returns a signed
`ActionResult`. `SmartHomeTriggerBridge` submits background triggers the other
direction. See `docs/agent-provider-protocol.md` for the wire contract.

## Single source of truth for lights

`LightCatalog.kt` is the **only** place the supported lights are declared. Both
integration modes generate their tool/action parameter schemas and their system
prompts from it (`SmartHomeAgentRuntime` and `SmartHomePackage`), so the two
paths can never drift apart. Adding a light = editing `LightCatalog.lights`.

## Demo-only shortcuts (not production patterns)

- **Mijia notification bridge** (`AIniceEventBridge`, `MijiaNotificationBridgeService`):
  parses Xiaomi Mijia notification text with Chinese keyword heuristics to
  synthesize geofence/presence events. This is a demo convenience — a production
  integration should consume structured events, not scrape notifications.
- **Credentials**: the model API key is cached and stored in plain
  `SharedPreferences` for brevity. Use `EncryptedSharedPreferences` / Keystore in
  a real app. (The engine cache key uses a redacted fingerprint, not the raw key.)
- **Yeelight LAN** (`YeelightLanClient`): optional real-device control over the
  Yeelight LAN protocol; leave it disabled to stay fully virtual.

## Running

```bash
cd examples/provider_app/android_smart_home
./gradlew assembleDebug
```

The build pulls the napaxi SDKs from local source via `includeBuild` +
`dependencySubstitution` (see `settings.gradle.kts`).

In the app:

1. Tap **助手 → 模型** to configure provider / base url / model / api key.
2. Say a request, e.g. *“打开客厅落地灯”* — handled locally by the embedded SDK.
3. Ask something beyond lights, e.g. *“我家空调能联动吗”* — the agent calls
   `request_napaxi_collaboration` and a **交给 Napaxi** button appears.
4. Tap **连接** to install the provider agent into a running napaxi host, then use
   **交给 Napaxi** or the geofence test to exercise the provider protocol path.
