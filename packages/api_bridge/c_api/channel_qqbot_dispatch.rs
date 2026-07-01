use serde_json::Value;

use super::*;

pub(super) fn dispatch_channel_qqbot(method: &str, payload: &Value) -> Option<String> {
    Some(match method {
        "build_outbound_payload" => ok_raw(napaxi_core::api::channel_qqbot::build_outbound_payload(
            &get_string(payload, "message_json"),
            &get_string(payload, "markdown_endpoint_kinds_json"),
        )),
        "build_outbound_payload_plain" => ok_raw(
            napaxi_core::api::channel_qqbot::build_outbound_payload_plain(&get_string(
                payload,
                "message_json",
            )),
        ),
        "should_fallback_from_markdown" => ok(json!(
            napaxi_core::api::channel_qqbot::should_fallback_from_markdown(get_i64(
                payload, "status", 0
            ))
        )),
        "outbound_endpoint_path" => ok(json!(
            napaxi_core::api::channel_qqbot::outbound_endpoint_path(
                &get_string(payload, "peer_kind"),
                &get_string(payload, "peer_id"),
            )
        )),
        "api_base" => ok(json!(napaxi_core::api::channel_qqbot::api_base(get_bool(
            payload, "sandbox"
        )))),
        "is_message_event" => ok(json!(napaxi_core::api::channel_qqbot::is_message_event(
            &get_string(payload, "event_type",)
        ))),
        "normalize_inbound" => ok_raw(napaxi_core::api::channel_qqbot::normalize_inbound(
            &get_string(payload, "event_type"),
            &get_string(payload, "data_json"),
        )),
        "gateway_step" => ok_raw(napaxi_core::api::channel_qqbot::gateway_step(
            &get_string(payload, "state_json"),
            &get_string(payload, "event_json"),
        )),
        _ => return None,
    })
}
