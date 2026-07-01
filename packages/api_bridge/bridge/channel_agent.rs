use crate::frb_generated::StreamSink;

#[flutter_rust_bridge::frb(sync)]
pub fn register_channel_agent_route(handle: i64, route_json: String) -> String {
    napaxi_core::api::channel_agent::register_channel_agent_route_handle(handle, &route_json)
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_channel_agent_routes(handle: i64, channel_name: Option<String>) -> String {
    napaxi_core::api::channel_agent::list_channel_agent_routes_handle(
        handle,
        channel_name.as_deref(),
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn remove_channel_agent_route(handle: i64, route_id: String) -> bool {
    napaxi_core::api::channel_agent::remove_channel_agent_route_handle(handle, &route_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn resolve_channel_agent_route(
    handle: i64,
    bridge_config_json: String,
    inbound_json: String,
) -> String {
    napaxi_core::api::channel_agent::resolve_channel_agent_route_handle(
        handle,
        &bridge_config_json,
        &inbound_json,
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn channel_agent_status(handle: i64, channel_name: Option<String>) -> String {
    napaxi_core::api::channel_agent::channel_agent_status_handle(handle, channel_name.as_deref())
}

pub fn stream_channel_agent_pump(
    handle: i64,
    config_json: String,
    bridge_config_json: String,
    sink: StreamSink<String>,
) {
    super::init::runtime().block_on(
        napaxi_core::api::channel_agent::stream_channel_agent_pump_handle(
            handle,
            &config_json,
            &bridge_config_json,
            |event| {
                let _ = sink.add(event);
            },
        ),
    );
}
