//! Direct `read_file` execution path.

use std::fs::{self, File};
use std::io::Read;

use crate::storage::FileBridge;

use super::descriptors::MAX_MAX_BYTES;
use super::paths::resolve_read_path;

const DEFAULT_MAX_BYTES: usize = 64 * 1024;

pub(super) fn read_file(
    files_dir: &str,
    workspace_files_dir: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    let path = params
        .get("path")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "read_file path is required".to_string())?;
    if crate::workspace::looks_like_filesystem_path(path) && !path.starts_with('/') {
        return Err("read_file expects a sandbox path such as /workspace/file".to_string());
    }

    let max_bytes = params
        .get("max_bytes")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(DEFAULT_MAX_BYTES as u64)
        .clamp(1, MAX_MAX_BYTES as u64) as usize;

    let bridge = FileBridge::new_with_workspace_files_dir(files_dir, workspace_files_dir);
    let (real_path, base_dir) = resolve_read_path(&bridge, path)?;
    let metadata = fs::symlink_metadata(&real_path).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => format!("file not found: {path}"),
        _ => error.to_string(),
    })?;
    if metadata.file_type().is_symlink() {
        return Err(format!("read_file does not follow symlinks: {path}"));
    }
    if metadata.is_dir() {
        return Err(format!(
            "read_file expected a file but found a directory: {path}"
        ));
    }

    let canonical_real = fs::canonicalize(&real_path).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => format!("file not found: {path}"),
        _ => error.to_string(),
    })?;
    let canonical_base = fs::canonicalize(&base_dir).map_err(|error| error.to_string())?;
    if !canonical_real.starts_with(&canonical_base) {
        return Err(format!(
            "read_file path escapes the allowed sandbox: {path}"
        ));
    }

    let mut file = File::open(&real_path).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => format!("file not found: {path}"),
        _ => error.to_string(),
    })?;
    let mut buffer = Vec::new();
    file.by_ref()
        .take(max_bytes as u64)
        .read_to_end(&mut buffer)
        .map_err(|error| error.to_string())?;

    let bytes_read = buffer.len();
    let size_bytes = metadata.len();
    let truncated = size_bytes > bytes_read as u64;
    let is_utf8 = std::str::from_utf8(&buffer).is_ok();
    let content = String::from_utf8(buffer)
        .unwrap_or_else(|bytes| String::from_utf8_lossy(&bytes.into_bytes()).to_string());
    let sandbox_path = bridge
        .real_to_sandbox(&canonical_real.display().to_string())
        .unwrap_or_else(|| path.to_string());

    Ok(serde_json::json!({
        "path": sandbox_path,
        "real_path": canonical_real.display().to_string(),
        "size_bytes": size_bytes,
        "bytes_read": bytes_read,
        "truncated": truncated,
        "is_utf8": is_utf8,
        "content": content,
    })
    .to_string())
}
