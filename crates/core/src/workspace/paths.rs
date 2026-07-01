//! Workspace path constants, scoping, and normalization.

use std::path::{Path, PathBuf};

pub(super) const README: &str = "README.md";
pub(super) const MEMORY: &str = "MEMORY.md";
pub(super) const PROJECT: &str = "PROJECT.md";
pub(super) const IDENTITY: &str = "IDENTITY.md";
pub(super) const SOUL: &str = "SOUL.md";
pub(super) const AGENTS: &str = "AGENTS.md";
pub(super) const USER: &str = "USER.md";
pub(super) const HEARTBEAT: &str = "HEARTBEAT.md";
pub(super) const TOOLS: &str = "TOOLS.md";
pub(super) const BOOTSTRAP: &str = "BOOTSTRAP.md";
pub(super) const PROFILE: &str = "context/profile.json";
pub(super) const ASSISTANT_DIRECTIVES: &str = "context/assistant-directives.md";

pub(super) const LEGACY_MEMORY_PATHS: &[&str] = &[
    README, MEMORY, PROJECT, IDENTITY, SOUL, AGENTS, USER, HEARTBEAT, TOOLS, BOOTSTRAP, "context",
    "daily",
];

const SYSTEM_PROMPT_FILES: &[&str] = &[
    SOUL,
    AGENTS,
    USER,
    IDENTITY,
    MEMORY,
    PROJECT,
    TOOLS,
    HEARTBEAT,
    BOOTSTRAP,
    PROFILE,
    ASSISTANT_DIRECTIVES,
];

pub(super) const PROFILE_SECTION_BEGIN: &str = "<!-- BEGIN:profile-sync -->";
pub(super) const PROFILE_SECTION_END: &str = "<!-- END:profile-sync -->";
pub(super) const JOURNAL_TURNS_DIR: &str = "napaxi/journal/turns";
pub(super) const DEFAULT_ACCOUNT_ID: &str = crate::runtime::DEFAULT_ACCOUNT_ID;
pub(super) const DEFAULT_AGENT_ID: &str = crate::runtime::DEFAULT_AGENT_ID;

pub fn scoped_files_dir(files_dir: &str, account_id: &str, agent_id: &str) -> String {
    Path::new(files_dir)
        .join("napaxi_scopes")
        .join("accounts")
        .join(sanitize_scope_component(account_id, DEFAULT_ACCOUNT_ID))
        .join("agents")
        .join(sanitize_scope_component(agent_id, DEFAULT_AGENT_ID))
        .display()
        .to_string()
}

pub fn default_scoped_files_dir(files_dir: &str, agent_id: &str) -> String {
    scoped_files_dir(files_dir, DEFAULT_ACCOUNT_ID, agent_id)
}

pub(super) fn memory_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("memory")
}

pub(super) fn workspace_path(files_dir: &str, path: &str) -> Result<PathBuf, ()> {
    let normalized = normalize_workspace_memory_path(path).map_err(|_| ())?;
    Ok(memory_dir(files_dir).join(normalized))
}

pub(super) fn workspace_path_allow_empty(files_dir: &str, path: &str) -> Result<PathBuf, ()> {
    let normalized = normalize_workspace_path(path);
    if normalized.is_empty() {
        return Ok(memory_dir(files_dir));
    }
    workspace_path(files_dir, &normalized)
}

pub(super) fn normalize_workspace_path(path: &str) -> String {
    path.trim()
        .trim_start_matches("/workspace/")
        .trim_start_matches('/')
        .to_string()
}

pub fn normalize_workspace_memory_path(path: &str) -> Result<String, String> {
    let normalized = normalize_workspace_path(path);
    if normalized.is_empty()
        || normalized.starts_with('/')
        || normalized
            .split('/')
            .any(|segment| segment.is_empty() || segment == "." || segment == "..")
    {
        return Err("Invalid workspace path".to_string());
    }
    Ok(normalized)
}

pub fn looks_like_filesystem_path(path: &str) -> bool {
    if path.is_empty() {
        return false;
    }
    if Path::new(path).is_absolute() || path.starts_with("~/") {
        return true;
    }
    let bytes = path.as_bytes();
    bytes.len() >= 3
        && bytes[0].is_ascii_alphabetic()
        && bytes[1] == b':'
        && (bytes[2] == b'\\' || bytes[2] == b'/')
}

pub(super) fn is_system_prompt_file(path: &str) -> bool {
    SYSTEM_PROMPT_FILES
        .iter()
        .any(|system_path| path.eq_ignore_ascii_case(system_path))
}

fn sanitize_scope_component(value: &str, default_value: &str) -> String {
    let sanitized: String = value
        .trim()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let sanitized = sanitized.trim_matches(['.', '_', '-']);
    if sanitized.is_empty() {
        default_value.to_string()
    } else {
        sanitized.chars().take(96).collect()
    }
}
