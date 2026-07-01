use serde_json::Value;

use super::*;

pub(super) fn dispatch_channel(handle: i64, method: &str, payload: &Value) -> Option<String> {
    Some(match method {
        "list" => ok_raw(napaxi_core::api::channel::list_channels_handle(handle)),
        "register" => ok(json!(napaxi_core::api::channel::register_channel_handle(
            handle,
            &get_string(payload, "config_json"),
        ))),
        "unregister" => ok(json!(napaxi_core::api::channel::unregister_channel_handle(
            handle,
            &get_string(payload, "channel_name"),
        ))),
        "submit_inbound" => ok_raw(napaxi_core::api::channel::submit_channel_inbound_handle(
            handle,
            &get_string(payload, "envelope_json"),
        )),
        "take_inbound" => ok_raw(napaxi_core::api::channel::take_channel_inbound_handle(
            handle,
            &get_string(payload, "channel_name"),
            get_usize(payload, "limit"),
        )),
        "ack_inbound" => ok(json!(napaxi_core::api::channel::ack_channel_inbound_handle(
            handle,
            &get_string(payload, "inbound_id"),
        ))),
        "fail_inbound" => ok(json!(
            napaxi_core::api::channel::fail_channel_inbound_handle(
                handle,
                &get_string(payload, "inbound_id"),
                &get_string(payload, "error"),
            )
        )),
        "release_inbound" => ok(json!(
            napaxi_core::api::channel::release_channel_inbound_handle(
                handle,
                &get_string(payload, "inbound_id"),
            )
        )),
        "enqueue_outbound" => ok_raw(napaxi_core::api::channel::enqueue_channel_outbound_handle(
            handle,
            &get_string(payload, "outbound_json"),
        )),
        "reply_inbound" => ok_raw(napaxi_core::api::channel::reply_channel_inbound_handle(
            handle,
            &get_string(payload, "inbound_id"),
            &get_string(payload, "reply_json"),
        )),
        "lease_outbound" => {
            let account_id = get_string(payload, "account_id");
            ok_raw(napaxi_core::api::channel::lease_channel_outbound_handle(
                handle,
                &get_string(payload, "channel_name"),
                if account_id.is_empty() {
                    None
                } else {
                    Some(account_id.as_str())
                },
                get_usize(payload, "limit"),
            ))
        }
        "ack_outbound" => ok(json!(
            napaxi_core::api::channel::ack_channel_outbound_handle(
                handle,
                &get_string(payload, "outbound_id"),
                &get_string(payload, "receipt_json"),
            )
        )),
        "fail_outbound" => ok(json!(
            napaxi_core::api::channel::fail_channel_outbound_handle(
                handle,
                &get_string(payload, "outbound_id"),
                &get_string(payload, "error"),
            )
        )),
        _ => return None,
    })
}
