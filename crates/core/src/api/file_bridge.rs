//! File bridge API and sandbox path mapping.
//!
//! Two layers (mirrors `api::engine`):
//!
//! - **Legacy `_handle` re-exports**: bool/String returns kept stable for
//!   the FRB bridge.
//! - **Typed layer on `EngineHandle`**: `init_file_bridge`,
//!   `delete_sandbox_file`, `save_message_attachments` return `CoreResult`
//!   so adapters can distinguish IO failures from `invalid_handle`.

use crate::api::engine::EngineHandle;
use crate::error::{CoreError, CoreResult, StorageError};
use crate::runtime::handle_to_arc;

pub use crate::storage::{
    delete_sandbox_file_handle, delete_sandbox_file_scoped_handle,
    delete_thread_attachments_handle, detect_file_references_json_handle,
    detect_file_references_json_scoped_handle, init_file_bridge_handle,
    init_file_bridge_scoped_handle, list_workspace_filesystem_json_handle,
    list_workspace_filesystem_json_scoped_handle, load_thread_attachments_json_handle,
    real_to_sandbox_handle, real_to_sandbox_scoped_handle, rootfs_dir_handle,
    sandbox_to_real_handle, sandbox_to_real_scoped_handle, save_message_attachments_handle,
    skills_dir_handle, workspace_dir_handle, workspace_dir_scoped_handle, workspace_size_handle,
    workspace_size_scoped_handle,
};

// ---------------------------------------------------------------------------
// Typed layer
// ---------------------------------------------------------------------------

impl EngineHandle {
    /// Ensure the workspace directory exists on disk. Surfaces `storage_io`
    /// for actual filesystem failures (permission, ENOSPC) instead of a
    /// silent `false`.
    pub fn init_file_bridge(self) -> CoreResult<()> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        let bridge = crate::storage::FileBridge::new(engine.files_dir());
        bridge.ensure_workspace_inner().map_err(Into::into)
    }

    /// Delete a sandbox-path file or directory. Missing paths are `Ok(())`
    /// (idempotent delete); IO failures surface as `storage_io`.
    pub fn delete_sandbox_file(self, sandbox_path: &str) -> CoreResult<()> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        let bridge = crate::storage::FileBridge::new(engine.files_dir());
        crate::storage::delete_sandbox_file_with_bridge_inner(&bridge, sandbox_path)
            .map_err(Into::into)
    }

    /// Persist attachment metadata for one user message. Bad JSON becomes
    /// `storage_decode`, IO failures become `storage_io`.
    pub fn save_message_attachments(
        self,
        thread_id: &str,
        user_msg_index: i32,
        attachments_json: &str,
    ) -> CoreResult<()> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        crate::storage::save_message_attachments_inner(
            engine.files_dir(),
            thread_id,
            user_msg_index,
            attachments_json,
        )
        .map_err(Into::into)
    }

    /// Delete a thread's attachment manifest. Missing file is `Ok(())`.
    pub fn delete_thread_attachments(self, thread_id: &str) -> CoreResult<()> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        crate::storage::delete_thread_attachments_inner(engine.files_dir(), thread_id)
            .map_err(Into::into)
    }
}

// Re-export the storage error variants adapters branch on.
pub use crate::error::StorageError as FileBridgeError;
// Silence the noisy "unused import" inside this module — re-export is the point.
#[allow(unused_imports)]
use StorageError as _;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_file_bridge_methods_reject_invalid_handle() {
        let h = EngineHandle::new(0);
        assert_eq!(h.init_file_bridge().unwrap_err().code(), "invalid_handle");
        assert_eq!(
            h.delete_sandbox_file("/workspace/x").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            h.save_message_attachments("t", 0, "[]").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            h.delete_thread_attachments("t").unwrap_err().code(),
            "invalid_handle"
        );
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
    fn valid_handle_init_file_bridge_and_delete_idempotent() {
        let (h, _tmp) = make_handle();
        let eh = EngineHandle::new(h);
        eh.init_file_bridge().expect("init should succeed");
        // Delete a nonexistent file is idempotent (Ok).
        eh.delete_sandbox_file("/workspace/does_not_exist")
            .expect("idempotent delete should succeed");
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn valid_handle_save_and_delete_thread_attachments() {
        let (h, _tmp) = make_handle();
        let eh = EngineHandle::new(h);
        eh.init_file_bridge().unwrap();
        eh.save_message_attachments("thread-1", 0, "[]")
            .expect("save empty attachments should succeed");
        eh.delete_thread_attachments("thread-1")
            .expect("delete attachments should succeed");
        // Deleting again is fine (idempotent).
        eh.delete_thread_attachments("thread-1")
            .expect("second delete should still succeed");
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn legacy_handle_functions_return_stable_defaults_for_invalid_handle() {
        assert!(!init_file_bridge_handle(0));
        assert!(!delete_sandbox_file_handle(0, "/workspace/x"));
    }
}
