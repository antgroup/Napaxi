//! Patch result types, line counting, and progress emission.

use std::fs;
use std::path::Path;

use crate::storage::FileBridge;
use crate::tool_loop::InternalToolProgressSender;

#[derive(Debug)]
pub(super) struct PatchApplyResult {
    pub(super) action: &'static str,
    pub(super) path: String,
    pub(super) real_path: String,
    pub(super) size_bytes: u64,
    pub(super) line_count: usize,
    pub(super) added_lines: usize,
    pub(super) removed_lines: usize,
}

impl PatchApplyResult {
    pub(super) fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "action": self.action,
            "path": self.path,
            "real_path": self.real_path,
            "size_bytes": self.size_bytes,
            "line_count": self.line_count,
            "added_lines": self.added_lines,
            "removed_lines": self.removed_lines,
        })
    }
}

pub(super) fn build_patch_result(
    bridge: &FileBridge,
    real_path: &Path,
    fallback_path: &str,
    action: &'static str,
    content: &str,
    added_lines: usize,
    removed_lines: usize,
) -> Result<PatchApplyResult, String> {
    let metadata = fs::metadata(real_path).map_err(|error| error.to_string())?;
    let canonical_real = fs::canonicalize(real_path).map_err(|error| error.to_string())?;
    let sandbox_path = bridge
        .real_to_sandbox(&canonical_real.display().to_string())
        .unwrap_or_else(|| fallback_path.to_string());
    Ok(PatchApplyResult {
        action,
        path: sandbox_path,
        real_path: canonical_real.display().to_string(),
        size_bytes: metadata.len(),
        line_count: count_lines(content),
        added_lines,
        removed_lines,
    })
}

pub(super) fn emit_patch_progress(
    progress: Option<&InternalToolProgressSender>,
    result: &PatchApplyResult,
) {
    let Some(progress) = progress else {
        return;
    };
    let summary = serde_json::json!({
        "type": "apply_patch_progress",
        "action": result.action,
        "path": result.path,
        "added_lines": result.added_lines,
        "removed_lines": result.removed_lines,
    });
    let _ = progress.send(crate::tool_loop::InternalToolProgressEvent {
        stream: "patch".to_string(),
        content: summary.to_string(),
    });
}

pub(super) fn count_lines(content: &str) -> usize {
    if content.is_empty() {
        0
    } else {
        content.lines().count()
    }
}
