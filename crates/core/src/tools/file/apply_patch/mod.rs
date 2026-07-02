//! `apply_patch` is the sole file mutation tool exposed to the LLM.
//!
//! The patch envelope follows the OpenAI Codex `apply_patch` format:
//! ```text
//! *** Begin Patch
//! *** Add File: /workspace/new.md
//! +first line
//! +second line
//! *** Update File: /workspace/existing.md
//! @@
//!  context above
//! -old line
//! +new line
//!  context below
//! *** Delete File: /workspace/old.md
//! *** End Patch
//! ```
//!
//! `*** Add File:` is also used to fully overwrite an existing file by first
//! deleting it in the same envelope (mirrors codex's `Add` semantics with
//! `overwritten_content`).
//!
//! Implementation is split into:
//! - [`parser`]: envelope tokenisation with line numbers
//! - [`seek`]: line-wise fuzzy match (exact → rstrip → trim → unicode)
//! - [`apply`]: filesystem-aware execution
//! - [`errors`]: typed errors with model-facing hints

mod apply;
mod errors;
mod parser;
mod seek;

#[cfg(test)]
mod tests;

use crate::file_tools::FileToolExecutionResult;
use crate::storage::FileBridge;
use crate::tool_loop::InternalToolProgressSender;

pub const APPLY_PATCH_TOOL_NAME: &str = "apply_patch";

/// Dispatcher invoked from the file tool router.
pub(super) fn execute_apply_patch(
    bridge: &FileBridge,
    params: serde_json::Value,
    progress: Option<InternalToolProgressSender>,
) -> Result<FileToolExecutionResult, String> {
    let patch = params
        .get("patch")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            "apply_patch requires a non-empty 'patch' string (Begin/End envelope)".to_string()
        })?;
    let create_parent_dirs = params
        .get("create_parent_dirs")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(true);

    match apply::execute(bridge, patch, create_parent_dirs, progress) {
        Ok(result) => Ok(result),
        Err(err) => Err(err.to_tool_payload()),
    }
}
