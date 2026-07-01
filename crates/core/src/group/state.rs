//! Persistence and shared mutation primitives for group state.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::Utc;
use uuid::Uuid;

use super::types::{
    Group, GroupInfo, GroupMessage, GroupMessageType, GroupSessionState, GroupState,
};

pub(super) const DEFAULT_COORDINATOR: &str = crate::runtime::DEFAULT_AGENT_ID;
pub(super) const MAX_GROUPS: usize = 20;

pub(super) fn store_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join("groups.json")
}

pub(super) fn load_state(files_dir: &str) -> GroupState {
    let Ok(content) = fs::read_to_string(store_path(files_dir)) else {
        return GroupState::default();
    };
    serde_json::from_str(&content).unwrap_or_default()
}

pub(super) fn save_state(files_dir: &str, state: &GroupState) -> bool {
    let path = store_path(files_dir);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    serde_json::to_string_pretty(state)
        .ok()
        .and_then(|content| fs::write(path, content).ok())
        .is_some()
}

pub(super) fn normalize_agent_id(agent_id: &str) -> String {
    let trimmed = agent_id.trim();
    if trimmed.is_empty() {
        DEFAULT_COORDINATOR.to_string()
    } else {
        trimmed.to_string()
    }
}

pub(super) fn parse_members(members_json: &str) -> Option<Vec<String>> {
    serde_json::from_str::<Vec<String>>(members_json)
        .ok()
        .map(|members| {
            members
                .into_iter()
                .map(|member| normalize_agent_id(&member))
                .filter(|member| !member.is_empty())
                .collect()
        })
}

pub(super) fn message(
    group_id: &str,
    sender: &str,
    content: String,
    target_agent: Option<String>,
) -> GroupMessage {
    GroupMessage {
        id: Uuid::new_v4().to_string(),
        group_id: group_id.to_string(),
        sender: sender.to_string(),
        content,
        message_type: GroupMessageType::Text,
        timestamp: Utc::now(),
        tool_call_id: None,
        tool_name: None,
        target_agent,
    }
}

pub(super) fn session_mut<'a>(
    state: &'a mut GroupState,
    group_id: &str,
) -> &'a mut GroupSessionState {
    if let Some(index) = state
        .sessions
        .iter()
        .position(|session| session.group_id == group_id)
    {
        return &mut state.sessions[index];
    }
    state.sessions.push(GroupSessionState {
        group_id: group_id.to_string(),
        messages: Vec::new(),
    });
    state
        .sessions
        .last_mut()
        .expect("session was just inserted")
}

pub(super) fn session<'a>(state: &'a GroupState, group_id: &str) -> Option<&'a GroupSessionState> {
    state
        .sessions
        .iter()
        .find(|session| session.group_id == group_id)
}

pub(super) fn evict_if_needed(state: &mut GroupState) {
    if state.groups.len() <= MAX_GROUPS {
        return;
    }
    state.groups.sort_by_key(|group| group.created_at);
    let remove_count = state.groups.len() - MAX_GROUPS;
    let removed: Vec<_> = state
        .groups
        .drain(0..remove_count)
        .map(|group| group.id)
        .collect();
    state
        .sessions
        .retain(|session| !removed.iter().any(|id| id == &session.group_id));
}

pub(super) fn group_info(state: &GroupState, group: &Group) -> GroupInfo {
    let messages = session(state, &group.id)
        .map(|session| session.messages.as_slice())
        .unwrap_or(&[]);
    let last = messages.last();
    GroupInfo {
        id: group.id.clone(),
        name: group.name.clone(),
        members: group.members.clone(),
        coordinator: group.coordinator.clone(),
        created_at: group.created_at,
        message_count: messages.len(),
        last_message_preview: last.map(|message| {
            let preview: String = message.content.chars().take(80).collect();
            if message.content.chars().count() > 80 {
                format!("{preview}...")
            } else {
                preview
            }
        }),
        last_message_time: last.map(|message| message.timestamp),
        custom_prompt: group.custom_prompt.clone(),
    }
}
