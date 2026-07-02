// Hand-written FRB bridge entrypoints over `napaxi_core::api`. The crate-root
// `warn(clippy::unwrap_used)` (see `lib.rs`) keeps the non-test paths here
// `.unwrap()`-free so a regression surfaces as a clippy warning instead of
// aborting the host app. `expect()` is still allowed for genuine startup
// invariants (e.g. Tokio runtime creation below).

mod wire;

pub mod init {
    use crate::frb_generated::StreamSink;
    use std::sync::{Arc, OnceLock};
    use tokio::runtime::Runtime;

    use super::wire::{wire_bool_unit, wire_i64, wire_string_or_default};

    pub(crate) fn runtime() -> &'static Runtime {
        static RT: OnceLock<Runtime> = OnceLock::new();
        RT.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"))
    }

    pub fn register_tool_request_stream(sink: StreamSink<String>) {
        let dispatcher: napaxi_core::api::tools::ToolRequestDispatcher = Arc::new(
            move |request_id: u64, tool_name: &str, params_json: &str, context| {
                let mut request = serde_json::json!({
                    "request_id": request_id,
                    "tool_name": tool_name,
                    "params_json": params_json,
                });
                if let Some(context) = context {
                    request["context"] =
                        serde_json::to_value(context).unwrap_or(serde_json::Value::Null);
                }
                let _ = sink.add(request.to_string());
            },
        );
        napaxi_core::api::engine::set_tool_request_dispatcher(dispatcher);
        tracing::info!("Tool request stream registered");
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn update_custom_tools(handle: i64, tools_json: String) -> bool {
        runtime().block_on(napaxi_core::api::engine::update_custom_tools_handle(
            handle,
            &tools_json,
        ))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn resolve_tool_execution(request_id: u64, result: String, is_error: bool) -> bool {
        napaxi_core::api::tools::resolve_tool_execution(request_id, result, is_error)
    }

    pub fn tool_broker_list_tools(handle: i64, request_json: String) -> String {
        runtime().block_on(napaxi_core::api::tools::tool_broker_list_tools_json_handle(
            handle,
            &request_json,
        ))
    }

    pub fn tool_broker_call_tool(handle: i64, request_json: String) -> String {
        runtime().block_on(napaxi_core::api::tools::tool_broker_call_tool_json_handle(
            handle,
            &request_json,
        ))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn platform_tool_descriptors_json() -> String {
        napaxi_core::api::tools::platform_tool_descriptors_json()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn is_platform_tool(name: String) -> bool {
        napaxi_core::api::tools::is_platform_tool(&name)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn browser_tool_descriptors_json() -> String {
        napaxi_core::api::tools::browser_tool_descriptors_json()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn is_browser_tool(name: String) -> bool {
        napaxi_core::api::tools::is_browser_tool(&name)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn create_engine(config_json: String, platform_context_json: String) -> i64 {
        wire_i64(
            "create_engine",
            napaxi_core::api::engine::create_engine_handle(&config_json, &platform_context_json),
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn ensure_agent_ready(handle: i64, config_json: String) -> bool {
        if handle == 0 {
            return false;
        }
        if config_json.trim().is_empty() {
            return true;
        }
        wire_bool_unit(
            "ensure_agent_ready",
            napaxi_core::api::engine::update_config_handle_typed(handle, &config_json),
        )
    }

    pub fn send_message(
        handle: i64,
        config_json: String,
        message: String,
        attachments_json: String,
        _max_iterations: i32,
    ) -> String {
        runtime().block_on(napaxi_core::api::engine::send_message_json_handle(
            handle,
            &config_json,
            &message,
            &attachments_json,
            _max_iterations,
        ))
    }
    pub fn send_to_session(
        handle: i64,
        config_json: String,
        agent_id: String,
        session_key_json: String,
        message: String,
        attachments_json: String,
        _max_iterations: i32,
    ) -> String {
        runtime().block_on(napaxi_core::api::engine::send_to_session_json_handle(
            handle,
            &config_json,
            &agent_id,
            &session_key_json,
            &message,
            &attachments_json,
            _max_iterations,
        ))
    }

    pub fn send_message_stream(
        handle: i64,
        config_json: String,
        message: String,
        attachments_json: String,
        _max_iterations: i32,
        sink: StreamSink<String>,
    ) {
        runtime().block_on(napaxi_core::api::engine::stream_message_handle(
            handle,
            &config_json,
            &message,
            &attachments_json,
            _max_iterations,
            |event| {
                let _ = sink.add(event);
            },
        ));
    }

    pub fn send_to_session_stream(
        handle: i64,
        config_json: String,
        agent_id: String,
        session_key_json: String,
        message: String,
        attachments_json: String,
        _max_iterations: i32,
        sink: StreamSink<String>,
    ) {
        runtime().block_on(napaxi_core::api::engine::stream_to_session_handle(
            handle,
            &config_json,
            &agent_id,
            &session_key_json,
            &message,
            &attachments_json,
            _max_iterations,
            |event| {
                let _ = sink.add(event);
            },
        ));
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn update_config(handle: i64, config_json: String) -> bool {
        wire_bool_unit(
            "update_config",
            napaxi_core::api::engine::update_config_handle_typed(handle, &config_json),
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_config(handle: i64) -> String {
        wire_string_or_default(
            "get_config",
            napaxi_core::api::engine::get_config_handle_typed(handle),
            r#"{"error":"invalid engine handle"}"#,
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn dispose_engine(handle: i64) {
        napaxi_core::api::engine::dispose_engine_handle(handle);
    }
}

pub mod capability;

pub mod automation {
    #[flutter_rust_bridge::frb(sync)]
    pub fn create_automation_job(handle: i64, job_json: String) -> String {
        napaxi_core::api::automation::create_automation_job_handle(handle, &job_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn update_automation_job(handle: i64, job_id: String, patch_json: String) -> String {
        napaxi_core::api::automation::update_automation_job_handle(handle, &job_id, &patch_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn delete_automation_job(handle: i64, job_id: String) -> bool {
        napaxi_core::api::automation::delete_automation_job_handle(handle, &job_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_automation_jobs(handle: i64, filter_json: String) -> String {
        napaxi_core::api::automation::list_automation_jobs_handle(handle, &filter_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_automation_job(handle: i64, job_id: String) -> String {
        napaxi_core::api::automation::get_automation_job_handle(handle, &job_id)
    }

    pub fn run_automation_job(handle: i64, job_id: String, mode: String) -> String {
        super::init::runtime().block_on(napaxi_core::api::automation::run_automation_job_handle(
            handle, &job_id, &mode,
        ))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_automation_runs(
        handle: i64,
        job_id: Option<String>,
        limit: i64,
        offset: i64,
    ) -> String {
        napaxi_core::api::automation::list_automation_runs_handle(
            handle,
            job_id.as_deref(),
            limit,
            offset,
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_next_automation_wake(handle: i64) -> String {
        napaxi_core::api::automation::get_next_automation_wake_handle(handle)
    }

    pub fn record_automation_wake(handle: i64, job_id: String, source: String) -> String {
        super::init::runtime().block_on(
            napaxi_core::api::automation::record_automation_wake_handle(handle, &job_id, &source),
        )
    }
}

pub mod session_runs {
    #[flutter_rust_bridge::frb(sync)]
    pub fn list_session_runs(handle: i64, filter_json: String, limit: i64, offset: i64) -> String {
        napaxi_core::api::session_runs::list_session_runs_handle(
            handle,
            &filter_json,
            limit,
            offset,
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_session_run(handle: i64, run_id: String) -> String {
        napaxi_core::api::session_runs::get_session_run_handle(handle, &run_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_active_session_runs(handle: i64) -> String {
        napaxi_core::api::session_runs::get_active_session_runs_handle(handle)
    }
}

pub mod agent_app {
    #[flutter_rust_bridge::frb(sync)]
    pub fn register_agent_app_package(handle: i64, package_json: String) -> String {
        napaxi_core::api::agent_app::register_agent_app_package(handle, &package_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_agent_app_packages(handle: i64) -> String {
        napaxi_core::api::agent_app::list_agent_app_packages(handle)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_agent_app_package(handle: i64, agent_id: String) -> String {
        napaxi_core::api::agent_app::get_agent_app_package(handle, &agent_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn delete_agent_app_package(handle: i64, agent_id: String) -> bool {
        napaxi_core::api::agent_app::delete_agent_app_package(handle, &agent_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn submit_agent_app_action_result(handle: i64, result_json: String) -> String {
        napaxi_core::api::agent_app::submit_agent_app_action_result(handle, &result_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_agent_app_action_proposals(handle: i64, agent_id: String) -> String {
        napaxi_core::api::agent_app::list_agent_app_action_proposals(handle, &agent_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_agent_app_action_proposal(handle: i64, request_id: String) -> String {
        napaxi_core::api::agent_app::get_agent_app_action_proposal(handle, &request_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn accept_agent_app_trigger(handle: i64, trigger_json: String) -> String {
        napaxi_core::api::agent_app::accept_agent_app_trigger(handle, &trigger_json)
    }
}

pub mod a2a {
    #[flutter_rust_bridge::frb(sync)]
    pub fn get_a2a_agent_card(handle: i64, agent_id: String) -> String {
        napaxi_core::api::a2a::get_a2a_agent_card_handle(handle, &agent_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn create_a2a_peer_invite(handle: i64, agent_id: String, options_json: String) -> String {
        napaxi_core::api::a2a::create_peer_invite_handle(handle, &agent_id, &options_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn accept_a2a_peer_invite(handle: i64, envelope_json: String) -> String {
        napaxi_core::api::a2a::accept_peer_invite_handle(handle, &envelope_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_a2a_peers(handle: i64, agent_id: String) -> String {
        napaxi_core::api::a2a::list_peers_handle(handle, &agent_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn delete_a2a_peer(handle: i64, peer_id: String) -> bool {
        napaxi_core::api::a2a::delete_peer_handle(handle, &peer_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn open_a2a_peer_session(
        handle: i64,
        peer_json: String,
        transport: String,
        endpoint: String,
    ) -> String {
        napaxi_core::api::a2a::open_peer_session_handle(handle, &peer_json, &transport, &endpoint)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_a2a_peer_sessions(handle: i64, peer_id: String) -> String {
        napaxi_core::api::a2a::list_peer_sessions_handle(handle, &peer_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn create_a2a_task_message(
        handle: i64,
        session_id: String,
        message: String,
        options_json: String,
    ) -> String {
        napaxi_core::api::a2a::create_task_message_handle(
            handle,
            &session_id,
            &message,
            &options_json,
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn create_a2a_task_progress_message(
        handle: i64,
        session_id: String,
        task_id: String,
        message: String,
        progress_json: String,
    ) -> String {
        napaxi_core::api::a2a::create_task_progress_message_handle(
            handle,
            &session_id,
            &task_id,
            &message,
            &progress_json,
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn create_a2a_task_result_message(
        handle: i64,
        session_id: String,
        task_id: String,
        result_json: String,
    ) -> String {
        napaxi_core::api::a2a::create_task_result_message_handle(
            handle,
            &session_id,
            &task_id,
            &result_json,
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn record_a2a_peer_message(handle: i64, message_json: String, source: String) -> String {
        napaxi_core::api::a2a::record_peer_message_handle(handle, &message_json, &source)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn record_a2a_delivery_status(
        handle: i64,
        message_json: String,
        status: String,
        error: String,
    ) -> String {
        napaxi_core::api::a2a::record_delivery_status_handle(handle, &message_json, &status, &error)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_a2a_peer_messages(
        handle: i64,
        session_id: String,
        limit: i64,
        offset: i64,
    ) -> String {
        napaxi_core::api::a2a::list_peer_messages_handle(handle, &session_id, limit, offset)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_a2a_delivery_records(
        handle: i64,
        session_id: String,
        limit: i64,
        offset: i64,
    ) -> String {
        napaxi_core::api::a2a::list_delivery_records_handle(handle, &session_id, limit, offset)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn accept_a2a_deep_link(handle: i64, envelope_json: String, source: String) -> String {
        napaxi_core::api::a2a::accept_deep_link_handle(handle, &envelope_json, &source)
    }

    pub fn run_a2a_task(handle: i64, task_id: String, mode: String) -> String {
        super::init::runtime().block_on(napaxi_core::api::a2a::run_task_handle(
            handle, &task_id, &mode,
        ))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_a2a_tasks(handle: i64, filter_json: String, limit: i64, offset: i64) -> String {
        napaxi_core::api::a2a::list_tasks_handle(handle, &filter_json, limit, offset)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_a2a_task(handle: i64, task_id: String) -> String {
        napaxi_core::api::a2a::get_task_handle(handle, &task_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn build_a2a_result_link(handle: i64, task_id: String, callback_url: String) -> String {
        napaxi_core::api::a2a::build_result_link_handle(handle, &task_id, &callback_url)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn record_a2a_result_envelope(handle: i64, envelope_json: String) -> String {
        napaxi_core::api::a2a::record_result_envelope_handle(handle, &envelope_json)
    }
}

pub mod agent {
    use super::wire::wire_bool_unit;

    pub fn get_or_create_agent(handle: i64, agent_id: String, _config_json: String) -> String {
        napaxi_core::api::engine::get_or_create_agent_handle(handle, &agent_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_agents(handle: i64) -> String {
        napaxi_core::api::engine::list_agents_handle(handle)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn delete_agent(handle: i64, agent_id: String) -> bool {
        wire_bool_unit(
            "delete_agent",
            napaxi_core::api::engine::delete_agent_handle_typed(handle, &agent_id),
        )
    }

    pub fn agent_send(
        handle: i64,
        agent_id: String,
        config_json: String,
        session_key_json: String,
        message: String,
        max_iterations: i32,
    ) -> String {
        super::init::runtime().block_on(napaxi_core::api::agent::send_agent_json_handle(
            handle,
            &agent_id,
            &config_json,
            &session_key_json,
            &message,
            max_iterations,
        ))
    }
}

pub mod session {
    use super::wire::wire_bool;

    pub fn create_session(
        handle: i64,
        _config_json: String,
        agent_id: String,
        channel_type: String,
        account_id: String,
        existing_thread_id: Option<String>,
    ) -> String {
        napaxi_core::api::session::create_session_handle(
            handle,
            &agent_id,
            &channel_type,
            &account_id,
            existing_thread_id.as_deref(),
        )
    }
    pub fn list_sessions(
        handle: i64,
        _config_json: String,
        agent_id: String,
        account_id: String,
    ) -> String {
        napaxi_core::api::session::list_sessions_handle(handle, &agent_id, &account_id)
    }
    pub fn delete_session(
        handle: i64,
        _config_json: String,
        _agent_id: String,
        session_key_json: String,
    ) -> bool {
        napaxi_core::api::session::delete_session_handle(handle, &session_key_json)
    }
    pub fn clear_session(
        handle: i64,
        _config_json: String,
        _agent_id: String,
        session_key_json: String,
    ) -> bool {
        napaxi_core::api::session::clear_session_handle(handle, &session_key_json)
    }
    pub fn delete_session_if_empty(handle: i64, session_key_json: String) -> bool {
        napaxi_core::api::session::delete_session_if_empty_handle(handle, &session_key_json)
    }
    pub fn prune_empty_sessions(handle: i64, agent_id: String, account_id: String) -> usize {
        napaxi_core::api::session::prune_empty_sessions_handle(handle, &agent_id, &account_id)
    }
    pub fn get_history(
        handle: i64,
        _config_json: String,
        _agent_id: String,
        thread_id: String,
    ) -> String {
        napaxi_core::api::session::get_history_handle(handle, &thread_id)
    }
    pub fn get_history_page(
        handle: i64,
        _config_json: String,
        _agent_id: String,
        thread_id: String,
        before: Option<String>,
        limit: i64,
    ) -> String {
        napaxi_core::api::session::get_history_page_handle(
            handle,
            &thread_id,
            before.as_deref(),
            limit,
        )
    }
    pub fn compact_context(
        handle: i64,
        config_json: String,
        _agent_id: String,
        session_key_json: String,
        focus: Option<String>,
    ) -> String {
        super::init::runtime().block_on(napaxi_core::api::session::compact_session_handle_async(
            handle,
            &config_json,
            &session_key_json,
            focus.as_deref(),
        ))
    }
    pub fn context_status(
        handle: i64,
        config_json: String,
        _agent_id: String,
        thread_id: String,
    ) -> String {
        napaxi_core::api::session::context_status_handle(handle, &config_json, &thread_id)
    }
    pub fn inject_message(
        handle: i64,
        config_json: String,
        agent_id: String,
        session_key_json: String,
        message: String,
        attachments_json: String,
    ) -> bool {
        napaxi_core::api::engine::inject_message_handle(
            handle,
            &config_json,
            &agent_id,
            &session_key_json,
            &message,
            &attachments_json,
        )
    }
    pub fn retract_injected_message(
        handle: i64,
        session_key_json: String,
        message: String,
    ) -> bool {
        napaxi_core::api::engine::retract_injected_message_handle(
            handle,
            &session_key_json,
            &message,
        )
    }
    pub fn answer_human_request(_handle: i64, request_id: String, response: String) -> bool {
        napaxi_core::api::tools::answer_human_request(&request_id, &response)
    }
    pub fn cancel_session(
        handle: i64,
        _config_json: String,
        _agent_id: String,
        session_key_json: String,
    ) -> bool {
        wire_bool(
            "cancel_session",
            napaxi_core::api::engine::cancel_session_handle_typed(handle, &session_key_json),
        )
    }
}

pub mod skill;
pub mod evolution {
    #[flutter_rust_bridge::frb(sync)]
    pub fn list_pending_evolution(handle: i64) -> String {
        napaxi_core::api::evolution::list_pending_evolution_handle(handle)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_evolution_runs(handle: i64, run_ids_json: String) -> String {
        napaxi_core::api::evolution::list_evolution_runs_handle(handle, &run_ids_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_evolution_diagnostics(handle: i64) -> String {
        napaxi_core::api::evolution::list_evolution_diagnostics_handle(handle)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn reject_pending_evolution(handle: i64, pending_id: String) -> String {
        napaxi_core::api::evolution::reject_pending_evolution_handle(handle, &pending_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn apply_pending_evolution(handle: i64, pending_id: String) -> String {
        super::init::runtime().block_on(
            napaxi_core::api::evolution::apply_pending_evolution_handle(handle, &pending_id),
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn run_skill_consolidation_review(
        handle: i64,
        agent_id: String,
        config_json: String,
        dry_run: bool,
    ) -> String {
        super::init::runtime().block_on(
            napaxi_core::api::evolution::run_skill_consolidation_review_handle(
                handle,
                &agent_id,
                &config_json,
                dry_run,
            ),
        )
    }
}

pub mod agent_defs {
    pub fn create_agent_definition(handle: i64, def_json: String) -> String {
        napaxi_core::api::agent::create_definition_handle(handle, &def_json)
    }
    pub fn update_agent_definition(handle: i64, def_json: String) -> bool {
        napaxi_core::api::agent::update_definition_handle(handle, &def_json)
    }
    pub fn delete_agent_definition(handle: i64, def_id: String) -> bool {
        napaxi_core::api::agent::delete_definition_handle(handle, &def_id)
    }
    pub fn list_agent_definitions(handle: i64) -> String {
        napaxi_core::api::agent::list_definitions_handle(handle)
    }
    pub fn get_agent_definition(handle: i64, def_id: String) -> String {
        napaxi_core::api::agent::get_definition_json_handle(handle, &def_id)
    }
    pub fn list_available_tools(handle: i64) -> String {
        super::init::runtime().block_on(napaxi_core::api::engine::available_tool_infos_json_handle(
            handle,
            napaxi_core::api::engine::DEFAULT_ACCOUNT_ID,
            napaxi_core::api::engine::DEFAULT_AGENT_ID,
        ))
    }
    pub fn create_agent_from_definition(handle: i64, def_id: String, _config_json: String) -> i64 {
        if napaxi_core::api::agent::create_agent_from_definition_handle(handle, &def_id) {
            1
        } else {
            0
        }
    }
    pub fn import_agent_md(handle: i64, content: String) -> String {
        napaxi_core::api::agent::import_agent_md_handle(handle, &content)
    }
}

pub mod group {
    pub fn create_group(handle: i64, name: String, members_json: String) -> String {
        napaxi_core::api::group::create_group_handle(handle, &name, &members_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn delete_group(handle: i64, group_id: String) -> bool {
        napaxi_core::api::group::delete_group_handle(handle, &group_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn list_groups(handle: i64) -> String {
        napaxi_core::api::group::list_groups_handle(handle)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_group(handle: i64, group_id: String) -> String {
        napaxi_core::api::group::get_group_handle(handle, &group_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn rename_group(handle: i64, group_id: String, new_name: String) -> bool {
        napaxi_core::api::group::rename_group_handle(handle, &group_id, &new_name)
    }
    pub fn update_group_members(handle: i64, group_id: String, members_json: String) -> bool {
        napaxi_core::api::group::update_group_members_handle(handle, &group_id, &members_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn set_group_custom_prompt(handle: i64, group_id: String, prompt: Option<String>) -> bool {
        napaxi_core::api::group::set_group_custom_prompt_handle(handle, &group_id, prompt)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_group_messages(handle: i64, group_id: String) -> String {
        napaxi_core::api::group::get_group_messages_handle(handle, &group_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn clear_group_history(handle: i64, group_id: String) -> bool {
        napaxi_core::api::group::clear_group_history_handle(handle, &group_id)
    }
    pub fn send_to_group(
        handle: i64,
        group_id: String,
        config_json: String,
        message: String,
        max_iterations: i32,
    ) -> String {
        super::init::runtime().block_on(napaxi_core::api::group::send_to_group_handle(
            handle,
            &group_id,
            &config_json,
            &message,
            max_iterations,
        ))
    }
    pub fn send_to_group_agent(
        handle: i64,
        group_id: String,
        agent_id: String,
        config_json: String,
        session_key_json: String,
        message: String,
        max_iterations: i32,
    ) -> String {
        super::init::runtime().block_on(napaxi_core::api::group::send_to_group_agent_handle(
            handle,
            &group_id,
            &agent_id,
            &config_json,
            &session_key_json,
            &message,
            max_iterations,
        ))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn export_group_state(handle: i64) -> String {
        napaxi_core::api::group::export_group_state_handle(handle)
    }
    pub fn import_group_state(handle: i64, state_json: String) -> bool {
        napaxi_core::api::group::import_group_state_handle(handle, &state_json)
    }
}

pub mod channel {
    #[flutter_rust_bridge::frb(sync)]
    pub fn list_channels(handle: i64) -> String {
        napaxi_core::api::channel::list_channels_handle(handle)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn register_channel(handle: i64, config_json: String) -> bool {
        napaxi_core::api::channel::register_channel_handle(handle, &config_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn unregister_channel(handle: i64, channel_name: String) -> bool {
        napaxi_core::api::channel::unregister_channel_handle(handle, &channel_name)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn submit_channel_inbound(handle: i64, envelope_json: String) -> String {
        napaxi_core::api::channel::submit_channel_inbound_handle(handle, &envelope_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn take_channel_inbound(handle: i64, channel_name: String, limit: usize) -> String {
        napaxi_core::api::channel::take_channel_inbound_handle(handle, &channel_name, limit)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn ack_channel_inbound(handle: i64, inbound_id: String) -> bool {
        napaxi_core::api::channel::ack_channel_inbound_handle(handle, &inbound_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn fail_channel_inbound(handle: i64, inbound_id: String, error: String) -> bool {
        napaxi_core::api::channel::fail_channel_inbound_handle(handle, &inbound_id, &error)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn release_channel_inbound(handle: i64, inbound_id: String) -> bool {
        napaxi_core::api::channel::release_channel_inbound_handle(handle, &inbound_id)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn enqueue_channel_outbound(handle: i64, outbound_json: String) -> String {
        napaxi_core::api::channel::enqueue_channel_outbound_handle(handle, &outbound_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn reply_channel_inbound(handle: i64, inbound_id: String, reply_json: String) -> String {
        napaxi_core::api::channel::reply_channel_inbound_handle(handle, &inbound_id, &reply_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn lease_channel_outbound(
        handle: i64,
        channel_name: String,
        account_id: Option<String>,
        limit: usize,
    ) -> String {
        napaxi_core::api::channel::lease_channel_outbound_handle(
            handle,
            &channel_name,
            account_id.as_deref(),
            limit,
        )
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn ack_channel_outbound(handle: i64, outbound_id: String, receipt_json: String) -> bool {
        napaxi_core::api::channel::ack_channel_outbound_handle(handle, &outbound_id, &receipt_json)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn fail_channel_outbound(handle: i64, outbound_id: String, error: String) -> bool {
        napaxi_core::api::channel::fail_channel_outbound_handle(handle, &outbound_id, &error)
    }
}

pub mod channel_agent;
pub mod channel_qqbot;
pub mod file_bridge;
pub mod workspace;
pub mod mcp {
    pub async fn mcp_add_server(
        handle: i64,
        name: String,
        url: String,
        headers_json: String,
        user_id: String,
    ) -> String {
        napaxi_core::api::mcp::add_server_handle(handle, &name, &url, &headers_json, &user_id).await
    }

    pub async fn mcp_remove_server(handle: i64, name: String, user_id: String) -> String {
        napaxi_core::api::mcp::remove_server_handle(handle, &name, &user_id)
    }

    pub async fn mcp_list_servers(handle: i64, user_id: String) -> String {
        napaxi_core::api::mcp::list_servers_handle(handle, &user_id)
    }

    pub async fn mcp_activate_server(handle: i64, name: String, user_id: String) -> String {
        napaxi_core::api::mcp::activate_server_handle(handle, &name, &user_id).await
    }

    pub async fn mcp_start_oauth(
        handle: i64,
        name: String,
        user_id: String,
        redirect_uri: String,
        oauth_json: String,
    ) -> String {
        napaxi_core::api::mcp::start_oauth_handle(
            handle,
            &name,
            &user_id,
            &redirect_uri,
            &oauth_json,
        )
        .await
    }

    pub async fn mcp_finish_oauth(
        handle: i64,
        name: String,
        user_id: String,
        code: String,
        state: String,
    ) -> String {
        napaxi_core::api::mcp::finish_oauth_handle(handle, &name, &user_id, &code, &state).await
    }

    pub async fn mcp_deactivate_server(handle: i64, name: String, user_id: String) -> String {
        napaxi_core::api::mcp::deactivate_server_handle(handle, &name, &user_id)
    }

    pub async fn mcp_list_tools(handle: i64, server_name: String, user_id: String) -> String {
        napaxi_core::api::mcp::list_tools_handle(handle, &server_name, &user_id)
    }
}
