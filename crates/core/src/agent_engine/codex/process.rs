#[cfg(target_os = "android")]
use std::time::{Duration, Instant};

use serde::Deserialize;
use serde_json::json;

use crate::agent_engine::AgentEngineTurnRequest;
use crate::types::ChatEvent;

#[cfg(target_os = "android")]
use super::events::map_app_server_message;
#[cfg(target_os = "android")]
use super::protocol::{
    JsonRpcClient, extract_thread_id, parse_json_lines, response_error, response_id,
    startup_requests, thread_open_request, thread_start_request, turn_start_request,
};
#[cfg(target_os = "android")]
use super::state::{
    PendingCodexHumanRequest, active_sessions, load_state, native_library_dir_for,
    pending_human_requests, save_state, session_key,
};

#[cfg(not(target_os = "android"))]
const CODEX_UNSUPPORTED: &str = "napaxi.agent_engine.codex is unsupported on this platform";
#[cfg(target_os = "android")]
const CODEX_STARTUP_TIMEOUT: Duration = Duration::from_secs(5);
#[cfg(target_os = "android")]
const CODEX_TURN_TIMEOUT: Duration = Duration::from_secs(60 * 60);
#[cfg(target_os = "android")]
const CODEX_IDLE_TIMEOUT: Duration = Duration::from_secs(10 * 60);

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
#[derive(Debug, Deserialize)]
struct ConfigureCodexRequest {
    #[serde(default)]
    files_dir: String,
    #[serde(default)]
    config_toml: String,
    #[serde(default)]
    auth_json: String,
}

pub(crate) fn configure_codex_agent_engine_json(_handle: i64, request_json: &str) -> String {
    let mut request = match serde_json::from_str::<ConfigureCodexRequest>(request_json) {
        Ok(request) => request,
        Err(error) => {
            return json!({"success":false,"error":format!("Invalid Codex config request JSON: {error}")}).to_string();
        }
    };
    if let Some(files_dir) = crate::runtime::files_dir_from_handle(_handle) {
        request.files_dir = files_dir;
    }
    if request.files_dir.trim().is_empty() {
        return json!({
            "success": false,
            "providerAvailable": false,
            "error": "invalid engine handle or missing files_dir",
        })
        .to_string();
    }
    configure_codex_agent_engine(request)
}

#[cfg(not(target_os = "android"))]
fn configure_codex_agent_engine(_request: ConfigureCodexRequest) -> String {
    json!({"success":false,"providerAvailable":false,"error":CODEX_UNSUPPORTED}).to_string()
}

#[cfg_attr(not(any(target_os = "android", test)), allow(dead_code))]
fn codex_config_dir(files_dir: &str) -> std::path::PathBuf {
    std::path::Path::new(files_dir)
        .join("linux-env")
        .join("rootfs")
        .join("root")
        .join(".codex")
}

#[cfg(target_os = "android")]
fn configure_codex_agent_engine(request: ConfigureCodexRequest) -> String {
    let codex_dir = codex_config_dir(&request.files_dir);
    let result = (|| -> anyhow::Result<()> {
        std::fs::create_dir_all(&codex_dir)?;
        if !request.config_toml.is_empty() {
            std::fs::write(codex_dir.join("config.toml"), request.config_toml)?;
        }
        if !request.auth_json.is_empty() {
            std::fs::write(codex_dir.join("auth.json"), request.auth_json)?;
        }
        Ok(())
    })();
    match result {
        Ok(()) => json!({"success":true,"providerAvailable":true}).to_string(),
        Err(error) => {
            json!({"success":false,"providerAvailable":true,"error":error.to_string()}).to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_config_dir_targets_linux_env_rootfs_home() {
        assert_eq!(
            codex_config_dir("app_files"),
            std::path::Path::new("app_files")
                .join("linux-env")
                .join("rootfs")
                .join("root")
                .join(".codex"),
        );
    }
}

#[cfg(not(target_os = "android"))]
pub(crate) async fn run_codex_turn<F, C>(
    request: AgentEngineTurnRequest,
    mut emit: F,
    _is_cancelled: C,
) -> Vec<ChatEvent>
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool,
{
    let event = ChatEvent::Error {
        message: CODEX_UNSUPPORTED.to_string(),
    };
    emit(event.clone());
    let _ = request;
    vec![event]
}

#[cfg(target_os = "android")]
pub(crate) async fn run_codex_turn<F, C>(
    request: AgentEngineTurnRequest,
    mut emit: F,
    mut is_cancelled: C,
) -> Vec<ChatEvent>
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool,
{
    if is_cancelled() {
        return vec![ChatEvent::Interrupted];
    }

    let native_library_dir = request
        .engine_config
        .get("native_library_dir")
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .or_else(|| native_library_dir_for(&request.files_dir));
    let Some(native_library_dir) = native_library_dir else {
        let event = ChatEvent::Error {
            message: "missing native_library_dir for Android Codex agent engine".to_string(),
        };
        emit(event.clone());
        return vec![event];
    };

    let key = session_key(&request);
    let mut state = load_state(&request.files_dir, &key);
    let (pty, start_action) =
        match acquire_session_process(&request, &native_library_dir, &key, &state) {
            Ok(value) => value,
            Err(error) => {
                let event = ChatEvent::Error {
                    message: error.to_string(),
                };
                emit(event.clone());
                return vec![event];
            }
        };

    let mut pending_thread_open = None;
    let mut sent_turn = false;
    match start_action {
        StartAction::OpenThread {
            request_id,
            line,
            is_resume,
        } => {
            pending_thread_open = Some((request_id, is_resume));
            if let Err(error) = write_line(pty, &line) {
                release_session_process(&key, true);
                let event = ChatEvent::Error {
                    message: error.to_string(),
                };
                emit(event.clone());
                return vec![event];
            }
        }
        StartAction::StartTurn { line } => {
            sent_turn = true;
            if let Err(error) = write_line(pty, &line) {
                release_session_process(&key, true);
                let event = ChatEvent::Error {
                    message: error.to_string(),
                };
                emit(event.clone());
                return vec![event];
            }
        }
    }

    let mut events = Vec::new();
    let started = Instant::now();
    let mut saw_completion = false;
    let mut should_close = false;
    loop {
        if is_cancelled() {
            let event = ChatEvent::Interrupted;
            emit(event.clone());
            events.push(event);
            should_close = true;
            break;
        }
        if started.elapsed() > CODEX_TURN_TIMEOUT {
            let event = ChatEvent::Error {
                message: "Codex agent engine turn timed out".to_string(),
            };
            emit(event.clone());
            events.push(event);
            should_close = true;
            break;
        }
        for (request_id, response) in drain_human_responses(&key) {
            let event = ChatEvent::HumanResponse {
                request_id,
                response,
            };
            emit(event.clone());
            events.push(event);
        }
        match crate::android_linux_env::pty::drain_pty_events(pty) {
            Ok(drained) => {
                for event in drained {
                    match event.kind {
                        crate::android_linux_env::pty::PtyEventKind::Output => {
                            let messages = {
                                let sessions = active_sessions();
                                let mut guard = sessions.lock().map_err(|e| e.to_string()).ok();
                                guard
                                    .as_mut()
                                    .and_then(|guard| guard.get_mut(&key))
                                    .map(|active| {
                                        active.last_used = Instant::now();
                                        parse_json_lines(&mut active.buffer, &event.data)
                                    })
                                    .unwrap_or_default()
                            };
                            for message in messages {
                                log_codex_runtime_message(&message);
                                if let Some((open_id, is_resume)) = pending_thread_open {
                                    if response_id(&message) == Some(open_id) {
                                        if let Some(error) = response_error(&message) {
                                            if is_resume {
                                                let start_line = with_active_rpc(&key, |rpc| {
                                                    let (id, line) = thread_start_request(rpc);
                                                    pending_thread_open = Some((id, false));
                                                    line
                                                });
                                                if let Some(start_line) = start_line {
                                                    if let Err(error) = write_line(pty, &start_line)
                                                    {
                                                        let event = ChatEvent::Error {
                                                            message: error.to_string(),
                                                        };
                                                        emit(event.clone());
                                                        events.push(event);
                                                        saw_completion = true;
                                                        should_close = true;
                                                        break;
                                                    }
                                                } else {
                                                    let event = ChatEvent::Error {
                                                        message: "Codex session registry entry disappeared"
                                                            .to_string(),
                                                    };
                                                    emit(event.clone());
                                                    events.push(event);
                                                    saw_completion = true;
                                                    should_close = true;
                                                    break;
                                                }
                                                let _ = error;
                                                continue;
                                            }
                                            let event = ChatEvent::Error {
                                                message: format!("thread/start failed: {error}"),
                                            };
                                            emit(event.clone());
                                            events.push(event);
                                            saw_completion = true;
                                            should_close = true;
                                            break;
                                        }
                                        if let Some(thread_id) = extract_thread_id(&message) {
                                            state.native_thread_id = Some(thread_id);
                                            save_state(&request.files_dir, &key, &state);
                                        }
                                        if state.native_thread_id.is_none() {
                                            // Newer Codex app-server builds may acknowledge thread/start
                                            // separately from the thread/started notification that carries
                                            // the actual thread id. Keep waiting instead of failing this turn.
                                            continue;
                                        }
                                        pending_thread_open = None;
                                        if let Err(event) = write_turn_after_thread_open(
                                            pty, &key, &request, &state,
                                        ) {
                                            emit(event.clone());
                                            events.push(event);
                                            saw_completion = true;
                                            should_close = true;
                                            break;
                                        }
                                        sent_turn = true;
                                        continue;
                                    }
                                }
                                if let Some(thread_id) = extract_thread_id(&message) {
                                    state.native_thread_id = Some(thread_id);
                                    save_state(&request.files_dir, &key, &state);
                                    if pending_thread_open.is_some() {
                                        pending_thread_open = None;
                                        if let Err(event) = write_turn_after_thread_open(
                                            pty, &key, &request, &state,
                                        ) {
                                            emit(event.clone());
                                            events.push(event);
                                            saw_completion = true;
                                            should_close = true;
                                            break;
                                        }
                                        sent_turn = true;
                                        continue;
                                    }
                                }
                                let mapped = map_app_server_message(&message);
                                #[cfg(target_os = "android")]
                                if let Some(human_request) = mapped.human_request.as_ref() {
                                    register_human_request(
                                        &key,
                                        &human_request.request_id,
                                        &human_request.rpc_id,
                                        &human_request.question_id,
                                    );
                                }
                                if let Some(event) = mapped.event {
                                    emit(event.clone());
                                    events.push(event);
                                }
                                if mapped.completed {
                                    saw_completion = true;
                                    if mapped.failed {
                                        should_close = true;
                                        break;
                                    }
                                }
                            }
                        }
                        crate::android_linux_env::pty::PtyEventKind::Exit
                        | crate::android_linux_env::pty::PtyEventKind::Closed => {
                            if !saw_completion {
                                let event = ChatEvent::Error {
                                    message: "Codex app-server exited before the turn completed"
                                        .to_string(),
                                };
                                emit(event.clone());
                                events.push(event);
                            }
                            saw_completion = true;
                            should_close = true;
                        }
                        crate::android_linux_env::pty::PtyEventKind::Log => {}
                    }
                }
            }
            Err(error) => {
                let event = ChatEvent::Error {
                    message: error.to_string(),
                };
                emit(event.clone());
                events.push(event);
                should_close = true;
                break;
            }
        }
        if !sent_turn && started.elapsed() > CODEX_STARTUP_TIMEOUT && pending_thread_open.is_some()
        {
            let event = ChatEvent::Error {
                message: "Codex app-server did not open a thread before startup timeout"
                    .to_string(),
            };
            emit(event.clone());
            events.push(event);
            should_close = true;
            break;
        }
        if saw_completion {
            break;
        }
        std::thread::sleep(Duration::from_millis(30));
    }
    release_session_process(&key, should_close);
    events
}

#[cfg(target_os = "android")]
enum StartAction {
    OpenThread {
        request_id: u64,
        line: String,
        is_resume: bool,
    },
    StartTurn {
        line: String,
    },
}

#[cfg(target_os = "android")]
fn acquire_session_process(
    request: &AgentEngineTurnRequest,
    native_library_dir: &str,
    key: &str,
    state: &super::state::CodexSessionState,
) -> anyhow::Result<(u64, StartAction)> {
    cleanup_idle_sessions();
    let sessions = active_sessions();
    let mut guard = sessions
        .lock()
        .map_err(|e| anyhow::anyhow!("Codex session registry lock poisoned: {e}"))?;
    if let Some(active) = guard.get_mut(key) {
        if active.running {
            anyhow::bail!("Codex agent engine session already has an active turn");
        }
        active.running = true;
        active.last_used = Instant::now();
        let action = if state.native_thread_id.is_some() {
            StartAction::StartTurn {
                line: turn_start_request(&mut active.rpc, request, state),
            }
        } else {
            let (request_id, line, is_resume) = thread_open_request(&mut active.rpc, state);
            StartAction::OpenThread {
                request_id,
                line,
                is_resume,
            }
        };
        return Ok((active.pty, action));
    }

    let argv = vec![
        "/bin/sh".to_string(),
        "-lc".to_string(),
        "mkdir -p /workspace/codex /root/.codex && stty raw -echo -icanon -ixon -ixoff 2>/dev/null; export HOME=/root CODEX_HOME=/root/.codex PATH=\"/root/.local/bin:$PATH\"; exec codex app-server 2>&1".to_string(),
    ];
    let pty = crate::android_linux_env::pty::open_pty_session(
        &request.files_dir,
        native_library_dir,
        &request.workspace_files_dir,
        &argv,
        Some("/workspace/codex"),
        120,
        40,
    )?;
    let mut rpc = JsonRpcClient::new();
    for request_line in startup_requests(&mut rpc) {
        let _ = crate::android_linux_env::pty::write_pty_session(pty, &(request_line + "\n"));
    }
    let (request_id, line, is_resume) = thread_open_request(&mut rpc, state);
    let action = StartAction::OpenThread {
        request_id,
        line,
        is_resume,
    };
    guard.insert(
        key.to_string(),
        super::state::ActiveCodexSession {
            pty,
            rpc,
            buffer: String::new(),
            running: true,
            last_used: Instant::now(),
            human_responses: Vec::new(),
        },
    );
    Ok((pty, action))
}

#[cfg(target_os = "android")]
fn write_line(pty: u64, line: &str) -> anyhow::Result<()> {
    crate::android_linux_env::pty::write_pty_session(pty, &(line.to_string() + "\n"))
}

#[cfg(target_os = "android")]
fn with_active_rpc<T>(key: &str, build: impl FnOnce(&mut JsonRpcClient) -> T) -> Option<T> {
    let sessions = active_sessions();
    let mut guard = sessions.lock().ok()?;
    let active = guard.get_mut(key)?;
    active.last_used = Instant::now();
    Some(build(&mut active.rpc))
}

#[cfg(target_os = "android")]
fn write_turn_after_thread_open(
    pty: u64,
    key: &str,
    request: &AgentEngineTurnRequest,
    state: &super::state::CodexSessionState,
) -> Result<(), ChatEvent> {
    let turn_line = with_active_rpc(key, |rpc| turn_start_request(rpc, request, state))
        .ok_or_else(|| ChatEvent::Error {
            message: "Codex session registry entry disappeared".to_string(),
        })?;
    write_line(pty, &turn_line).map_err(|error| ChatEvent::Error {
        message: error.to_string(),
    })
}

#[cfg(target_os = "android")]
fn log_codex_runtime_message(message: &serde_json::Value) {
    if let Some(codex_home) = message
        .pointer("/result/codexHome")
        .and_then(|v| v.as_str())
    {
        log::info!("[napaxiCodexTrace] app-server codexHome={codex_home}");
    }
    if response_id(message).is_some() {
        let model_provider = message
            .pointer("/result/modelProvider")
            .or_else(|| message.pointer("/result/thread/modelProvider"))
            .and_then(|v| v.as_str());
        let model = message.pointer("/result/model").and_then(|v| v.as_str());
        if model_provider.is_some() || model.is_some() {
            log::info!(
                "[napaxiCodexTrace] app-server modelProvider={} model={}",
                model_provider.unwrap_or(""),
                model.unwrap_or("")
            );
        }
    }
}

#[cfg(target_os = "android")]
fn release_session_process(key: &str, close: bool) {
    let sessions = active_sessions();
    let active = {
        let Ok(mut guard) = sessions.lock() else {
            return;
        };
        if close {
            guard.remove(key)
        } else {
            if let Some(active) = guard.get_mut(key) {
                active.running = false;
                active.last_used = Instant::now();
            }
            None
        }
    };
    if close {
        remove_pending_human_requests_for_session(key);
    }
    if let Some(active) = active {
        let _ = crate::android_linux_env::pty::close_pty_session(active.pty);
    }
}

#[cfg(target_os = "android")]
fn register_human_request(key: &str, request_id: &str, rpc_id: &str, question_id: &str) {
    if let Ok(mut guard) = pending_human_requests().lock() {
        guard.insert(
            request_id.to_string(),
            PendingCodexHumanRequest {
                session_key: key.to_string(),
                rpc_id: rpc_id.to_string(),
                question_id: question_id.to_string(),
            },
        );
    }
}

#[cfg(target_os = "android")]
fn drain_human_responses(key: &str) -> Vec<(String, String)> {
    active_sessions()
        .lock()
        .ok()
        .and_then(|mut guard| {
            guard.get_mut(key).map(|active| {
                active.last_used = Instant::now();
                std::mem::take(&mut active.human_responses)
            })
        })
        .unwrap_or_default()
}

#[cfg(target_os = "android")]
fn remove_pending_human_requests_for_session(key: &str) {
    if let Ok(mut guard) = pending_human_requests().lock() {
        guard.retain(|_, pending| pending.session_key != key);
    }
}

#[cfg(target_os = "android")]
pub(crate) fn answer_human_request(request_id: &str, response: &str) -> bool {
    let pending = {
        let Ok(mut guard) = pending_human_requests().lock() else {
            return false;
        };
        guard.remove(request_id)
    };
    let Some(pending) = pending else {
        return false;
    };
    let payload = json!({
        "jsonrpc": "2.0",
        "id": rpc_id_json_value(&pending.rpc_id),
        "result": {
            "answers": {
                pending.question_id.clone(): {
                    "answers": [response]
                }
            }
        }
    })
    .to_string();
    let wrote = active_sessions()
        .lock()
        .ok()
        .and_then(|mut guard| {
            let active = guard.get_mut(&pending.session_key)?;
            match crate::android_linux_env::pty::write_pty_session(active.pty, &(payload + "\n")) {
                Ok(()) => {
                    active
                        .human_responses
                        .push((request_id.to_string(), response.to_string()));
                    Some(true)
                }
                Err(_) => Some(false),
            }
        })
        .unwrap_or(false);
    if !wrote {
        if let Ok(mut guard) = pending_human_requests().lock() {
            guard.insert(request_id.to_string(), pending);
        }
        return false;
    }
    true
}

#[cfg(target_os = "android")]
fn rpc_id_json_value(raw: &str) -> serde_json::Value {
    raw.parse::<u64>()
        .map(serde_json::Value::from)
        .unwrap_or_else(|_| serde_json::Value::String(raw.to_string()))
}

#[cfg(not(target_os = "android"))]
pub(crate) fn answer_human_request(_request_id: &str, _response: &str) -> bool {
    false
}

#[cfg(target_os = "android")]
fn cleanup_idle_sessions() {
    let expired = {
        let sessions = active_sessions();
        let mut guard = match sessions.lock() {
            Ok(guard) => guard,
            Err(_) => return,
        };
        let now = Instant::now();
        let keys = guard
            .iter()
            .filter(|(_, active)| {
                !active.running && now.duration_since(active.last_used) > CODEX_IDLE_TIMEOUT
            })
            .map(|(key, _)| key.clone())
            .collect::<Vec<_>>();
        keys.into_iter()
            .filter_map(|key| guard.remove(&key))
            .collect::<Vec<_>>()
    };
    for active in expired {
        let _ = crate::android_linux_env::pty::close_pty_session(active.pty);
    }
}
