use serde_json::Value;

use super::*;

pub(super) fn dispatch(handle: i64, method: &str, payload: &Value) -> Option<String> {
    let response = match method {
        "agent_card" => ok_raw(napaxi_core::api::a2a::get_a2a_agent_card_handle(
            handle,
            &get_string(payload, "agent_id"),
        )),
        "create_peer_invite" => ok_raw(napaxi_core::api::a2a::create_peer_invite_handle(
            handle,
            &get_string(payload, "agent_id"),
            &get_string(payload, "options_json"),
        )),
        "accept_peer_invite" => ok_raw(napaxi_core::api::a2a::accept_peer_invite_handle(
            handle,
            &get_string(payload, "envelope_json"),
        )),
        "list_peers" => ok_raw(napaxi_core::api::a2a::list_peers_handle(
            handle,
            &get_string(payload, "agent_id"),
        )),
        "delete_peer" => ok(json!(napaxi_core::api::a2a::delete_peer_handle(
            handle,
            &get_string(payload, "peer_id"),
        ))),
        "open_peer_session" => ok_raw(napaxi_core::api::a2a::open_peer_session_handle(
            handle,
            &get_string(payload, "peer_json"),
            &get_string(payload, "transport"),
            &get_string(payload, "endpoint"),
        )),
        "list_peer_sessions" => ok_raw(napaxi_core::api::a2a::list_peer_sessions_handle(
            handle,
            &get_string(payload, "peer_id"),
        )),
        "create_task_message" => ok_raw(napaxi_core::api::a2a::create_task_message_handle(
            handle,
            &get_string(payload, "session_id"),
            &get_string(payload, "message"),
            &get_string(payload, "options_json"),
        )),
        "create_task_progress_message" => {
            ok_raw(napaxi_core::api::a2a::create_task_progress_message_handle(
                handle,
                &get_string(payload, "session_id"),
                &get_string(payload, "task_id"),
                &get_string(payload, "message"),
                &get_string(payload, "progress_json"),
            ))
        }
        "create_task_result_message" => {
            ok_raw(napaxi_core::api::a2a::create_task_result_message_handle(
                handle,
                &get_string(payload, "session_id"),
                &get_string(payload, "task_id"),
                &get_string(payload, "result_json"),
            ))
        }
        "record_peer_message" => ok_raw(napaxi_core::api::a2a::record_peer_message_handle(
            handle,
            &get_string(payload, "message_json"),
            &get_string(payload, "source"),
        )),
        "record_delivery_status" => ok_raw(napaxi_core::api::a2a::record_delivery_status_handle(
            handle,
            &get_string(payload, "message_json"),
            &get_string(payload, "status"),
            &get_string(payload, "error"),
        )),
        "list_peer_messages" => ok_raw(napaxi_core::api::a2a::list_peer_messages_handle(
            handle,
            &get_string(payload, "session_id"),
            get_i64(payload, "limit", 100),
            get_i64(payload, "offset", 0),
        )),
        "list_delivery_records" => ok_raw(napaxi_core::api::a2a::list_delivery_records_handle(
            handle,
            &get_string(payload, "session_id"),
            get_i64(payload, "limit", 100),
            get_i64(payload, "offset", 0),
        )),
        "accept_deep_link" => ok_raw(napaxi_core::api::a2a::accept_deep_link_handle(
            handle,
            &get_string(payload, "envelope_json"),
            &get_string(payload, "source"),
        )),
        "run_task" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::a2a::run_task_handle(
                handle,
                &get_string(payload, "task_id"),
                &get_string(payload, "mode"),
            ),
        )),
        "list_tasks" => ok_raw(napaxi_core::api::a2a::list_tasks_handle(
            handle,
            &get_string(payload, "filter_json"),
            get_i64(payload, "limit", 100),
            get_i64(payload, "offset", 0),
        )),
        "get_task" => ok_raw(napaxi_core::api::a2a::get_task_handle(
            handle,
            &get_string(payload, "task_id"),
        )),
        "build_result_link" => ok_raw(napaxi_core::api::a2a::build_result_link_handle(
            handle,
            &get_string(payload, "task_id"),
            &get_string(payload, "callback_url"),
        )),
        "record_result" => ok_raw(napaxi_core::api::a2a::record_result_envelope_handle(
            handle,
            &get_string(payload, "envelope_json"),
        )),
        _ => return None,
    };
    Some(response)
}
