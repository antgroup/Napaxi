//! Napaxi-owned sandbox file tools for the mobile runtime.
//!
//! Public surface (`descriptors`, `execute`, `is_file_tool`, `*_TOOL_NAME`)
//! is preserved through the re-exports below. Implementation is split into:
//!
//! - [`descriptors`]: tool descriptor JSON schemas
//! - [`paths`]: sandbox path resolution and validation
//! - [`read`]: `read_file`
//! - [`apply_patch`]: the sole file-mutation tool (Codex-compatible envelope)
//! - [`progress`]: shared patch result types, line counting, progress events

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod apply_patch;
mod descriptors;
mod paths;
mod progress;
mod read;

#[cfg(test)]
mod tests;

pub use apply_patch::APPLY_PATCH_TOOL_NAME;
pub use descriptors::{
    READ_FILE_TOOL_NAME, apply_patch_descriptor, descriptors, is_file_tool, read_file_descriptor,
};

use crate::storage::FileBridge;
use crate::tool_loop::InternalToolProgressSender;

pub struct FileToolExecutionResult {
    pub output: String,
}

impl FileToolExecutionResult {
    pub(super) fn from_output(output: String) -> Self {
        Self { output }
    }
}

pub fn execute(
    files_dir: &str,
    workspace_files_dir: &str,
    tool_name: &str,
    params: serde_json::Value,
    progress: Option<InternalToolProgressSender>,
) -> Result<FileToolExecutionResult, String> {
    match tool_name {
        READ_FILE_TOOL_NAME => read::read_file(files_dir, workspace_files_dir, params)
            .map(FileToolExecutionResult::from_output),
        APPLY_PATCH_TOOL_NAME => apply_patch_tool(files_dir, workspace_files_dir, params, progress),
        _ => Err(format!("Tool not found: {tool_name}")),
    }
}

fn apply_patch_tool(
    files_dir: &str,
    workspace_files_dir: &str,
    params: serde_json::Value,
    progress: Option<InternalToolProgressSender>,
) -> Result<FileToolExecutionResult, String> {
    let bridge = FileBridge::new_with_workspace_files_dir(files_dir, workspace_files_dir);
    let result = apply_patch::execute_apply_patch(&bridge, params, progress);
    let outcome = if result.is_ok() { "ok" } else { "err" };
    tracing::info!(
        target: "napaxi.tools.apply_patch.metrics",
        outcome = outcome,
        "apply_patch invocation"
    );
    result
}
