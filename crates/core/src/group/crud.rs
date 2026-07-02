//! Group CRUD: create, delete, list, get, rename, update_members, custom_prompt.

use chrono::Utc;
use uuid::Uuid;

use super::state::{
    DEFAULT_COORDINATOR, evict_if_needed, group_info, load_state, parse_members, save_state,
    session_mut,
};
use super::types::Group;

pub fn create_group(files_dir: &str, name: &str, members_json: &str) -> String {
    let Some(members) = parse_members(members_json) else {
        return String::new();
    };
    let mut state = load_state(files_dir);
    let group = Group {
        id: Uuid::new_v4().to_string(),
        name: name.to_string(),
        members,
        coordinator: DEFAULT_COORDINATOR.to_string(),
        created_at: Utc::now(),
        custom_prompt: None,
    };
    session_mut(&mut state, &group.id);
    state.groups.push(group.clone());
    evict_if_needed(&mut state);
    if save_state(files_dir, &state) {
        group.id
    } else {
        String::new()
    }
}

pub fn delete_group(files_dir: &str, group_id: &str) -> bool {
    let mut state = load_state(files_dir);
    let old_len = state.groups.len();
    state.groups.retain(|group| group.id != group_id);
    state
        .sessions
        .retain(|session| session.group_id != group_id);
    state.groups.len() != old_len && save_state(files_dir, &state)
}

pub fn list_groups(files_dir: &str) -> String {
    let state = load_state(files_dir);
    let groups: Vec<_> = state
        .groups
        .iter()
        .map(|group| group_info(&state, group))
        .collect();
    serde_json::to_string(&groups).unwrap_or_else(|_| "[]".to_string())
}

pub fn get_group(files_dir: &str, group_id: &str) -> String {
    let state = load_state(files_dir);
    state
        .groups
        .iter()
        .find(|group| group.id == group_id)
        .and_then(|group| serde_json::to_string(group).ok())
        .unwrap_or_else(|| "null".to_string())
}

pub fn get_group_value(files_dir: &str, group_id: &str) -> Option<Group> {
    load_state(files_dir)
        .groups
        .into_iter()
        .find(|group| group.id == group_id)
}

pub fn rename_group(files_dir: &str, group_id: &str, new_name: &str) -> bool {
    let mut state = load_state(files_dir);
    let Some(group) = state.groups.iter_mut().find(|group| group.id == group_id) else {
        return false;
    };
    group.name = new_name.to_string();
    save_state(files_dir, &state)
}

pub fn update_group_members(files_dir: &str, group_id: &str, members_json: &str) -> bool {
    let Some(members) = parse_members(members_json) else {
        return false;
    };
    let mut state = load_state(files_dir);
    let Some(group) = state.groups.iter_mut().find(|group| group.id == group_id) else {
        return false;
    };
    group.members = members;
    save_state(files_dir, &state)
}

pub fn set_group_custom_prompt(files_dir: &str, group_id: &str, prompt: Option<String>) -> bool {
    let mut state = load_state(files_dir);
    let Some(group) = state.groups.iter_mut().find(|group| group.id == group_id) else {
        return false;
    };
    group.custom_prompt = prompt.and_then(|prompt| {
        let prompt = prompt.trim().to_string();
        if prompt.is_empty() {
            None
        } else {
            Some(prompt)
        }
    });
    save_state(files_dir, &state)
}
