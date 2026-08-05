//! FRB project and session-placement entrypoints.

pub fn register_project(
    handle: i64,
    project_id: String,
    account_id: String,
    agent_id: String,
    name: String,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::project::register_project_handle(
        handle,
        &project_id,
        &account_id,
        &agent_id,
        &name,
    ))
}

pub fn list_projects(handle: i64, account_id: String, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::project::list_projects_handle(
        handle,
        &account_id,
        &agent_id,
    ))
}

pub fn archive_project(
    handle: i64,
    project_id: String,
    account_id: String,
    agent_id: String,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::project::archive_project_handle(
        handle,
        &project_id,
        &account_id,
        &agent_id,
    ))
}

pub fn get_session_placement(handle: i64, session_key_json: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::project::get_session_placement_handle(
        handle,
        &session_key_json,
    ))
}

pub fn list_session_placements(handle: i64, account_id: String, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::project::list_session_placements_handle(
        handle,
        &account_id,
        &agent_id,
    ))
}

pub fn move_session_to_project(
    handle: i64,
    session_key_json: String,
    project_id: Option<String>,
    workspace_policy: String,
    expected_revision: Option<i64>,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::project::move_session_to_project_handle(
        handle,
        &session_key_json,
        project_id.as_deref(),
        &workspace_policy,
        expected_revision,
    ))
}

pub fn list_project_files(
    handle: i64,
    project_id: String,
    account_id: String,
    agent_id: String,
    subdir: Option<String>,
    recursive: bool,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::project::list_project_files_handle(
        handle,
        &project_id,
        &account_id,
        &agent_id,
        subdir.as_deref(),
        recursive,
    ))
}
