//! Group state import/export for persistence and backup.

use std::collections::HashMap;

use super::state::{evict_if_needed, load_state, save_state};
use super::types::{GroupSessionState, GroupState};

pub fn export_group_state(files_dir: &str) -> String {
    serde_json::to_string(&load_state(files_dir)).unwrap_or_else(|_| "{}".to_string())
}

pub fn import_group_state(files_dir: &str, state_json: &str) -> bool {
    let Ok(mut state) = serde_json::from_str::<GroupState>(state_json) else {
        return false;
    };
    let known: HashMap<_, _> = state
        .groups
        .iter()
        .map(|group| (group.id.clone(), true))
        .collect();
    state
        .sessions
        .retain(|session| known.contains_key(&session.group_id));
    for group in &state.groups {
        if !state
            .sessions
            .iter()
            .any(|session| session.group_id == group.id)
        {
            state.sessions.push(GroupSessionState {
                group_id: group.id.clone(),
                messages: Vec::new(),
            });
        }
    }
    evict_if_needed(&mut state);
    save_state(files_dir, &state)
}
