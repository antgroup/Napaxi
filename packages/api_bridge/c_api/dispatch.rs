//! Internal bridge method routing for the C API. Split out of
//! `c_api.rs`: maps (namespace, method, payload) to napaxi_core::api
//! calls. The `#[no_mangle]` FFI entrypoints and shared helpers stay in
//! `c_api/mod.rs`.

use serde_json::Value;

use super::*;

pub(super) fn dispatch(handle: i64, namespace: &str, method: &str, payload: &Value) -> String {
    if namespace == "channel" {
        if let Some(response) = super::channel_dispatch::dispatch_channel(handle, method, payload) {
            return response;
        }
    }
    if namespace == "channel_agent" {
        if let Some(response) =
            super::channel_agent_dispatch::dispatch_channel_agent(handle, method, payload)
        {
            return response;
        }
    }
    if namespace == "channel_qqbot" {
        if let Some(response) =
            super::channel_qqbot_dispatch::dispatch_channel_qqbot(method, payload)
        {
            return response;
        }
    }

    match (namespace, method) {
        ("tools", "platform_tool_descriptors") => {
            ok_raw(napaxi_core::api::tools::platform_tool_descriptors_json())
        }
        ("tools", "is_platform_tool") => ok(json!(napaxi_core::api::tools::is_platform_tool(
            &get_string(payload, "name")
        ))),
        ("tools", "browser_tool_descriptors") => {
            ok_raw(napaxi_core::api::tools::browser_tool_descriptors_json())
        }
        ("tools", "is_browser_tool") => ok(json!(napaxi_core::api::tools::is_browser_tool(
            &get_string(payload, "name")
        ))),
        ("tools", "answer_human_request") => {
            ok(json!(napaxi_core::api::tools::answer_human_request(
                &get_string(payload, "request_id"),
                &get_string(payload, "response"),
            )))
        }
        ("tools", "tool_broker_list_tools") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::tools::tool_broker_list_tools_json_handle(
                handle,
                &get_string(payload, "request_json"),
            ),
        )),
        ("tools", "tool_broker_call_tool") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::tools::tool_broker_call_tool_json_handle(
                handle,
                &get_string(payload, "request_json"),
            ),
        )),
        ("agent_engine", "run_event") => ok_raw(napaxi_core::api::agent_engine::run_event_json(
            &get_string(payload, "request_json"),
        )),
        ("capability", "list_definitions") => {
            ok_raw(napaxi_core::api::capability::list_capability_definitions_json())
        }
        ("capability", "list_status") => ok_raw(
            napaxi_core::api::capability::list_capability_status_json_handle(
                handle,
                &get_string(payload, "profile_json"),
                &get_string(payload, "selection_json"),
            ),
        ),
        ("capability", "list_scenarios") => {
            ok_raw(napaxi_core::api::capability::list_scenario_packs_json_handle(handle))
        }
        ("capability", "install_scenario") => ok_raw(
            napaxi_core::api::capability::install_scenario_pack_json_handle(
                handle,
                &get_string(payload, "pack_json"),
            ),
        ),
        ("capability", "remove_scenario") => ok_raw(
            napaxi_core::api::capability::remove_scenario_pack_json_handle(
                handle,
                &get_string(payload, "scenario_id"),
            ),
        ),
        ("capability", "list_scenario_status") => ok_raw(
            napaxi_core::api::capability::list_scenario_status_json_handle(
                handle,
                &get_string(payload, "profile_json"),
                &get_string(payload, "selection_json"),
            ),
        ),
        ("capability", "resolve_scenario") => {
            ok_raw(napaxi_core::api::capability::resolve_scenario_json_handle(
                handle,
                &get_string(payload, "profile_json"),
                &get_string(payload, "selection_json"),
                &get_string(payload, "scenario_id"),
            ))
        }
        ("capability", "provider_capability_id") => ok(json!(
            napaxi_core::api::capability::provider_capability_id(&get_string(payload, "provider"))
        )),
        ("capability", "agent_engine_capability_id") => ok(json!(
            napaxi_core::api::capability::agent_engine_capability_id(&get_string(
                payload,
                "engine_id"
            ))
        )),
        ("capability", "tool_capability_id") => ok(json!(
            napaxi_core::api::capability::tool_capability_id(&get_string(payload, "tool_name"))
        )),
        ("automation", "create_job") => {
            ok_raw(napaxi_core::api::automation::create_automation_job_handle(
                handle,
                &get_string(payload, "job_json"),
            ))
        }
        ("automation", "update_job") => {
            ok_raw(napaxi_core::api::automation::update_automation_job_handle(
                handle,
                &get_string(payload, "job_id"),
                &get_string(payload, "patch_json"),
            ))
        }
        ("automation", "delete_job") => ok(json!(
            napaxi_core::api::automation::delete_automation_job_handle(
                handle,
                &get_string(payload, "job_id"),
            )
        )),
        ("automation", "list_jobs") => {
            ok_raw(napaxi_core::api::automation::list_automation_jobs_handle(
                handle,
                &get_string(payload, "filter_json"),
            ))
        }
        ("automation", "get_job") => {
            ok_raw(napaxi_core::api::automation::get_automation_job_handle(
                handle,
                &get_string(payload, "job_id"),
            ))
        }
        ("automation", "run_job") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::automation::run_automation_job_handle(
                handle,
                &get_string(payload, "job_id"),
                &get_string(payload, "mode"),
            ),
        )),
        ("automation", "list_runs") => {
            ok_raw(napaxi_core::api::automation::list_automation_runs_handle(
                handle,
                get_opt_string(payload, "job_id").as_deref(),
                get_i64(payload, "limit", 50),
                get_i64(payload, "offset", 0),
            ))
        }
        ("automation", "next_wake") => {
            ok_raw(napaxi_core::api::automation::get_next_automation_wake_handle(handle))
        }
        ("automation", "record_wake") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::automation::record_automation_wake_handle(
                handle,
                &get_string(payload, "job_id"),
                &get_string(payload, "source"),
            ),
        )),
        ("session_runs", "list") => {
            ok_raw(napaxi_core::api::session_runs::list_session_runs_handle(
                handle,
                &get_string(payload, "filter_json"),
                get_i64(payload, "limit", 50),
                get_i64(payload, "offset", 0),
            ))
        }
        ("session_runs", "get") => ok_raw(napaxi_core::api::session_runs::get_session_run_handle(
            handle,
            &get_string(payload, "run_id"),
        )),
        ("session_runs", "active") => {
            ok_raw(napaxi_core::api::session_runs::get_active_session_runs_handle(handle))
        }
        ("agent_app", "register_package") => {
            ok_raw(napaxi_core::api::agent_app::register_agent_app_package(
                handle,
                &get_string(payload, "package_json"),
            ))
        }
        ("agent_app", "list_packages") => {
            ok_raw(napaxi_core::api::agent_app::list_agent_app_packages(handle))
        }
        ("agent_app", "get_package") => ok_raw(napaxi_core::api::agent_app::get_agent_app_package(
            handle,
            &get_string(payload, "agent_id"),
        )),
        ("agent_app", "delete_package") => {
            ok(json!(napaxi_core::api::agent_app::delete_agent_app_package(
                handle,
                &get_string(payload, "agent_id"),
            )))
        }
        ("agent_app", "submit_action_result") => {
            ok_raw(napaxi_core::api::agent_app::submit_agent_app_action_result(
                handle,
                &get_string(payload, "result_json"),
            ))
        }
        ("agent_app", "list_proposals") => {
            ok_raw(napaxi_core::api::agent_app::list_agent_app_action_proposals(
                handle,
                &get_string(payload, "agent_id"),
            ))
        }
        ("agent_app", "get_proposal") => {
            ok_raw(napaxi_core::api::agent_app::get_agent_app_action_proposal(
                handle,
                &get_string(payload, "request_id"),
            ))
        }
        ("agent_app", "accept_trigger") => {
            ok_raw(napaxi_core::api::agent_app::accept_agent_app_trigger(
                handle,
                &get_string(payload, "trigger_json"),
            ))
        }
        ("a2a", method) => {
            super::a2a_dispatch::dispatch(handle, method, payload).unwrap_or_else(|| {
                err(
                    "unknown_method",
                    format!("unknown Napaxi API method a2a.{method}"),
                )
            })
        }
        ("agent", "get_or_create") => ok_raw(napaxi_core::api::engine::get_or_create_agent_handle(
            handle,
            &get_string(payload, "agent_id"),
        )),
        ("agent", "list") => ok_raw(napaxi_core::api::engine::list_agents_handle(handle)),
        ("agent", "delete") => ok(json!(
            napaxi_core::api::engine::delete_agent_handle_typed(
                handle,
                &get_string(payload, "agent_id"),
            )
            .is_ok()
        )),
        ("agent", "send") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::agent::send_agent_json_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "config_json"),
                &get_string(payload, "session_key_json"),
                &get_string(payload, "message"),
                get_i32(payload, "max_iterations", 8),
            ),
        )),
        ("agent_defs", "create") => ok_raw(napaxi_core::api::agent::create_definition_handle(
            handle,
            &get_string(payload, "definition_json"),
        )),
        ("agent_defs", "update") => ok(json!(napaxi_core::api::agent::update_definition_handle(
            handle,
            &get_string(payload, "definition_json"),
        ))),
        ("agent_defs", "delete") => ok(json!(napaxi_core::api::agent::delete_definition_handle(
            handle,
            &get_string(payload, "definition_id"),
        ))),
        ("agent_defs", "list") => ok_raw(napaxi_core::api::agent::list_definitions_handle(handle)),
        ("agent_defs", "get") => ok_raw(napaxi_core::api::agent::get_definition_json_handle(
            handle,
            &get_string(payload, "definition_id"),
        )),
        ("agent_defs", "list_available_tools") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::engine::available_tool_infos_json_handle(
                handle,
                napaxi_core::api::engine::DEFAULT_ACCOUNT_ID,
                napaxi_core::api::engine::DEFAULT_AGENT_ID,
            ),
        )),
        ("agent_defs", "create_from_definition") => ok(json!(
            napaxi_core::api::agent::create_agent_from_definition_handle(
                handle,
                &get_string(payload, "definition_id"),
            )
        )),
        ("agent_defs", "import_markdown") => ok_raw(
            napaxi_core::api::agent::import_agent_md_handle(handle, &get_string(payload, "content")),
        ),
        ("session", "create") => ok_raw(napaxi_core::api::session::create_session_handle(
            handle,
            &get_string(payload, "agent_id"),
            &get_string(payload, "channel_type"),
            &get_string(payload, "account_id"),
            get_opt_string(payload, "existing_thread_id").as_deref(),
        )),
        ("session", "list") => ok_raw(napaxi_core::api::session::list_sessions_handle(
            handle,
            &get_string(payload, "agent_id"),
            &get_string(payload, "account_id"),
        )),
        ("session", "delete") => ok(json!(napaxi_core::api::session::delete_session_handle(
            handle,
            &get_string(payload, "session_key_json"),
        ))),
        ("session", "clear") => ok(json!(napaxi_core::api::session::clear_session_handle(
            handle,
            &get_string(payload, "session_key_json"),
        ))),
        ("session", "delete_if_empty") => ok(json!(
            napaxi_core::api::session::delete_session_if_empty_handle(
                handle,
                &get_string(payload, "session_key_json"),
            )
        )),
        ("session", "prune_empty") => ok(json!(
            napaxi_core::api::session::prune_empty_sessions_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "account_id"),
            )
        )),
        ("session", "history") => ok_raw(napaxi_core::api::session::get_history_handle(
            handle,
            &get_string(payload, "thread_id"),
        )),
        ("session", "history_page") => ok_raw(napaxi_core::api::session::get_history_page_handle(
            handle,
            &get_string(payload, "thread_id"),
            get_opt_string(payload, "before").as_deref(),
            get_i64(payload, "limit", 50),
        )),
        ("session", "compact_context") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::session::compact_session_handle_async(
                handle,
                &get_string(payload, "config_json"),
                &get_string(payload, "session_key_json"),
                get_opt_string(payload, "focus").as_deref(),
            ),
        )),
        ("session", "context_status") => ok_raw(napaxi_core::api::session::context_status_handle(
            handle,
            &get_string(payload, "config_json"),
            &get_string(payload, "thread_id"),
        )),
        ("session", "inject_message") => ok(json!(napaxi_core::api::engine::inject_message_handle(
            handle,
            &get_string(payload, "config_json"),
            &get_string(payload, "agent_id"),
            &get_string(payload, "session_key_json"),
            &get_string(payload, "message"),
            &get_string(payload, "attachments_json"),
        ))),
        ("session", "retract_injected_message") => ok(json!(
            napaxi_core::api::engine::retract_injected_message_handle(
                handle,
                &get_string(payload, "session_key_json"),
                &get_string(payload, "message"),
            )
        )),
        ("session", "cancel") => ok(json!(
            napaxi_core::api::engine::cancel_session_handle_typed(
                handle,
                &get_string(payload, "session_key_json"),
            )
            .unwrap_or(false)
        )),
        ("skill", "list") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::list_skills_handle(handle, &get_string(payload, "agent_id")),
        )),
        ("skill", "status") | ("skill", "list_status") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::list_skill_status_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                ),
            ))
        }
        ("skill", "sources") | ("skill", "list_sources") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::list_skill_sources_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                ),
            ))
        }
        ("skill", "record_source_changed") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::record_skill_source_changed_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "source_id"),
            ),
        )),
        ("skill", "get_status") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::get_skill_status_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
            ),
        )),
        ("skill", "check") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::check_skills_handle(handle, &get_string(payload, "agent_id")),
        )),
        ("skill", "commands") | ("skill", "list_commands") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::list_skill_commands_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                ),
            ))
        }
        ("skill", "resolve_command") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::resolve_skill_command_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "text"),
            ),
        )),
        ("skill", "run_command") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::run_skill_command_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "command_name"),
                get_opt_string(payload, "args").as_deref(),
                get_opt_string(payload, "session_key_json").as_deref(),
            ),
        )),
        ("skill", "set_enabled") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::set_skill_enabled_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
                get_bool(payload, "enabled"),
            ),
        )),
        ("skill", "update_config") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::update_skill_config_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_key"),
                &get_string(payload, "patch_json"),
            ),
        )),
        ("skill", "remediation_actions") | ("skill", "list_remediation_actions") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::list_skill_remediation_actions_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                    &get_string(payload, "skill_name"),
                ),
            ))
        }
        ("skill", "snapshots") | ("skill", "list_snapshots") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::list_skill_snapshots_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                    get_usize(payload, "limit"),
                    get_usize(payload, "offset"),
                ),
            ))
        }
        ("skill", "get_snapshot") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::get_skill_snapshot_handle(
                handle,
                &get_string(payload, "snapshot_id"),
            ),
        )),
        ("skill", "secret_requirements") | ("skill", "list_secret_requirements") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::list_skill_secret_requirements_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                    get_opt_string(payload, "skill_name").as_deref(),
                ),
            ))
        }
        ("skill", "record_secret_availability") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::record_skill_secret_availability_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
                &get_string(payload, "key"),
                get_bool(payload, "available"),
                &get_string(payload, "source"),
            ),
        )),
        ("skill", "request_remediation") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::request_skill_remediation_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
                &get_string(payload, "action_id"),
            ),
        )),
        ("skill", "update_remediation_run") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::update_skill_remediation_run_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "run_id"),
                &get_string(payload, "status"),
                get_opt_string(payload, "result_json").as_deref(),
            ),
        )),
        ("skill", "remediation_runs") | ("skill", "list_remediation_runs") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::list_skill_remediation_runs_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                    get_opt_string(payload, "skill_name").as_deref(),
                    get_usize(payload, "limit"),
                    get_usize(payload, "offset"),
                ),
            ))
        }
        ("skill", "record_requirement_resolution") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::skill::record_skill_requirement_resolution_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                    &get_string(payload, "skill_name"),
                    &get_string(payload, "action_id"),
                    &get_string(payload, "result_json"),
                ),
            ))
        }
        ("skill", "install") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::install_skill_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_content"),
            ),
        )),
        ("skill", "remove") => ok(json!(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::remove_skill_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
            )
        ))),
        ("skill", "reload") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::reload_skills_handle(handle, &get_string(payload, "agent_id")),
        )),
        ("skill", "get") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::get_skill_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
            ),
        )),
        ("skill", "usage") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::list_skill_usage_handle(
                handle,
                &get_string(payload, "agent_id"),
            ),
        )),
        ("skill", "pin") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::pin_skill_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
                get_bool(payload, "pinned"),
            ),
        )),
        ("skill", "archive") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::archive_skill_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
            ),
        )),
        ("skill", "restore") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::restore_skill_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
            ),
        )),
        ("skill", "run_curator") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::run_skill_curator_handle(
                handle,
                &get_string(payload, "agent_id"),
                get_bool(payload, "dry_run"),
            ),
        )),
        ("skill", "read_support_file") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::read_skill_support_file_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "skill_name"),
                &get_string(payload, "file_path"),
            ),
        )),
        ("skill", "search_catalog") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::search_catalog(&get_string(payload, "query")),
        )),
        ("skill", "get_catalog_skill") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::get_catalog_skill(&get_string(payload, "slug")),
        )),
        ("skill", "install_from_catalog") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::skill::install_from_catalog_handle(
                handle,
                &get_string(payload, "agent_id"),
                &get_string(payload, "slug"),
            ),
        )),
        ("evolution", "list_pending") => ok_raw(
            napaxi_core::api::evolution::list_pending_evolution_handle(handle),
        ),
        ("evolution", "list_runs") => {
            ok_raw(napaxi_core::api::evolution::list_evolution_runs_handle(
                handle,
                &get_string(payload, "run_ids_json"),
            ))
        }
        ("evolution", "list_diagnostics") => {
            ok_raw(napaxi_core::api::evolution::list_evolution_diagnostics_handle(handle))
        }
        ("evolution", "reject_pending") => {
            ok_raw(napaxi_core::api::evolution::reject_pending_evolution_handle(
                handle,
                &get_string(payload, "pending_id"),
            ))
        }
        ("evolution", "apply_pending") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::evolution::apply_pending_evolution_handle(
                handle,
                &get_string(payload, "pending_id"),
            ),
        )),
        ("evolution", "run_skill_consolidation_review") => {
            ok_raw(crate::bridge::init::runtime().block_on(
                napaxi_core::api::evolution::run_skill_consolidation_review_handle(
                    handle,
                    &get_string(payload, "agent_id"),
                    &get_string(payload, "config_json"),
                    get_bool(payload, "dry_run"),
                ),
            ))
        }
        ("group", "create") => ok_raw(napaxi_core::api::group::create_group_handle(
            handle,
            &get_string(payload, "name"),
            &get_string(payload, "members_json"),
        )),
        ("group", "delete") => ok(json!(napaxi_core::api::group::delete_group_handle(
            handle,
            &get_string(payload, "group_id"),
        ))),
        ("group", "list") => ok_raw(napaxi_core::api::group::list_groups_handle(handle)),
        ("group", "get") => ok_raw(napaxi_core::api::group::get_group_handle(
            handle,
            &get_string(payload, "group_id"),
        )),
        ("group", "rename") => ok(json!(napaxi_core::api::group::rename_group_handle(
            handle,
            &get_string(payload, "group_id"),
            &get_string(payload, "new_name"),
        ))),
        ("group", "update_members") => {
            ok(json!(napaxi_core::api::group::update_group_members_handle(
                handle,
                &get_string(payload, "group_id"),
                &get_string(payload, "members_json"),
            )))
        }
        ("group", "set_custom_prompt") => ok(json!(
            napaxi_core::api::group::set_group_custom_prompt_handle(
                handle,
                &get_string(payload, "group_id"),
                get_opt_string(payload, "prompt"),
            )
        )),
        ("group", "messages") => ok_raw(napaxi_core::api::group::get_group_messages_handle(
            handle,
            &get_string(payload, "group_id"),
        )),
        ("group", "clear_history") => {
            ok(json!(napaxi_core::api::group::clear_group_history_handle(
                handle,
                &get_string(payload, "group_id"),
            )))
        }
        ("group", "send") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::group::send_to_group_handle(
                handle,
                &get_string(payload, "group_id"),
                &get_string(payload, "config_json"),
                &get_string(payload, "message"),
                get_i32(payload, "max_iterations", 8),
            ),
        )),
        ("group", "send_to_agent") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::group::send_to_group_agent_handle(
                handle,
                &get_string(payload, "group_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "config_json"),
                &get_string(payload, "session_key_json"),
                &get_string(payload, "message"),
                get_i32(payload, "max_iterations", 8),
            ),
        )),
        ("group", "export_state") => {
            ok_raw(napaxi_core::api::group::export_group_state_handle(handle))
        }
        ("group", "import_state") => ok(json!(napaxi_core::api::group::import_group_state_handle(
            handle,
            &get_string(payload, "state_json"),
        ))),
        ("workspace", "read_file") => {
            ok_raw(napaxi_core::api::workspace::read_workspace_file_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "path"),
            ))
        }
        ("workspace", "write_file") => ok(json!(
            napaxi_core::api::workspace::write_workspace_file_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "path"),
                &get_string(payload, "content"),
            )
        )),
        ("workspace", "append_file") => ok(json!(
            napaxi_core::api::workspace::append_workspace_file_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "path"),
                &get_string(payload, "content"),
            )
        )),
        ("workspace", "delete_file") => ok(json!(
            napaxi_core::api::workspace::delete_workspace_file_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "path"),
            )
        )),
        ("workspace", "list_files") => {
            ok_raw(napaxi_core::api::workspace::list_workspace_files_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "directory"),
            ))
        }
        ("workspace", "system_prompt") => ok_raw(napaxi_core::api::workspace::system_prompt_handle(
            handle,
            &get_string(payload, "account_id"),
            &get_string(payload, "agent_id"),
        )),
        ("workspace", "reseed") => ok_raw(napaxi_core::api::workspace::reseed_workspace_handle(
            handle,
            &get_string(payload, "account_id"),
            &get_string(payload, "agent_id"),
        )),
        ("workspace", "search_memory") => ok_raw(napaxi_core::api::workspace::search_memory_handle(
            handle,
            &get_string(payload, "account_id"),
            &get_string(payload, "agent_id"),
            &get_string(payload, "query"),
            get_u32(payload, "limit", 20),
        )),
        ("workspace", "recall_sessions") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::workspace::recall_sessions_handle(
                handle,
                &get_string(payload, "config_json"),
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "current_thread_id"),
                &get_string(payload, "query"),
                get_u32(payload, "limit", 20),
            ),
        )),
        ("workspace", "rebuild_recall_index") => {
            ok_raw(napaxi_core::api::workspace::rebuild_recall_index_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            ))
        }
        ("workspace", "recall_index_stats") => {
            ok_raw(napaxi_core::api::workspace::recall_index_stats_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            ))
        }
        ("workspace", "list_journal_days") => {
            ok_raw(napaxi_core::api::workspace::list_journal_days_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            ))
        }
        ("workspace", "read_journal_day") => {
            ok_raw(napaxi_core::api::workspace::read_journal_day_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "date"),
            ))
        }
        ("file_bridge", "save_message_attachments") => ok(json!(
            napaxi_core::api::file_bridge::save_message_attachments_handle(
                handle,
                &get_string(payload, "thread_id"),
                get_i32(payload, "user_msg_index", 0),
                &get_string(payload, "attachments_json"),
            )
        )),
        ("file_bridge", "load_thread_attachments") => ok_raw(
            napaxi_core::api::file_bridge::load_thread_attachments_json_handle(
                handle,
                &get_string(payload, "thread_id"),
            ),
        ),
        ("file_bridge", "delete_thread_attachments") => ok(json!(
            napaxi_core::api::file_bridge::delete_thread_attachments_handle(
                handle,
                &get_string(payload, "thread_id"),
            )
        )),
        ("file_bridge", "init") => ok(json!(
            napaxi_core::api::file_bridge::init_file_bridge_handle(handle)
        )),
        ("file_bridge", "init_scoped") => ok(json!(
            napaxi_core::api::file_bridge::init_file_bridge_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            )
        )),
        ("file_bridge", "sandbox_to_real") => {
            ok(json!(napaxi_core::api::file_bridge::sandbox_to_real_handle(
                handle,
                &get_string(payload, "sandbox_path"),
            )))
        }
        ("file_bridge", "sandbox_to_real_scoped") => ok(json!(
            napaxi_core::api::file_bridge::sandbox_to_real_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "sandbox_path"),
            )
        )),
        ("file_bridge", "real_to_sandbox") => {
            ok(json!(napaxi_core::api::file_bridge::real_to_sandbox_handle(
                handle,
                &get_string(payload, "real_path"),
            )))
        }
        ("file_bridge", "real_to_sandbox_scoped") => ok(json!(
            napaxi_core::api::file_bridge::real_to_sandbox_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "real_path"),
            )
        )),
        ("file_bridge", "detect_file_references") => ok_raw(
            napaxi_core::api::file_bridge::detect_file_references_json_handle(
                handle,
                &get_string(payload, "text"),
            ),
        ),
        ("file_bridge", "detect_file_references_scoped") => ok_raw(
            napaxi_core::api::file_bridge::detect_file_references_json_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "text"),
            ),
        ),
        ("file_bridge", "delete_sandbox_file") => ok(json!(
            napaxi_core::api::file_bridge::delete_sandbox_file_handle(
                handle,
                &get_string(payload, "sandbox_path"),
            )
        )),
        ("file_bridge", "delete_sandbox_file_scoped") => ok(json!(
            napaxi_core::api::file_bridge::delete_sandbox_file_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                &get_string(payload, "sandbox_path"),
            )
        )),
        ("file_bridge", "list_workspace_filesystem") => ok_raw(
            napaxi_core::api::file_bridge::list_workspace_filesystem_json_handle(
                handle,
                get_opt_string(payload, "subdir").as_deref(),
                get_bool(payload, "recursive"),
            ),
        ),
        ("file_bridge", "list_workspace_filesystem_scoped") => ok_raw(
            napaxi_core::api::file_bridge::list_workspace_filesystem_json_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
                get_opt_string(payload, "subdir").as_deref(),
                get_bool(payload, "recursive"),
            ),
        ),
        ("file_bridge", "workspace_size") => ok(json!(
            napaxi_core::api::file_bridge::workspace_size_handle(handle)
        )),
        ("file_bridge", "workspace_size_scoped") => ok(json!(
            napaxi_core::api::file_bridge::workspace_size_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            )
        )),
        ("file_bridge", "workspace_dir") => ok(json!(
            napaxi_core::api::file_bridge::workspace_dir_handle(handle)
        )),
        ("file_bridge", "workspace_dir_scoped") => ok(json!(
            napaxi_core::api::file_bridge::workspace_dir_scoped_handle(
                handle,
                &get_string(payload, "account_id"),
                &get_string(payload, "agent_id"),
            )
        )),
        ("file_bridge", "rootfs_dir") => ok(json!(
            napaxi_core::api::file_bridge::rootfs_dir_handle(handle)
        )),
        ("file_bridge", "skills_dir") => ok(json!(
            napaxi_core::api::file_bridge::skills_dir_handle(handle)
        )),
        ("mcp", "add_server") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::mcp::add_server_handle(
                handle,
                &get_string(payload, "name"),
                &get_string(payload, "url"),
                &get_string(payload, "headers_json"),
                &get_string(payload, "user_id"),
            ),
        )),
        ("mcp", "remove_server") => ok_raw(napaxi_core::api::mcp::remove_server_handle(
            handle,
            &get_string(payload, "name"),
            &get_string(payload, "user_id"),
        )),
        ("mcp", "list_servers") => ok_raw(napaxi_core::api::mcp::list_servers_handle(
            handle,
            &get_string(payload, "user_id"),
        )),
        ("mcp", "activate_server") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::mcp::activate_server_handle(
                handle,
                &get_string(payload, "name"),
                &get_string(payload, "user_id"),
            ),
        )),
        ("mcp", "start_oauth") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::mcp::start_oauth_handle(
                handle,
                &get_string(payload, "name"),
                &get_string(payload, "user_id"),
                &get_string(payload, "redirect_uri"),
                &get_string(payload, "oauth_json"),
            ),
        )),
        ("mcp", "finish_oauth") => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::mcp::finish_oauth_handle(
                handle,
                &get_string(payload, "name"),
                &get_string(payload, "user_id"),
                &get_string(payload, "code"),
                &get_string(payload, "state"),
            ),
        )),
        ("mcp", "deactivate_server") => ok_raw(napaxi_core::api::mcp::deactivate_server_handle(
            handle,
            &get_string(payload, "name"),
            &get_string(payload, "user_id"),
        )),
        ("mcp", "list_tools") => ok_raw(napaxi_core::api::mcp::list_tools_handle(
            handle,
            &get_string(payload, "server_name"),
            &get_string(payload, "user_id"),
        )),
        _ => err(
            "unknown_method",
            format!("unknown Napaxi API method {namespace}.{method}"),
        ),
    }
}
