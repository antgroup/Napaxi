use std::collections::HashMap;
use std::fs;
use std::sync::{Mutex, OnceLock};
#[cfg(any(target_os = "android", target_os = "ios"))]
use std::time::Instant;

use serde::{Deserialize, Serialize};

#[cfg(any(target_os = "android", target_os = "ios"))]
use super::protocol::JsonRpcClient;
use crate::agent_engine::AgentEngineTurnRequest;

#[cfg(target_os = "android")]
use crate::android_linux_env as linux_env;
#[cfg(target_os = "ios")]
use crate::ios_qemu_env as linux_env;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct CodexSessionState {
    pub(crate) native_thread_id: Option<String>,
    #[serde(default)]
    pub(crate) config_fingerprint: String,
    #[serde(default)]
    pub(crate) dynamic_tools_fingerprint: String,
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(crate) struct ActiveCodexSession {
    pub(crate) pty: u64,
    pub(crate) rpc: JsonRpcClient,
    pub(crate) buffer: String,
    pub(crate) running: bool,
    pub(crate) last_used: Instant,
    pub(crate) human_responses: Vec<(String, String)>,
    pub(crate) files_dir: String,
    pub(crate) config_fingerprint: String,
    pub(crate) dynamic_tools_fingerprint: String,
    pub(crate) close_after_turn: bool,
}

#[cfg(any(target_os = "android", target_os = "ios"))]
static ACTIVE_CODEX_SESSIONS: OnceLock<Mutex<HashMap<String, ActiveCodexSession>>> =
    OnceLock::new();

#[cfg(any(target_os = "android", target_os = "ios"))]
#[derive(Debug, Clone)]
pub(crate) struct PendingCodexHumanRequest {
    pub(crate) session_key: String,
    pub(crate) rpc_id: String,
    pub(crate) question_id: String,
}

#[cfg(any(target_os = "android", target_os = "ios"))]
static PENDING_CODEX_HUMAN_REQUESTS: OnceLock<Mutex<HashMap<String, PendingCodexHumanRequest>>> =
    OnceLock::new();

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(crate) fn pending_human_requests() -> &'static Mutex<HashMap<String, PendingCodexHumanRequest>>
{
    PENDING_CODEX_HUMAN_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(crate) fn active_sessions() -> &'static Mutex<HashMap<String, ActiveCodexSession>> {
    ACTIVE_CODEX_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(crate) fn remove_active_session(key: &str) -> Option<ActiveCodexSession> {
    let active = active_sessions().lock().ok()?.remove(key);
    if active.is_some() {
        remove_pending_human_requests_for_session(key);
    }
    active
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn remove_pending_human_requests_for_session(key: &str) {
    if let Ok(mut guard) = pending_human_requests().lock() {
        guard.retain(|_, pending| pending.session_key != key);
    }
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(crate) fn invalidate_sessions_for_config(files_dir: &str, fingerprint: Option<&str>) {
    clear_stale_native_thread_mappings(files_dir, fingerprint);
    let (stale, running_marked) = {
        let Ok(mut guard) = active_sessions().lock() else {
            return;
        };
        let mut running_marked = 0usize;
        let keys = guard
            .iter_mut()
            .filter_map(|(key, active)| {
                if active.files_dir != files_dir
                    || fingerprint.is_some_and(|value| active.config_fingerprint == value)
                {
                    return None;
                }
                if active.running {
                    active.close_after_turn = true;
                    running_marked += 1;
                    None
                } else {
                    Some(key.clone())
                }
            })
            .collect::<Vec<_>>();
        let stale = keys
            .into_iter()
            .filter_map(|key| guard.remove(&key))
            .collect::<Vec<_>>();
        (stale, running_marked)
    };
    if !stale.is_empty() || running_marked > 0 {
        log::info!(
            "[napaxiCodexTrace] invalidated Codex sessions for config: closed_idle={} close_after_turn={}",
            stale.len(),
            running_marked,
        );
    }
    for active in stale {
        // This path is used by the Flutter settings save flow through a
        // synchronous FFI call. Do not wait for proot/app-server teardown here:
        // an uncooperative child can otherwise block the UI thread long enough
        // to look like a settings-save freeze or trigger an Android ANR.
        let _ = linux_env::pty::close_pty_session_nonblocking(active.pty);
    }
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
    session_key_parts(
        &request.account_id,
        &request.agent_id,
        &request.session_key_json,
    )
}

pub(crate) fn session_key_parts(
    account_id: &str,
    agent_id: &str,
    session_key_json: &str,
) -> String {
    format!("{account_id}::{agent_id}::{session_key_json}")
}

pub(crate) fn bind_native_thread(
    files_dir: &str,
    account_id: &str,
    agent_id: &str,
    session_key_json: &str,
    native_thread_id: &str,
    config_fingerprint: &str,
) {
    let key = session_key_parts(account_id, agent_id, session_key_json);
    save_state(
        files_dir,
        &key,
        &CodexSessionState {
            native_thread_id: Some(native_thread_id.to_string()),
            config_fingerprint: config_fingerprint.to_string(),
            dynamic_tools_fingerprint: String::new(),
        },
    );
}

pub(crate) fn set_current_config_fingerprint(files_dir: &str, fingerprint: Option<&str>) {
    let path = state_dir(files_dir).join("config_fingerprint");
    let Some(fingerprint) = fingerprint else {
        let _ = fs::remove_file(path);
        return;
    };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::write(path, fingerprint);
}

pub(crate) fn current_config_fingerprint(files_dir: &str) -> Option<String> {
    fs::read_to_string(state_dir(files_dir).join("config_fingerprint"))
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
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

#[cfg(any(target_os = "android", target_os = "ios", test))]
pub(crate) fn clear_state(files_dir: &str, key: &str) {
    let _ = fs::remove_file(state_path(files_dir, key));
}

#[cfg(any(target_os = "android", target_os = "ios", test))]
fn clear_stale_native_thread_mappings(files_dir: &str, fingerprint: Option<&str>) {
    let Ok(entries) = fs::read_dir(state_dir(files_dir)) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let keep = fingerprint.is_some_and(|expected| {
            fs::read_to_string(&path)
                .ok()
                .and_then(|raw| serde_json::from_str::<CodexSessionState>(&raw).ok())
                .is_some_and(|state| state.config_fingerprint == expected)
        });
        if !keep {
            let _ = fs::remove_file(path);
        }
    }
}

fn state_path(files_dir: &str, key: &str) -> std::path::PathBuf {
    let safe = key
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect::<String>();
    state_dir(files_dir).join(format!("{safe}.json"))
}

fn state_dir(files_dir: &str) -> std::path::PathBuf {
    std::path::Path::new(files_dir)
        .join("agent_engine")
        .join("codex")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clears_persisted_native_thread_mappings_after_config_change() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy();
        let state = CodexSessionState {
            native_thread_id: Some("thread-old".to_string()),
            config_fingerprint: "fingerprint-old".to_string(),
            dynamic_tools_fingerprint: "tools-old".to_string(),
        };
        save_state(&files_dir, "session-one", &state);
        save_state(&files_dir, "session-two", &state);

        clear_stale_native_thread_mappings(&files_dir, None);

        assert!(
            load_state(&files_dir, "session-one")
                .native_thread_id
                .is_none()
        );
        assert!(
            load_state(&files_dir, "session-two")
                .native_thread_id
                .is_none()
        );
    }

    #[test]
    fn keeps_only_native_thread_mappings_for_the_current_config() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy();
        save_state(
            &files_dir,
            "current",
            &CodexSessionState {
                native_thread_id: Some("thread-current".to_string()),
                config_fingerprint: "fingerprint-current".to_string(),
                dynamic_tools_fingerprint: "tools-current".to_string(),
            },
        );
        save_state(
            &files_dir,
            "stale",
            &CodexSessionState {
                native_thread_id: Some("thread-stale".to_string()),
                config_fingerprint: "fingerprint-stale".to_string(),
                dynamic_tools_fingerprint: "tools-stale".to_string(),
            },
        );

        clear_stale_native_thread_mappings(&files_dir, Some("fingerprint-current"));

        assert_eq!(
            load_state(&files_dir, "current")
                .native_thread_id
                .as_deref(),
            Some("thread-current")
        );
        assert!(load_state(&files_dir, "stale").native_thread_id.is_none());
    }

    #[test]
    fn binds_recovered_native_thread_to_runtime_session_key() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy();
        let session_json = r#"{"channel_type":"app","account_id":"user","thread_id":"ui"}"#;

        bind_native_thread(
            &files_dir,
            "user",
            "engine.codex",
            session_json,
            "native-thread",
            "fingerprint",
        );

        let state = load_state(
            &files_dir,
            &session_key_parts("user", "engine.codex", session_json),
        );
        assert_eq!(state.native_thread_id.as_deref(), Some("native-thread"));
        assert_eq!(state.config_fingerprint, "fingerprint");
        let mut rpc = super::super::protocol::JsonRpcClient::new();
        let (_, request, is_resume) =
            super::super::protocol::thread_open_request(&mut rpc, &state, None, &[]);
        let request: serde_json::Value = serde_json::from_str(&request).unwrap();
        assert!(is_resume);
        assert_eq!(request["method"], "thread/resume");
        assert_eq!(request["params"]["threadId"], "native-thread");
    }

    #[test]
    fn persists_and_clears_current_config_fingerprint() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy();
        set_current_config_fingerprint(&files_dir, Some("current"));
        assert_eq!(
            current_config_fingerprint(&files_dir).as_deref(),
            Some("current")
        );
        set_current_config_fingerprint(&files_dir, None);
        assert!(current_config_fingerprint(&files_dir).is_none());
    }
}
