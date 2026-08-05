use serde_json::Value;

use super::*;

pub(super) fn dispatch_agent_engine(handle: i64, method: &str, payload: &Value) -> Option<String> {
    Some(match method {
        "run_event" => ok_raw(napaxi_core::api::agent_engine::run_event_json(&get_string(
            payload,
            "request_json",
        ))),
        "configure_codex" => ok_raw(
            napaxi_core::api::agent_engine::configure_codex_agent_engine_json(
                handle,
                &get_string(payload, "request_json"),
            ),
        ),
        "query_codex_history" => ok_raw(
            napaxi_core::api::agent_engine::query_codex_agent_engine_history_json(
                handle,
                &get_string(payload, "request_json"),
            ),
        ),
        _ => return None,
    })
}
