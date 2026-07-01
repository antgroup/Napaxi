//! Channel-to-agent runtime API.

pub use crate::channel_agent::{
    channel_agent_status_handle, list_channel_agent_routes_handle,
    register_channel_agent_route_handle, remove_channel_agent_route_handle,
    resolve_channel_agent_route_handle, stream_channel_agent_pump_handle,
};
