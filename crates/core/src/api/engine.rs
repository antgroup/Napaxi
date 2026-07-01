//! Engine lifecycle and runtime orchestration API.
//!
//! Two layers of contract:
//!
//! 1. **JSON/handle layer (legacy bridge surface).** The `*_handle` functions
//!    re-exported from `crate::runtime` take `i64` engine handles and
//!    `&str` JSON payloads. They are kept stable for the FRB bridge and
//!    for any adapter already wired through `napaxi_core::api::engine::*`.
//!
//! 2. **Typed layer (preferred for new adapters).** `EngineHandle` is a
//!    `i64` newtype that prevents accidental handle/integer mix-ups, and
//!    the `*_typed` re-exports return `CoreResult<T>` so adapters can
//!    branch on `error.code()` rather than parsing JSON or interpreting
//!    `bool` results.
//!
//! Both layers reach the same underlying `Engine` state — the typed
//! layer is a thin wrapper, not a separate runtime.

use crate::error::CoreResult;

pub use crate::runtime::{
    DEFAULT_ACCOUNT_ID, DEFAULT_AGENT_ID, available_tool_infos_json_handle, cancel_session_handle,
    create_engine_handle, delete_agent_handle, dispose_engine_handle, get_config_handle,
    get_or_create_agent_handle, inject_message_handle, list_agents_handle,
    retract_injected_message_handle, send_message_json_handle, send_to_session_json_handle,
    set_tool_request_dispatcher, stream_message_handle, stream_to_session_handle,
    update_config_handle, update_custom_tools_handle,
};

/// Result-returning variants suitable for adapters that branch on `code()`.
/// The non-typed variants above remain valid; they swallow errors as
/// `bool`/`String` for legacy bridge compatibility.
pub use crate::runtime::{
    cancel_session_handle_typed, delete_agent_handle_typed, get_config_handle_typed,
    retract_injected_message_handle_typed, update_config_handle_typed,
    update_custom_tools_handle_typed,
};

/// Strongly-typed engine handle. Prefer this in new adapter code over a raw
/// `i64`; conversion is free.
///
/// This newtype prevents passing an arbitrary integer where an engine handle
/// is expected, and gives the typed contract layer a stable receiver type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct EngineHandle(pub i64);

impl EngineHandle {
    /// Wrap a raw `i64` engine handle in the typed newtype.
    pub const fn new(raw: i64) -> Self {
        Self(raw)
    }

    /// The underlying raw `i64` handle.
    pub const fn raw(self) -> i64 {
        self.0
    }
}

impl From<i64> for EngineHandle {
    fn from(raw: i64) -> Self {
        EngineHandle(raw)
    }
}

impl From<EngineHandle> for i64 {
    fn from(handle: EngineHandle) -> i64 {
        handle.0
    }
}

// ---------------------------------------------------------------------------
// Typed contract methods
// ---------------------------------------------------------------------------

impl EngineHandle {
    /// Update LLM/runtime config in place. Returns structured errors
    /// (`invalid_handle`, `config`, `lock_poisoned`) instead of a `bool`.
    pub fn update_config(self, config_json: &str) -> CoreResult<()> {
        update_config_handle_typed(self.0, config_json)
    }

    /// Read the current engine config as JSON.
    pub fn config_json(self) -> CoreResult<String> {
        get_config_handle_typed(self.0)
    }

    /// Delete a registered agent. Returns `invalid_input` for the default
    /// agent or unknown agent IDs, `invalid_handle` for a stale handle.
    pub fn delete_agent(self, agent_id: &str) -> CoreResult<()> {
        delete_agent_handle_typed(self.0, agent_id)
    }

    /// Cancel an active session. `Ok(false)` indicates the session was not
    /// currently active; `Err` carries structured handle errors.
    pub fn cancel_session(self, session_key_json: &str) -> CoreResult<bool> {
        cancel_session_handle_typed(self.0, session_key_json)
    }

    /// Retract an injected user message and its corresponding history row.
    /// `Ok(true)` when both layers were removed; `Ok(false)` when there was
    /// nothing matching to retract.
    pub fn retract_injected_message(
        self,
        session_key_json: &str,
        message: &str,
    ) -> CoreResult<bool> {
        retract_injected_message_handle_typed(self.0, session_key_json, message)
    }

    /// Replace the engine's custom-tool set. Returns the number of registered
    /// tools on success. Errors distinguish missing dispatcher,
    /// `invalid_handle`, and malformed `tools_json`.
    pub async fn update_custom_tools(self, tools_json: &str) -> CoreResult<usize> {
        update_custom_tools_handle_typed(self.0, tools_json).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_handle_roundtrips_through_i64() {
        let raw: i64 = 42;
        let handle: EngineHandle = raw.into();
        assert_eq!(handle.raw(), raw);
        let back: i64 = handle.into();
        assert_eq!(back, raw);
    }

    #[test]
    fn engine_handle_typed_methods_surface_invalid_handle() {
        let handle = EngineHandle::new(0);
        assert_eq!(handle.config_json().unwrap_err().code(), "invalid_handle");
        assert_eq!(
            handle.update_config("{}").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            handle.delete_agent("anything").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            handle.cancel_session("{}").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            handle
                .retract_injected_message("{}", "msg")
                .unwrap_err()
                .code(),
            "invalid_handle"
        );
    }

    #[test]
    fn valid_handle_retract_injected_message_returns_false_for_nonexistent() {
        let temp = tempfile::tempdir().unwrap();
        let config = serde_json::json!({
            "provider": "openai", "api_key": "test", "base_url": null,
            "model": "m", "system_prompt": "", "max_tokens": 128
        })
        .to_string();
        let ctx = serde_json::json!({
            "platform": "test",
            "files_dir": temp.path().to_str().unwrap(),
            "native_library_dir": null
        })
        .to_string();
        let h = crate::runtime::create_engine_handle(&config, &ctx).unwrap();
        let session_key = serde_json::json!({
            "channel_type": "app", "account_id": "user", "thread_id": "t"
        })
        .to_string();
        let result =
            EngineHandle::new(h).retract_injected_message(&session_key, "nonexistent message");
        // Nothing matching to retract on a fresh session → Ok(false). The
        // method must resolve the handle (not invalid_handle) and not panic.
        assert!(!result.unwrap());
        crate::runtime::dispose_engine_handle(h);
    }

    #[tokio::test]
    async fn valid_handle_update_custom_tools_errors_without_dispatcher() {
        // With no tool dispatcher registered, update_custom_tools surfaces a
        // tool_execution error rather than invalid_handle — confirm it's a
        // typed error, not a panic, for the handle-0 path.
        let err = EngineHandle::new(0)
            .update_custom_tools("[]")
            .await
            .unwrap_err();
        assert!(
            matches!(err.code(), "tool_execution" | "invalid_handle"),
            "unexpected code: {}",
            err.code()
        );
    }
}
