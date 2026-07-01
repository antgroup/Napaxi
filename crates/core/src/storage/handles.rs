//! Engine-handle wrappers (sync `_handle` and `_scoped_handle` variants).

use super::attachments::{
    delete_thread_attachments, load_thread_attachments_json, save_message_attachments,
};
use super::bridge::{FileBridge, delete_sandbox_file_with_bridge};
use super::filesystem::{
    detect_file_references_json_with_bridge, list_workspace_filesystem_json_with_bridge,
    workspace_size_with_bridge,
};

fn bridge_from_handle(handle: i64) -> Option<FileBridge> {
    let files_dir = crate::runtime::files_dir_from_handle(handle)?;
    Some(FileBridge::new(&files_dir))
}

fn scoped_bridge_from_handle(handle: i64, account_id: &str, agent_id: &str) -> Option<FileBridge> {
    let files_dir = crate::runtime::files_dir_from_handle(handle)?;
    let workspace_files_dir =
        crate::runtime::scoped_workspace_files_dir(&files_dir, account_id, agent_id);
    Some(FileBridge::new_with_workspace_files_dir(
        &files_dir,
        &workspace_files_dir,
    ))
}

pub fn save_message_attachments_handle(
    handle: i64,
    thread_id: &str,
    user_msg_index: i32,
    attachments_json: &str,
) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    save_message_attachments(&files_dir, thread_id, user_msg_index, attachments_json)
}

pub fn load_thread_attachments_json_handle(handle: i64, thread_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "{}".to_string();
    };
    load_thread_attachments_json(&files_dir, thread_id)
}

pub fn delete_thread_attachments_handle(handle: i64, thread_id: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    delete_thread_attachments(&files_dir, thread_id)
}

pub fn sandbox_to_real_handle(handle: i64, sandbox_path: &str) -> Option<String> {
    bridge_from_handle(handle)?.sandbox_to_real(sandbox_path)
}

pub fn sandbox_to_real_scoped_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    sandbox_path: &str,
) -> Option<String> {
    scoped_bridge_from_handle(handle, account_id, agent_id)?.sandbox_to_real(sandbox_path)
}

pub fn real_to_sandbox_handle(handle: i64, real_path: &str) -> Option<String> {
    bridge_from_handle(handle)?.real_to_sandbox(real_path)
}

pub fn real_to_sandbox_scoped_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    real_path: &str,
) -> Option<String> {
    scoped_bridge_from_handle(handle, account_id, agent_id)?.real_to_sandbox(real_path)
}

pub fn delete_sandbox_file_handle(handle: i64, sandbox_path: &str) -> bool {
    let Some(bridge) = bridge_from_handle(handle) else {
        return false;
    };
    delete_sandbox_file_with_bridge(&bridge, sandbox_path)
}

pub fn delete_sandbox_file_scoped_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    sandbox_path: &str,
) -> bool {
    let Some(bridge) = scoped_bridge_from_handle(handle, account_id, agent_id) else {
        return false;
    };
    delete_sandbox_file_with_bridge(&bridge, sandbox_path)
}

pub fn detect_file_references_json_handle(handle: i64, text: &str) -> String {
    let Some(bridge) = bridge_from_handle(handle) else {
        return "[]".to_string();
    };
    detect_file_references_json_with_bridge(&bridge, text)
}

pub fn detect_file_references_json_scoped_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    text: &str,
) -> String {
    let Some(bridge) = scoped_bridge_from_handle(handle, account_id, agent_id) else {
        return "[]".to_string();
    };
    detect_file_references_json_with_bridge(&bridge, text)
}

pub fn list_workspace_filesystem_json_handle(
    handle: i64,
    subdir: Option<&str>,
    recursive: bool,
) -> String {
    let Some(bridge) = bridge_from_handle(handle) else {
        return "[]".to_string();
    };
    list_workspace_filesystem_json_with_bridge(&bridge, subdir, recursive)
}

pub fn list_workspace_filesystem_json_scoped_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    subdir: Option<&str>,
    recursive: bool,
) -> String {
    let Some(bridge) = scoped_bridge_from_handle(handle, account_id, agent_id) else {
        return "[]".to_string();
    };
    list_workspace_filesystem_json_with_bridge(&bridge, subdir, recursive)
}

pub fn init_file_bridge_handle(handle: i64) -> bool {
    let Some(bridge) = bridge_from_handle(handle) else {
        return false;
    };
    bridge.ensure_workspace()
}

pub fn init_file_bridge_scoped_handle(handle: i64, account_id: &str, agent_id: &str) -> bool {
    let Some(bridge) = scoped_bridge_from_handle(handle, account_id, agent_id) else {
        return false;
    };
    bridge.ensure_workspace()
}

pub fn workspace_size_handle(handle: i64) -> u64 {
    let Some(bridge) = bridge_from_handle(handle) else {
        return 0;
    };
    workspace_size_with_bridge(&bridge)
}

pub fn workspace_size_scoped_handle(handle: i64, account_id: &str, agent_id: &str) -> u64 {
    let Some(bridge) = scoped_bridge_from_handle(handle, account_id, agent_id) else {
        return 0;
    };
    workspace_size_with_bridge(&bridge)
}

pub fn workspace_dir_handle(handle: i64) -> String {
    let Some(bridge) = bridge_from_handle(handle) else {
        return String::new();
    };
    bridge.workspace_dir().display().to_string()
}

pub fn workspace_dir_scoped_handle(handle: i64, account_id: &str, agent_id: &str) -> String {
    let Some(bridge) = scoped_bridge_from_handle(handle, account_id, agent_id) else {
        return String::new();
    };
    bridge.workspace_dir().display().to_string()
}

pub fn rootfs_dir_handle(handle: i64) -> String {
    let Some(bridge) = bridge_from_handle(handle) else {
        return String::new();
    };
    bridge.rootfs_dir().display().to_string()
}

pub fn skills_dir_handle(handle: i64) -> String {
    let Some(bridge) = bridge_from_handle(handle) else {
        return String::new();
    };
    bridge.skills_dir().display().to_string()
}
