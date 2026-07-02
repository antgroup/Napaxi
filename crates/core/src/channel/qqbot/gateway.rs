//! Sans-IO QQ gateway state machine, modeled as a pure reducer.
//!
//! The adapter owns the WebSocket and the heartbeat timer. It drives this
//! reducer with events (an incoming gateway frame, or a heartbeat-due tick) and
//! executes the returned actions (send a frame, (re)start the heartbeat timer,
//! submit an inbound message, mark connection state). No socket, no timer, no
//! clock lives here — only the protocol decisions (opcode dispatch, hello →
//! identify, heartbeat sequence tracking, READY/RESUMED handling, reconnect /
//! invalid-session classification).
//!
//! `step(state_json, event_json) -> { "state": <new state>, "actions": [...] }`.
//! The adapter holds the opaque `state` blob between calls, so core needs no
//! per-connection handle, registry, or disposal.

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::protocol;

/// Default heartbeat interval if the gateway HELLO omits one (matches the Dart
/// adapter's historical fallback).
const DEFAULT_HEARTBEAT_INTERVAL_MS: i64 = 45_000;

/// Identify parameters supplied by the adapter at connect time. The access
/// token is fetched fresh by the adapter (transport) right before connecting,
/// so it lives here rather than as long-lived core state.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct QqIdentifyConfig {
    #[serde(default)]
    pub token: String,
    #[serde(default)]
    pub intents: i64,
    #[serde(default)]
    pub shard_count: i64,
    /// Operating system string for the identify `properties.$os` field.
    #[serde(default)]
    pub os: String,
    /// `properties.$browser`; defaults to "napaxi" when empty.
    #[serde(default)]
    pub browser: String,
    /// `properties.$device`; set by the adapter (e.g. "napaxi_flutter_sdk").
    #[serde(default)]
    pub device: String,
}

/// Protocol state for a single QQ gateway connection. Holds only protocol
/// fields — never the socket, timer, or close codes (those are transport).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct QqGatewayState {
    #[serde(default)]
    pub phase: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seq: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub heartbeat_interval_ms: Option<i64>,
    #[serde(default)]
    pub heartbeat_ack_count: i64,
    #[serde(default)]
    pub connected: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub resume_requested: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_event_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_opcode: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_error: Option<String>,
    #[serde(default)]
    pub identify: QqIdentifyConfig,
}

impl QqGatewayState {
    fn clear_error(&mut self) {
        self.last_error = None;
    }
}

fn is_false(value: &bool) -> bool {
    !*value
}

/// Reduce one gateway event over the current state, returning the new state and
/// the actions the adapter should perform. `state_json` may be empty/`{}` for a
/// fresh connection (the adapter seeds `identify` before connecting).
pub fn step(state_json: &str, event_json: &str) -> String {
    let mut state: QqGatewayState = serde_json::from_str(state_json).unwrap_or_default();
    let event: Value = serde_json::from_str(event_json).unwrap_or_else(|_| json!({}));
    let mut actions: Vec<Value> = Vec::new();

    match event.get("type").and_then(Value::as_str).unwrap_or("") {
        "frame" => {
            let text = event.get("text").and_then(Value::as_str).unwrap_or("");
            handle_frame(&mut state, text, &mut actions);
        }
        "heartbeat_due" => {
            actions.push(heartbeat_action(&state));
        }
        other => {
            state.last_error = Some(format!("QQBot Gateway unknown event: {other}"));
        }
    }

    json!({ "state": state, "actions": actions }).to_string()
}

fn handle_frame(state: &mut QqGatewayState, text: &str, actions: &mut Vec<Value>) {
    state.phase = "frame_received".to_string();
    let payload: Value = match serde_json::from_str(text) {
        Ok(value) => value,
        Err(error) => {
            state.last_error = Some(format!("QQBot Gateway frame parse failed: {error}"));
            return;
        }
    };
    if !payload.is_object() {
        return;
    }
    if let Some(seq) = payload.get("s").and_then(Value::as_i64) {
        state.seq = Some(seq);
    }
    let event_type = payload
        .get("t")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if !event_type.is_empty() {
        state.last_event_type = Some(event_type.clone());
    }
    let op = payload.get("op").and_then(Value::as_i64).unwrap_or(-1);
    state.last_opcode = Some(op);

    match op {
        0 => handle_dispatch(state, &event_type, &payload, actions),
        1 => actions.push(heartbeat_action(state)),
        7 => {
            state.connected = false;
            state.resume_requested = true;
            state.phase = "reconnect_requested".to_string();
            state.last_error = Some("QQBot Gateway requested reconnect.".to_string());
            actions.push(json!({ "type": "reconnect", "resume": true }));
        }
        9 => {
            let resumable = payload.get("d").and_then(Value::as_bool).unwrap_or(false);
            state.connected = false;
            state.resume_requested = resumable;
            if !resumable {
                state.session_id = None;
                state.seq = None;
            }
            state.phase = "invalid_session".to_string();
            state.last_error = Some(format!(
                "QQBot Gateway invalid session (resumable={resumable})."
            ));
            actions.push(json!({ "type": "reconnect", "resume": resumable }));
        }
        10 => handle_hello(state, &payload, actions),
        11 => {
            state.heartbeat_ack_count += 1;
            state.clear_error();
        }
        _ => {}
    }
}

fn handle_hello(state: &mut QqGatewayState, payload: &Value, actions: &mut Vec<Value>) {
    let interval = payload
        .get("d")
        .and_then(|d| d.get("heartbeat_interval"))
        .and_then(Value::as_i64)
        .unwrap_or(DEFAULT_HEARTBEAT_INTERVAL_MS);
    state.heartbeat_interval_ms = Some(interval);
    if state.resume_requested {
        if let Some(session_id) = state
            .session_id
            .as_deref()
            .filter(|value| !value.is_empty())
            .map(str::to_string)
        {
            state.phase = "resume_sent".to_string();
            actions.push(json!({
                "type": "send_frame",
                "frame": build_resume(&state.identify.token, &session_id, state.seq),
            }));
        } else {
            state.resume_requested = false;
            state.phase = "identify_sent".to_string();
            actions.push(json!({ "type": "send_frame", "frame": build_identify(&state.identify) }));
        }
    } else {
        state.phase = "identify_sent".to_string();
        actions.push(json!({ "type": "send_frame", "frame": build_identify(&state.identify) }));
    }
    actions.push(json!({ "type": "start_heartbeat", "interval_ms": interval }));
}

fn handle_dispatch(
    state: &mut QqGatewayState,
    event_type: &str,
    payload: &Value,
    actions: &mut Vec<Value>,
) {
    let data = payload.get("d").cloned().unwrap_or_else(|| json!({}));
    match event_type {
        "READY" => {
            state.connected = true;
            state.phase = "ready".to_string();
            state.resume_requested = false;
            state.session_id = data
                .get("session_id")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
                .map(str::to_string);
            state.clear_error();
            actions.push(heartbeat_action(state));
            actions.push(json!({ "type": "mark_ready" }));
        }
        "RESUMED" => {
            state.connected = true;
            state.phase = "resumed".to_string();
            state.resume_requested = false;
            state.clear_error();
            actions.push(json!({ "type": "mark_ready" }));
        }
        other if protocol::is_message_event(other) => {
            let normalized = protocol::normalize_inbound(other, &data.to_string());
            let normalized: Value = serde_json::from_str(&normalized).unwrap_or_else(|_| json!({}));
            actions.push(json!({
                "type": "submit_inbound",
                "event_type": other,
                "inbound": normalized,
                "raw": data,
            }));
        }
        _ => {}
    }
}

/// Builds the heartbeat frame `{ "op": 1, "d": <last seq or null> }`.
fn heartbeat_action(state: &QqGatewayState) -> Value {
    json!({
        "type": "send_frame",
        "frame": { "op": 1, "d": state.seq },
    })
}

/// Builds the op-2 identify frame from the connect-time identify config.
pub fn build_identify(config: &QqIdentifyConfig) -> Value {
    let browser = if config.browser.is_empty() {
        "napaxi"
    } else {
        config.browser.as_str()
    };
    let device = if config.device.is_empty() {
        "napaxi_sdk"
    } else {
        config.device.as_str()
    };
    json!({
        "op": 2,
        "d": {
            "token": format!("QQBot {}", config.token),
            "intents": config.intents,
            "shard": [0, config.shard_count.max(1)],
            "properties": {
                "$os": config.os,
                "$browser": browser,
                "$device": device,
            },
        },
    })
}

/// Builds the op-6 resume frame after a reconnectable gateway interruption.
pub fn build_resume(token: &str, session_id: &str, seq: Option<i64>) -> Value {
    json!({
        "op": 6,
        "d": {
            "token": format!("QQBot {}", token),
            "session_id": session_id,
            "seq": seq,
        },
    })
}
