use super::gateway::{self, QqGatewayState};
use serde_json::{Value, json};

/// Drives one reducer step and returns (new_state, actions).
fn step(state: &Value, event: Value) -> (Value, Vec<Value>) {
    let out: Value =
        serde_json::from_str(&gateway::step(&state.to_string(), &event.to_string())).unwrap();
    let actions = out["actions"].as_array().cloned().unwrap_or_default();
    (out["state"].clone(), actions)
}

fn frame(payload: Value) -> Value {
    json!({ "type": "frame", "text": payload.to_string() })
}

/// A fresh state seeded with the identify config the adapter supplies at connect.
fn seeded_state() -> Value {
    json!({
        "identify": {
            "token": "tok-123",
            "intents": 33554432,
            "shard_count": 1,
            "os": "ios",
            "device": "napaxi_flutter_sdk",
        }
    })
}

/// Pins the gateway reducer to the shared cross-adapter lifecycle fixture.
/// Replays each scripted `{state_in, event}` and asserts the reducer's
/// `{state_out, actions}` matches. The fixture documents the QQ gateway
/// handshake contract for any adapter (Flutter/iOS/Android) that adopts the
/// shared protocol; this guard keeps core from drifting from it.
#[test]
fn gateway_matches_shared_contract_fixture() {
    let fixture_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../packages/api_contract/fixtures/channel/qqbot/gateway.json"
    );
    let fixture: Value = serde_json::from_str(
        &std::fs::read_to_string(fixture_path).expect("read qqbot gateway fixture"),
    )
    .expect("parse qqbot gateway fixture");

    for case in fixture["lifecycle"].as_array().unwrap() {
        let out: Value = serde_json::from_str(&gateway::step(
            &case["state_in"].to_string(),
            &case["event"].to_string(),
        ))
        .unwrap();
        assert_eq!(
            out["state"], case["state_out"],
            "gateway state_out drifted for event {}",
            case["event"]
        );
        assert_eq!(
            out["actions"], case["actions"],
            "gateway actions drifted for event {}",
            case["event"]
        );
    }
}

#[test]
fn hello_triggers_identify_and_heartbeat_start() {
    let (state, actions) = step(
        &seeded_state(),
        frame(json!({"op": 10, "d": {"heartbeat_interval": 30000}})),
    );
    assert_eq!(state["phase"], json!("identify_sent"));
    assert_eq!(state["heartbeat_interval_ms"], json!(30000));

    // First action: send the op-2 identify frame built from the seeded config.
    let identify = &actions[0];
    assert_eq!(identify["type"], json!("send_frame"));
    assert_eq!(identify["frame"]["op"], json!(2));
    assert_eq!(identify["frame"]["d"]["token"], json!("QQBot tok-123"));
    assert_eq!(identify["frame"]["d"]["intents"], json!(33554432));
    assert_eq!(identify["frame"]["d"]["shard"], json!([0, 1]));
    assert_eq!(identify["frame"]["d"]["properties"]["$os"], json!("ios"));
    assert_eq!(
        identify["frame"]["d"]["properties"]["$device"],
        json!("napaxi_flutter_sdk")
    );

    // Second action: start the heartbeat timer at the hello interval.
    assert_eq!(actions[1]["type"], json!("start_heartbeat"));
    assert_eq!(actions[1]["interval_ms"], json!(30000));
}

#[test]
fn hello_without_interval_uses_default() {
    let (state, _) = step(&seeded_state(), frame(json!({"op": 10, "d": {}})));
    assert_eq!(state["heartbeat_interval_ms"], json!(45000));
}

#[test]
fn ready_captures_session_and_marks_connected() {
    let (state, actions) = step(
        &seeded_state(),
        frame(json!({"op": 0, "t": "READY", "s": 5, "d": {"session_id": "sess-1"}})),
    );
    assert_eq!(state["connected"], json!(true));
    assert_eq!(state["phase"], json!("ready"));
    assert_eq!(state["session_id"], json!("sess-1"));
    assert_eq!(state["seq"], json!(5));
    // READY sends an initial heartbeat (with the captured seq) and marks ready.
    assert_eq!(actions[0]["type"], json!("send_frame"));
    assert_eq!(actions[0]["frame"]["op"], json!(1));
    assert_eq!(actions[0]["frame"]["d"], json!(5));
    assert_eq!(actions[1]["type"], json!("mark_ready"));
}

#[test]
fn dispatch_message_event_emits_submit_inbound() {
    let (_, actions) = step(
        &seeded_state(),
        frame(json!({
            "op": 0,
            "t": "C2C_MESSAGE_CREATE",
            "s": 7,
            "d": {"openid": "dm-user", "content": "hi", "author": {"id": "a1"}},
        })),
    );
    assert_eq!(actions[0]["type"], json!("submit_inbound"));
    assert_eq!(actions[0]["event_type"], json!("C2C_MESSAGE_CREATE"));
    assert_eq!(actions[0]["inbound"]["peer"]["kind"], json!("direct"));
    assert_eq!(actions[0]["inbound"]["peer"]["id"], json!("dm-user"));
    assert_eq!(actions[0]["inbound"]["text"], json!("hi"));
    // raw payload is preserved for the adapter's receipt.
    assert_eq!(actions[0]["raw"]["openid"], json!("dm-user"));
}

#[test]
fn server_heartbeat_request_replies_with_last_seq() {
    let mut state = seeded_state();
    // Advance seq via a dispatch, then op-1 (server asks us to heartbeat).
    let (s1, _) = step(
        &state,
        frame(json!({"op": 0, "t": "READY", "s": 9, "d": {}})),
    );
    state = s1;
    let (_, actions) = step(&state, frame(json!({"op": 1})));
    assert_eq!(actions[0]["type"], json!("send_frame"));
    assert_eq!(actions[0]["frame"]["op"], json!(1));
    assert_eq!(actions[0]["frame"]["d"], json!(9));
}

#[test]
fn heartbeat_due_tick_sends_heartbeat() {
    let state = json!({"seq": 3});
    let (_, actions) = step(&state, json!({"type": "heartbeat_due"}));
    assert_eq!(actions[0]["frame"]["op"], json!(1));
    assert_eq!(actions[0]["frame"]["d"], json!(3));
}

#[test]
fn heartbeat_ack_increments_and_clears_error() {
    let state = json!({"last_error": "stale", "heartbeat_ack_count": 1});
    let (state, actions) = step(&state, frame(json!({"op": 11})));
    assert_eq!(state["heartbeat_ack_count"], json!(2));
    assert!(state.get("last_error").is_none() || state["last_error"].is_null());
    assert!(actions.is_empty());
}

#[test]
fn opcode_7_requests_resume_reconnect() {
    let (state, actions) = step(&seeded_state(), frame(json!({"op": 7})));
    assert_eq!(state["connected"], json!(false));
    assert_eq!(state["phase"], json!("reconnect_requested"));
    assert_eq!(state["resume_requested"], json!(true));
    assert_eq!(actions[0]["type"], json!("reconnect"));
    assert_eq!(actions[0]["resume"], json!(true));
}

#[test]
fn opcode_9_resume_flag_drives_reconnect_mode() {
    let (state, resumable) = step(&seeded_state(), frame(json!({"op": 9, "d": true})));
    assert_eq!(state["resume_requested"], json!(true));
    assert_eq!(resumable[0]["type"], json!("reconnect"));
    assert_eq!(resumable[0]["resume"], json!(true));

    let (state, not_resumable) = step(
        &json!({"session_id": "sess-1", "seq": 12, "identify": seeded_state()["identify"].clone()}),
        frame(json!({"op": 9, "d": false})),
    );
    assert_eq!(state["phase"], json!("invalid_session"));
    assert!(state.get("resume_requested").is_none() || state["resume_requested"].is_null());
    assert!(state.get("session_id").is_none() || state["session_id"].is_null());
    assert!(state.get("seq").is_none() || state["seq"].is_null());
    assert_eq!(not_resumable[0]["resume"], json!(false));
}

#[test]
fn reconnect_hello_sends_resume_when_session_and_seq_are_available() {
    let (state, actions) = step(
        &json!({
            "session_id": "sess-1",
            "seq": 42,
            "resume_requested": true,
            "identify": seeded_state()["identify"].clone(),
        }),
        frame(json!({"op": 10, "d": {"heartbeat_interval": 30000}})),
    );
    assert_eq!(state["phase"], json!("resume_sent"));
    assert_eq!(actions[0]["type"], json!("send_frame"));
    assert_eq!(actions[0]["frame"]["op"], json!(6));
    assert_eq!(actions[0]["frame"]["d"]["token"], json!("QQBot tok-123"));
    assert_eq!(actions[0]["frame"]["d"]["session_id"], json!("sess-1"));
    assert_eq!(actions[0]["frame"]["d"]["seq"], json!(42));
    assert_eq!(actions[1]["type"], json!("start_heartbeat"));
}

#[test]
fn reconnect_hello_falls_back_to_identify_without_session() {
    let (state, actions) = step(
        &json!({
            "resume_requested": true,
            "identify": seeded_state()["identify"].clone(),
        }),
        frame(json!({"op": 10, "d": {"heartbeat_interval": 30000}})),
    );
    assert_eq!(state["phase"], json!("identify_sent"));
    assert!(state.get("resume_requested").is_none() || state["resume_requested"].is_null());
    assert_eq!(actions[0]["frame"]["op"], json!(2));
}

#[test]
fn resumed_dispatch_marks_ready_and_clears_resume_request() {
    let (state, actions) = step(
        &json!({"resume_requested": true, "session_id": "sess-1", "seq": 42}),
        frame(json!({"op": 0, "t": "RESUMED", "s": 43, "d": {}})),
    );
    assert_eq!(state["connected"], json!(true));
    assert_eq!(state["phase"], json!("resumed"));
    assert!(state.get("resume_requested").is_none() || state["resume_requested"].is_null());
    assert_eq!(state["seq"], json!(43));
    assert_eq!(actions[0]["type"], json!("mark_ready"));
}

#[test]
fn malformed_frame_records_error_without_panicking() {
    let (state, actions) = step(
        &seeded_state(),
        json!({"type": "frame", "text": "not json"}),
    );
    assert!(
        state["last_error"]
            .as_str()
            .unwrap()
            .contains("parse failed")
    );
    assert!(actions.is_empty());
}

#[test]
fn full_lifecycle_hello_identify_ready_heartbeat_dispatch() {
    // A scripted end-to-end gateway handshake, all offline.
    let mut state = seeded_state();

    // HELLO -> identify + start heartbeat
    let (s, a) = step(
        &state,
        frame(json!({"op": 10, "d": {"heartbeat_interval": 40000}})),
    );
    assert_eq!(a[0]["frame"]["op"], json!(2));
    state = s;

    // READY -> connected, session captured
    let (s, _) = step(
        &state,
        frame(json!({"op": 0, "t": "READY", "s": 1, "d": {"session_id": "sx"}})),
    );
    assert_eq!(s["connected"], json!(true));
    state = s;

    // heartbeat due -> send with current seq
    let (s, a) = step(&state, json!({"type": "heartbeat_due"}));
    assert_eq!(a[0]["frame"]["d"], json!(1));
    state = s;

    // group message -> submit_inbound
    let (s, a) = step(
        &state,
        frame(json!({
            "op": 0, "t": "GROUP_AT_MESSAGE_CREATE", "s": 2,
            "d": {"group_openid": "g1", "content": "yo", "author": {"user_openid": "u1"}},
        })),
    );
    assert_eq!(a[0]["type"], json!("submit_inbound"));
    assert_eq!(a[0]["inbound"]["peer"]["kind"], json!("group"));
    assert_eq!(s["seq"], json!(2));
    state = s;

    // reconnect requested
    let (s, a) = step(&state, frame(json!({"op": 7})));
    assert_eq!(a[0]["type"], json!("reconnect"));
    assert_eq!(s["connected"], json!(false));
}

#[test]
fn build_identify_defaults_browser_and_device() {
    let config = serde_json::from_value::<gateway::QqIdentifyConfig>(json!({
        "token": "t", "intents": 1, "shard_count": 0, "os": "android",
    }))
    .unwrap();
    let frame = gateway::build_identify(&config);
    assert_eq!(frame["d"]["properties"]["$browser"], json!("napaxi"));
    assert_eq!(frame["d"]["properties"]["$device"], json!("napaxi_sdk"));
    // shard_count 0 is clamped to at least 1.
    assert_eq!(frame["d"]["shard"], json!([0, 1]));
}

#[test]
fn state_round_trips_through_serde() {
    let state = QqGatewayState {
        phase: "ready".to_string(),
        seq: Some(12),
        session_id: Some("sess".to_string()),
        connected: true,
        ..Default::default()
    };
    let json = serde_json::to_string(&state).unwrap();
    let back: QqGatewayState = serde_json::from_str(&json).unwrap();
    assert_eq!(back.seq, Some(12));
    assert_eq!(back.session_id.as_deref(), Some("sess"));
    assert!(back.connected);
}
