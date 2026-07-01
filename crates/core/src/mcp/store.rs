use std::fs;
use std::path::{Path, PathBuf};

use super::{LEGACY_DEFAULT_ACCOUNT_ID, McpSecretEntry, McpSecretState, McpServer, McpState};

pub(super) fn store_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join("mcp_servers.json")
}

pub(super) fn secret_store_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join("napaxi")
        .join(".mcp_server_secrets.json")
}

pub(super) fn default_user(user_id: &str) -> String {
    let user_id = user_id.trim();
    if user_id.is_empty() {
        crate::runtime::DEFAULT_ACCOUNT_ID.to_string()
    } else {
        user_id.to_string()
    }
}

pub(super) fn load_state(files_dir: &str) -> McpState {
    let Ok(content) = fs::read_to_string(store_path(files_dir)) else {
        return McpState::default();
    };
    let mut state: McpState = serde_json::from_str(&content).unwrap_or_default();
    hydrate_oauth_secrets(files_dir, &mut state);
    normalize_legacy_default_users(&mut state);
    state
}

fn normalize_legacy_default_users(state: &mut McpState) {
    let default_account_id = crate::runtime::DEFAULT_ACCOUNT_ID;
    if default_account_id == LEGACY_DEFAULT_ACCOUNT_ID {
        return;
    }

    let mut default_server_names: Vec<String> = state
        .servers
        .iter()
        .filter(|server| server.user_id == default_account_id)
        .map(|server| server.name.clone())
        .collect();
    let mut normalized = Vec::with_capacity(state.servers.len());
    for mut server in state.servers.drain(..) {
        if server.user_id == LEGACY_DEFAULT_ACCOUNT_ID {
            if default_server_names.iter().any(|name| name == &server.name) {
                continue;
            }
            server.user_id = default_account_id.to_string();
            default_server_names.push(server.name.clone());
        }
        normalized.push(server);
    }
    state.servers = normalized;
}

pub(super) fn save_state(files_dir: &str, state: &McpState) -> bool {
    let path = store_path(files_dir);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    if !harden_private_dir(parent) {
        return false;
    }
    if !save_secret_state(files_dir, state) {
        return false;
    }
    serde_json::to_string_pretty(state)
        .ok()
        .and_then(|content| write_private_file(&path, content).ok())
        .is_some()
}

fn load_secret_state(files_dir: &str) -> McpSecretState {
    let Ok(content) = fs::read_to_string(secret_store_path(files_dir)) else {
        return McpSecretState::default();
    };
    serde_json::from_str(&content).unwrap_or_default()
}

fn save_secret_state(files_dir: &str, state: &McpState) -> bool {
    let path = secret_store_path(files_dir);
    let entries: Vec<_> = state
        .servers
        .iter()
        .filter_map(secret_entry_from_server)
        .collect();
    if entries.is_empty() {
        return fs::remove_file(&path).is_ok() || !path.exists();
    }
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    if !harden_private_dir(parent) {
        return false;
    }
    let secret_state = McpSecretState { entries };
    serde_json::to_string_pretty(&secret_state)
        .ok()
        .and_then(|content| write_private_file(&path, content).ok())
        .is_some()
}

fn secret_entry_from_server(server: &McpServer) -> Option<McpSecretEntry> {
    let client_secret = server
        .oauth
        .as_ref()
        .and_then(|oauth| oauth.client_secret.clone());
    if client_secret.is_none() && server.oauth_pending.is_none() && server.oauth_tokens.is_none() {
        return None;
    }
    Some(McpSecretEntry {
        name: server.name.clone(),
        user_id: server.user_id.clone(),
        client_secret,
        oauth_pending: server.oauth_pending.clone(),
        oauth_tokens: server.oauth_tokens.clone(),
    })
}

fn hydrate_oauth_secrets(files_dir: &str, state: &mut McpState) {
    let secret_state = load_secret_state(files_dir);
    for server in &mut state.servers {
        let Some(entry) = secret_state
            .entries
            .iter()
            .find(|entry| entry.name == server.name && entry.user_id == server.user_id)
        else {
            continue;
        };
        if let Some(client_secret) = entry.client_secret.clone()
            && let Some(oauth) = &mut server.oauth
        {
            oauth.client_secret = Some(client_secret);
        }
        if entry.oauth_pending.is_some() {
            server.oauth_pending = entry.oauth_pending.clone();
        }
        if entry.oauth_tokens.is_some() {
            server.oauth_tokens = entry.oauth_tokens.clone();
        }
    }
}

fn write_private_file(path: &Path, content: String) -> std::io::Result<()> {
    fs::write(path, content)?;
    harden_private_file(path)
}

#[cfg(unix)]
fn harden_private_dir(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).is_ok()
}

#[cfg(not(unix))]
fn harden_private_dir(_path: &Path) -> bool {
    true
}

#[cfg(unix)]
fn harden_private_file(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
}

#[cfg(not(unix))]
fn harden_private_file(_path: &Path) -> std::io::Result<()> {
    Ok(())
}
