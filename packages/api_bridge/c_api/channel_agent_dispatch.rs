use serde_json::Value;

use super::*;

pub(super) fn dispatch_channel_agent(handle: i64, method: &str, payload: &Value) -> Option<String> {
    Some(match method {
        "register_route" => ok_raw(
            napaxi_core::api::channel_agent::register_channel_agent_route_handle(
                handle,
                &get_string(payload, "route_json"),
            ),
        ),
        "list_routes" => ok_raw(
            napaxi_core::api::channel_agent::list_channel_agent_routes_handle(
                handle,
                get_opt_string(payload, "channel_name").as_deref(),
            ),
        ),
        "remove_route" => ok(json!(
            napaxi_core::api::channel_agent::remove_channel_agent_route_handle(
                handle,
                &get_string(payload, "route_id"),
            )
        )),
        "resolve_route" => ok_raw(
            napaxi_core::api::channel_agent::resolve_channel_agent_route_handle(
                handle,
                &get_string(payload, "bridge_config_json"),
                &get_string(payload, "inbound_json"),
            ),
        ),
        "status" => ok_raw(napaxi_core::api::channel_agent::channel_agent_status_handle(
            handle,
            get_opt_string(payload, "channel_name").as_deref(),
        )),
        _ => return None,
    })
}
