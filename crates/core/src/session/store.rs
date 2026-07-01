//! On-disk persistence and small string/time helpers shared across session
//! lifecycle, mutation, and history modules.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use uuid::Uuid;

use super::types::{SessionKey, SessionRecord};

pub(super) const SESSION_DIR: &str = "napaxi_sessions";
pub(super) const DEFAULT_AGENT_ID: &str = crate::runtime::DEFAULT_AGENT_ID;
pub(super) const INVALID_HANDLE_JSON: &str = r#"{"error":"invalid engine handle"}"#;

pub(super) fn read_all_records(files_dir: &str) -> Vec<SessionRecord> {
    let Ok(entries) = fs::read_dir(session_dir(files_dir)) else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter_map(|entry| fs::read_to_string(entry.path()).ok())
        .filter_map(|content| serde_json::from_str::<SessionRecord>(&content).ok())
        .map(|mut record| {
            record.agent_id = normalize_stored_agent_id(&record.agent_id);
            record
        })
        .collect()
}

pub(super) fn read_record(files_dir: &str, thread_id: &str) -> Option<SessionRecord> {
    let thread_id = Uuid::parse_str(thread_id).ok()?.to_string();
    let content = fs::read_to_string(session_file(files_dir, &thread_id)).ok()?;
    let mut record: SessionRecord = serde_json::from_str(&content).ok()?;
    record.agent_id = normalize_stored_agent_id(&record.agent_id);
    Some(record)
}

pub(super) fn write_record(files_dir: &str, record: &SessionRecord) -> bool {
    let dir = session_dir(files_dir);
    if fs::create_dir_all(&dir).is_err() {
        return false;
    }
    let Ok(content) = serde_json::to_string_pretty(record) else {
        return false;
    };
    crate::storage::atomic_write_text_sync(
        &session_file(files_dir, &record.key.thread_id),
        &content,
    )
    .is_ok()
}

pub(super) fn parse_session_key(session_key_json: &str) -> Option<SessionKey> {
    serde_json::from_str(session_key_json).ok()
}

pub(super) fn session_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join(SESSION_DIR)
}

pub(super) fn session_file(files_dir: &str, thread_id: &str) -> PathBuf {
    session_dir(files_dir).join(format!("{thread_id}.json"))
}

pub(super) fn normalize_agent_id(agent_id: &str) -> String {
    defaulted(agent_id, DEFAULT_AGENT_ID)
}

pub(super) fn normalize_stored_agent_id(agent_id: &str) -> String {
    let trimmed = agent_id.trim();
    if trimmed.is_empty() || trimmed == "default" {
        DEFAULT_AGENT_ID.to_string()
    } else {
        trimmed.to_string()
    }
}

pub(super) fn defaulted(value: &str, fallback: &str) -> String {
    let value = value.trim();
    if value.is_empty() {
        fallback.to_string()
    } else {
        value.to_string()
    }
}

pub(super) fn now_rfc3339() -> String {
    Utc::now().to_rfc3339()
}

pub(super) fn parse_time(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
}

pub(super) fn empty_page() -> String {
    r#"{"messages":[],"has_more":false,"next_before":null}"#.to_string()
}

pub(super) fn error_json(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}
