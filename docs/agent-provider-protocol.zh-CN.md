# Agent Provider Protocol

本文件是 [`agent-provider-protocol.md`](agent-provider-protocol.md) 的中文 companion，面向希望把 App 自有能力暴露给 Napaxi host 的 provider app 团队。

## 角色

- **Host**：拥有 Agent runtime、proposal 创建、capability policy 和 model tool loop。
- **Provider app**：拥有用户确认、登录态、风控、业务执行和可信 result。
- **Agent Provider SDK**：帮助 provider app 定义 package、解析 handoff intent、校验 proposal、构造 result。

SDK 不提供静默跨 App 执行，也不存储 provider credentials。

## 显式 Provider 选择

Host 可以让当前默认 Agent 在单轮消息中使用指定 Provider，而不切换
Agent。规范化消息前缀是：

```text
@{provider:<provider_id>} <用户请求>
```

Core 会在准备工具前解析并移除该前缀，只挂载该 Provider 的 actions，
同时把 `@<display_name>` 保留在会话历史中。Flutter、Android 和 iOS SDK
都提供 `AgentProviderSelection` 构造这一单轮选择。选择不会延续到下一条
消息，也不会更改当前 Agent、会话或 memory scope。
可读名称只有在唯一时才会解析；如果多个 Provider 显示名相同，Core 会
返回包含 canonical provider ids 的歧义错误，不会任意选中一个。canonical
`provider_id` 未安装或未启用时，也会在模型执行前直接失败。

为兼容 V2，Provider package 仍携带 legacy `agent_id`，Proposal 也继续以
它完成 Provider 侧校验；但注册 Provider 不再创建 `AgentDefinition`，调用
动作的是当前默认 Agent。Package 按 `provider_id` 保存，旧版 Agent-keyed
文件会在读取时迁移。

## Napaxi 端上生成的 Provider App

`android-apk-build` 技能生成的新 Android App 默认包含
`assets/agent-app.json`、可信安装入口和 Action Activity。可复用的调用方
证书、HMAC、过期时间、nonce、幂等和重放校验由无第三方依赖的 Java
Lite SDK 提供，生成 App 不能复制或重写这些安全逻辑。

生成的 Action Activity 从 bundled templates 开始，并统一通过
`AgentProviderActionRegistry` 路由。构建校验器会检查每个 package action
都有且只有一个源码注册。新 App 默认开启 Provider，用户可以显式关闭，
旧版没有 Provider 声明的项目仍然可以重建。

生成 App 的 UI 和 Action Activity 必须调用同一个 domain service。High
和 critical risk 动作必须在 Provider App 内展示确认 UI。安装 APK 后，
Host 通过现有 discovery API 找到 Provider，用户确认启用后再进行可信
安装握手；APK 安装不能等同于静默授权。

Napaxi 产品端的 V1 用户动线是：

1. 用户在 Napaxi 中描述并生成任意 Android App；生成技能根据实际业务
   产出 Provider package 和 action handler，不绑定记事本等固定领域。
2. 用户通过系统安装器安装 APK。回到 Napaxi 或下次启动时，Host 扫描
   系统中声明 Provider 协议的 App，并询问是否启用。
3. 用户也可以随时进入“设置 → 已连接应用”，查看可连接、已启用或已经
   从系统卸载的 App，执行启用或停用。停用只解除 Napaxi 连接，不卸载
   App，也不删除 App 自有数据。
4. 连接后，用户在消息开头输入 `@`，从已连接且仍安装的 Agent 应用中
   选择；Host 插入 `@<display_name>` 并显式使用该 App。本版不做自然语言
   自动选择，也不改变当前 Agent、会话或 memory scope。

仓库中的 provider 示例只用于协议、构建校验和自动化测试，不是产品验收
所依赖的预装 Demo。完整验收应从 Napaxi 内生成一个新的业务 App 开始。

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
      "display_name": "Create order",
      "localized_display_names": {"zh-CN": "创建订单"},
      "description": "Create a new order in the app.",
      "localized_descriptions": {"zh-CN": "在应用中创建一个新订单。"},
      "risk": "high",
      "confirmation_policy": "provider_required",
      "execution_modes": ["app_handoff"],
      "timeout_seconds": 600
    }
  ]
}
```

为兼容已有 Provider，`display_name`、`localized_display_names` 和
`localized_descriptions` 在协议层仍是可选字段，但新 Provider 应当提供。
Host 会用它们展示 Agent 应用的能力详情；locale key 使用 `zh-CN`、`en` 这类
BCP 47 风格标签，未匹配到本地化内容时回退到 `display_name` 和 `description`。

`confirmation_policy` 仅支持 `none` 和 `provider_required`。Host 与 Lite Provider
SDK 会把历史值 `provider` 兼容归一化为 `provider_required`，保证旧清单仍采用失败
关闭的确认策略；新生成的 Provider 不得继续输出该历史别名，未知值会被拒绝。

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

同一个 Host 安装实例应稳定复用一个 `host_instance_id`，但不同 Provider 仍使用各自独立的 shared secret。若 trusted validation 在业务逻辑执行前返回 `host_not_bound`，Host 可以在 Provider 包/Bundle 身份和签名身份均未变化的前提下，使用原 `host_instance_id` 与原 shared secret 重新发送一次显式 `INSTALL_AGENT`，成功后只重试原 Proposal 一次。第二次失败、Provider 身份变化或用户取消时不得循环恢复，也不得静默信任新的签名身份。

生成的 Android Provider 通过 application metadata `agent.provider.TRUSTED_REFRESH_SUPPORTED=true` 明确允许可信的原地刷新。覆盖安装后，只有系统包名和签名证书仍与 trusted binding 一致、Provider 返回的 `provider_id` 与 `agent_id` 也均未变化时，Host 才能复用原 `host_instance_id`/shared secret 重新握手并把最新 manifest 注册回 Core。Core 持有的自动调用开关和使用记录会保留。versionCode 和 lastUpdateTime 只用于发现更新，不是信任依据；应用缺失或签名/Provider/Agent 身份变化时必须停止展示，并要求显式重新连接。

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

## Android 运行诊断

Napaxi 端上新生成的 Android App 默认包含私有、限量的运行诊断存储。它会
记录未捕获 Java 异常、Android 可提供的历史进程退出原因（包括 ANR 和原生
崩溃）、少量 action 生命周期线索以及结构化运行日志。日志分为 `debug`、
`info`、`warning`、`error` 和 `crash`；默认不采集 `debug`。日志最多保留
300 条或 512 KiB，三天后自动过期，每次向 Host 返回的数据再限制为 256 KiB。
内容会先做基础脱敏，并始终保留在 Provider App 的私有存储中；不会自动进入
对话、记忆、workspace 文件或模型上下文。

Napaxi 在 Agent 应用详情页通过第三个、对模型隐藏的 Android 入口读取：

- Action: `agent.provider.action.GET_DIAGNOSTICS`
- Request extra: `agent.provider.extra.DIAGNOSTICS_REQUEST_JSON`
- Result extra: `agent.provider.extra.DIAGNOSTICS_RESULT_JSON`

诊断协议 v1 支持 `list`、`ack` 和 `configure`；`configure` 只控制 debug
日志，info、warning、error 和 crash 始终保留。请求包含 `provider_id`、
`host_instance_id`、操作、报告 ID 列表、详细日志设置、创建时间、过期时间和 nonce，并用
现有可信 Host binding 的 shared secret 进行 `hmac-sha256-v1` 签名。Provider
返回数据前会验证调用方包名和证书、binding、过期时间及签名。该入口不能
声明为 `AgentPackage.actions`，不能挂载成模型工具，也不能被自然语言路由
自动调用。

生成 App 应记录小而明确的语义事件，而不是复制整段 `logcat`。每条包含模块、
事件名、简短描述、可选 trace id 和有限的结构化字段；同一次用户操作应在 UI、
domain、存储或网络和结果阶段复用 trace id。不得记录凭证、完整请求响应、原始
用户内容或任意 WebView console 输出。

第一版由 Android Lite SDK 和 Flutter Android Host bridge 实现；旧 Android
Provider App 与 iOS 会返回明确的“不支持”，不影响已有 action。

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
