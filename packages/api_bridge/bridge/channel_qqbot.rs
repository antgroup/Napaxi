//! Bridge surface for the core QQ-bot protocol helpers.
//!
//! All functions are pure (no engine handle, no I/O): the Dart adapter owns the
//! WebSocket gateway, heartbeat timer, and HTTP transport, and calls these to
//! build payloads, classify responses, route endpoints, and normalize inbound
//! events — the platform-independent protocol logic that core now owns.

/// Builds the QQ OpenAPI outbound send payload for a channel outbound message.
/// Returns `{ "body": {...}, "content_format": "...", "used_markdown": bool }`.
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_build_outbound_payload(
    message_json: String,
    markdown_endpoint_kinds_json: String,
) -> String {
    napaxi_core::api::channel_qqbot::build_outbound_payload(
        &message_json,
        &markdown_endpoint_kinds_json,
    )
}

/// Builds the outbound payload forcing plain text (the Markdown fallback path).
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_build_outbound_payload_plain(message_json: String) -> String {
    napaxi_core::api::channel_qqbot::build_outbound_payload_plain(&message_json)
}

/// Whether a failed Markdown send should be retried as plain text (non-429 4xx).
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_should_fallback_from_markdown(status: i64) -> bool {
    napaxi_core::api::channel_qqbot::should_fallback_from_markdown(status)
}

/// Returns the QQ OpenAPI relative path for delivering to the given peer kind.
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_outbound_endpoint_path(peer_kind: String, peer_id: String) -> String {
    napaxi_core::api::channel_qqbot::outbound_endpoint_path(&peer_kind, &peer_id)
}

/// Returns the API base host for the given sandbox flag.
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_api_base(sandbox: bool) -> String {
    napaxi_core::api::channel_qqbot::api_base(sandbox).to_string()
}

/// Whether a gateway dispatch event type is a QQ inbound message event.
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_is_message_event(event_type: String) -> bool {
    napaxi_core::api::channel_qqbot::is_message_event(&event_type)
}

/// Normalizes a QQ gateway message-create event into the shared inbound shape.
/// Returns `{ "peer", "sender", "text"?, "platform_message_id"?, "thread_id"? }`
/// or `{ "peer": null, "error": "..." }` when the event has no usable peer id.
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_normalize_inbound(event_type: String, data_json: String) -> String {
    napaxi_core::api::channel_qqbot::normalize_inbound(&event_type, &data_json)
}

/// Drives the sans-IO QQ gateway state machine one step. `state_json` is the
/// opaque protocol state held by the adapter between frames (empty/`{}` for a
/// fresh connection, with the identify config seeded). `event_json` is a
/// `{"type":"frame","text":...}` or `{"type":"heartbeat_due"}` event. Returns
/// `{ "state": <new state>, "actions": [...] }` — the adapter executes the
/// actions (send_frame, start_heartbeat, submit_inbound, mark_ready, reconnect)
/// against its socket/timer.
#[flutter_rust_bridge::frb(sync)]
pub fn qqbot_gateway_step(state_json: String, event_json: String) -> String {
    napaxi_core::api::channel_qqbot::gateway_step(&state_json, &event_json)
}
