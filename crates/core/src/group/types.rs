//! Public DTOs for group state.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::types::ChatEvent;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Group {
    pub id: String,
    pub name: String,
    pub members: Vec<String>,
    pub coordinator: String,
    pub created_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub custom_prompt: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GroupMessageType {
    Text,
    ToolCall,
    ToolResult,
    System,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMessage {
    pub id: String,
    pub group_id: String,
    pub sender: String,
    pub content: String,
    #[serde(rename = "type")]
    pub message_type: GroupMessageType,
    pub timestamp: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_call_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_agent: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupInfo {
    pub id: String,
    pub name: String,
    pub members: Vec<String>,
    pub coordinator: String,
    pub created_at: DateTime<Utc>,
    pub message_count: usize,
    pub last_message_preview: Option<String>,
    pub last_message_time: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub custom_prompt: Option<String>,
}

#[derive(Debug, Clone)]
pub struct GroupMemberTask {
    pub member_id: String,
    pub task: String,
    pub session_key_json: String,
    pub config_json: String,
}

#[derive(Debug, Clone)]
pub struct GroupToolExecution {
    pub output: String,
    pub events: Vec<ChatEvent>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupState {
    pub groups: Vec<Group>,
    pub sessions: Vec<GroupSessionState>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupSessionState {
    pub group_id: String,
    pub messages: Vec<GroupMessage>,
}
