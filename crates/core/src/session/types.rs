//! Session-domain value types: stable wire structs (`SessionKey`,
//! `SessionMessage`, `SessionAppendMessage`) and internal storage records
//! (`SessionRecord`, `SessionInfo`).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionKey {
    pub channel_type: String,
    pub account_id: String,
    pub thread_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct SessionRecord {
    pub(super) key: SessionKey,
    pub(super) agent_id: String,
    pub(super) title: String,
    pub(super) preview: String,
    pub(super) created_at: String,
    pub(super) updated_at: String,
    pub(super) messages: Vec<SessionMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionMessage {
    pub id: String,
    pub role: String,
    pub content: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "is_false")]
    pub interrupted: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct SessionAppendMessage {
    pub role: String,
    pub content: String,
    pub interrupted: bool,
    pub turn_id: Option<String>,
}

fn is_false(value: &bool) -> bool {
    !*value
}

#[derive(Debug, Clone, Serialize)]
pub(super) struct SessionInfo<'a> {
    pub(super) key: &'a SessionKey,
    pub(super) title: &'a str,
    pub(super) preview: &'a str,
    pub(super) message_count: usize,
    pub(super) created_at: &'a str,
    pub(super) updated_at: &'a str,
}
