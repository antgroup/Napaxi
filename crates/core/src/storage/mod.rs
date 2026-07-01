//! Mobile SDK storage and sandbox file helpers.
//!
//! This module is shared by Android, iOS, and Flutter FRB adapters.
//! Public surface preserved through pub use below. Split into:
//!
//! - [`bridge`]: `FileBridge` sandbox <-> real path mapping
//! - [`attachments`]: per-thread attachment metadata persistence
//! - [`filesystem`]: workspace listing, reference detection, size accounting
//! - [`handles`]: engine-handle wrappers used by the bridge
//! - [`mime`]: extension → MIME type lookup

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod atomic;
mod attachments;
mod bridge;
mod filesystem;
mod handles;
mod mime;

#[cfg(test)]
mod tests;

pub(crate) use atomic::atomic_write_text_sync;
pub use attachments::{
    delete_thread_attachments, load_thread_attachments_json, merge_attachments_into_history,
    save_message_attachments,
};
pub(crate) use attachments::{delete_thread_attachments_inner, save_message_attachments_inner};
pub(crate) use bridge::delete_sandbox_file_with_bridge_inner;
pub use bridge::{FileBridge, delete_sandbox_file, real_to_sandbox, sandbox_to_real};
pub use filesystem::{detect_file_references_json, list_workspace_filesystem_json, workspace_size};
pub use handles::{
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
pub use mime::mime_from_extension;
