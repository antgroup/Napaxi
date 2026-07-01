//! QQ-bot protocol API: stateless, platform-independent protocol helpers that
//! adapters call instead of re-implementing the QQ OpenAPI wire logic.
//!
//! These are pure functions (no engine handle, no I/O); the adapter still owns
//! the WebSocket gateway, heartbeat timer, and HTTP transport.

pub use crate::channel::qqbot::gateway::step as gateway_step;
pub use crate::channel::qqbot::protocol::{
    api_base, build_outbound_payload, build_outbound_payload_plain, is_message_event,
    normalize_inbound, outbound_endpoint_path, should_fallback_from_markdown,
};
