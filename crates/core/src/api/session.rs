//! Session metadata and history API.
//!
//! Two layers (mirrors `api::engine`):
//!
//! - **JSON/handle layer**: the `_handle` re-exports below take raw `i64`
//!   handles and JSON strings, kept stable for the FRB bridge.
//! - **Typed layer**: `EngineHandle` carries typed methods that return
//!   `CoreResult<String>` (the JSON payload stays a string because session
//!   history is large and Dart parses it anyway; the boundary win is that
//!   `invalid_handle` no longer hides behind a magic JSON shape).

use crate::api::engine::EngineHandle;
use crate::error::{CoreError, CoreResult};
use crate::runtime::handle_to_arc;

pub use crate::session::{
    clear_session_handle, create_session_handle, delete_session_handle,
    delete_session_if_empty_handle, get_history_handle, get_history_page_handle,
    inject_user_message_handle, list_sessions_handle, prune_empty_sessions_handle,
};

/// Compact a session's history (synchronous), returning the result as JSON.
pub fn compact_session_handle(
    handle: i64,
    config_json: &str,
    session_key_json: &str,
    focus: Option<&str>,
) -> String {
    crate::context::compact_session_handle(handle, config_json, session_key_json, focus)
}

/// Compact a session's history asynchronously, returning the result as JSON.
pub async fn compact_session_handle_async(
    handle: i64,
    config_json: &str,
    session_key_json: &str,
    focus: Option<&str>,
) -> String {
    crate::context::compact_session_handle_async(handle, config_json, session_key_json, focus).await
}

/// Report context-window usage for a thread (token counts, headroom) as JSON.
pub fn context_status_handle(handle: i64, config_json: &str, thread_id: &str) -> String {
    crate::context::context_status_handle(handle, config_json, thread_id)
}

// ---------------------------------------------------------------------------
// Typed contract methods on EngineHandle
// ---------------------------------------------------------------------------

impl EngineHandle {
    /// Compact a session via the context engine. Returns the resulting
    /// context-status JSON payload. `Err(InvalidHandle)` for stale handles.
    pub fn compact_session(
        self,
        config_json: &str,
        session_key_json: &str,
        focus: Option<&str>,
    ) -> CoreResult<String> {
        validate_handle(self.raw())?;
        Ok(crate::context::compact_session_handle(
            self.raw(),
            config_json,
            session_key_json,
            focus,
        ))
    }

    /// Snapshot of context bookkeeping for a thread (token estimates, last
    /// compaction, etc.) as JSON. `Err(InvalidHandle)` for stale handles.
    pub fn context_status(self, config_json: &str, thread_id: &str) -> CoreResult<String> {
        validate_handle(self.raw())?;
        Ok(crate::context::context_status_handle(
            self.raw(),
            config_json,
            thread_id,
        ))
    }

    /// List sessions for an agent+account scope. JSON array payload.
    pub fn list_sessions(self, agent_id: &str, account_id: &str) -> CoreResult<String> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        Ok(crate::session::list_sessions(
            engine.files_dir(),
            agent_id,
            account_id,
        ))
    }

    /// Get raw chat history for a thread as JSON.
    pub fn get_history(self, thread_id: &str) -> CoreResult<String> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        Ok(crate::session::get_history(engine.files_dir(), thread_id))
    }

    /// Delete a session (history + metadata). `Ok(())` even when the session
    /// did not exist; `Err(InvalidHandle)` only for stale handles.
    pub fn delete_session(self, session_key_json: &str) -> CoreResult<()> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        crate::session::delete_session(engine.files_dir(), session_key_json);
        Ok(())
    }

    /// Clear a session's chat history but keep its metadata.
    pub fn clear_session(self, session_key_json: &str) -> CoreResult<()> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        crate::session::clear_session(engine.files_dir(), session_key_json);
        Ok(())
    }

    /// Delete a session only if it carries no durable content (no messages,
    /// title, or preview). Returns `Ok(true)` when an empty ghost session was
    /// removed, `Ok(false)` when the session was kept. Call on session rotation
    /// or runtime shutdown to stop empty rows piling up in `list_sessions`.
    pub fn delete_session_if_empty(self, session_key_json: &str) -> CoreResult<bool> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        Ok(crate::session::delete_session_if_empty(
            engine.files_dir(),
            session_key_json,
        ))
    }

    /// Remove all empty ghost sessions for an agent+account scope, returning
    /// the count pruned. One-shot cleanup for stores that accumulated ghost
    /// rows before rotation/shutdown hygiene was in place.
    pub fn prune_empty_sessions(self, agent_id: &str, account_id: &str) -> CoreResult<usize> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        Ok(crate::session::prune_empty_sessions(
            engine.files_dir(),
            agent_id,
            account_id,
        ))
    }
}

fn validate_handle(handle: i64) -> CoreResult<()> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    unsafe { handle_to_arc(handle) }
        .map(|_| ())
        .ok_or(CoreError::InvalidHandle(handle))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_session_methods_reject_invalid_handle() {
        let h = EngineHandle::new(0);
        assert_eq!(
            h.compact_session("{}", "{}", None).unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            h.context_status("{}", "t").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            h.list_sessions("a", "u").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(h.get_history("t").unwrap_err().code(), "invalid_handle");
        assert_eq!(h.delete_session("{}").unwrap_err().code(), "invalid_handle");
        assert_eq!(h.clear_session("{}").unwrap_err().code(), "invalid_handle");
    }

    fn make_handle() -> (i64, tempfile::TempDir) {
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
        (h, temp)
    }

    #[test]
    fn valid_handle_list_sessions_returns_json_array() {
        let (h, _tmp) = make_handle();
        let eh = EngineHandle::new(h);
        let list = eh.list_sessions("default", "user").unwrap();
        let _parsed: Vec<serde_json::Value> =
            serde_json::from_str(&list).expect("list_sessions should return a valid JSON array");
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn valid_handle_get_history_returns_json() {
        let (h, _tmp) = make_handle();
        let eh = EngineHandle::new(h);
        let history = eh.get_history("thread-1").unwrap();
        assert!(
            history.starts_with('[') || history.starts_with('{') || history == "[]",
            "history: {history}"
        );
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn valid_handle_delete_and_clear_session_are_idempotent() {
        let (h, _tmp) = make_handle();
        let eh = EngineHandle::new(h);
        let session_key = serde_json::json!({
            "channel_type": "app", "account_id": "user", "thread_id": "t"
        })
        .to_string();
        eh.delete_session(&session_key)
            .expect("delete nonexistent session should succeed");
        eh.clear_session(&session_key)
            .expect("clear nonexistent session should succeed");
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn valid_handle_context_status_returns_json() {
        let (h, _tmp) = make_handle();
        let eh = EngineHandle::new(h);
        let status = eh.context_status("{}", "thread-1").unwrap();
        assert!(
            status.starts_with('{'),
            "context status should be JSON object: {status}"
        );
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn legacy_handle_functions_return_stable_shapes() {
        assert!(list_sessions_handle(0, "", "").starts_with('['));
        let history = get_history_handle(0, "t");
        assert!(history.starts_with('[') || history.starts_with('{'));
    }

    #[test]
    fn legacy_compact_session_handle_returns_json_for_invalid_handle() {
        let result = compact_session_handle(0, "{}", "{}", None);
        assert!(
            result.starts_with('{') || result.contains("error"),
            "compact: {result}"
        );
    }

    #[test]
    fn legacy_context_status_handle_returns_json_for_invalid_handle() {
        let result = context_status_handle(0, "{}", "t");
        assert!(
            result.starts_with('{') || result.contains("error"),
            "ctx status: {result}"
        );
    }

    #[test]
    fn valid_handle_compact_session_typed_returns_ok() {
        let (h, _tmp) = make_handle();
        let session_key = serde_json::json!({
            "channel_type": "app", "account_id": "user", "thread_id": "t"
        })
        .to_string();
        let result = EngineHandle::new(h)
            .compact_session("{}", &session_key, None)
            .unwrap();
        assert!(result.starts_with('{'), "compact typed: {result}");
        crate::runtime::dispose_engine_handle(h);
    }

    #[tokio::test]
    async fn legacy_compact_session_handle_async_returns_json() {
        let result = compact_session_handle_async(0, "{}", "{}", None).await;
        assert!(
            result.starts_with('{') || result.contains("error"),
            "async compact: {result}"
        );
    }
}
