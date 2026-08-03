use serde_json::Value;

use super::*;

const LEGACY_PLATFORM_DESCRIPTORS: &str = "platform_descriptors";
const LEGACY_MOBILE_PLATFORM_TOOL_DESCRIPTORS: &str =
    concat!("mobile_", "platform_tool_descriptors");
const LEGACY_IS_MOBILE_PLATFORM_TOOL: &str = concat!("is_", "mobile_", "platform_tool");

pub(super) fn dispatch_tools(handle: i64, method: &str, payload: &Value) -> Option<String> {
    Some(match method {
        method
            if method == "platform_tool_descriptors"
                || method == LEGACY_PLATFORM_DESCRIPTORS
                || method == LEGACY_MOBILE_PLATFORM_TOOL_DESCRIPTORS =>
        {
            ok_raw(napaxi_core::api::tools::platform_tool_descriptors_json())
        }
        method if method == "is_platform_tool" || method == LEGACY_IS_MOBILE_PLATFORM_TOOL => {
            ok(json!(napaxi_core::api::tools::is_platform_tool(
                &get_string(payload, "name")
            )))
        }
        "browser_tool_descriptors" => {
            ok_raw(napaxi_core::api::tools::browser_tool_descriptors_json())
        }
        "is_browser_tool" => ok(json!(napaxi_core::api::tools::is_browser_tool(
            &get_string(payload, "name")
        ))),
        "answer_human_request" => ok(json!(napaxi_core::api::tools::answer_human_request(
            &get_string(payload, "request_id"),
            &get_string(payload, "response"),
        ))),
        "tool_broker_list_tools" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::tools::tool_broker_list_tools_json_handle(
                handle,
                &get_string(payload, "request_json"),
            ),
        )),
        "tool_broker_call_tool" => ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::tools::tool_broker_call_tool_json_handle(
                handle,
                &get_string(payload, "request_json"),
            ),
        )),
        _ => return None,
    })
}
