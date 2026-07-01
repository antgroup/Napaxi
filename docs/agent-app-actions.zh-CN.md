# Agent App Actions

本文件是 [`agent-app-actions.md`](agent-app-actions.md) 的中文 companion，说明 Napaxi host 侧如何把用户意图转成可审计的 `ActionProposal`，再交给连接的 app/backend 执行。

## 核心流程

Napaxi 不让模型直接静默执行外部业务动作。模型调用 action tool 后，core 会：

1. 创建并持久化 `ActionProposal`。
2. 将 proposal 交给 host dispatcher。
3. 由连接的 app/backend 完成确认、风控和执行。
4. 接收并校验 `ActionResult`。
5. 将 tool result 回到模型循环，由 Agent 生成最终自然语言回复。

## Capability

Agent App actions 由一个编译期 capability 承载：

```text
napaxi.tool.agent_app_action
```

默认属性：

- `kind`: `tool`
- `activation`: `host`
- `risk`: `high`
- `requirements`: `host_action_dispatcher`、`provider_confirmation_for_high_risk`

Host 必须在 capability profile 和 selection 中声明并启用它。Flutter 在 `NapaxiEngine.create(agentAppActionExecutor: ...)` 被提供时自动处理。Android Activity context 可安装默认 provider action dispatcher；非 Activity context 应提供自定义 executor。

## Package

`AgentAppPackage` 将 provider action data 绑定到一个 Agent。注册 package 后，core 会持久化 package，并创建或更新对应 `AgentDefinition`。一次 turn 中，只有当前 Agent 的 package actions 会暴露为 tool descriptors。

Provider actions 是 package data，不是动态 native plugin。Action tool name 必须使用 `app_action_` 前缀，以便 admission 映射到 `napaxi.tool.agent_app_action`。

## Proposal 与 Result

`ActionProposal` 包含：

- `request_id`
- `nonce`
- `idempotency_key`
- `created_at`
- `expires_at`
- risk 和 confirmation policy

这些字段用于恢复 app handoff、系统挂起、延迟 callback，并防止重放。

Android provider 若使用 protocol v2 trust fields，core 会对 proposal 做 `hmac-sha256-v1` 签名。Host dispatcher 不应把 shared secret 发给 provider action Activity。

`ActionResult` 会被 core 校验：

- proposal 必须存在。
- 成功 result 不能在 proposal 过期后接收。
- 已终态 proposal 不接受重复成功结果。
- result 持久化后再作为 tool result 回到模型循环。

## Events

UI、debug view 和后台通知可以订阅生命周期事件：

- `action_proposal_created`
- `action_handoff_started`
- `action_waiting_for_provider`
- `action_result_received`
- `action_expired`
- `action_failed`

## Ownership

- `crates/core/src/capabilities/`：capability definition 和 tool name mapping。
- `crates/core/src/agents/agent_app.rs`：package store、action descriptors、proposal persistence、result broker、dispatcher 调用。
- `crates/core/src/runtime/`：per-Agent tool composition 和 capability-gated flow。
- `crates/core/src/api/agent_app.rs`：adapter-neutral APIs。
- `packages/flutter/lib/`、`packages/android/`、`packages/ios/`：平台 SDK model 和 wrapper。

Demo apps 可以安装 mock packages 和 mock dispatchers，但可复用 policy 与 runtime 行为必须留在 core 或 SDK packages。
