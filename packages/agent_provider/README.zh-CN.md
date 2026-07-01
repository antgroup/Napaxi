# Napaxi Agent Provider SDK

`packages/agent_provider` 是 provider-side SDK，面向希望把 app-owned actions 暴露给 Napaxi host 的应用。

它帮助移动应用：

1. 定义 `AgentAppPackage` 和 action schema。
2. 处理来自 host 的 install request。
3. 校验 foreground/background trigger。
4. 构造可信 `ActionResult`。
5. 做 HMAC signature verification 和 replay protection。

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

let result = AgentProvider.validateProposal(
    url: incomingURL,
    expectedProviderId: "com.napaxi.smartdesk",
    expectedAgentId: "desk-agent"
)
```

Trusted validation 会额外做 HMAC-SHA256 signature verification 和 replay detection。

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

Background trigger：

```kotlin
val result = AgentProvider.submitBackgroundTrigger(
    context = context,
    actionId = "adjust_height",
    inputJson = """{"height": 120}""",
    agentProviderPackage = "com.napaxi.smartdesk",
    agentActivityClass = SmartDeskActivity::class.java,
)
```

## Parity

Swift 和 Kotlin 实现应保持验证逻辑一致：

- provider/agent/action ID matching
- nonce 和 idempotency key presence
- expiry checking
- HMAC-SHA256 signature verification
- replay detection

完整协议见 [`../../docs/agent-provider-protocol.zh-CN.md`](../../docs/agent-provider-protocol.zh-CN.md)。
