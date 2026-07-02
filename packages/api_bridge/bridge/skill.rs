//! FRB skill bridge functions. Split out of `bridge/mod.rs`;
//! path `bridge::skill::*` is unchanged for codegen.

#[flutter_rust_bridge::frb(sync)]

pub fn list_skills(handle: i64, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::list_skills_handle(
        handle, &agent_id,
    ))
}
#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_status(handle: i64, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::list_skill_status_handle(
        handle, &agent_id,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_sources(handle: i64, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::list_skill_sources_handle(
        handle, &agent_id,
    ))
}

pub fn record_skill_source_changed(handle: i64, agent_id: String, source_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::record_skill_source_changed_handle(
        handle, &agent_id, &source_id,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn get_skill_status(handle: i64, agent_id: String, skill_name: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::get_skill_status_handle(
        handle,
        &agent_id,
        &skill_name,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn check_skills(handle: i64, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::check_skills_handle(
        handle, &agent_id,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_commands(handle: i64, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::list_skill_commands_handle(
        handle, &agent_id,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn resolve_skill_command(handle: i64, agent_id: String, text: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::resolve_skill_command_handle(
        handle, &agent_id, &text,
    ))
}

pub fn run_skill_command(
    handle: i64,
    agent_id: String,
    command_name: String,
    args: Option<String>,
    session_key_json: Option<String>,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::run_skill_command_handle(
        handle,
        &agent_id,
        &command_name,
        args.as_deref(),
        session_key_json.as_deref(),
    ))
}

pub fn set_skill_enabled(
    handle: i64,
    agent_id: String,
    skill_name: String,
    enabled: bool,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::set_skill_enabled_handle(
        handle,
        &agent_id,
        &skill_name,
        enabled,
    ))
}

pub fn update_skill_config(
    handle: i64,
    agent_id: String,
    skill_key: String,
    patch_json: String,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::update_skill_config_handle(
        handle,
        &agent_id,
        &skill_key,
        &patch_json,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_remediation_actions(handle: i64, agent_id: String, skill_name: String) -> String {
    super::init::runtime().block_on(
        napaxi_core::api::skill::list_skill_remediation_actions_handle(
            handle,
            &agent_id,
            &skill_name,
        ),
    )
}

#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_snapshots(handle: i64, agent_id: String, limit: i32, offset: i32) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::list_skill_snapshots_handle(
        handle,
        &agent_id,
        limit.max(0) as usize,
        offset.max(0) as usize,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn get_skill_snapshot(handle: i64, snapshot_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::get_skill_snapshot_handle(
        handle,
        &snapshot_id,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_secret_requirements(
    handle: i64,
    agent_id: String,
    skill_name: Option<String>,
) -> String {
    super::init::runtime().block_on(
        napaxi_core::api::skill::list_skill_secret_requirements_handle(
            handle,
            &agent_id,
            skill_name.as_deref(),
        ),
    )
}

pub fn record_skill_secret_availability(
    handle: i64,
    agent_id: String,
    skill_name: String,
    key: String,
    available: bool,
    source: String,
) -> String {
    super::init::runtime().block_on(
        napaxi_core::api::skill::record_skill_secret_availability_handle(
            handle,
            &agent_id,
            &skill_name,
            &key,
            available,
            &source,
        ),
    )
}

pub fn request_skill_remediation(
    handle: i64,
    agent_id: String,
    skill_name: String,
    action_id: String,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::request_skill_remediation_handle(
        handle,
        &agent_id,
        &skill_name,
        &action_id,
    ))
}

pub fn update_skill_remediation_run(
    handle: i64,
    agent_id: String,
    run_id: String,
    status: String,
    result_json: Option<String>,
) -> String {
    super::init::runtime().block_on(
        napaxi_core::api::skill::update_skill_remediation_run_handle(
            handle,
            &agent_id,
            &run_id,
            &status,
            result_json.as_deref(),
        ),
    )
}

#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_remediation_runs(
    handle: i64,
    agent_id: String,
    skill_name: Option<String>,
    limit: i32,
    offset: i32,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::list_skill_remediation_runs_handle(
        handle,
        &agent_id,
        skill_name.as_deref(),
        limit.max(0) as usize,
        offset.max(0) as usize,
    ))
}

pub fn record_skill_requirement_resolution(
    handle: i64,
    agent_id: String,
    skill_name: String,
    action_id: String,
    result_json: String,
) -> String {
    super::init::runtime().block_on(
        napaxi_core::api::skill::record_skill_requirement_resolution_handle(
            handle,
            &agent_id,
            &skill_name,
            &action_id,
            &result_json,
        ),
    )
}
pub fn install_skill(handle: i64, agent_id: String, skill_content: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::install_skill_handle(
        handle,
        &agent_id,
        &skill_content,
    ))
}
pub fn remove_skill(handle: i64, agent_id: String, skill_name: String) -> bool {
    super::init::runtime().block_on(napaxi_core::api::skill::remove_skill_handle(
        handle,
        &agent_id,
        &skill_name,
    ))
}
pub fn reload_skills(handle: i64, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::reload_skills_handle(
        handle, &agent_id,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn get_skill(handle: i64, agent_id: String, skill_name: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::get_skill_handle(
        handle,
        &agent_id,
        &skill_name,
    ))
}

#[flutter_rust_bridge::frb(sync)]

pub fn list_skill_usage(handle: i64, agent_id: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::list_skill_usage_handle(
        handle, &agent_id,
    ))
}

pub fn pin_skill(handle: i64, agent_id: String, skill_name: String, pinned: bool) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::pin_skill_handle(
        handle,
        &agent_id,
        &skill_name,
        pinned,
    ))
}

pub fn archive_skill(handle: i64, agent_id: String, skill_name: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::archive_skill_handle(
        handle,
        &agent_id,
        &skill_name,
    ))
}

pub fn restore_skill(handle: i64, agent_id: String, skill_name: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::restore_skill_handle(
        handle,
        &agent_id,
        &skill_name,
    ))
}

pub fn run_skill_curator(handle: i64, agent_id: String, dry_run: bool) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::run_skill_curator_handle(
        handle, &agent_id, dry_run,
    ))
}

pub fn read_skill_support_file(
    handle: i64,
    agent_id: String,
    skill_name: String,
    file_path: String,
) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::read_skill_support_file_handle(
        handle,
        &agent_id,
        &skill_name,
        &file_path,
    ))
}

pub async fn search_catalog(query: String) -> String {
    napaxi_core::api::skill::search_catalog(&query).await
}

pub async fn get_catalog_skill(slug: String) -> String {
    napaxi_core::api::skill::get_catalog_skill(&slug).await
}
pub fn install_from_catalog(handle: i64, agent_id: String, slug: String) -> String {
    super::init::runtime().block_on(napaxi_core::api::skill::install_from_catalog_handle(
        handle, &agent_id, &slug,
    ))
}
