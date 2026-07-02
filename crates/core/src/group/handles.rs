//! Engine-handle wrappers over the file-backed group APIs.

use super::coordinator::events_json;
use super::crud::{
    create_group, delete_group, get_group, list_groups, rename_group, set_group_custom_prompt,
    update_group_members,
};
use super::delegate::{send_to_group, send_to_group_agent};
use super::export::{export_group_state, import_group_state};
use super::messages::{clear_group_history, get_group_messages};

fn error_json(message: &str) -> String {
    serde_json::json!({
        "type": "error",
        "message": message,
    })
    .to_string()
}

fn error_array(message: &str) -> String {
    format!("[{}]", error_json(message))
}

pub fn create_group_handle(handle: i64, name: &str, members_json: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return String::new();
    };
    create_group(&files_dir, name, members_json)
}

pub fn delete_group_handle(handle: i64, group_id: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    delete_group(&files_dir, group_id)
}

pub fn list_groups_handle(handle: i64) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_groups(&files_dir)
}

pub fn get_group_handle(handle: i64, group_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "null".to_string();
    };
    get_group(&files_dir, group_id)
}

pub fn rename_group_handle(handle: i64, group_id: &str, new_name: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    rename_group(&files_dir, group_id, new_name)
}

pub fn update_group_members_handle(handle: i64, group_id: &str, members_json: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    update_group_members(&files_dir, group_id, members_json)
}

pub fn set_group_custom_prompt_handle(handle: i64, group_id: &str, prompt: Option<String>) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    set_group_custom_prompt(&files_dir, group_id, prompt)
}

pub fn get_group_messages_handle(handle: i64, group_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    get_group_messages(&files_dir, group_id)
}

pub fn clear_group_history_handle(handle: i64, group_id: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    clear_group_history(&files_dir, group_id)
}

pub async fn send_to_group_handle(
    handle: i64,
    group_id: &str,
    config_json: &str,
    message: &str,
    max_iterations: i32,
) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return error_json("engine handle is not available");
    };
    match send_to_group(engine, group_id, config_json, message, max_iterations).await {
        Ok(events) => events_json(&events),
        Err(message) => error_json(&message),
    }
}

pub async fn send_to_group_agent_handle(
    handle: i64,
    group_id: &str,
    agent_id: &str,
    config_json: &str,
    session_key_json: &str,
    message: &str,
    max_iterations: i32,
) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return error_array("engine handle is not available");
    };
    match send_to_group_agent(
        engine,
        group_id,
        agent_id,
        config_json,
        session_key_json,
        message,
        max_iterations,
    )
    .await
    {
        Ok(events) => events_json(&events),
        Err(message) => error_array(&message),
    }
}

pub fn export_group_state_handle(handle: i64) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "{}".to_string();
    };
    export_group_state(&files_dir)
}

pub fn import_group_state_handle(handle: i64, state_json: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    import_group_state(&files_dir, state_json)
}
