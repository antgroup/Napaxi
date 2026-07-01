//! Collected and streaming send-to-session handle wrappers + event helpers.

use std::sync::Arc;

use crate::turn::session_thread_id;
use crate::types::{ChatEvent, PlatformLlmConfig};

use super::engine::{DEFAULT_AGENT_ID, Engine};
use super::handle::{handle_to_arc, parse_config};
use super::sessions::{default_session, session_account_id};
use super::tool_context::prepare_session_tool_context_with_config_and_thread;

pub use crate::turn::{
    TurnInput as SessionTurnInput, run_turn as run_session_turn, stream_turn as stream_session_turn,
};

async fn send_to_session_event_jsons(
    engine: Arc<Engine>,
    config_json: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    display_message: Option<&str>,
    attachments_json: &str,
    max_iterations: i32,
    is_group_context: bool,
) -> Vec<String> {
    let files_dir = engine.files_dir().to_string();
    let account_id = session_account_id(session_key_json);
    let llm_config = match parse_config(config_json) {
        Ok(config) => engine.config_with_capabilities(config),
        Err(error) => return vec![event_json(chat_error(format!("Invalid config: {error}")))],
    };
    let effective_config_json =
        serde_json::to_string(&llm_config).unwrap_or_else(|_| config_json.to_string());
    let current_thread_id = session_thread_id(session_key_json);
    let tool_context = prepare_session_tool_context_with_config_and_thread(
        &engine,
        &account_id,
        agent_id,
        llm_config,
        current_thread_id,
    );
    let turn_runtime = engine.begin_session_turn(session_key_json);
    crate::capabilities::with_admission_sink(
        engine.admission_sink(),
        run_session_turn(
            SessionTurnInput {
                files_dir,
                workspace_files_dir: tool_context.workspace_files_dir,
                config_json: effective_config_json,
                agent_id: agent_id.to_string(),
                session_key_json: session_key_json.to_string(),
                message: message.to_string(),
                display_message: display_message.map(str::to_string),
                attachments_json: attachments_json.to_string(),
                tools: Some(engine.tools()),
                max_iterations,
                extra_tools: tool_context.extra_tools,
                internal_tool_handler: tool_context.internal_tool_handler,
                is_group_context,
                agent_engine: crate::agent_engine::selection_from_definition(
                    crate::agents::get_definition(engine.files_dir(), agent_id).as_ref(),
                )
                .into(),
            },
            || engine.is_turn_cancelled(&turn_runtime),
        ),
    )
    .await
    .into_iter()
    .map(event_json)
    .collect()
}

pub async fn send_to_session_events_handle(
    handle: i64,
    config_json: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    attachments_json: &str,
    max_iterations: i32,
    is_group_context: bool,
) -> Vec<String> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return vec![event_json(chat_error("engine handle is not available"))];
    };
    send_to_session_event_jsons(
        engine,
        config_json,
        agent_id,
        session_key_json,
        message,
        None,
        attachments_json,
        max_iterations,
        is_group_context,
    )
    .await
}

pub async fn send_message_json_handle(
    handle: i64,
    config_json: &str,
    message: &str,
    attachments_json: &str,
    max_iterations: i32,
) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return events_array_json(&[event_json(chat_error("engine handle is not available"))]);
    };
    let session_key_json = default_session(engine.files_dir(), DEFAULT_AGENT_ID);
    let events = send_to_session_event_jsons(
        engine,
        config_json,
        DEFAULT_AGENT_ID,
        &session_key_json,
        message,
        None,
        attachments_json,
        max_iterations,
        false,
    )
    .await;
    events_array_json(&events)
}

pub async fn send_to_session_json_handle(
    handle: i64,
    config_json: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    attachments_json: &str,
    max_iterations: i32,
) -> String {
    let events = send_to_session_events_handle(
        handle,
        config_json,
        agent_id,
        session_key_json,
        message,
        attachments_json,
        max_iterations,
        false,
    )
    .await;
    events_array_json(&events)
}

async fn stream_session_event_jsons<F>(
    engine: Arc<Engine>,
    config_json: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    display_message: Option<&str>,
    attachments_json: &str,
    max_iterations: i32,
    mut emit: F,
) where
    F: FnMut(String),
{
    let files_dir = engine.files_dir().to_string();
    let account_id = session_account_id(session_key_json);
    let llm_config: PlatformLlmConfig = match parse_config(config_json) {
        Ok(config) => engine.config_with_capabilities(config),
        Err(error) => {
            emit(event_json(chat_error(format!("Invalid config: {error}"))));
            return;
        }
    };
    let effective_config_json =
        serde_json::to_string(&llm_config).unwrap_or_else(|_| config_json.to_string());
    let current_thread_id = session_thread_id(session_key_json);
    let tool_context = prepare_session_tool_context_with_config_and_thread(
        &engine,
        &account_id,
        agent_id,
        llm_config,
        current_thread_id,
    );
    let turn_runtime = engine.begin_session_turn(session_key_json);
    crate::capabilities::with_admission_sink(
        engine.admission_sink(),
        stream_session_turn(
            SessionTurnInput {
                files_dir,
                workspace_files_dir: tool_context.workspace_files_dir,
                config_json: effective_config_json,
                agent_id: agent_id.to_string(),
                session_key_json: session_key_json.to_string(),
                message: message.to_string(),
                display_message: display_message.map(str::to_string),
                attachments_json: attachments_json.to_string(),
                tools: Some(engine.tools()),
                max_iterations,
                extra_tools: tool_context.extra_tools,
                internal_tool_handler: tool_context.internal_tool_handler,
                is_group_context: false,
                agent_engine: crate::agent_engine::selection_from_definition(
                    crate::agents::get_definition(engine.files_dir(), agent_id).as_ref(),
                )
                .into(),
            },
            |event| emit(event_json(event)),
            || engine.is_turn_cancelled(&turn_runtime),
        ),
    )
    .await;
}

pub async fn stream_message_handle<F>(
    handle: i64,
    config_json: &str,
    message: &str,
    attachments_json: &str,
    max_iterations: i32,
    mut emit: F,
) where
    F: FnMut(String),
{
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        emit(event_json(chat_error("engine handle is not available")));
        return;
    };
    let session_key_json = default_session(engine.files_dir(), DEFAULT_AGENT_ID);
    stream_session_event_jsons(
        engine,
        config_json,
        DEFAULT_AGENT_ID,
        &session_key_json,
        message,
        None,
        attachments_json,
        max_iterations,
        emit,
    )
    .await;
}

pub async fn stream_to_session_handle<F>(
    handle: i64,
    config_json: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    attachments_json: &str,
    max_iterations: i32,
    emit: F,
) where
    F: FnMut(String),
{
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        let mut emit = emit;
        emit(event_json(chat_error("engine handle is not available")));
        return;
    };
    stream_session_event_jsons(
        engine,
        config_json,
        agent_id,
        session_key_json,
        message,
        None,
        attachments_json,
        max_iterations,
        emit,
    )
    .await;
}

pub async fn stream_to_session_with_display_handle<F>(
    handle: i64,
    config_json: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    display_message: Option<&str>,
    attachments_json: &str,
    max_iterations: i32,
    emit: F,
) where
    F: FnMut(String),
{
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        let mut emit = emit;
        emit(event_json(chat_error("engine handle is not available")));
        return;
    };
    stream_session_event_jsons(
        engine,
        config_json,
        agent_id,
        session_key_json,
        message,
        display_message,
        attachments_json,
        max_iterations,
        emit,
    )
    .await;
}

fn chat_error(message: impl Into<String>) -> ChatEvent {
    ChatEvent::Error {
        message: message.into(),
    }
}

fn event_json(event: ChatEvent) -> String {
    serde_json::to_string(&event).unwrap_or_else(|_| {
        r#"{"type":"error","message":"failed to serialize chat event"}"#.to_string()
    })
}

fn events_array_json(events: &[String]) -> String {
    format!("[{}]", events.join(","))
}
