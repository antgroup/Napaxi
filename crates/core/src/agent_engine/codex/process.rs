#[cfg(any(target_os = "android", target_os = "ios"))]
use std::time::{Duration, Instant};

#[cfg(any(target_os = "android", target_os = "ios"))]
use serde_json::json;

#[cfg(any(target_os = "android", target_os = "ios"))]
use crate::agent_engine::AgentEngineTurnRequest;

use crate::agent_engine::CodexTurnPlan;
#[cfg(target_os = "android")]
use crate::android_linux_env as linux_env;
#[cfg(target_os = "ios")]
use crate::ios_qemu_env as linux_env;
use crate::types::ChatEvent;

#[cfg(any(target_os = "android", target_os = "ios"))]
use super::config;
#[cfg(any(target_os = "android", target_os = "ios"))]
use super::configure::{clear_config_and_sessions, sync_prepared_config};
#[cfg(any(target_os = "android", target_os = "ios"))]
use super::dynamic_tools::handle_server_tool_call;
#[cfg(any(target_os = "android", target_os = "ios"))]
use super::events::map_app_server_message;
#[cfg(any(target_os = "android", target_os = "ios"))]
use super::protocol::{
    JsonRpcClient, app_server_request_auto_response, dynamic_tools_fingerprint, extract_thread_id,
    initialize_request, initialized_notification, parse_json_lines, response_error, response_id,
    server_request_id, skill_roots_then_turn_lines, skills_extra_roots_set_request,
    skills_list_request, thread_open_request, thread_start_request,
};
#[cfg(any(target_os = "android", target_os = "ios"))]
use super::state::{
    PendingCodexHumanRequest, active_sessions, clear_state, load_state, native_library_dir_for,
    pending_human_requests, save_state, session_key,
};

#[cfg(not(any(target_os = "android", target_os = "ios")))]
const CODEX_UNSUPPORTED: &str = "napaxi.agent_engine.codex is unsupported on this platform";
#[cfg(any(target_os = "android", target_os = "ios"))]
const CODEX_STARTUP_TIMEOUT: Duration = Duration::from_secs(5);
#[cfg(any(target_os = "android", target_os = "ios"))]
const CODEX_TURN_TIMEOUT: Duration = Duration::from_secs(60 * 60);
#[cfg(any(target_os = "android", target_os = "ios"))]
const CODEX_IDLE_TIMEOUT: Duration = Duration::from_secs(10 * 60);

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) async fn run_codex_turn<F, C>(
    plan: CodexTurnPlan,
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
    let _ = plan;
    vec![event]
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(crate) async fn run_codex_turn<F, C>(
    plan: CodexTurnPlan,
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

    let CodexTurnPlan {
        request,
        tools,
        internal_tool_handler,
        tool_descriptors,
    } = plan;

    let prepared_config = match config::prepare_from_json(&request.config_json) {
        Ok(prepared) => prepared,
        Err(error) => {
            let error = clear_config_and_sessions(&request.files_dir)
                .err()
                .unwrap_or(error);
            let event = ChatEvent::Error {
                message: error.message,
            };
            emit(event.clone());
            return vec![event];
        }
    };
    if let Err(error) = sync_prepared_config(&request.files_dir, &prepared_config) {
        let event = ChatEvent::Error {
            message: error.message,
        };
        emit(event.clone());
        return vec![event];
    }
    if let Err(error) =
        crate::skills::export_prompt_skills(&request.files_dir, &request.agent_id).await
    {
        let event = ChatEvent::Error {
            message: format!("Codex skill export failed: {error}"),
        };
        emit(event.clone());
        return vec![event];
    }

    let native_library_dir = request
        .engine_config
        .get("native_library_dir")
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .or_else(|| native_library_dir_for(&request.files_dir));
    #[cfg(target_os = "android")]
    let Some(native_library_dir) = native_library_dir else {
        let event = ChatEvent::Error {
            message: "missing native_library_dir for Android Codex agent engine".to_string(),
        };
        emit(event.clone());
        return vec![event];
    };
    #[cfg(target_os = "ios")]
    let native_library_dir = native_library_dir.unwrap_or_default();

    let key = session_key(&request);
    let mut state = load_state(&request.files_dir, &key);
    let runtime_fingerprint =
        super::env::runtime_fingerprint(&prepared_config.fingerprint, &request.engine_config);
    let dynamic_tools_fingerprint = dynamic_tools_fingerprint(&tool_descriptors);
    if state.config_fingerprint != runtime_fingerprint
        || state.dynamic_tools_fingerprint != dynamic_tools_fingerprint
    {
        state.native_thread_id = None;
        state.config_fingerprint = runtime_fingerprint.clone();
        state.dynamic_tools_fingerprint = dynamic_tools_fingerprint.clone();
        save_state(&request.files_dir, &key, &state);
    }
    let (pty, start_action) = match acquire_session_process(
        &request,
        &native_library_dir,
        &key,
        &state,
        &runtime_fingerprint,
        &dynamic_tools_fingerprint,
        &tool_descriptors,
    ) {
        Ok(value) => value,
        Err(error) => {
            let event = ChatEvent::Error {
                message: error.to_string(),
            };
            emit(event.clone());
            return vec![event];
        }
    };

    let mut pending_initialize = None;
    let mut pending_thread_open = None;
    let mut sent_turn = false;
    match start_action {
        StartAction::InitializeThenOpen {
            initialize_id,
            initialize_line,
            initialized_line,
            open_request_id,
            open_line,
            is_resume,
        } => {
            // Codex rejects thread/start until initialize has been acknowledged.
            pending_initialize = Some(InitializePendingOpen {
                initialize_id,
                initialized_line,
                open_request_id,
                open_line,
                is_resume,
            });
            if let Err(error) = write_line(pty, &initialize_line) {
                release_session_process(&key, true);
                let event = ChatEvent::Error {
                    message: error.to_string(),
                };
                emit(event.clone());
                return vec![event];
            }
        }
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
        StartAction::StartTurn { lines } => {
            sent_turn = true;
            if let Err(error) = write_lines(pty, &lines) {
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
        match linux_env::pty::drain_pty_events(pty) {
            Ok(drained) => {
                for event in drained {
                    match event.kind {
                        linux_env::pty::PtyEventKind::Output => {
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
                                if let Some(pending) = pending_initialize.take() {
                                    if is_rpc_response(&message)
                                        && response_id(&message) == Some(pending.initialize_id)
                                    {
                                        if let Some(error) = response_error(&message) {
                                            let event = ChatEvent::Error {
                                                message: format!("initialize failed: {error}"),
                                            };
                                            emit(event.clone());
                                            events.push(event);
                                            saw_completion = true;
                                            should_close = true;
                                            break;
                                        }
                                        if let Err(error) =
                                            write_line(pty, &pending.initialized_line)
                                                .and_then(|()| write_line(pty, &pending.open_line))
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
                                        pending_thread_open =
                                            Some((pending.open_request_id, pending.is_resume));
                                        continue;
                                    }
                                    pending_initialize = Some(pending);
                                }
                                if let Some((open_id, is_resume)) = pending_thread_open {
                                    if is_rpc_response(&message)
                                        && response_id(&message) == Some(open_id)
                                    {
                                        if let Some(error) = response_error(&message) {
                                            if is_resume {
                                                let start_line = with_active_rpc(&key, |rpc| {
                                                    let (id, line) = thread_start_request(
                                                        rpc,
                                                        Some(&request),
                                                        &tool_descriptors,
                                                    );
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
                                if let Some(rpc_request_id) = server_request_id(&message) {
                                    if let Some(response_line) = handle_server_tool_call(
                                        rpc_request_id.clone(),
                                        &message,
                                        &request,
                                        tools.as_ref(),
                                        internal_tool_handler.as_ref(),
                                        &tool_descriptors,
                                        &mut is_cancelled,
                                        &mut emit,
                                        &mut events,
                                    )
                                    .await
                                    .or_else(|| {
                                        app_server_request_auto_response(&message, rpc_request_id)
                                    }) {
                                        if let Err(error) = write_line(pty, &response_line) {
                                            let event = ChatEvent::Error {
                                                message: error.to_string(),
                                            };
                                            emit(event.clone());
                                            events.push(event);
                                            saw_completion = true;
                                            should_close = true;
                                            break;
                                        }
                                        continue;
                                    }
                                }
                                let mapped = map_app_server_message(&message);
                                #[cfg(any(target_os = "android", target_os = "ios"))]
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
                                for event in mapped.extra_events {
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
                        linux_env::pty::PtyEventKind::Exit
                        | linux_env::pty::PtyEventKind::Closed => {
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
                        linux_env::pty::PtyEventKind::Log => {}
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
        if !sent_turn
            && started.elapsed() > CODEX_STARTUP_TIMEOUT
            && (pending_initialize.is_some() || pending_thread_open.is_some())
        {
            let event = ChatEvent::Error {
                message: if pending_initialize.is_some() {
                    "Codex app-server did not initialize before startup timeout".to_string()
                } else {
                    "Codex app-server did not open a thread before startup timeout".to_string()
                },
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

#[cfg(any(target_os = "android", target_os = "ios"))]
enum StartAction {
    InitializeThenOpen {
        initialize_id: u64,
        initialize_line: String,
        initialized_line: String,
        open_request_id: u64,
        open_line: String,
        is_resume: bool,
    },
    OpenThread {
        request_id: u64,
        line: String,
        is_resume: bool,
    },
    StartTurn {
        lines: Vec<String>,
    },
}

#[cfg(any(target_os = "android", target_os = "ios"))]
struct InitializePendingOpen {
    initialize_id: u64,
    initialized_line: String,
    open_request_id: u64,
    open_line: String,
    is_resume: bool,
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn acquire_session_process(
    request: &AgentEngineTurnRequest,
    native_library_dir: &str,
    key: &str,
    state: &super::state::CodexSessionState,
    config_fingerprint: &str,
    dynamic_tools_fingerprint: &str,
    dynamic_tools: &[crate::tool_registry::ToolDescriptor],
) -> anyhow::Result<(u64, StartAction)> {
    cleanup_idle_sessions();
    let sessions = active_sessions();
    let mut guard = sessions
        .lock()
        .map_err(|e| anyhow::anyhow!("Codex session registry lock poisoned: {e}"))?;
    if let Some(active) = guard.get(key) {
        let stale = active.config_fingerprint != config_fingerprint
            || active.dynamic_tools_fingerprint != dynamic_tools_fingerprint;
        if stale && active.running {
            anyhow::bail!(
                "Codex agent engine configuration changed while a session has an active turn"
            );
        }
        if stale {
            let stale = guard.remove(key);
            drop(guard);
            if let Some(stale) = stale {
                remove_pending_human_requests_for_session(key);
                let _ = linux_env::pty::close_pty_session(stale.pty);
            }
            return acquire_session_process(
                request,
                native_library_dir,
                key,
                state,
                config_fingerprint,
                dynamic_tools_fingerprint,
                dynamic_tools,
            );
        }
    }
    if let Some(active) = guard.get_mut(key) {
        active.running = true;
        active.last_used = Instant::now();
        let action = if state.native_thread_id.is_some() {
            StartAction::StartTurn {
                lines: skill_roots_then_turn_lines(&mut active.rpc, request, state),
            }
        } else {
            let (request_id, line, is_resume) =
                thread_open_request(&mut active.rpc, state, Some(request), dynamic_tools);
            StartAction::OpenThread {
                request_id,
                line,
                is_resume,
            }
        };
        return Ok((active.pty, action));
    }

    ensure_codex_cli_available(&request.files_dir)?;

    let network_env = super::env::codex_process_env(&request.engine_config);
    let network_exports = super::env::shell_export_prefix(&network_env);
    let argv = vec![
        "/bin/sh".to_string(),
        "-lc".to_string(),
        format!(
            "mkdir -p /workspace /root/.codex && stty raw -echo -icanon -ixon -ixoff 2>/dev/null; export HOME=/root CODEX_HOME=/root/.codex PATH=\"/root/.local/bin:$PATH\"; {network_exports}exec codex app-server 2>&1"
        ),
    ];
    let workspace_dir = crate::storage::FileBridge::new_with_workspace_files_dir(
        &request.files_dir,
        &request.workspace_files_dir,
    )
    .workspace_dir()
    .display()
    .to_string();
    let pty = linux_env::pty::open_pty_session(
        &request.files_dir,
        native_library_dir,
        &workspace_dir,
        &argv,
        Some("/workspace"),
        120,
        40,
    )?;
    let mut rpc = JsonRpcClient::new();
    let (initialize_id, initialize_line) = initialize_request(&mut rpc);
    let initialized_line = initialized_notification(&rpc);
    let (_skills_root_id, skills_root_line) = skills_extra_roots_set_request(&mut rpc);
    let (_skills_list_id, skills_list_line) = skills_list_request(&mut rpc, true);
    let (open_request_id, open_line, is_resume) =
        thread_open_request(&mut rpc, state, Some(request), dynamic_tools);
    let action = StartAction::InitializeThenOpen {
        initialize_id,
        initialize_line,
        initialized_line,
        open_request_id,
        open_line: [skills_root_line, skills_list_line, open_line].join("\n"),
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
            files_dir: request.files_dir.clone(),
            config_fingerprint: config_fingerprint.to_string(),
            dynamic_tools_fingerprint: dynamic_tools_fingerprint.to_string(),
            close_after_turn: false,
        },
    );
    Ok((pty, action))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn ensure_codex_cli_available(files_dir: &str) -> anyhow::Result<()> {
    let rootfs_dir = std::path::Path::new(files_dir).join("linux-env/rootfs");
    let candidates = [
        rootfs_dir.join("root/.local/bin/codex"),
        rootfs_dir.join("usr/local/bin/codex"),
        rootfs_dir.join("usr/bin/codex"),
    ];
    if candidates.iter().any(|path| path.exists()) {
        return Ok(());
    }
    anyhow::bail!(
        "Codex CLI is missing from the bundled Linux rootfs; rebuild the bundled rootfs with tools/scripts/bake_android_rootfs.sh so `codex app-server` is available"
    )
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn write_line(pty: u64, line: &str) -> anyhow::Result<()> {
    linux_env::pty::write_pty_session(pty, &(line.to_string() + "\n"))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn write_lines(pty: u64, lines: &[String]) -> anyhow::Result<()> {
    for line in lines {
        write_line(pty, line)?;
    }
    Ok(())
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn with_active_rpc<T>(key: &str, build: impl FnOnce(&mut JsonRpcClient) -> T) -> Option<T> {
    let sessions = active_sessions();
    let mut guard = sessions.lock().ok()?;
    let active = guard.get_mut(key)?;
    active.last_used = Instant::now();
    Some(build(&mut active.rpc))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn write_turn_after_thread_open(
    pty: u64,
    key: &str,
    request: &AgentEngineTurnRequest,
    state: &super::state::CodexSessionState,
) -> Result<(), ChatEvent> {
    let turn_lines = with_active_rpc(key, |rpc| skill_roots_then_turn_lines(rpc, request, state))
        .ok_or_else(|| ChatEvent::Error {
        message: "Codex session registry entry disappeared".to_string(),
    })?;
    write_lines(pty, &turn_lines).map_err(|error| ChatEvent::Error {
        message: error.to_string(),
    })
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn is_rpc_response(message: &serde_json::Value) -> bool {
    response_id(message).is_some()
        && (message.get("result").is_some() || message.get("error").is_some())
}

#[cfg(any(target_os = "android", target_os = "ios"))]
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

#[cfg(any(target_os = "android", target_os = "ios"))]
fn release_session_process(key: &str, close: bool) {
    let sessions = active_sessions();
    let (active, did_close, clear_mapping) = {
        let Ok(mut guard) = sessions.lock() else {
            return;
        };
        let close_after_turn = guard.get(key).is_some_and(|active| active.close_after_turn);
        if close || close_after_turn {
            (guard.remove(key), true, close_after_turn)
        } else {
            if let Some(active) = guard.get_mut(key) {
                active.running = false;
                active.last_used = Instant::now();
            }
            (None, false, false)
        }
    };
    if did_close {
        remove_pending_human_requests_for_session(key);
    }
    if let Some(active) = active {
        if clear_mapping {
            clear_state(&active.files_dir, key);
        }
        let _ = linux_env::pty::close_pty_session(active.pty);
    }
}

#[cfg(any(target_os = "android", target_os = "ios"))]
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

#[cfg(any(target_os = "android", target_os = "ios"))]
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

#[cfg(any(target_os = "android", target_os = "ios"))]
fn remove_pending_human_requests_for_session(key: &str) {
    if let Ok(mut guard) = pending_human_requests().lock() {
        guard.retain(|_, pending| pending.session_key != key);
    }
}

#[cfg(any(target_os = "android", target_os = "ios"))]
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
            match linux_env::pty::write_pty_session(active.pty, &(payload + "\n")) {
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

#[cfg(any(target_os = "android", target_os = "ios"))]
fn rpc_id_json_value(raw: &str) -> serde_json::Value {
    raw.parse::<u64>()
        .map(serde_json::Value::from)
        .unwrap_or_else(|_| serde_json::Value::String(raw.to_string()))
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) fn answer_human_request(_request_id: &str, _response: &str) -> bool {
    false
}

#[cfg(any(target_os = "android", target_os = "ios"))]
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
        let _ = linux_env::pty::close_pty_session(active.pty);
    }
}
#[cfg(test)]
mod tests {
    use crate::agent_engine::codex::config;

    #[test]
    fn codex_config_dir_targets_linux_env_rootfs_home() {
        assert_eq!(
            config::config_dir("app_files"),
            std::path::Path::new("app_files")
                .join("linux-env")
                .join("rootfs")
                .join("root")
                .join(".codex"),
        );
    }
}
