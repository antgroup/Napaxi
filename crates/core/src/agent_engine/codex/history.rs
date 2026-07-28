#![cfg_attr(not(any(target_os = "android", test)), allow(dead_code))]

use serde::Deserialize;
use serde_json::{Value, json};

const HISTORY_OPERATION_PREFIX: &str = "history_";
#[cfg(target_os = "android")]
const CODEX_WORKSPACE: &str = "/workspace";

#[cfg(target_os = "android")]
use std::time::{Duration, Instant};

#[cfg(target_os = "android")]
use super::config;
#[cfg(target_os = "android")]
use super::protocol::{
    JsonRpcClient, initialize_request, initialized_notification, parse_json_lines, response_error,
    response_id, thread_delete_request, thread_history_resume_request, thread_list_request,
    thread_read_request,
};
#[cfg(target_os = "android")]
use super::state::{
    bind_native_thread, clear_state, current_config_fingerprint, load_state,
    native_library_dir_for, remove_active_session, session_key_parts,
};

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
#[derive(Debug, Default, Deserialize)]
struct CodexHistoryRequest {
    #[serde(default)]
    operation: String,
    #[serde(default)]
    thread_id: String,
    #[serde(default)]
    account_id: String,
    #[serde(default)]
    agent_id: String,
    #[serde(default)]
    session_key_json: String,
}

pub(crate) fn is_history_request(raw: &str) -> bool {
    serde_json::from_str::<Value>(raw)
        .ok()
        .and_then(|value| value.get("operation")?.as_str().map(str::to_string))
        .is_some_and(|operation| operation.starts_with(HISTORY_OPERATION_PREFIX))
}

pub(crate) fn handle_request_json(handle: i64, raw: &str) -> String {
    let request = match serde_json::from_str::<CodexHistoryRequest>(raw) {
        Ok(request) => request,
        Err(error) => {
            return history_error(
                false,
                "history_query_failed",
                format!("Invalid Codex history request: {error}"),
            );
        }
    };
    handle_request(handle, request)
}

#[cfg(not(target_os = "android"))]
fn handle_request(_handle: i64, _request: CodexHistoryRequest) -> String {
    history_error(
        false,
        "unsupported_platform",
        "napaxi.agent_engine.codex is unsupported on this platform",
    )
}

#[cfg(target_os = "android")]
fn handle_request(handle: i64, request: CodexHistoryRequest) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return history_error(false, "unsupported_platform", "invalid engine handle");
    };
    match request.operation.as_str() {
        "history_list_threads" => list_threads(handle, &files_dir, &request),
        "history_read_thread" => read_thread(handle, &files_dir, &request),
        "history_bind_thread" => bind_thread(&files_dir, &request),
        "history_delete_thread" => delete_thread(handle, &files_dir, &request),
        _ => history_error(
            true,
            "history_query_failed",
            format!("Unknown Codex history operation: {}", request.operation),
        ),
    }
}

#[cfg(target_os = "android")]
fn list_threads(handle: i64, files_dir: &str, request: &CodexHistoryRequest) -> String {
    let mut rpc = match HistoryRpc::open(handle, files_dir, request) {
        Ok(rpc) => rpc,
        Err(error) => return history_error(true, "history_query_failed", error.to_string()),
    };
    let mut data = match rpc.list(Some(CODEX_WORKSPACE)) {
        Ok(data) => data,
        Err(error) => return history_error(true, "history_query_failed", error.to_string()),
    };
    if data.is_empty() {
        data = match rpc.list(None) {
            Ok(data) => data,
            Err(error) => return history_error(true, "history_query_failed", error.to_string()),
        };
    }
    let threads = data
        .iter()
        .filter_map(map_thread_summary)
        .collect::<Vec<_>>();
    history_success(json!({"threads": threads}))
}

#[cfg(target_os = "android")]
fn read_thread(handle: i64, files_dir: &str, request: &CodexHistoryRequest) -> String {
    let thread_id = request.thread_id.trim();
    if thread_id.is_empty() {
        return history_error(true, "missing_native_thread", "Codex thread ID is required");
    }
    let mut rpc = match HistoryRpc::open(handle, files_dir, request) {
        Ok(rpc) => rpc,
        Err(error) => return history_error(true, "history_query_failed", error.to_string()),
    };
    let resume = rpc.resume(thread_id).ok();
    let mut items = extract_thread_items(resume.as_ref());
    if items.is_empty() {
        let read = match rpc.read(thread_id) {
            Ok(read) => read,
            Err(error) => return history_error(true, "history_query_failed", error.to_string()),
        };
        items = extract_thread_items(Some(&read));
    }
    let mut messages = map_history_items(&items);
    if let Some(rollout_messages) =
        history_rollout::read_persisted_rollout_messages(files_dir, thread_id)
    {
        if history_rollout::history_messages_are_more_complete(&rollout_messages, &messages) {
            messages = rollout_messages;
        }
    }
    history_success(json!({"nativeThreadId": thread_id, "messages": messages}))
}

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
#[path = "history_rollout.rs"]
mod history_rollout;

#[cfg(target_os = "android")]
fn delete_thread(handle: i64, files_dir: &str, request: &CodexHistoryRequest) -> String {
    let requested_thread_id = request.thread_id.trim();
    let session_key = (!request.session_key_json.trim().is_empty()).then(|| {
        session_key_parts(
            normalized_account_id(&request.account_id),
            normalized_agent_id(&request.agent_id),
            &request.session_key_json,
        )
    });
    let stored_native_thread_id = session_key
        .as_deref()
        .and_then(|key| load_state(files_dir, key).native_thread_id);
    let thread_id = stored_native_thread_id
        .as_deref()
        .unwrap_or(requested_thread_id)
        .trim();
    if thread_id.is_empty() {
        return history_error(true, "missing_native_thread", "Codex thread ID is required");
    }
    let mut rpc = match HistoryRpc::open(handle, files_dir, request) {
        Ok(rpc) => rpc,
        Err(error) => return history_error(true, "history_query_failed", error.to_string()),
    };
    if let Err(error) = rpc.delete(thread_id) {
        return history_error(true, "history_query_failed", error.to_string());
    }
    if let Some(key) = session_key {
        clear_state(files_dir, &key);
        if let Some(active) = remove_active_session(&key) {
            let _ = crate::android_linux_env::pty::close_pty_session_nonblocking(active.pty);
        }
    }
    history_success(json!({"nativeThreadId": thread_id}))
}

#[cfg(target_os = "android")]
fn bind_thread(files_dir: &str, request: &CodexHistoryRequest) -> String {
    let thread_id = request.thread_id.trim();
    if thread_id.is_empty() || request.session_key_json.trim().is_empty() {
        return history_error(
            true,
            "missing_native_thread",
            "Codex thread ID and session key are required",
        );
    }
    let Some(fingerprint) = current_config_fingerprint(files_dir) else {
        return history_error(
            true,
            "missing_main_model",
            "Codex main model configuration must be synchronized before binding history",
        );
    };
    bind_native_thread(
        files_dir,
        normalized_account_id(&request.account_id),
        normalized_agent_id(&request.agent_id),
        &request.session_key_json,
        thread_id,
        &fingerprint,
    );
    history_success(json!({"nativeThreadId": thread_id}))
}

#[cfg(target_os = "android")]
struct HistoryRpc {
    pty: u64,
    rpc: JsonRpcClient,
    buffer: String,
}

#[cfg(target_os = "android")]
impl HistoryRpc {
    fn open(handle: i64, files_dir: &str, request: &CodexHistoryRequest) -> anyhow::Result<Self> {
        let config_dir = config::config_dir(files_dir);
        if !config_dir.join("config.toml").is_file() || !config_dir.join("auth.json").is_file() {
            anyhow::bail!("Codex sandbox configuration is missing");
        }
        let native_library_dir = native_library_dir_for(files_dir).ok_or_else(|| {
            anyhow::anyhow!("missing native_library_dir for Android Codex history")
        })?;
        let workspace_files_dir =
            crate::runtime::default_engine_workspace_files_dir_from_handle(handle)
                .unwrap_or_else(|| files_dir.to_string());
        let workspace_dir = crate::storage::FileBridge::new_with_workspace_files_dir(
            files_dir,
            &workspace_files_dir,
        )
        .workspace_dir()
        .display()
        .to_string();
        let argv = vec![
            "/bin/sh".to_string(),
            "-lc".to_string(),
            "mkdir -p /workspace /root/.codex && stty raw -echo -icanon -ixon -ixoff 2>/dev/null; export HOME=/root CODEX_HOME=/root/.codex PATH=\"/root/.local/bin:$PATH\"; exec codex app-server 2>&1".to_string(),
        ];
        let pty = crate::android_linux_env::pty::open_pty_session(
            files_dir,
            &native_library_dir,
            &workspace_dir,
            &argv,
            Some(CODEX_WORKSPACE),
            120,
            40,
        )?;
        let mut rpc = JsonRpcClient::new();
        let (initialize_id, initialize) = initialize_request(&mut rpc);
        let mut history_rpc = Self {
            pty,
            rpc,
            buffer: String::new(),
        };
        history_rpc.call(initialize_id, &initialize, Duration::from_secs(15))?;
        let initialized = initialized_notification(&history_rpc.rpc);
        crate::android_linux_env::pty::write_pty_session(pty, &(initialized + "\n"))?;
        Ok(history_rpc)
    }

    fn list(&mut self, cwd: Option<&str>) -> anyhow::Result<Vec<Value>> {
        let (id, line) = thread_list_request(&mut self.rpc, cwd);
        let result = self.call(id, &line, Duration::from_secs(10))?;
        Ok(result
            .get("data")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default())
    }

    fn resume(&mut self, thread_id: &str) -> anyhow::Result<Value> {
        let (id, line) = thread_history_resume_request(&mut self.rpc, thread_id);
        self.call(id, &line, Duration::from_secs(15))
    }

    fn read(&mut self, thread_id: &str) -> anyhow::Result<Value> {
        let (id, line) = thread_read_request(&mut self.rpc, thread_id);
        self.call(id, &line, Duration::from_secs(15))
    }

    fn delete(&mut self, thread_id: &str) -> anyhow::Result<Value> {
        let (id, line) = thread_delete_request(&mut self.rpc, thread_id);
        self.call(id, &line, Duration::from_secs(15))
    }

    fn call(&mut self, id: u64, line: &str, timeout: Duration) -> anyhow::Result<Value> {
        crate::android_linux_env::pty::write_pty_session(self.pty, &(line.to_string() + "\n"))?;
        let started = Instant::now();
        while started.elapsed() < timeout {
            for event in crate::android_linux_env::pty::drain_pty_events(self.pty)? {
                match event.kind {
                    crate::android_linux_env::pty::PtyEventKind::Output => {
                        for message in parse_json_lines(&mut self.buffer, &event.data) {
                            if response_id(&message) != Some(id) {
                                continue;
                            }
                            if let Some(error) = response_error(&message) {
                                anyhow::bail!(error);
                            }
                            return Ok(message.get("result").cloned().unwrap_or(Value::Null));
                        }
                    }
                    crate::android_linux_env::pty::PtyEventKind::Exit
                    | crate::android_linux_env::pty::PtyEventKind::Closed => {
                        anyhow::bail!("Codex app-server exited while reading history");
                    }
                    crate::android_linux_env::pty::PtyEventKind::Log => {}
                }
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        anyhow::bail!("Codex history request timed out")
    }
}

#[cfg(target_os = "android")]
impl Drop for HistoryRpc {
    fn drop(&mut self) {
        let _ = crate::android_linux_env::pty::close_pty_session_nonblocking(self.pty);
    }
}

#[cfg(target_os = "android")]
fn normalized_account_id(value: &str) -> &str {
    if value.trim().is_empty() {
        "default"
    } else {
        value
    }
}

#[cfg(target_os = "android")]
fn normalized_agent_id(value: &str) -> &str {
    if value.trim().is_empty() {
        "engine.codex"
    } else {
        value
    }
}

#[path = "history_mapping.rs"]
mod history_mapping;
#[cfg(target_os = "android")]
use history_mapping::{extract_thread_items, map_history_items, map_thread_summary};

#[cfg(target_os = "android")]
fn history_success(extra: Value) -> String {
    let mut result = json!({
        "success": true,
        "providerAvailable": true,
        "errorCode": null,
        "error": null,
        "threads": [],
        "messages": [],
        "nativeThreadId": "",
    });
    if let (Some(target), Some(extra)) = (result.as_object_mut(), extra.as_object()) {
        target.extend(extra.clone());
    }
    result.to_string()
}

fn history_error(
    provider_available: bool,
    error_code: impl Into<String>,
    error: impl Into<String>,
) -> String {
    json!({
        "success": false,
        "providerAvailable": provider_available,
        "errorCode": error_code.into(),
        "error": error.into(),
        "threads": [],
        "messages": [],
        "nativeThreadId": "",
    })
    .to_string()
}
