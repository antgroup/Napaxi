# Capability Admission

本文件是 [`capability-admission.md`](capability-admission.md) 的中文 companion，说明 Napaxi 如何用 capability gate 控制 provider、tool、MCP、platform tool 和 service entry。

## 概念

Capability 是 SDK 中的一等扩展点。每个 LLM provider、built-in tool、MCP tool 和 platform tool 都有一个 capability definition，包含：

- 稳定 `napaxi.*` id。
- kind，例如 `llm_provider`、`tool`、`platform_tool`、`mcp`、`policy`、`service`。
- risk level：low、medium、high、critical。
- activation：always、config、host、policy。

Capability 状态：

1. **Registered**：已编译进 SDK binary。
2. **Available**：当前 platform 和 host capability profile 满足要求。
3. **Enabled**：runtime config 或 selection 允许它参与运行。

未 enabled 的 capability 不会参与 tool descriptors、provider routing 或 invocation。

## Admission gates

核心 gate 类型：

| Gate kind | 时机 |
| --- | --- |
| `Descriptor` | 构造暴露给 LLM 的 tool list 前。 |
| `Invocation` | LLM 选择 tool 后、执行前。 |
| `Provider` | 打开 LLM provider session 前。 |
| `AgentEngine` | 选择处理 turn 的 agent engine 时。 |
| `Service` | service capability 的入口或执行面被触发时。 |

任意 policy hook 返回 `Deny` 都会短路执行。

```text
Tool/provider/MCP call
        │
        ▼
  require_enabled?
        │
        ▼
  policy chain
        │ allow / deny
        ▼
 execute or CapabilityError::Denied
```

## Policy hook

Host 可以通过 `napaxi_core::api::capability::register_policy_hook` 注册 policy hook。Hook 是 process-global 的，返回的 `PolicyHookGuard` 控制生命周期。

示意：

```rust
let guard = register_policy_hook(Arc::new(|admission| {
    if admission.subject.starts_with("external_") {
        CapabilityAdmissionDecision::Deny("blocked by host policy".into())
    } else {
        CapabilityAdmissionDecision::Allow
    }
}));
```

## Admission trace

Admission decision 会记录到 ring buffer。Engine 操作期间，trace 会写入该 engine 自己的 buffer；脱离 engine scope 的记录会进入 process-global fallback buffer。

Adapter UI 可以使用 trace 展示：

- 哪个 capability 被访问。
- gate 类型。
- subject。
- allow/deny。
- reason。

## 新增 capability

1. 在 `crates/core/src/capabilities/` 定义稳定 `napaxi.*` id、kind、version、risk、requirements、activation。
2. 如果有新的 tool/provider 命名族，加入 capability id 映射。
3. 在 runtime 路径中确保 IO 或执行前运行 admission。
4. 更新 [`mobile-capabilities.zh-CN.md`](mobile-capabilities.zh-CN.md)。

## Shell command safety

Shell 安全判断需要 allow / prompt / deny 三态，因此与二态 admission decision 分开。Capability admission 只决定 shell tool 是否可用；具体命令是否执行由 shell tool 自身安全层判断。
