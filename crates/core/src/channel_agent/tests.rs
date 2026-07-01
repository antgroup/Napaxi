use super::*;
use crate::channel::ChannelModality;

fn inbound(peer_id: &str, thread_id: Option<&str>) -> ChannelInboundMessage {
    ChannelInboundMessage {
        id: "in_1".to_string(),
        channel_name: "qqbot".to_string(),
        account_id: "bot-a".to_string(),
        peer: ChannelPeer {
            kind: ChannelEndpointKind::Direct,
            id: peer_id.to_string(),
            display_name: Some("QQ 好友".to_string()),
        },
        sender: crate::channel::ChannelActor {
            id: peer_id.to_string(),
            display_name: Some("Alice".to_string()),
            is_bot: None,
        },
        platform_message_id: Some("msg-1".to_string()),
        thread_id: thread_id.map(str::to_string),
        text: Some("帮我看下日程".to_string()),
        media: Vec::new(),
        raw: None,
        error: None,
        status: "queued".to_string(),
        received_at: Utc::now(),
        updated_at: Utc::now(),
    }
}

fn bridge_config() -> ChannelAgentBridgeConfig {
    normalize_config(ChannelAgentBridgeConfig {
        channel_name: "qqbot".to_string(),
        session_account_id: "user-a".to_string(),
        default_agent_id: "default-agent".to_string(),
        inbound_limit: 1,
        max_iterations: 0,
        empty_response_text: None,
        human_answer_required_text: None,
        human_answer_failed_text: None,
    })
}

fn engine_handle(files_dir: &str) -> i64 {
    engine_handle_with_capabilities(files_dir, &[crate::channel::CHANNEL_IM_CAPABILITY_ID])
}

fn engine_handle_with_capabilities(files_dir: &str, capabilities: &[&str]) -> i64 {
    let config_json = serde_json::json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null,
        "capability_profile": {
            "platform": "test",
            "supported_capabilities": capabilities
        },
        "capability_selection": {
            "enabled_capabilities": capabilities
        }
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

fn engine_handle_without_channel_capability(files_dir: &str) -> i64 {
    let config_json = serde_json::json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null,
        "capability_profile": {
            "platform": "test",
            "supported_capabilities": []
        },
        "capability_selection": {
            "enabled_capabilities": []
        }
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

#[test]
fn route_precedence_prefers_thread_then_peer_then_channel_default() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let now = Utc::now();
    let routes = vec![
        ChannelAgentRoute {
            id: "default".to_string(),
            channel_name: "qqbot".to_string(),
            channel_account_id: None,
            peer_kind: None,
            peer_id: None,
            thread_id: None,
            session_account_id: "user-a".to_string(),
            agent_id: "default-route-agent".to_string(),
            enabled: true,
            session_policy: ChannelSessionPolicy::StableByPeerOrThread,
            created_at: now,
            updated_at: now,
        },
        ChannelAgentRoute {
            id: "peer".to_string(),
            channel_name: "qqbot".to_string(),
            channel_account_id: None,
            peer_kind: Some(ChannelEndpointKind::Direct),
            peer_id: Some("openid-a".to_string()),
            thread_id: None,
            session_account_id: "user-a".to_string(),
            agent_id: "peer-agent".to_string(),
            enabled: true,
            session_policy: ChannelSessionPolicy::StableByPeerOrThread,
            created_at: now,
            updated_at: now,
        },
        ChannelAgentRoute {
            id: "thread".to_string(),
            channel_name: "qqbot".to_string(),
            channel_account_id: None,
            peer_kind: None,
            peer_id: None,
            thread_id: Some("thread-a".to_string()),
            session_account_id: "user-a".to_string(),
            agent_id: "thread-agent".to_string(),
            enabled: true,
            session_policy: ChannelSessionPolicy::StableByPeerOrThread,
            created_at: now,
            updated_at: now,
        },
    ];
    assert!(save_routes(&files_dir, &routes));

    let resolved_thread = resolve_route(
        &files_dir,
        &bridge_config(),
        &inbound("openid-a", Some("thread-a")),
    )
    .unwrap();
    assert_eq!(resolved_thread.agent_id, "thread-agent");
    assert_eq!(resolved_thread.route_source, "thread_route");

    let resolved_peer =
        resolve_route(&files_dir, &bridge_config(), &inbound("openid-a", None)).unwrap();
    assert_eq!(resolved_peer.agent_id, "peer-agent");
    assert_eq!(resolved_peer.route_source, "peer_route");

    let resolved_default =
        resolve_route(&files_dir, &bridge_config(), &inbound("openid-b", None)).unwrap();
    assert_eq!(resolved_default.agent_id, "default-route-agent");
    assert_eq!(resolved_default.route_source, "channel_default_route");
}

#[test]
fn stable_session_id_is_stable_and_isolated_by_agent_channel_and_account() {
    let direct = ChannelPeer {
        kind: ChannelEndpointKind::Direct,
        id: "openid-a".to_string(),
        display_name: None,
    };
    let first = stable_session_thread_id(
        "qqbot", "user-a", "agent-a", "bot-a", &direct, None, "openid-a",
    );
    let second = stable_session_thread_id(
        "qqbot", "user-a", "agent-a", "bot-a", &direct, None, "openid-a",
    );
    assert_eq!(first, second);
    assert_ne!(
        first,
        stable_session_thread_id(
            "qqbot", "user-a", "agent-b", "bot-a", &direct, None, "openid-a",
        )
    );
    assert_ne!(
        first,
        stable_session_thread_id(
            "wechat", "user-a", "agent-a", "bot-a", &direct, None, "openid-a",
        )
    );
}

#[test]
fn message_id_thread_alias_falls_back_to_peer_for_stable_session() {
    let files_dir = tempfile::tempdir().unwrap();
    let first = inbound("openid-a", Some("msg-1"));
    let second = ChannelInboundMessage {
        id: "in_2".to_string(),
        platform_message_id: Some("msg-2".to_string()),
        thread_id: Some("msg-2".to_string()),
        text: Some("第二条".to_string()),
        ..inbound("openid-a", Some("msg-2"))
    };
    let first_route = resolve_route(
        &files_dir.path().to_string_lossy(),
        &bridge_config(),
        &first,
    )
    .unwrap();
    let second_route = resolve_route(
        &files_dir.path().to_string_lossy(),
        &bridge_config(),
        &second,
    )
    .unwrap();

    assert_eq!(
        first_route.session_key.thread_id,
        second_route.session_key.thread_id
    );
}

#[test]
fn display_text_hides_peer_ids_while_agent_input_has_context() {
    let inbound = inbound("openid-a", Some("thread-a"));
    let display = display_text(&inbound);
    let agent_input = agent_input(&inbound);

    assert_eq!(display, "帮我看下日程");
    assert!(!display.contains("openid-a"));
    assert!(agent_input.contains("Peer id: openid-a"));
    assert!(agent_input.contains("Channel: qqbot"));
    assert!(agent_input.contains("Message:\n帮我看下日程"));
}

#[test]
fn local_a2a_agent_input_supports_clarification_without_display_leak() {
    let mut inbound = inbound("android-peer-123456", Some("a2a-thread"));
    inbound.channel_name = "local_a2a".to_string();
    inbound.peer.display_name = Some("Android Agent".to_string());
    inbound.sender.display_name = Some("Android Agent".to_string());
    inbound.text = Some("你怎么看甜粽子和咸粽子？".to_string());
    inbound.raw = Some(serde_json::json!({
        "a2a_collaboration": {
            "sessionId": "a2a-collab-123",
            "goal": "讨论粽子口味",
            "fromPeerId": "android-peer-123456",
            "toPeerId": "ios-peer-abcdef",
            "expectsReply": true,
            "conversationHistory": [
                "Other Agent: 我觉得甜粽子更像点心。",
                "You: 但咸粽子更像正餐，也更有层次。"
            ],
            "round": 1,
            "maxRounds": 4
        }
    }));

    let display = display_text(&inbound);
    let input = agent_input(&inbound);

    assert_eq!(display, "你怎么看甜粽子和咸粽子？");
    assert!(!display.contains("a2a-collab-123"));
    assert!(input.contains("Conversation goal: 讨论粽子口味"));
    assert!(input.contains("Recent dialogue:"));
    assert!(input.contains("Other Agent: 我觉得甜粽子更像点心。"));
    assert!(input.contains("You: 但咸粽子更像正餐，也更有层次。"));
    assert!(!input.contains("Round: 1 of 4"));
    assert!(!input.contains("maxRounds"));
    assert!(input.contains("Output only the next message text"));
    assert!(input.contains("ongoing Agent-to-Agent conversation"));
    assert!(input.contains("ask a clear follow-up or challenge naturally"));
    assert!(!input.contains("normal A2A channel"));
    assert!(!input.contains("routing note"));
    assert!(!input.contains("call a2a_send_message"));
    assert!(!input.contains("a2a_wait_messages"));
}

#[test]
fn media_library_tool_result_artifacts_become_channel_media() {
    let mut media = Vec::new();
    let output = serde_json::json!({
        "success": true,
        "artifacts": [{
            "artifactId": "photo-1",
            "kind": "image",
            "mimeType": "image/jpeg",
            "name": "IMG_1.jpg",
            "uri": "/workspace/attachments/media/IMG_1.jpg",
            "sandbox_path": "/workspace/attachments/media/IMG_1.jpg",
            "sizeBytes": 42
        }]
    });
    append_tool_result_media(
        &mut media,
        &serde_json::json!({
            "type": "tool_result",
            "call_id": "call_media",
            "name": "media_library",
            "output": output.to_string(),
            "is_error": false
        }),
    );

    assert_eq!(media.len(), 1);
    assert_eq!(media[0].kind, ChannelModality::Image);
    assert_eq!(
        media[0].uri.as_deref(),
        Some("/workspace/attachments/media/IMG_1.jpg")
    );
    assert_eq!(media[0].mime_type.as_deref(), Some("image/jpeg"));
    assert_eq!(media[0].size_bytes, Some(42));
    assert_eq!(
        media[0]
            .raw
            .as_ref()
            .and_then(|raw| raw.get("sandbox_path"))
            .and_then(serde_json::Value::as_str),
        Some("/workspace/attachments/media/IMG_1.jpg")
    );
}

#[tokio::test]
async fn channel_agent_handle_wrappers_gate_channel_capability() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle_without_channel_capability(&files_dir);
    let route_json = serde_json::to_string(&ChannelAgentRoute {
        id: String::new(),
        channel_name: "qqbot".to_string(),
        channel_account_id: None,
        peer_kind: None,
        peer_id: None,
        thread_id: None,
        session_account_id: "user-a".to_string(),
        agent_id: "agent-a".to_string(),
        enabled: true,
        session_policy: ChannelSessionPolicy::StableByPeerOrThread,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    })
    .unwrap();

    let denied: serde_json::Value =
        serde_json::from_str(&register_channel_agent_route_handle(handle, &route_json)).unwrap();
    assert!(
        denied
            .get("error")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .contains(crate::channel::CHANNEL_IM_CAPABILITY_ID)
    );
    assert_eq!(list_channel_agent_routes_handle(handle, None), "[]");

    let mut events = Vec::new();
    stream_channel_agent_pump_handle(
        handle,
        r#"{"provider":"__test_noop__","api_key":"test","model":"test"}"#,
        &serde_json::to_string(&bridge_config()).unwrap(),
        |event| events.push(event),
    )
    .await;
    assert_eq!(events.len(), 1);
    assert!(events[0].contains(crate::channel::CHANNEL_IM_CAPABILITY_ID));

    // SAFETY: `handle` is an engine handle owned by this test and consumed exactly once here.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[tokio::test]
async fn channel_agent_handle_wrappers_accept_device_channel_capability() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle_with_capabilities(
        &files_dir,
        &[crate::channel::CHANNEL_DEVICE_CAPABILITY_ID],
    );
    let route_json = serde_json::to_string(&ChannelAgentRoute {
        id: String::new(),
        channel_name: "bluetooth_headset".to_string(),
        channel_account_id: None,
        peer_kind: None,
        peer_id: None,
        thread_id: None,
        session_account_id: "user-a".to_string(),
        agent_id: "agent-a".to_string(),
        enabled: true,
        session_policy: ChannelSessionPolicy::StableByPeerOrThread,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    })
    .unwrap();

    let accepted: ChannelAgentRoute =
        serde_json::from_str(&register_channel_agent_route_handle(handle, &route_json)).unwrap();

    assert_eq!(accepted.channel_name, "bluetooth_headset");
    assert!(list_channel_agent_routes_handle(handle, None).contains("bluetooth_headset"));

    // SAFETY: `handle` is an engine handle owned by this test and consumed exactly once here.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[tokio::test]
async fn channel_agent_final_reply_is_queued_as_markdown() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);
    let inbound = serde_json::json!({
        "channel":"qqbot",
        "account_id":"bot-a",
        "platform_message_id":"msg-1",
        "peer":{"kind":"direct","id":"openid-a"},
        "sender":{"id":"openid-a"},
        "text":"hello"
    })
    .to_string();
    let receipt: crate::channel::ChannelAcceptedReceipt = serde_json::from_str(
        &crate::channel::submit_channel_inbound(&files_dir, &inbound),
    )
    .unwrap();
    assert!(receipt.accepted);

    let config_json = serde_json::json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let bridge_config_json = serde_json::to_string(&bridge_config()).unwrap();
    let mut events = Vec::new();
    crate::llm::with_scripted_turns(
        vec![crate::llm::LlmTurn {
            content: "**done**".to_string(),
            reasoning_content: None,
            tool_calls: Vec::new(),
            usage: None,
        }],
        stream_channel_agent_pump_handle(handle, &config_json, &bridge_config_json, |event| {
            events.push(event);
        }),
    )
    .await;

    assert!(events.iter().any(|event| event.contains("outbound_queued")));
    let outbound: Vec<crate::channel::ChannelOutboundMessage> = serde_json::from_str(
        &crate::channel::lease_channel_outbound(&files_dir, "qqbot", Some("bot-a"), 10),
    )
    .unwrap();
    assert_eq!(outbound.len(), 1);
    assert_eq!(outbound[0].text.as_deref(), Some("**done**"));
    assert_eq!(
        outbound[0].format.as_deref(),
        Some(crate::channel::CHANNEL_CONTENT_FORMAT_MARKDOWN)
    );

    // SAFETY: `handle` is an engine handle owned by this test and consumed exactly once here.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[tokio::test]
async fn channel_agent_failed_event_includes_chat_error() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);
    let inbound = serde_json::json!({
        "channel":"qqbot",
        "account_id":"bot-a",
        "platform_message_id":"msg-1",
        "peer":{"kind":"direct","id":"openid-a"},
        "sender":{"id":"openid-a"},
        "text":"hello"
    })
    .to_string();
    let receipt: crate::channel::ChannelAcceptedReceipt = serde_json::from_str(
        &crate::channel::submit_channel_inbound(&files_dir, &inbound),
    )
    .unwrap();
    assert!(receipt.accepted);

    let config_json = serde_json::json!({
        "provider": "openai",
        "api_key": "",
        "base_url": null,
        "model": "gpt-test",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let bridge_config_json = serde_json::to_string(&bridge_config()).unwrap();
    let mut events = Vec::new();
    stream_channel_agent_pump_handle(handle, &config_json, &bridge_config_json, |event| {
        events.push(event);
    })
    .await;

    let failed: serde_json::Value = events
        .iter()
        .filter_map(|event| serde_json::from_str::<serde_json::Value>(event).ok())
        .find(|event| event.get("type").and_then(serde_json::Value::as_str) == Some("failed"))
        .expect("failed event");
    assert_eq!(
        failed.get("error").and_then(serde_json::Value::as_str),
        Some("Chat error: LLM API key is required")
    );
    let outbound: Vec<crate::channel::ChannelOutboundMessage> = serde_json::from_str(
        &crate::channel::lease_channel_outbound(&files_dir, "qqbot", Some("bot-a"), 10),
    )
    .unwrap();
    assert_eq!(
        outbound[0]
            .raw
            .as_ref()
            .and_then(|raw| raw.get("error"))
            .and_then(serde_json::Value::as_str),
        Some("Chat error: LLM API key is required")
    );

    // SAFETY: `handle` is an engine handle owned by this test and consumed exactly once here.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[tokio::test]
async fn channel_agent_pump_processes_configured_inbound_batch() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);
    for (platform_message_id, text) in [("msg-1", "first"), ("msg-2", "second")] {
        let inbound = serde_json::json!({
            "channel":"qqbot",
            "account_id":"bot-a",
            "platform_message_id": platform_message_id,
            "peer":{"kind":"direct","id":"openid-a"},
            "sender":{"id":"openid-a"},
            "text": text
        })
        .to_string();
        let receipt: crate::channel::ChannelAcceptedReceipt = serde_json::from_str(
            &crate::channel::submit_channel_inbound(&files_dir, &inbound),
        )
        .unwrap();
        assert!(receipt.accepted);
    }

    let config_json = serde_json::json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let mut bridge = bridge_config();
    bridge.inbound_limit = 2;
    let bridge_config_json = serde_json::to_string(&bridge).unwrap();
    let mut events = Vec::new();
    crate::llm::with_scripted_turns(
        vec![
            crate::llm::LlmTurn {
                content: "reply one".to_string(),
                reasoning_content: None,
                tool_calls: Vec::new(),
                usage: None,
            },
            crate::llm::LlmTurn {
                content: "reply two".to_string(),
                reasoning_content: None,
                tool_calls: Vec::new(),
                usage: None,
            },
        ],
        stream_channel_agent_pump_handle(handle, &config_json, &bridge_config_json, |event| {
            events.push(event);
        }),
    )
    .await;

    assert_eq!(
        events
            .iter()
            .filter(|event| event.contains("\"type\":\"inbound_received\""))
            .count(),
        2
    );
    let thread_ids: std::collections::BTreeSet<String> = events
        .iter()
        .filter_map(|event| serde_json::from_str::<serde_json::Value>(event).ok())
        .filter(|event| {
            event.get("type").and_then(serde_json::Value::as_str) == Some("inbound_received")
        })
        .filter_map(|event| {
            event
                .get("session_key")
                .and_then(|key| key.get("thread_id"))
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
        .collect();
    assert_eq!(thread_ids.len(), 1);

    let sessions: Vec<serde_json::Value> = serde_json::from_str(&crate::session::list_sessions(
        &files_dir,
        "default-agent",
        "user-a",
    ))
    .unwrap();
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0]["message_count"], serde_json::json!(4));

    let outbound: Vec<crate::channel::ChannelOutboundMessage> = serde_json::from_str(
        &crate::channel::lease_channel_outbound(&files_dir, "qqbot", Some("bot-a"), 10),
    )
    .unwrap();
    assert_eq!(outbound.len(), 2);
    let texts: Vec<_> = outbound
        .iter()
        .filter_map(|message| message.text.as_deref())
        .collect();
    assert_eq!(texts, vec!["reply one", "reply two"]);

    // SAFETY: `handle` is an engine handle owned by this test and consumed exactly once here.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}
