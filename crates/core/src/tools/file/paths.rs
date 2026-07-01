//! Sandbox path resolution and validation for the file tool.

use std::fs;
use std::path::{Path, PathBuf};

use crate::storage::FileBridge;

pub(super) const ROOTFS_PREFIXES: &[&str] = &[
    "/tmp", "/root", "/home", "/var", "/usr", "/opt", "/etc", "/srv", "/run",
];

pub(super) fn resolve_read_path(
    bridge: &FileBridge,
    sandbox_path: &str,
) -> Result<(PathBuf, PathBuf), String> {
    let normalized = sandbox_path.trim();
    if normalized == "/workspace" || normalized.starts_with("/workspace/") {
        let real = bridge.sandbox_to_real(normalized).ok_or_else(|| {
            "read_file must use /workspace, /skills, or rootfs sandbox paths".to_string()
        })?;
        return Ok((
            validate_real_path(Path::new(&real), normalized, "read_file")?,
            bridge.workspace_dir().to_path_buf(),
        ));
    }
    if normalized == "/skills" || normalized.starts_with("/skills/") {
        let real = bridge.sandbox_to_real(normalized).ok_or_else(|| {
            "read_file must use /workspace, /skills, or rootfs sandbox paths".to_string()
        })?;
        return Ok((
            validate_real_path(Path::new(&real), normalized, "read_file")?,
            bridge.skills_dir().to_path_buf(),
        ));
    }
    if ROOTFS_PREFIXES
        .iter()
        .any(|prefix| normalized == *prefix || normalized.starts_with(&format!("{prefix}/")))
    {
        let real = bridge.sandbox_to_real(normalized).ok_or_else(|| {
            "read_file must use /workspace, /skills, or rootfs sandbox paths".to_string()
        })?;
        return Ok((
            validate_real_path(Path::new(&real), normalized, "read_file")?,
            bridge.rootfs_dir().to_path_buf(),
        ));
    }
    Err(
        "read_file must use a sandbox path such as /workspace/file, /skills/file, or /tmp/file"
            .to_string(),
    )
}

pub(super) fn resolve_write_path(
    bridge: &FileBridge,
    sandbox_path: &str,
) -> Result<(PathBuf, PathBuf), String> {
    let normalized = sandbox_path.trim();
    if normalized == "/skills" || normalized.starts_with("/skills/") {
        return Err("apply_patch cannot write under /skills".to_string());
    }
    if normalized == "/workspace" || normalized.starts_with("/workspace/") {
        let real = bridge
            .sandbox_to_real(normalized)
            .ok_or_else(|| "apply_patch must use /workspace or rootfs sandbox paths".to_string())?;
        return Ok((
            validate_real_path(Path::new(&real), normalized, "apply_patch")?,
            bridge.workspace_dir().to_path_buf(),
        ));
    }
    if ROOTFS_PREFIXES
        .iter()
        .any(|prefix| normalized == *prefix || normalized.starts_with(&format!("{prefix}/")))
    {
        let real = bridge
            .sandbox_to_real(normalized)
            .ok_or_else(|| "apply_patch must use /workspace or rootfs sandbox paths".to_string())?;
        return Ok((
            validate_real_path(Path::new(&real), normalized, "apply_patch")?,
            bridge.rootfs_dir().to_path_buf(),
        ));
    }
    Err("apply_patch must use a sandbox path such as /workspace/file or /tmp/file".to_string())
}

pub(super) fn validate_real_path(
    real_path: &Path,
    sandbox_path: &str,
    tool_name: &str,
) -> Result<PathBuf, String> {
    if real_path.components().any(|component| {
        matches!(
            component,
            std::path::Component::ParentDir | std::path::Component::CurDir
        )
    }) {
        return Err(format!(
            "{tool_name} path contains invalid segments: {sandbox_path}"
        ));
    }
    Ok(real_path.to_path_buf())
}

pub(super) fn existing_regular_file(
    real_path: &Path,
    base_dir: &Path,
    sandbox_path: &str,
) -> Result<Option<String>, String> {
    let Ok(metadata) = fs::symlink_metadata(real_path) else {
        return Ok(None);
    };
    if metadata.file_type().is_symlink() {
        return Err(format!(
            "apply_patch does not follow symlinks: {sandbox_path}"
        ));
    }
    if metadata.is_dir() {
        return Err(format!(
            "apply_patch expected a file but found a directory: {sandbox_path}"
        ));
    }
    let canonical_real = fs::canonicalize(real_path).map_err(|error| error.to_string())?;
    let canonical_base = fs::canonicalize(base_dir).map_err(|error| error.to_string())?;
    if !canonical_real.starts_with(&canonical_base) {
        return Err(format!(
            "apply_patch path escapes the allowed sandbox: {sandbox_path}"
        ));
    }
    fs::read_to_string(real_path)
        .map(Some)
        .map_err(|error| format!("apply_patch can only edit UTF-8 text files: {error}"))
}
