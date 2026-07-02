//! Write-side session operations: append, replace turn segment, interrupt
//! flags, inject user message + attachments, remove latest user message,
//! and trace-message persistence.

use uuid::Uuid;

use crate::storage;

use super::store::{now_rfc3339, parse_session_key, read_record, write_record};
use super::types::{SessionAppendMessage, SessionMessage};

pub fn append_message(files_dir: &str, session_key_json: &str, role: &str, content: &str) -> bool {
    append_messages(
        files_dir,
        session_key_json,
        &[SessionAppendMessage {
            role: role.to_string(),
            content: content.to_string(),
            interrupted: false,
            turn_id: None,
        }],
    )
}

pub fn append_messages(
    files_dir: &str,
    session_key_json: &str,
    messages: &[SessionAppendMessage],
) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let Some(mut record) = read_record(files_dir, &key.thread_id) else {
        return false;
    };
    let now = now_rfc3339();
    for message in messages {
        record.messages.push(SessionMessage {
            id: Uuid::new_v4().to_string(),
            role: message.role.clone(),
            content: message.content.clone(),
            created_at: now.clone(),
            interrupted: message.interrupted,
            turn_id: message.turn_id.clone(),
        });
        if message.role == "user" || message.role == "assistant" {
            record.preview = message.content.chars().take(200).collect();
            if record.title.is_empty() && message.role == "user" {
                record.title = message.content.chars().take(80).collect();
            }
        }
    }
    record.updated_at = now;
    write_record(files_dir, &record)
}

/// Pop any trailing messages whose `turn_id` matches the given id, then append
/// `messages` (each stamped with `turn_id`). Lets callers checkpoint a turn's
/// partial state idempotently across many writes within the same turn.
pub fn replace_turn_segment(
    files_dir: &str,
    session_key_json: &str,
    turn_id: &str,
    messages: &[SessionAppendMessage],
) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let Some(mut record) = read_record(files_dir, &key.thread_id) else {
        return false;
    };
    while record
        .messages
        .last()
        .and_then(|message| message.turn_id.as_deref())
        == Some(turn_id)
    {
        record.messages.pop();
    }
    let now = now_rfc3339();
    for message in messages {
        record.messages.push(SessionMessage {
            id: Uuid::new_v4().to_string(),
            role: message.role.clone(),
            content: message.content.clone(),
            created_at: now.clone(),
            interrupted: message.interrupted,
            turn_id: Some(turn_id.to_string()),
        });
        if message.role == "user" || message.role == "assistant" {
            record.preview = message.content.chars().take(200).collect();
            if record.title.is_empty() && message.role == "user" {
                record.title = message.content.chars().take(80).collect();
            }
        }
    }
    record.updated_at = now;
    write_record(files_dir, &record)
}

/// Mark the last `asking_human` message whose `request_id` matches as
/// interrupted. Used when an in-flight ask_human is cancelled by session
/// shutdown so reloaded history renders the bubble as Cancelled, not Pending.
pub fn mark_asking_human_interrupted(
    files_dir: &str,
    session_key_json: &str,
    request_id: &str,
) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let Some(mut record) = read_record(files_dir, &key.thread_id) else {
        return false;
    };
    let Some(index) = record.messages.iter().rposition(|message| {
        if message.role != "asking_human" {
            return false;
        }
        serde_json::from_str::<serde_json::Value>(&message.content)
            .ok()
            .and_then(|value| {
                value
                    .get("request_id")
                    .and_then(|id| id.as_str().map(str::to_string))
            })
            .as_deref()
            == Some(request_id)
    }) else {
        return false;
    };
    record.messages[index].interrupted = true;
    record.updated_at = now_rfc3339();
    write_record(files_dir, &record)
}

pub fn inject_user_message(
    files_dir: &str,
    session_key_json: &str,
    message: &str,
    attachments_json: &str,
) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let Some(mut record) = read_record(files_dir, &key.thread_id) else {
        return false;
    };

    let user_index = record
        .messages
        .iter()
        .filter(|message| message.role == "user")
        .count() as i32;
    let now = now_rfc3339();
    record.messages.push(SessionMessage {
        id: Uuid::new_v4().to_string(),
        role: "user".to_string(),
        content: message.to_string(),
        created_at: now.clone(),
        interrupted: false,
        turn_id: None,
    });
    record.preview = message.chars().take(200).collect();
    if record.title.is_empty() {
        record.title = message.chars().take(80).collect();
    }
    record.updated_at = now;
    if !write_record(files_dir, &record) {
        return false;
    }

    let attachments_json = attachments_json.trim();
    if attachments_json.is_empty() || attachments_json == "[]" {
        return true;
    }
    storage::save_message_attachments(files_dir, &key.thread_id, user_index, attachments_json)
}

pub fn remove_latest_user_message(files_dir: &str, session_key_json: &str, message: &str) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let Some(mut record) = read_record(files_dir, &key.thread_id) else {
        return false;
    };
    let Some(index) = record
        .messages
        .iter()
        .rposition(|item| item.role == "user" && item.content == message)
    else {
        return false;
    };
    record.messages.remove(index);
    record.preview = record
        .messages
        .iter()
        .rev()
        .find(|item| item.role == "user" || item.role == "assistant")
        .map(|item| item.content.chars().take(200).collect())
        .unwrap_or_default();
    record.updated_at = now_rfc3339();
    write_record(files_dir, &record)
}

pub fn inject_user_message_handle(
    handle: i64,
    session_key_json: &str,
    message: &str,
    attachments_json: &str,
) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    inject_user_message(&files_dir, session_key_json, message, attachments_json)
}

#[allow(dead_code)] // Reserved trace-append entry point for future session tooling.
pub fn append_trace_messages(
    files_dir: &str,
    session_key_json: &str,
    reasoning: &str,
    tool_calls: &[serde_json::Value],
) -> bool {
    let mut ok = true;
    if !reasoning.trim().is_empty() {
        ok &= append_message(files_dir, session_key_json, "reasoning", reasoning);
    }
    if !tool_calls.is_empty() {
        let content = serde_json::json!({ "calls": tool_calls }).to_string();
        ok &= append_message(files_dir, session_key_json, "tool_calls", &content);
    }
    ok
}
