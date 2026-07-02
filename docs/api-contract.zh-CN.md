# API Contract 与错误模型

本文件是 [`api-contract.md`](api-contract.md) 的中文 companion，说明 `crates/core/src/api/` 暴露给 SDK adapter 的两层 contract，以及跨边界的结构化错误模型。

## 两层 contract

`napaxi_core::api` 通过两层接口暴露 adapter-facing 行为。两层都访问同一个 runtime；typed layer 只是更安全的薄封装，不是另一套 engine。

### JSON / handle layer

函数名通常以 `_handle` 结尾，接收 `i64` engine handle 和 JSON 字符串，返回 `bool`、`String` 或 `Option<String>`。例如：

```rust
napaxi_core::api::engine::update_config_handle(handle, &config_json) -> bool
napaxi_core::api::engine::get_config_handle(handle) -> String
napaxi_core::api::engine::cancel_session_handle(handle, session_key_json) -> bool
```

这一层用于保持 `packages/api_bridge/` 以及既有 adapter 兼容。错误信息会被压缩进 legacy return shape，详细错误通过 tracing 记录。

### Typed layer

函数名通常以 `_typed` 结尾，返回 `CoreResult<T>`，并使用 `EngineHandle` 等强类型 receiver。新 adapter 建议优先使用 typed layer：

```rust
use napaxi_core::api::engine::EngineHandle;

let engine = EngineHandle::new(raw_handle);
engine.update_config(&config_json)?;
let cfg = engine.config_json()?;
let was_active = engine.cancel_session(key)?;
```

需要根据失败类型分支的 adapter，应使用 typed layer 并检查 `error.code()`。

## 错误模型

`napaxi_core::error::CoreError` 是跨模块和 adapter 边界的 umbrella enum，并通过 `napaxi_core::api::error::CoreError` 重新导出。

Domain error 会提升为 `CoreError`：

```text
StorageError ──┐
LlmError      ──┤
ToolError     ──┼──> CoreError
McpError      ──┤
CapabilityError ┘
```

模块内部仍使用 domain error；跨 `api/*` 或 runtime handle 边界时再转换为 `CoreError`。

## Wire envelope

`CoreError::to_wire_json()` 会生成稳定 JSON envelope：

```json
{ "error": { "code": "invalid_handle", "message": "invalid engine handle: 0" } }
```

- `code` 是稳定短标识，用于 adapter 分支。
- `message` 面向人类阅读，可能随版本变化。

常见 error code：

| Code | 含义 |
| --- | --- |
| `invalid_handle` | Engine handle 无效或已过期。 |
| `invalid_input` | 调用方传入不可恢复的非法值。 |
| `config` | runtime config 解析或应用失败。 |
| `cancelled` | session/turn 被取消。 |
| `serialization` | JSON 编解码失败。 |
| `storage_*` | 文件、sandbox、attachment 或持久化错误。 |
| `llm_*` | LLM transport、provider、decode、stream 或 config 错误。 |
| `tool_*` | tool 未找到、参数错误、执行失败或 admission 被拒。 |
| `mcp_*` | MCP transport、OAuth、server 或 protocol 错误。 |
| `capability_*` | capability 未注册、不可用、未启用或被 policy 拒绝。 |

完整列表见英文规范。

## 迁移建议

- Domain module 内部使用 domain error。
- Cross-domain 或 `api/*` 边界返回 `CoreResult<T>`。
- Bridge code 优先匹配 typed boundary，并将错误序列化为 wire envelope。
- `CoreError::Other(anyhow::Error)` 是过渡形态，新代码应逐步使用更具体错误。

## 相关代码

- `crates/core/src/error.rs`
- `crates/core/src/api/error.rs`
- `crates/core/src/api/engine.rs`
- `packages/api_bridge/`
