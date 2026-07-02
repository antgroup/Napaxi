//! Session keys, scoped workspace dirs, cancellation, and human-loop injection.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

use crate::error::{CoreError, CoreResult};
use crate::turn::{
    attachment_content_parts_with_mode, attachment_metadata_json, parse_scene_prompt_attachments,
    persist_attachment_files, session_thread_id,
};

use super::engine::{DEFAULT_ACCOUNT_ID, DEFAULT_AGENT_ID, normalize_agent_id};
use super::handle::handle_to_arc;

pub fn default_session(files_dir: &str, agent_id: &str) -> String {
    crate::session::create_session(files_dir, agent_id, "app", DEFAULT_ACCOUNT_ID, None)
}

pub fn session_account_id(session_key_json: &str) -> String {
    serde_json::from_str::<crate::session::SessionKey>(session_key_json)
        .ok()
        .map(|key| key.account_id)
        .filter(|account_id| !account_id.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_ACCOUNT_ID.to_string())
}

pub fn scoped_workspace_files_dir(files_dir: &str, account_id: &str, agent_id: &str) -> String {
    crate::workspace::scoped_files_dir(files_dir, account_id, agent_id)
}

pub fn scoped_workspace_files_dir_from_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
) -> Option<String> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { handle_to_arc(handle) }?;
    Some(scoped_workspace_files_dir(
        engine.files_dir(),
        account_id,
        agent_id,
    ))
}

pub fn cancel_session_handle(handle: i64, session_key_json: &str) -> bool {
    match cancel_session_handle_typed(handle, session_key_json) {
        Ok(cancelled) => cancelled,
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                handle,
                "cancel_session_handle failed"
            );
            false
        }
    }
}

/// Result-returning variant. `Ok(true)` means the session was marked
/// cancelled, `Ok(false)` means it was not currently active. Errors capture
/// invalid handles.
pub fn cancel_session_handle_typed(handle: i64, session_key_json: &str) -> CoreResult<bool> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { handle_to_arc(handle) }.ok_or(CoreError::InvalidHandle(handle))?;
    crate::human_loop::cancel_session_scoped(engine.files_dir(), session_key_json);
    Ok(engine.cancel_session_key(session_key_json))
}

pub fn inject_message_handle(
    handle: i64,
    _config_json: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    attachments_json: &str,
) -> bool {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return false;
    };
    let Some(thread_id) = session_thread_id(session_key_json) else {
        return false;
    };
    let account_id = session_account_id(session_key_json);
    let workspace_files_dir = scoped_workspace_files_dir(
        engine.files_dir(),
        &account_id,
        &normalize_agent_id(agent_id),
    );
    let mut attachments = parse_scene_prompt_attachments(attachments_json);
    persist_attachment_files(
        engine.files_dir(),
        &workspace_files_dir,
        &thread_id,
        &mut attachments,
    );
    let raw_message = serde_json::json!({
        "role": "user",
        "content": if attachments.is_empty() {
            serde_json::Value::String(message.to_string())
        } else {
            attachment_content_parts_with_mode(message, &attachments, false)
        },
    });
    let interjection = crate::human_loop::HumanInterjection {
        content: message.to_string(),
        raw_message,
    };
    if !crate::human_loop::enqueue_interjection_scoped(
        engine.files_dir(),
        session_key_json,
        interjection,
    ) {
        return false;
    }
    let metadata_json = attachment_metadata_json(&attachments);
    crate::session::inject_user_message(
        engine.files_dir(),
        session_key_json,
        message,
        &metadata_json,
    )
}

pub fn retract_injected_message_handle(handle: i64, session_key_json: &str, message: &str) -> bool {
    match retract_injected_message_handle_typed(handle, session_key_json, message) {
        Ok(retracted) => retracted,
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                handle,
                "retract_injected_message_handle failed"
            );
            false
        }
    }
}

/// Result-returning variant. `Ok(true)` means the user message was both
/// retracted from the human-loop queue and removed from session history;
/// `Ok(false)` means there was nothing matching to retract. `Err` carries
/// `invalid_handle` for stale handles.
pub fn retract_injected_message_handle_typed(
    handle: i64,
    session_key_json: &str,
    message: &str,
) -> CoreResult<bool> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { handle_to_arc(handle) }.ok_or(CoreError::InvalidHandle(handle))?;
    if !crate::human_loop::retract_latest_interjection_scoped(
        engine.files_dir(),
        session_key_json,
        message,
    ) {
        return Ok(false);
    }
    Ok(crate::session::remove_latest_user_message(
        engine.files_dir(),
        session_key_json,
        message,
    ))
}

#[cfg(test)]
fn cancelled_sessions() -> &'static Mutex<HashSet<String>> {
    static CANCELLED: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    CANCELLED.get_or_init(|| Mutex::new(HashSet::new()))
}

pub(super) fn session_cancellation_key(session_key_json: &str) -> Option<String> {
    let key: crate::session::SessionKey = serde_json::from_str(session_key_json).ok()?;
    Some(format!(
        "{}:{}:{}",
        key.channel_type, key.account_id, key.thread_id
    ))
}

#[cfg(test)]
pub fn cancel_session_key(session_key_json: &str) -> bool {
    let Some(cancellation_key) = session_cancellation_key(session_key_json) else {
        return false;
    };
    let Ok(mut guard) = cancelled_sessions().lock() else {
        return false;
    };
    guard.insert(cancellation_key);
    true
}

#[cfg(test)]
pub fn clear_session_cancellation(session_key_json: &str) {
    let Some(cancellation_key) = session_cancellation_key(session_key_json) else {
        return;
    };
    if let Ok(mut guard) = cancelled_sessions().lock() {
        guard.remove(&cancellation_key);
    }
}

#[cfg(test)]
pub fn is_session_cancelled(session_key_json: &str) -> bool {
    let Some(cancellation_key) = session_cancellation_key(session_key_json) else {
        return false;
    };
    cancelled_sessions()
        .lock()
        .map(|guard| guard.contains(&cancellation_key))
        .unwrap_or(false)
}
