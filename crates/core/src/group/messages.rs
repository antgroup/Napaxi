//! Group message append, listing, history clearing, and membership check.

use super::state::{load_state, message, normalize_agent_id, save_state, session, session_mut};

pub fn get_group_messages(files_dir: &str, group_id: &str) -> String {
    let state = load_state(files_dir);
    let messages = session(&state, group_id)
        .map(|session| session.messages.as_slice())
        .unwrap_or(&[]);
    serde_json::to_string(messages).unwrap_or_else(|_| "[]".to_string())
}

pub fn clear_group_history(files_dir: &str, group_id: &str) -> bool {
    let mut state = load_state(files_dir);
    let Some(session) = state
        .sessions
        .iter_mut()
        .find(|session| session.group_id == group_id)
    else {
        return false;
    };
    session.messages.clear();
    save_state(files_dir, &state)
}

pub fn is_group_member(files_dir: &str, group_id: &str, agent_id: &str) -> bool {
    let agent_id = normalize_agent_id(agent_id);
    let state = load_state(files_dir);
    state
        .groups
        .iter()
        .find(|group| group.id == group_id)
        .is_some_and(|group| group.coordinator == agent_id || group.members.contains(&agent_id))
}

pub fn add_user_message(files_dir: &str, group_id: &str, content: &str) -> bool {
    add_message(files_dir, group_id, "user", content, None)
}

pub fn add_agent_message(files_dir: &str, group_id: &str, agent_id: &str, content: &str) -> bool {
    add_message(
        files_dir,
        group_id,
        &normalize_agent_id(agent_id),
        content,
        None,
    )
}

pub fn add_delegation_message(
    files_dir: &str,
    group_id: &str,
    from_agent: &str,
    to_agent: &str,
    content: &str,
) -> bool {
    add_message(
        files_dir,
        group_id,
        &normalize_agent_id(from_agent),
        content,
        Some(normalize_agent_id(to_agent)),
    )
}

fn add_message(
    files_dir: &str,
    group_id: &str,
    sender: &str,
    content: &str,
    target_agent: Option<String>,
) -> bool {
    let mut state = load_state(files_dir);
    if !state.groups.iter().any(|group| group.id == group_id) {
        return false;
    }
    session_mut(&mut state, group_id).messages.push(message(
        group_id,
        sender,
        content.to_string(),
        target_agent,
    ));
    save_state(files_dir, &state)
}
