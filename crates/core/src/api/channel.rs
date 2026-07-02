//! Channel registration API.

pub use crate::channel::{
    ack_channel_inbound_handle, ack_channel_outbound_handle, enqueue_channel_outbound_handle,
    fail_channel_inbound_handle, fail_channel_outbound_handle, lease_channel_outbound_handle,
    list_channels_handle, register_channel_handle, release_channel_inbound_handle,
    reply_channel_inbound_handle, submit_channel_inbound_handle, take_channel_inbound_handle,
    unregister_channel_handle,
};
