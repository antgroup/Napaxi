# Napaxi Agent Provider SDK

Provider-side SDK for apps exposing Agent App Actions to an Napaxi host.

This package provides platform-specific helper libraries that make it
straightforward for a mobile application to:

1. **Define actions** — Declare an `AgentAppPackage` with named actions, input
   schemas, and display metadata.
2. **Handle install requests** — Validate and respond to install requests from
   the Napaxi host, including trusted install with HMAC signature verification.
3. **Process triggers** — Receive and validate trigger requests (foreground and
   background), build result callbacks, and manage replay protection.

## iOS (Swift)

```swift
import AgentProvider

let pkgJson = AgentProvider.packageToJson(
    AgentAppPackage(
        providerId: "com.napaxi.smartdesk",
        agentId: "desk-agent",
        actions: [
            AgentAppAction(
                id: "adjust_height",
                name: "Adjust Desk Height",
                description: "Raise or lower the standing desk",
            ),
        ]
    )
)

// Validate a proposal from the host
let result = AgentProvider.validateProposal(
    url: incomingURL,
    expectedProviderId: "com.napaxi.smartdesk",
    expectedAgentId: "desk-agent"
)
```

### Trusted Install

```swift
AgentProvider.validateTrustedProposal(
    url: incomingURL,
    expectedProviderId: "com.napaxi.smartdesk",
    expectedAgentId: "desk-agent"
)
```

This performs HMAC-SHA256 signature verification and replay detection on top
of the standard validation.

## Android (Kotlin)

```kotlin
val pkgJson = AgentProvider.packageToJson(
    AgentAppPackage(
        providerId = "com.napaxi.smartdesk",
        agentId = "desk-agent",
        actions = listOf(
            AgentAppAction(
                id = "adjust_height",
                name = "Adjust Desk Height",
            ),
        ),
    ),
)
```

### Background Triggers

```kotlin
val result = AgentProvider.submitBackgroundTrigger(
    context = context,
    actionId = "adjust_height",
    inputJson = """{"height": 120}""",
    agentProviderPackage = "com.napaxi.smartdesk",
    agentActivityClass = SmartDeskActivity::class.java,
)
```

## Validation Parity

The Swift and Kotlin implementations mirror each other's validation logic.
Both enforce:

- Provider/agent/action ID matching
- Nonce and idempotency key presence
- Expiry checking
- HMAC-SHA256 signature verification (trusted install)
- Replay detection via consumed request IDs

See `docs/agent-app-actions.md` and `docs/agent-provider-protocol.md` for the
full protocol specification.

## Related

- [`packages/android`](../android/) — Native Android SDK (host side)
- [`packages/ios`](../ios/) — Native iOS SDK (host side)
- [`docs/agent-provider-protocol.md`](../../docs/agent-provider-protocol.md)