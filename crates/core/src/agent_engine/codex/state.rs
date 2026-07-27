use std::collections::HashMap;
use std::fs;
use std::sync::{Mutex, OnceLock};
#[cfg(target_os = "android")]
use std::time::Instant;

use serde::{Deserialize, Serialize};

#[cfg(target_os = "android")]
use super::protocol::JsonRpcClient;
use crate::agent_engine::AgentEngineTurnRequest;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct CodexSessionState {
    pub(crate) native_thread_id: Option<String>,
}

#[cfg(target_os = "android")]
pub(crate) struct ActiveCodexSession {
    pub(crate) pty: u64,
    pub(crate) rpc: JsonRpcClient,
    pub(crate) buffer: String,
    pub(crate) running: bool,
    pub(crate) last_used: Instant,
    pub(crate) human_responses: Vec<(String, String)>,
}

#[cfg(target_os = "android")]
static ACTIVE_CODEX_SESSIONS: OnceLock<Mutex<HashMap<String, ActiveCodexSession>>> =
    OnceLock::new();

#[cfg(target_os = "android")]
#[derive(Debug, Clone)]
pub(crate) struct PendingCodexHumanRequest {
    pub(crate) session_key: String,
    pub(crate) rpc_id: String,
    pub(crate) question_id: String,
}

#[cfg(target_os = "android")]
static PENDING_CODEX_HUMAN_REQUESTS: OnceLock<Mutex<HashMap<String, PendingCodexHumanRequest>>> =
    OnceLock::new();

#[cfg(target_os = "android")]
pub(crate) fn pending_human_requests() -> &'static Mutex<HashMap<String, PendingCodexHumanRequest>>
{
    PENDING_CODEX_HUMAN_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(target_os = "android")]
pub(crate) fn active_sessions() -> &'static Mutex<HashMap<String, ActiveCodexSession>> {
    ACTIVE_CODEX_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

static ANDROID_NATIVE_LIBRARY_DIRS: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();

fn native_dirs() -> &'static Mutex<HashMap<String, String>> {
    ANDROID_NATIVE_LIBRARY_DIRS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn register_android_native_library_dir(
    files_dir: &str,
    native_library_dir: Option<&str>,
) {
    let Some(native_library_dir) = native_library_dir else {
        return;
    };
    if let Ok(mut guard) = native_dirs().lock() {
        guard.insert(files_dir.to_string(), native_library_dir.to_string());
    }
}

pub(crate) fn native_library_dir_for(files_dir: &str) -> Option<String> {
    native_dirs()
        .lock()
        .ok()
        .and_then(|guard| guard.get(files_dir).cloned())
}

pub(crate) fn session_key(request: &AgentEngineTurnRequest) -> String {
    format!(
        "{}::{}::{}",
        request.account_id, request.agent_id, request.session_key_json
    )
}

pub(crate) fn load_state(files_dir: &str, key: &str) -> CodexSessionState {
    let path = state_path(files_dir, key);
    fs::read_to_string(path)
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

pub(crate) fn save_state(files_dir: &str, key: &str, state: &CodexSessionState) {
    let path = state_path(files_dir, key);
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(raw) = serde_json::to_string_pretty(state) {
        let _ = fs::write(path, raw);
    }
}

fn state_path(files_dir: &str, key: &str) -> std::path::PathBuf {
    let safe = key
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect::<String>();
    std::path::Path::new(files_dir)
        .join("agent_engine")
        .join("codex")
        .join(format!("{safe}.json"))
}
