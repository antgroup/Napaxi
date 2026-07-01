use super::protocol;
use serde_json::{Value, json};

fn parse(text: String) -> Value {
    serde_json::from_str(&text).expect("valid json")
}

/// Pins the core protocol implementation to the shared cross-adapter fixture.
///
/// The fixture at packages/api_contract/fixtures/channel/qqbot/protocol.json is
/// the single source of truth that the Flutter pure-Dart codec (and any future
/// iOS/Android codec) is also pinned against (see
/// channel_qqbot_parity_test.dart). Locking core ⇄ fixture here, and each
/// adapter ⇄ fixture on its side, stops the QQ protocol logic from silently
/// diverging across platforms.
#[test]
fn protocol_matches_shared_contract_fixture() {
    let fixture_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../packages/api_contract/fixtures/channel/qqbot/protocol.json"
    );
    let fixture: Value =
        serde_json::from_str(&std::fs::read_to_string(fixture_path).expect("read qqbot fixture"))
            .expect("parse qqbot fixture");

    for case in fixture["outbound"].as_array().unwrap() {
        let message = case["message"].to_string();
        let kinds = match &case["markdown_endpoint_kinds"] {
            Value::Null => String::new(),
            other => other.to_string(),
        };
        let actual = if case["force_plain_text"].as_bool().unwrap() {
            protocol::build_outbound_payload_plain(&message)
        } else {
            protocol::build_outbound_payload(&message, &kinds)
        };
        assert_eq!(
            parse(actual),
            case["expected"],
            "outbound case {} drifted from fixture",
            case["name"]
        );
    }

    for case in fixture["markdown_fallback"].as_array().unwrap() {
        assert_eq!(
            protocol::should_fallback_from_markdown(case["status"].as_i64().unwrap()),
            case["expected"].as_bool().unwrap(),
            "fallback case status {} drifted",
            case["status"]
        );
    }

    for case in fixture["endpoints"].as_array().unwrap() {
        assert_eq!(
            protocol::outbound_endpoint_path(
                case["peer_kind"].as_str().unwrap(),
                case["peer_id"].as_str().unwrap()
            ),
            case["expected"].as_str().unwrap(),
            "endpoint case {} drifted",
            case["peer_kind"]
        );
    }

    for case in fixture["inbound"].as_array().unwrap() {
        let actual = protocol::normalize_inbound(
            case["event_type"].as_str().unwrap(),
            &case["data"].to_string(),
        );
        assert_eq!(
            parse(actual),
            case["expected"],
            "inbound case {} drifted from fixture",
            case["name"]
        );
    }
}

#[test]
fn markdown_outbound_maps_to_msg_type_2_for_direct() {
    let message = json!({
        "peer": {"kind": "direct", "id": "openid-a"},
        "reply_to_message_id": "msg-a",
        "text": "**hello**",
        "format": "markdown",
    });
    let result = parse(protocol::build_outbound_payload(&message.to_string(), ""));
    assert_eq!(result["used_markdown"], json!(true));
    assert_eq!(result["content_format"], json!("markdown"));
    assert_eq!(result["body"]["msg_type"], json!(2));
    assert_eq!(result["body"]["markdown"]["content"], json!("**hello**"));
    assert_eq!(result["body"]["msg_id"], json!("msg-a"));
}

#[test]
fn markdown_outbound_falls_back_to_plain_for_unsupported_room() {
    let message = json!({
        "peer": {"kind": "room", "id": "channel-a"},
        "text": "**hello**",
        "format": "markdown",
    });
    let result = parse(protocol::build_outbound_payload(&message.to_string(), ""));
    assert_eq!(result["used_markdown"], json!(false));
    assert_eq!(result["body"]["msg_type"], json!(0));
    assert_eq!(result["body"]["content"], json!("**hello**"));
    assert!(result["body"].get("msg_id").is_none());
}

#[test]
fn forced_plain_text_never_emits_markdown() {
    let message = json!({
        "peer": {"kind": "direct", "id": "openid-a"},
        "text": "**hi**",
        "format": "markdown",
    });
    let result = parse(protocol::build_outbound_payload_plain(&message.to_string()));
    assert_eq!(result["body"]["msg_type"], json!(0));
    assert_eq!(result["used_markdown"], json!(false));
}

#[test]
fn custom_markdown_endpoint_kinds_override_default() {
    let message = json!({
        "peer": {"kind": "room", "id": "channel-a"},
        "text": "**hello**",
        "format": "markdown",
    });
    // Declaring room as markdown-capable flips the default plain fallback.
    let result = parse(protocol::build_outbound_payload(
        &message.to_string(),
        &json!(["room"]).to_string(),
    ));
    assert_eq!(result["used_markdown"], json!(true));
    assert_eq!(result["body"]["msg_type"], json!(2));
}

#[test]
fn markdown_fallback_only_for_non_throttling_4xx() {
    assert!(protocol::should_fallback_from_markdown(400));
    assert!(protocol::should_fallback_from_markdown(415));
    assert!(!protocol::should_fallback_from_markdown(429));
    assert!(!protocol::should_fallback_from_markdown(500));
    assert!(!protocol::should_fallback_from_markdown(200));
}

#[test]
fn outbound_endpoint_routes_by_peer_kind() {
    assert_eq!(
        protocol::outbound_endpoint_path("group", "g1"),
        "/v2/groups/g1/messages"
    );
    assert_eq!(
        protocol::outbound_endpoint_path("room", "c1"),
        "/channels/c1/messages"
    );
    assert_eq!(
        protocol::outbound_endpoint_path("direct", "u1"),
        "/v2/users/u1/messages"
    );
    // Unknown kinds fall back to the direct-user endpoint.
    assert_eq!(
        protocol::outbound_endpoint_path("thread", "x1"),
        "/v2/users/x1/messages"
    );
}

#[test]
fn outbound_endpoint_percent_encodes_peer_id() {
    assert_eq!(
        protocol::outbound_endpoint_path("group", "a/b c"),
        "/v2/groups/a%2Fb%20c/messages"
    );
}

#[test]
fn api_base_switches_on_sandbox() {
    assert_eq!(protocol::api_base(false), protocol::QQ_API_BASE);
    assert_eq!(protocol::api_base(true), protocol::QQ_API_BASE_SANDBOX);
}

#[test]
fn inbound_group_event_normalizes_to_group_peer() {
    let data = json!({
        "group_openid": "group-1",
        "content": "hi bot",
        "id": "evt-1",
        "author": {"user_openid": "user-1", "username": "Alice"},
    });
    let result = parse(protocol::normalize_inbound(
        "GROUP_AT_MESSAGE_CREATE",
        &data.to_string(),
    ));
    assert_eq!(result["peer"]["kind"], json!("group"));
    assert_eq!(result["peer"]["id"], json!("group-1"));
    assert_eq!(result["sender"]["id"], json!("user-1"));
    assert_eq!(result["sender"]["display_name"], json!("Alice"));
    assert_eq!(result["sender"]["is_bot"], json!(false));
    assert_eq!(result["text"], json!("hi bot"));
    assert_eq!(result["platform_message_id"], json!("evt-1"));
    assert_eq!(result["thread_id"], json!("group-1"));
}

#[test]
fn inbound_direct_event_uses_author_openid() {
    let data = json!({
        "openid": "dm-user",
        "content": "ping",
        "author": {"id": "author-id", "nick": "Bob"},
    });
    let result = parse(protocol::normalize_inbound(
        "C2C_MESSAGE_CREATE",
        &data.to_string(),
    ));
    assert_eq!(result["peer"]["kind"], json!("direct"));
    assert_eq!(result["peer"]["id"], json!("dm-user"));
    assert_eq!(result["sender"]["display_name"], json!("Bob"));
}

#[test]
fn inbound_room_event_uses_channel_id() {
    let data = json!({
        "channel_id": "chan-1",
        "channel_name": "general",
        "content": "@bot hi",
        "author": {"id": "u9"},
    });
    let result = parse(protocol::normalize_inbound(
        "AT_MESSAGE_CREATE",
        &data.to_string(),
    ));
    assert_eq!(result["peer"]["kind"], json!("room"));
    assert_eq!(result["peer"]["id"], json!("chan-1"));
    assert_eq!(result["peer"]["display_name"], json!("general"));
    assert_eq!(result["thread_id"], json!("chan-1"));
}

#[test]
fn inbound_without_peer_id_reports_error() {
    let data = json!({"content": "orphan"});
    let result = parse(protocol::normalize_inbound(
        "GROUP_AT_MESSAGE_CREATE",
        &data.to_string(),
    ));
    assert_eq!(result["peer"], Value::Null);
    assert!(result["error"].as_str().unwrap().contains("no peer id"));
}

#[test]
fn is_message_event_recognizes_qq_message_types() {
    assert!(protocol::is_message_event("C2C_MESSAGE_CREATE"));
    assert!(protocol::is_message_event("GROUP_AT_MESSAGE_CREATE"));
    assert!(protocol::is_message_event("AT_MESSAGE_CREATE"));
    assert!(!protocol::is_message_event("READY"));
    assert!(!protocol::is_message_event("RESUMED"));
}
