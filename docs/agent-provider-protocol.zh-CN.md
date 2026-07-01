# Agent Provider Protocol

本文件是 [`agent-provider-protocol.md`](agent-provider-protocol.md) 的中文 companion，面向希望把 App 自有能力暴露给 Napaxi host 的 provider app 团队。

## 角色

- **Host**：拥有 Agent runtime、proposal 创建、capability policy 和 model tool loop。
- **Provider app**：拥有用户确认、登录态、风控、业务执行和可信 result。
- **Agent Provider SDK**：帮助 provider app 定义 package、解析 handoff intent、校验 proposal、构造 result。

SDK 不提供静默跨 App 执行，也不存储 provider credentials。

## Package

Provider app 声明一个 `AgentPackage`，其中包含一个或多个 action：

```json
{
  "provider_id": "provider.test",
  "agent_id": "provider.agent",
  "display_name": "Provider Agent",
  "actions": [
    {
      "action_id": "provider.order.create",
      "tool_name": "app_action_provider_order_create",
      "risk": "high",
      "confirmation_policy": "provider_required",
      "execution_modes": ["app_handoff"],
      "timeout_seconds": 600
    }
  ]
}
```

Provider action tool name 继续使用 `app_action_` 前缀，便于 host admission 映射到编译期 Agent App Action capability。

## Android install handoff

Provider apps 暴露两个 Android entry points：

- Install entry：接收 trusted install request，返回 `AgentPackage`。
- Action entry：接收已安装并绑定身份后的 `ActionProposal`。

Install intent：

- Action: `agent.provider.action.INSTALL_AGENT`
- Request extra: `agent.provider.extra.INSTALL_REQUEST_JSON`
- Result extra: `agent.provider.extra.INSTALL_RESULT_JSON`

Protocol v2 install request 会包含 `host_signing_cert_sha256`、`host_instance_id` 和 `host_shared_secret`，用于 trusted proposal signing。

Provider 可使用：

```kotlin
val request = AgentProvider.parseInstallRequest(intent) ?: return
setResult(
    Activity.RESULT_OK,
    AgentProvider.buildInstallResultIntent(packageDef, request),
)
finish()
```

Host 不信任 provider 返回的 `install_binding`，而是从 Android 系统读取 package name、action Activity 和 signing certificate digest，并写入 trusted binding。

## Android action handoff

Host 发送：

- Action: `agent.provider.action.HANDLE_PROPOSAL`
- Proposal extra: `agent.provider.extra.PROPOSAL_JSON`
- Optional package/action extras

Provider 先做基础 schema validation：

```kotlin
val proposal = AgentProvider.parseProposal(intent) ?: return
val validation = AgentProvider.validateProposal(
    proposal = proposal,
    packageDef = packageDef,
    nowMillis = System.currentTimeMillis(),
)
```

对 silent、quiet、高风险或 no-UI action，必须使用 trusted validation：

```kotlin
val trust = AgentProviderSecurity.validateTrustedProposal(
    activity = this,
    proposal = proposal,
    packageDef = packageDef,
    store = TrustedHostStore(this, providerId),
    nowMillis = System.currentTimeMillis(),
)
```

Trusted validation 会检查 Android caller package/signature、proposal HMAC signature、expiry、nonce/idempotency 和 replay store。

## Result return

Provider app 通过 Activity result 或 callback URI 返回 `ActionResult`：

```kotlin
val result = ActionResult(
    requestId = proposal.requestId,
    status = ActionResultStatus.SUCCEEDED,
    resultJson = """{"order_id":"order-1"}""",
    completedAt = Instant.now().toString(),
)
setResult(Activity.RESULT_OK, AgentProvider.buildResultIntent(result))
finish()
```

Host 应把 callback 绑定到原 pending proposal，避免错配或重放。

## Provider 应拒绝的情况

- `provider_id`、`agent_id`、`action_id` 与 package 不匹配。
- `tool_name` 不匹配 action。
- `expires_at` 无效或已过期。
- `nonce` 或 `idempotency_key` 缺失。
- trusted execution 被请求，但 host binding、caller signature、proposal signature 或 replay check 失败。

High 和 critical risk actions 应由 provider 自己进行用户确认。Host confirmation 不能替代 provider confirmation。

## Ownership

- `packages/agent_provider/android/`
- `packages/agent_provider/ios/`
- `crates/core/` 和 host adapters 继续拥有 Agent runtime、proposal lifecycle、capability policy 和 result broker。
