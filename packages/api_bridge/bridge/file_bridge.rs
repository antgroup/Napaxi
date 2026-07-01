//! FRB file-bridge functions. Split out of `bridge/mod.rs`;
//! path `bridge::file_bridge::*` is unchanged for codegen.

#[flutter_rust_bridge::frb(sync)]

pub fn save_message_attachments(
    handle: i64,
    thread_id: String,
    user_msg_index: i32,
    attachments_json: String,
) -> bool {
    napaxi_core::api::file_bridge::save_message_attachments_handle(
        handle,
        &thread_id,
        user_msg_index,
        &attachments_json,
    )
}

#[flutter_rust_bridge::frb(sync)]

pub fn load_thread_attachments(handle: i64, thread_id: String) -> String {
    napaxi_core::api::file_bridge::load_thread_attachments_json_handle(handle, &thread_id)
}

#[flutter_rust_bridge::frb(sync)]

pub fn delete_thread_attachments(handle: i64, thread_id: String) -> bool {
    napaxi_core::api::file_bridge::delete_thread_attachments_handle(handle, &thread_id)
}

#[flutter_rust_bridge::frb(sync)]

pub fn init_file_bridge(handle: i64) -> bool {
    napaxi_core::api::file_bridge::init_file_bridge_handle(handle)
}

#[flutter_rust_bridge::frb(sync)]

pub fn init_file_bridge_scoped(handle: i64, account_id: String, agent_id: String) -> bool {
    napaxi_core::api::file_bridge::init_file_bridge_scoped_handle(handle, &account_id, &agent_id)
}

#[flutter_rust_bridge::frb(sync)]

pub fn sandbox_to_real(handle: i64, sandbox_path: String) -> Option<String> {
    napaxi_core::api::file_bridge::sandbox_to_real_handle(handle, &sandbox_path)
}

#[flutter_rust_bridge::frb(sync)]

pub fn sandbox_to_real_scoped(
    handle: i64,
    account_id: String,
    agent_id: String,
    sandbox_path: String,
) -> Option<String> {
    napaxi_core::api::file_bridge::sandbox_to_real_scoped_handle(
        handle,
        &account_id,
        &agent_id,
        &sandbox_path,
    )
}

#[flutter_rust_bridge::frb(sync)]

pub fn real_to_sandbox(handle: i64, real_path: String) -> Option<String> {
    napaxi_core::api::file_bridge::real_to_sandbox_handle(handle, &real_path)
}

#[flutter_rust_bridge::frb(sync)]

pub fn real_to_sandbox_scoped(
    handle: i64,
    account_id: String,
    agent_id: String,
    real_path: String,
) -> Option<String> {
    napaxi_core::api::file_bridge::real_to_sandbox_scoped_handle(
        handle,
        &account_id,
        &agent_id,
        &real_path,
    )
}

#[flutter_rust_bridge::frb(sync)]

pub fn detect_file_references(handle: i64, text: String) -> String {
    napaxi_core::api::file_bridge::detect_file_references_json_handle(handle, &text)
}

#[flutter_rust_bridge::frb(sync)]

pub fn detect_file_references_scoped(
    handle: i64,
    account_id: String,
    agent_id: String,
    text: String,
) -> String {
    napaxi_core::api::file_bridge::detect_file_references_json_scoped_handle(
        handle,
        &account_id,
        &agent_id,
        &text,
    )
}

pub fn delete_sandbox_file(handle: i64, sandbox_path: String) -> bool {
    napaxi_core::api::file_bridge::delete_sandbox_file_handle(handle, &sandbox_path)
}
pub fn delete_sandbox_file_scoped(
    handle: i64,
    account_id: String,
    agent_id: String,
    sandbox_path: String,
) -> bool {
    napaxi_core::api::file_bridge::delete_sandbox_file_scoped_handle(
        handle,
        &account_id,
        &agent_id,
        &sandbox_path,
    )
}
pub fn list_workspace_filesystem(handle: i64, subdir: Option<String>, recursive: bool) -> String {
    napaxi_core::api::file_bridge::list_workspace_filesystem_json_handle(
        handle,
        subdir.as_deref(),
        recursive,
    )
}
pub fn list_workspace_filesystem_scoped(
    handle: i64,
    account_id: String,
    agent_id: String,
    subdir: Option<String>,
    recursive: bool,
) -> String {
    napaxi_core::api::file_bridge::list_workspace_filesystem_json_scoped_handle(
        handle,
        &account_id,
        &agent_id,
        subdir.as_deref(),
        recursive,
    )
}

#[flutter_rust_bridge::frb(sync)]

pub fn workspace_size(handle: i64) -> u64 {
    napaxi_core::api::file_bridge::workspace_size_handle(handle)
}

#[flutter_rust_bridge::frb(sync)]

pub fn workspace_size_scoped(handle: i64, account_id: String, agent_id: String) -> u64 {
    napaxi_core::api::file_bridge::workspace_size_scoped_handle(handle, &account_id, &agent_id)
}

#[flutter_rust_bridge::frb(sync)]

pub fn workspace_dir(handle: i64) -> String {
    napaxi_core::api::file_bridge::workspace_dir_handle(handle)
}

#[flutter_rust_bridge::frb(sync)]

pub fn workspace_dir_scoped(handle: i64, account_id: String, agent_id: String) -> String {
    napaxi_core::api::file_bridge::workspace_dir_scoped_handle(handle, &account_id, &agent_id)
}

#[flutter_rust_bridge::frb(sync)]

pub fn rootfs_dir(handle: i64) -> String {
    napaxi_core::api::file_bridge::rootfs_dir_handle(handle)
}

#[flutter_rust_bridge::frb(sync)]

pub fn skills_dir(handle: i64) -> String {
    napaxi_core::api::file_bridge::skills_dir_handle(handle)
}

/// Write the Git commit identity (`user.name` / `user.email`) into the sandbox
/// rootfs `~/.gitconfig`. Returns `true` on success.
#[flutter_rust_bridge::frb(sync)]
pub fn configure_git_identity(handle: i64, name: String, email: String) -> bool {
    napaxi_core::api::engine::EngineHandle(handle)
        .configure_git_identity(&name, &email)
        .is_ok()
}

/// Read the Git commit identity from the sandbox rootfs `~/.gitconfig`.
/// Returns `{"name": "...", "email": "..."}` when set, or an empty string when
/// no identity (or no file) is present.
#[flutter_rust_bridge::frb(sync)]
pub fn read_git_identity(handle: i64) -> String {
    match napaxi_core::api::engine::EngineHandle(handle).read_git_identity() {
        Ok(Some((name, email))) => serde_json::json!({ "name": name, "email": email }).to_string(),
        _ => String::new(),
    }
}
