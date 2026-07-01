//! Session lifecycle operations: create, list, delete, and clear. Each
//! `*_handle` wrapper resolves the engine handle and delegates to its
//! `files_dir`-based counterpart.

use std::fs;

use uuid::Uuid;

use crate::storage;

use super::store::{
    INVALID_HANDLE_JSON, defaulted, error_json, normalize_agent_id, normalize_stored_agent_id,
    now_rfc3339, parse_session_key, read_all_records, session_file, write_record,
};
use super::types::{SessionInfo, SessionKey, SessionRecord};

pub fn create_session(
    files_dir: &str,
    agent_id: &str,
    channel_type: &str,
    account_id: &str,
    existing_thread_id: Option<&str>,
) -> String {
    let thread_id = existing_thread_id
        .filter(|id| !id.trim().is_empty())
        .and_then(|id| Uuid::parse_str(id).ok())
        .unwrap_or_else(Uuid::new_v4)
        .to_string();

    let key = SessionKey {
        channel_type: defaulted(channel_type, "app"),
        account_id: defaulted(account_id, crate::runtime::DEFAULT_ACCOUNT_ID),
        thread_id: thread_id.clone(),
    };

    let path = session_file(files_dir, &thread_id);
    if !path.exists() {
        let now = now_rfc3339();
        let record = SessionRecord {
            key: key.clone(),
            agent_id: normalize_agent_id(agent_id),
            title: String::new(),
            preview: String::new(),
            created_at: now.clone(),
            updated_at: now,
            messages: Vec::new(),
        };
        if !write_record(files_dir, &record) {
            return error_json("Failed to create session");
        }
    }

    serde_json::to_string(&key).unwrap_or_else(|e| error_json(&e.to_string()))
}

pub fn create_session_handle(
    handle: i64,
    agent_id: &str,
    channel_type: &str,
    account_id: &str,
    existing_thread_id: Option<&str>,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return INVALID_HANDLE_JSON.to_string();
    };
    create_session(
        &files_dir,
        agent_id,
        channel_type,
        account_id,
        existing_thread_id,
    )
}

pub fn list_sessions(files_dir: &str, agent_id: &str, account_id: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let mut records: Vec<SessionRecord> = read_all_records(files_dir)
        .into_iter()
        .filter(|record| {
            normalize_stored_agent_id(&record.agent_id) == agent_id
                && record.key.account_id == account_id
        })
        .collect();

    records.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    records.truncate(50);

    let items: Vec<SessionInfo<'_>> = records
        .iter()
        .map(|record| SessionInfo {
            key: &record.key,
            title: &record.title,
            preview: &record.preview,
            message_count: record.messages.len(),
            created_at: &record.created_at,
            updated_at: &record.updated_at,
        })
        .collect();

    serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string())
}

pub fn list_sessions_handle(handle: i64, agent_id: &str, account_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_sessions(&files_dir, agent_id, account_id)
}

/// Returns `true` when a session carries no durable content: no messages, no
/// title, and an empty preview. Such "ghost" rows are created the moment a
/// session is opened and accumulate in `list_sessions` if the user starts a
/// session and immediately rotates or closes it without sending anything.
fn record_is_empty(record: &SessionRecord) -> bool {
    record.messages.is_empty() && record.title.trim().is_empty() && record.preview.trim().is_empty()
}

/// Delete a session only if it has no durable content. Returns `true` when an
/// empty session was removed, `false` when the session is missing or still
/// carries messages/title/preview (in which case it is left untouched). Use
/// this on session rotation and runtime shutdown to keep ghost rows from
/// piling up in the session list.
pub fn delete_session_if_empty(files_dir: &str, session_key_json: &str) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let Some(record) = super::store::read_record(files_dir, &key.thread_id) else {
        return false;
    };
    if !record_is_empty(&record) {
        return false;
    }
    delete_session(files_dir, session_key_json)
}

pub fn delete_session_if_empty_handle(handle: i64, session_key_json: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    delete_session_if_empty(&files_dir, session_key_json)
}

/// Remove every empty ghost session for an agent+account scope, returning the
/// number of sessions pruned. A one-shot cleanup for stores that accumulated
/// ghost rows before `delete_session_if_empty` was wired into rotation/close.
pub fn prune_empty_sessions(files_dir: &str, agent_id: &str, account_id: &str) -> usize {
    let agent_id = normalize_agent_id(agent_id);
    read_all_records(files_dir)
        .into_iter()
        .filter(|record| {
            normalize_stored_agent_id(&record.agent_id) == agent_id
                && record.key.account_id == account_id
                && record_is_empty(record)
        })
        .filter(|record| {
            let key_json = serde_json::to_string(&record.key).unwrap_or_default();
            delete_session(files_dir, &key_json)
        })
        .count()
}

pub fn prune_empty_sessions_handle(handle: i64, agent_id: &str, account_id: &str) -> usize {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return 0;
    };
    prune_empty_sessions(&files_dir, agent_id, account_id)
}

pub fn delete_session(files_dir: &str, session_key_json: &str) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let path = session_file(files_dir, &key.thread_id);
    let deleted = if path.exists() {
        fs::remove_file(path).is_ok()
    } else {
        true
    };
    deleted
        && storage::delete_thread_attachments(files_dir, &key.thread_id)
        && crate::context::delete_context_state(files_dir, &key.thread_id)
        && crate::skills::delete_skill_continuation_state(files_dir, &key.thread_id)
}

pub fn delete_session_handle(handle: i64, session_key_json: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    delete_session(&files_dir, session_key_json)
}

pub fn clear_session(files_dir: &str, session_key_json: &str) -> bool {
    let Some(key) = parse_session_key(session_key_json) else {
        return false;
    };
    let Some(mut record) = super::store::read_record(files_dir, &key.thread_id) else {
        return false;
    };
    record.messages.clear();
    record.preview.clear();
    record.updated_at = now_rfc3339();
    write_record(files_dir, &record)
        && storage::delete_thread_attachments(files_dir, &key.thread_id)
        && crate::context::delete_context_state(files_dir, &key.thread_id)
        && crate::skills::delete_skill_continuation_state(files_dir, &key.thread_id)
}

pub fn clear_session_handle(handle: i64, session_key_json: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    clear_session(&files_dir, session_key_json)
}
