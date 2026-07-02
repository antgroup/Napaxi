//! Workspace filesystem listing, reference detection, and size accounting.
//!
//! Public non-`_handle` wrappers are kept as the in-crate API surface; SDK
//! adapters reach them through `storage::handles::*`, so cargo cannot see a
//! call site inside this crate alone.
#![allow(dead_code)]

use std::collections::HashSet;
use std::fs;
use std::path::Path;

use serde_json::Value;

use super::bridge::{FileBridge, ROOTFS_PREFIXES};
use super::mime::mime_from_extension;

pub fn detect_file_references_json(files_dir: &str, text: &str) -> String {
    let bridge = FileBridge::new(files_dir);
    detect_file_references_json_with_bridge(&bridge, text)
}

pub(super) fn detect_file_references_json_with_bridge(bridge: &FileBridge, text: &str) -> String {
    let mut seen = HashSet::new();
    let mut results = Vec::new();

    for token in text.split_whitespace() {
        let Some(path) = clean_candidate_path(token) else {
            continue;
        };
        if !seen.insert(path.clone()) {
            continue;
        }
        let Some(real_path) = bridge.sandbox_to_real(&path) else {
            continue;
        };
        let real = Path::new(&real_path);
        let exists = real.exists();
        let filename = Path::new(&path)
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        let mime_type = mime_from_extension(
            Path::new(&filename)
                .extension()
                .and_then(|s| s.to_str())
                .unwrap_or(""),
        );
        let size_bytes = if exists && real.is_file() {
            real.metadata().ok().map(|m| m.len())
        } else {
            None
        };
        results.push(serde_json::json!({
            "sandbox_path": path,
            "real_path": real_path,
            "filename": filename,
            "mime_type": mime_type,
            "is_image": mime_type.starts_with("image/"),
            "exists": exists,
            "size_bytes": size_bytes,
        }));
    }

    serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string())
}

fn clean_candidate_path(token: &str) -> Option<String> {
    let trimmed = token.trim_matches(|c: char| {
        matches!(
            c,
            '`' | '"' | '\'' | '*' | '<' | '>' | '[' | ']' | '(' | ')' | '{' | '}' | ',' | '.'
        )
    });
    let start = ROOTFS_PREFIXES
        .iter()
        .chain(["/workspace", "/skills"].iter())
        .filter_map(|prefix| trimmed.find(prefix).map(|idx| (idx, *prefix)))
        .min_by_key(|(idx, _)| *idx)?;
    let mut path = trimmed[start.0..].to_string();
    while path.ends_with(|c: char| {
        matches!(
            c,
            '`' | '"' | '\'' | '*' | '<' | '>' | '[' | ']' | '(' | ')' | '{' | '}' | ',' | '.'
        )
    }) {
        path.pop();
    }
    Some(path)
}

pub fn list_workspace_filesystem_json(
    files_dir: &str,
    subdir: Option<&str>,
    recursive: bool,
) -> String {
    let bridge = FileBridge::new(files_dir);
    list_workspace_filesystem_json_with_bridge(&bridge, subdir, recursive)
}

pub(super) fn list_workspace_filesystem_json_with_bridge(
    bridge: &FileBridge,
    subdir: Option<&str>,
    recursive: bool,
) -> String {
    let dir = subdir
        .filter(|s| !s.is_empty())
        .map(|s| bridge.workspace_dir().join(s))
        .unwrap_or_else(|| bridge.workspace_dir().to_path_buf());
    if !dir.exists() {
        return "[]".to_string();
    }

    let mut results = Vec::new();
    collect_workspace_entries(bridge, &dir, recursive, &mut results);
    results.sort_by(|a, b| {
        let a_dir = a
            .get("is_directory")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let b_dir = b
            .get("is_directory")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        b_dir.cmp(&a_dir).then_with(|| {
            b.get("modified")
                .and_then(Value::as_str)
                .unwrap_or("")
                .cmp(a.get("modified").and_then(Value::as_str).unwrap_or(""))
        })
    });
    serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string())
}

fn collect_workspace_entries(
    bridge: &FileBridge,
    dir: &Path,
    recursive: bool,
    results: &mut Vec<Value>,
) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        let is_dir = metadata.is_dir();
        let sandbox_path = bridge
            .real_to_sandbox(&path.display().to_string())
            .unwrap_or_default();
        if sandbox_path.is_empty() {
            continue;
        }
        let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("");
        results.push(serde_json::json!({
            "name": name,
            "sandbox_path": sandbox_path,
            "real_path": path.display().to_string(),
            "mime_type": if is_dir { "inode/directory".to_string() } else { mime_from_extension(ext).to_string() },
            "is_directory": is_dir,
            "size_bytes": if is_dir { 0 } else { metadata.len() },
            "modified": metadata.modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0),
        }));
        if recursive && is_dir {
            collect_workspace_entries(bridge, &path, recursive, results);
        }
    }
}

pub fn workspace_size(files_dir: &str) -> u64 {
    let bridge = FileBridge::new(files_dir);
    workspace_size_with_bridge(&bridge)
}

pub(super) fn workspace_size_with_bridge(bridge: &FileBridge) -> u64 {
    directory_size(bridge.workspace_dir())
}

fn directory_size(dir: &Path) -> u64 {
    let Ok(entries) = fs::read_dir(dir) else {
        return 0;
    };
    entries
        .flatten()
        .map(|entry| {
            let path = entry.path();
            if path.is_dir() {
                directory_size(&path)
            } else {
                entry.metadata().map(|m| m.len()).unwrap_or(0)
            }
        })
        .sum()
}
