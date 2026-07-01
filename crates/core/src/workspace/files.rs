//! Workspace file CRUD, listing, and write-time content guards.

use std::fs;
use std::io::Write;

use super::meta::{error_json, invalid_handle_json, modified_rfc3339, read_preview};
use super::paths::{
    MEMORY, is_system_prompt_file, memory_dir, normalize_workspace_memory_path,
    normalize_workspace_path, workspace_path, workspace_path_allow_empty,
};
use super::types::{WorkspaceEntry, WorkspaceFile};

pub fn read_workspace_file(files_dir: &str, path: &str) -> String {
    let Ok(real_path) = workspace_path(files_dir, path) else {
        return error_json("Invalid workspace path");
    };
    let Ok(content) = fs::read_to_string(&real_path) else {
        return "null".to_string();
    };
    let file = WorkspaceFile {
        path: normalize_workspace_path(path),
        content,
        updated_at: modified_rfc3339(&real_path),
    };
    serde_json::to_string(&file).unwrap_or_else(|e| error_json(&e.to_string()))
}

pub fn read_workspace_file_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    path: &str,
) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    read_workspace_file(&files_dir, path)
}

pub fn read_workspace_file_content(files_dir: &str, path: &str) -> Result<Option<String>, String> {
    let real_path = workspace_path(files_dir, path).map_err(|_| "Invalid workspace path")?;
    match fs::read_to_string(real_path) {
        Ok(content) => Ok(Some(content)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

pub fn write_workspace_file(files_dir: &str, path: &str, content: &str) -> bool {
    let Ok(real_path) = workspace_path(files_dir, path) else {
        return false;
    };
    if let Some(parent) = real_path.parent()
        && fs::create_dir_all(parent).is_err()
    {
        return false;
    }
    fs::write(real_path, content).is_ok()
}

pub fn write_workspace_file_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    path: &str,
    content: &str,
) -> bool {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return false;
    };
    write_workspace_file(&files_dir, path, content)
}

pub fn write_workspace_file_checked(
    files_dir: &str,
    path: &str,
    content: &str,
) -> Result<String, String> {
    let normalized = normalize_workspace_memory_path(path)?;
    if is_system_prompt_file(&normalized) && !content.is_empty() {
        reject_if_injected(&normalized, content)?;
    }
    let real_path = workspace_path(files_dir, &normalized).map_err(|_| "Invalid workspace path")?;
    if let Some(parent) = real_path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(real_path, content).map_err(|e| e.to_string())?;
    super::recall::upsert_memory_path_best_effort(files_dir, &normalized);
    Ok(normalized)
}

pub fn append_workspace_file(files_dir: &str, path: &str, content: &str) -> bool {
    let Ok(real_path) = workspace_path(files_dir, path) else {
        return false;
    };
    if let Some(parent) = real_path.parent()
        && fs::create_dir_all(parent).is_err()
    {
        return false;
    }
    let Ok(mut file) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(real_path)
    else {
        return false;
    };
    file.write_all(content.as_bytes()).is_ok()
}

pub fn append_workspace_file_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    path: &str,
    content: &str,
) -> bool {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return false;
    };
    append_workspace_file(&files_dir, path, content)
}

pub fn append_workspace_file_checked(
    files_dir: &str,
    path: &str,
    content: &str,
) -> Result<String, String> {
    let normalized = normalize_workspace_memory_path(path)?;
    if is_system_prompt_file(&normalized) && !content.is_empty() {
        reject_if_injected(&normalized, content)?;
    }
    let current = read_workspace_file_content(files_dir, &normalized)?.unwrap_or_default();
    let next = if current.is_empty() {
        content.to_string()
    } else if normalized == MEMORY {
        format!("{current}\n\n{content}")
    } else {
        format!("{current}\n{content}")
    };
    if is_system_prompt_file(&normalized) && !next.is_empty() {
        reject_if_injected(&normalized, &next)?;
    }
    write_workspace_file_checked(files_dir, &normalized, &next)?;
    Ok(normalized)
}

pub fn delete_workspace_file(files_dir: &str, path: &str) -> bool {
    let Ok(real_path) = workspace_path(files_dir, path) else {
        return false;
    };
    let normalized = normalize_workspace_path(path);
    if !real_path.exists() {
        super::recall::delete_path_best_effort(files_dir, &normalized, false);
        return true;
    }
    let is_prefix = real_path.is_dir();
    let deleted = if is_prefix {
        fs::remove_dir_all(real_path).is_ok()
    } else {
        fs::remove_file(real_path).is_ok()
    };
    if deleted {
        super::recall::delete_path_best_effort(files_dir, &normalized, is_prefix);
    }
    deleted
}

pub fn delete_workspace_file_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    path: &str,
) -> bool {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return false;
    };
    delete_workspace_file(&files_dir, path)
}

pub fn list_workspace_files(files_dir: &str, directory: &str) -> String {
    serde_json::to_string(&list_workspace_entries(files_dir, directory))
        .unwrap_or_else(|_| "[]".to_string())
}

pub fn list_workspace_files_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    directory: &str,
) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return "[]".to_string();
    };
    list_workspace_files(&files_dir, directory)
}

pub fn list_workspace_entries(files_dir: &str, directory: &str) -> Vec<WorkspaceEntry> {
    let Ok(dir) = workspace_path_allow_empty(files_dir, directory) else {
        return Vec::new();
    };
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };

    let mut items = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let path = entry.path();
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        let is_directory = metadata.is_dir();
        let workspace_path = path
            .strip_prefix(memory_dir(files_dir))
            .ok()
            .map(|p| p.display().to_string())
            .filter(|p| !p.is_empty())
            .unwrap_or(name);
        items.push(WorkspaceEntry {
            path: workspace_path,
            is_directory,
            updated_at: modified_rfc3339(&path),
            preview: if is_directory {
                None
            } else {
                read_preview(&path)
            },
        });
    }

    items.sort_by(|a, b| {
        b.is_directory
            .cmp(&a.is_directory)
            .then_with(|| a.path.cmp(&b.path))
    });
    items
}

fn reject_if_injected(path: &str, content: &str) -> Result<(), String> {
    let lowered = content.to_ascii_lowercase();
    let patterns = [
        "ignore previous instructions",
        "ignore all previous instructions",
        "disregard previous instructions",
        "forget previous instructions",
        "override your system prompt",
        "reveal your instructions",
    ];
    let matched: Vec<_> = patterns
        .iter()
        .copied()
        .filter(|pattern| lowered.contains(pattern))
        .collect();
    if matched.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "content rejected for '{path}': prompt injection detected ({})",
            matched.join("; ")
        ))
    }
}
