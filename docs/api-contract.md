# API Contract & Error Model

This document describes the two-layer contract that `crates/core/src/api/`
exposes to SDK adapters, and the structured error model that crosses that
boundary.

## Two contract layers

`napaxi_core::api` exposes adapter-facing behavior through two parallel
layers. Both layers reach the same underlying runtime — the typed layer is a
thin wrapper, not a separate engine.

### 1. JSON / handle layer (legacy bridge surface)

Functions whose names end in `_handle` take an `i64` engine handle and
JSON `&str` payloads. They return `bool`, `String` (often JSON), or
`Option<String>`. Examples:

```rust
napaxi_core::api::engine::update_config_handle(handle, &config_json) -> bool
napaxi_core::api::engine::get_config_handle(handle) -> String
napaxi_core::api::engine::delete_agent_handle(handle, agent_id) -> bool
napaxi_core::api::engine::cancel_session_handle(handle, session_key_json) -> bool
```

These are kept stable for `packages/api_bridge/` (FRB/FFI) and for any
adapter already wired through them. Failure information is collapsed into
the legacy return shape; the underlying error is logged through
`tracing::warn!` with structured `error/code` fields.

### 2. Typed layer (preferred for new adapters)

Functions whose names end in `_typed` return `CoreResult<T>` and use
strongly-typed receivers such as `EngineHandle`. Examples:

```rust
use napaxi_core::api::engine::EngineHandle;
use napaxi_core::api::error::{CoreError, CoreResult};

let engine = EngineHandle::new(raw_handle);

engine.update_config(&config_json)?;          // CoreResult<()>
let cfg = engine.config_json()?;              // CoreResult<String>
engine.delete_agent(agent_id)?;                // CoreResult<()>
let was_active = engine.cancel_session(key)?;  // CoreResult<bool>

// Or via free functions:
napaxi_core::api::engine::update_config_handle_typed(raw_handle, &json)?;
```

Adapters that need to branch on failure mode should call the typed layer
and inspect `error.code()`.

## Error model

### Umbrella enum

`napaxi_core::error::CoreError` (re-exported as `napaxi_core::api::error::CoreError`)
is what crosses module boundaries. Domain enums lift into it via `#[from]`:

```text
StorageError ──┐
LlmError      ──┤
ToolError     ──┼──> CoreError
McpError      ──┤
CapabilityError ┘
```

Domain modules continue to use their domain enum internally
(e.g. `Result<T, StorageError>` inside `crates/core/src/storage/`); the
umbrella appears only at the cross-domain boundary, usually inside
`api/*` or in `runtime/*` handle wrappers.

### Wire envelope

`CoreError::to_wire_json()` produces a stable envelope adapter bridges can
serialize over FFI/FRB:

```json
{ "error": { "code": "invalid_handle", "message": "invalid engine handle: 0" } }
```

`code` is a stable short identifier suitable for adapter branching.
`message` is human-readable and may change.

### Stable error codes

| Code                          | Source                          | Meaning                                                         |
| ----------------------------- | ------------------------------- | --------------------------------------------------------------- |
| `invalid_handle`              | `CoreError::InvalidHandle`      | Engine handle is stale or never registered                      |
| `invalid_input`               | `CoreError::InvalidInput`       | Caller supplied an unrecoverable value (e.g. default agent ID)  |
| `config`                      | `CoreError::Config`             | Failed to parse or apply runtime config                         |
| `cancelled`                   | `CoreError::Cancelled`          | Session/turn was cancelled                                      |
| `lock_poisoned`               | `CoreError::LockPoisoned`       | Internal mutex poisoned by an earlier panic                     |
| `serialization`               | `CoreError::Serialization`      | JSON encode/decode failure                                      |
| `other`                       | `CoreError::Other`              | Transitional bucket for unmigrated `anyhow::Error` call sites   |
| `storage_io`                  | `StorageError::Io`              | Filesystem error during a storage operation                     |
| `storage_not_found`           | `StorageError::NotFound`        | Path does not exist                                             |
| `storage_outside_sandbox`     | `StorageError::OutsideSandbox`  | Path resolves outside the sandbox                               |
| `storage_attachment`          | `StorageError::Attachment`      | Attachment metadata could not be normalized                     |
| `storage_decode`              | `StorageError::Decode`          | Stored payload failed to deserialize                            |
| `llm_http`                    | `LlmError::Http`                | Transport-level HTTP failure talking to a provider              |
| `llm_provider`                | `LlmError::Provider`            | Provider returned an error status / body                        |
| `llm_decode`                  | `LlmError::Decode`              | Provider response did not match the expected shape              |
| `llm_stream_truncated`        | `LlmError::StreamTruncated`     | SSE stream ended before the completion marker                   |
| `llm_cancelled`               | `LlmError::Cancelled`           | Turn cancelled by the host                                      |
| `llm_config`                  | `LlmError::Config`              | Missing API key, model, or other config required by the route   |
| `tool_not_found`              | `ToolError::NotFound`           | No tool registered for the requested name                       |
| `tool_invalid_params`         | `ToolError::InvalidParams`      | Tool received malformed parameters                              |
| `tool_execution`              | `ToolError::Execution`          | Tool ran but failed                                             |
| `tool_not_admitted`           | `ToolError::NotAdmitted`        | Capability policy denied tool invocation                        |
| `mcp_transport`               | `McpError::Transport`           | MCP server transport-layer failure                              |
| `mcp_oauth`                   | `McpError::OAuth`               | MCP OAuth handshake failed                                      |
| `mcp_server_not_found`        | `McpError::ServerNotFound`      | MCP server ID not registered                                    |
| `mcp_protocol`                | `McpError::Protocol`            | MCP message violated protocol expectations                      |
| `capability_not_registered`   | `CapabilityError::NotRegistered`| Capability ID is not compiled into this SDK build               |
| `capability_not_available`    | `CapabilityError::NotAvailable` | Host platform does not satisfy capability requirements          |
| `capability_not_enabled`      | `CapabilityError::NotEnabled`   | Capability is available but not selected by runtime config      |
| `capability_denied`           | `CapabilityError::Denied`       | Policy chain rejected the capability for this invocation        |

### LLM error classification

The LLM internals continue to use `anyhow::Result` because the error
context chains are valuable for debugging. The typed boundary
(`crate::llm::*_typed`) lifts those errors into `LlmError` using cheap
string matching against well-known patterns:

| Pattern (in `anyhow::Error.to_string()`)      | Mapped variant                       |
| --------------------------------------------- | ------------------------------------ |
| exact `"Chat cancelled"`                      | `LlmError::Cancelled`                |
| contains `"stream ended"` / `"stream failed before"` | `LlmError::StreamTruncated`   |
| contains `"did not contain"`                  | `LlmError::Decode`                   |
| otherwise                                     | `LlmError::Provider { status: 0, message }` |

## Migration guidance

- **Inside a domain module**: use the domain error type
  (`StorageError`, `LlmError`, ...), keep `?` chains short, only convert
  to `CoreError` at the module boundary.
- **At a cross-domain or `api/*` boundary**: return `CoreResult<T>`;
  domain errors lift automatically via `#[from]`.
- **In bridge code (`packages/api_bridge/`)**: prefer matching on the
  typed boundary and emitting `to_wire_json()` to the host. Legacy
  `bool`/`String` returns remain available while bridges migrate one
  function at a time.
- **`CoreError::Other(anyhow::Error)`**: transitional. Existing call
  sites that return `anyhow::Result` can lift into `CoreResult` with
  `?` until they grow a more specific variant.

## Where to look

- `crates/core/src/error.rs` — the two-layer enum definitions and the
  wire envelope
- `crates/core/src/api/error.rs` — adapter-visible re-exports
- `crates/core/src/api/engine.rs` — the `EngineHandle` typed contract
  sample
- `crates/core/src/llm/mod.rs` (typed boundary section) — the
  `anyhow → LlmError` classifier
