use serde_json::Value;

use super::*;

pub(super) fn dispatch_project(handle: i64, method: &str, payload: &Value) -> Option<String> {
    Some(match method {
        "register" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::project::register_project_handle(
                handle,
                &get_string(payload, "project_id"),
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "name"),
            ),
        )),
        "list" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::project::list_projects_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            ),
        )),
        "archive" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::project::archive_project_handle(
                handle,
                &get_string(payload, "project_id"),
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            ),
        )),
        "get_session_placement" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::project::get_session_placement_handle(
                handle,
                &get_string(payload, "session_key_json"),
            ),
        )),
        "list_session_placements" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::project::list_session_placements_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            ),
        )),
        "move_session" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::project::move_session_to_project_handle(
                handle,
                &get_string(payload, "session_key_json"),
                get_opt_string(payload, "project_id").as_deref(),
                &get_string(payload, "workspace_policy"),
                payload.get("expected_revision").and_then(Value::as_i64),
            ),
        )),
        "list_files" => ok_raw(
            crate::bridge::init::runtime().block_on(
                napaxi_core::api::project::list_project_files_handle(
                    handle,
                    &get_string(payload, "project_id"),
                    &get_string(payload, "account_id"),
                    &get_string(payload, "agent_id"),
                    get_opt_string(payload, "subdir").as_deref(),
                    payload
                        .get("recursive")
                        .and_then(Value::as_bool)
                        .unwrap_or(true),
                ),
            ),
        ),
        _ => return None,
    })
}
