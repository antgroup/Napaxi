use super::*;

fn engine_handle(files_dir: &str) -> i64 {
    engine_handle_with_capabilities(files_dir, &[CHANNEL_IM_CAPABILITY_ID])
}

fn engine_handle_with_capabilities(files_dir: &str, capabilities: &[&str]) -> i64 {
    let config_json = serde_json::json!({
        "provider": "openai",
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
        "provider": "openai",
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
fn manages_mobile_channel_registry() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    assert_eq!(list_channels(&files_dir), "[]");
    assert!(!register_channel(&files_dir, "not-json"));
    assert!(!register_channel(&files_dir, r#"{"type":""}"#));
    assert!(register_channel(
        &files_dir,
        r#"{"name":"telegram","type":"telegram","token":"redacted"}"#
    ));
    assert!(list_channels(&files_dir).contains("telegram"));
    assert!(register_channel(
        &files_dir,
        r#"{"name":"telegram","type":"telegram","token":"next"}"#
    ));
    let channels: Vec<ChannelConfig> = serde_json::from_str(&list_channels(&files_dir)).unwrap();
    assert_eq!(channels.len(), 1);
    assert_eq!(channels[0].name, "telegram");
    assert_eq!(channels[0].surface_kind, Some(ChannelSurfaceKind::Im));
    assert_eq!(
        channels[0].capability_id.as_deref(),
        Some(CHANNEL_IM_CAPABILITY_ID)
    );
    assert_eq!(
        channels[0]
            .config
            .get("token")
            .and_then(serde_json::Value::as_str),
        Some("next")
    );
    assert!(unregister_channel(&files_dir, "telegram"));
    assert_eq!(list_channels(&files_dir), "[]");
}

#[test]
fn handle_wrappers_delegate_to_channel_registry() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);

    assert_eq!(list_channels_handle(0), "[]");
    assert!(!register_channel_handle(0, r#"{"name":"telegram"}"#));
    assert!(!unregister_channel_handle(0, "telegram"));
    assert!(register_channel_handle(
        handle,
        r#"{"channelName":"telegram"}"#
    ));
    assert!(list_channels_handle(handle).contains("telegram"));
    assert!(unregister_channel_handle(handle, "telegram"));

    // SAFETY: `handle` is an engine handle owned by this call site and consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn handle_wrappers_gate_channel_capability() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle_without_channel_capability(&files_dir);

    assert!(!register_channel_handle(
        handle,
        r#"{"channelName":"telegram"}"#
    ));
    let denied: serde_json::Value = serde_json::from_str(&submit_channel_inbound_handle(
        handle,
        r#"{
          "channel":"telegram",
          "platform_message_id":"msg-1",
          "peer":{"kind":"direct","id":"user-a"},
          "sender":{"id":"user-a"},
          "text":"hello"
        }"#,
    ))
    .unwrap();
    assert!(
        denied
            .get("error")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .contains(CHANNEL_IM_CAPABILITY_ID)
    );
    assert_eq!(list_channels_handle(handle), "[]");

    // SAFETY: `handle` is an engine handle owned by this call site and consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn stores_channel_surface_metadata() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    assert!(register_channel(
        &files_dir,
        r#"{"name":"team-chat","type":"custom_im","surface_kind":"im","endpoint_kind":"group","modalities":["text","image","file"],"content_formats":["plain_text","markdown"],"transport":"webhook"}"#
    ));
    let channels: Vec<ChannelConfig> = serde_json::from_str(&list_channels(&files_dir)).unwrap();
    assert_eq!(channels[0].surface_kind, Some(ChannelSurfaceKind::Im));
    assert_eq!(channels[0].endpoint_kind, Some(ChannelEndpointKind::Group));
    assert_eq!(
        channels[0].modalities,
        vec![
            ChannelModality::Text,
            ChannelModality::Image,
            ChannelModality::File
        ]
    );
    assert_eq!(
        channels[0].content_formats,
        vec![
            CHANNEL_CONTENT_FORMAT_PLAIN_TEXT.to_string(),
            CHANNEL_CONTENT_FORMAT_MARKDOWN.to_string()
        ]
    );
    assert_eq!(channels[0].transport.as_deref(), Some("webhook"));
    assert_eq!(
        channels[0].capability_id.as_deref(),
        Some(CHANNEL_IM_CAPABILITY_ID)
    );
}

#[test]
fn stores_device_channel_surface_metadata() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    assert!(register_channel(
        &files_dir,
        r#"{"name":"bluetooth_headset","type":"bluetooth_headset","surface_kind":"device","endpoint_kind":"device","modalities":["audio","text","control","presence"],"content_formats":["plain_text","markdown"],"transport":"bluetooth_headset_host_audio"}"#
    ));
    let channels: Vec<ChannelConfig> = serde_json::from_str(&list_channels(&files_dir)).unwrap();
    assert_eq!(channels[0].surface_kind, Some(ChannelSurfaceKind::Device));
    assert_eq!(channels[0].endpoint_kind, Some(ChannelEndpointKind::Device));
    assert_eq!(
        channels[0].modalities,
        vec![
            ChannelModality::Audio,
            ChannelModality::Text,
            ChannelModality::Control,
            ChannelModality::Presence
        ]
    );
    assert_eq!(
        channels[0].capability_id.as_deref(),
        Some(CHANNEL_DEVICE_CAPABILITY_ID)
    );
}

#[test]
fn handle_wrappers_accept_device_channel_capability() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle_with_capabilities(&files_dir, &[CHANNEL_DEVICE_CAPABILITY_ID]);

    assert!(register_channel_handle(
        handle,
        r#"{"name":"bluetooth_headset","surface_kind":"device","endpoint_kind":"device"}"#
    ));
    let channels: Vec<ChannelConfig> = serde_json::from_str(&list_channels_handle(handle)).unwrap();
    assert_eq!(
        channels[0].capability_id.as_deref(),
        Some(CHANNEL_DEVICE_CAPABILITY_ID)
    );

    // SAFETY: `handle` is an engine handle owned by this call site and consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn accepts_inbound_and_leases_reply_for_im_adapters() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    let receipt: ChannelAcceptedReceipt = serde_json::from_str(&submit_channel_inbound(
        &files_dir,
        r#"{
          "channel":"feishu",
          "account_id":"main",
          "platform_message_id":"om_1",
          "peer":{"kind":"group","id":"oc_group","display_name":"Ops"},
          "sender":{"id":"ou_user","display_name":"Alice"},
          "thread_id":"om_root",
          "text":"ship status?"
        }"#,
    ))
    .unwrap();
    assert!(receipt.accepted);
    assert!(!receipt.duplicate);

    let duplicate: ChannelAcceptedReceipt = serde_json::from_str(&submit_channel_inbound(
        &files_dir,
        r#"{
          "channel":"feishu",
          "account_id":"main",
          "platform_message_id":"om_1",
          "peer":{"kind":"group","id":"oc_group"},
          "sender":{"id":"ou_user"},
          "text":"ship status?"
        }"#,
    ))
    .unwrap();
    assert!(duplicate.duplicate);
    assert_eq!(duplicate.id, receipt.id);

    let inbound: Vec<ChannelInboundMessage> =
        serde_json::from_str(&take_channel_inbound(&files_dir, "feishu", 10)).unwrap();
    assert_eq!(inbound.len(), 1);
    assert_eq!(inbound[0].status, "leased");
    assert_eq!(inbound[0].peer.kind, ChannelEndpointKind::Group);
    assert!(ack_channel_inbound(&files_dir, &receipt.id));

    let outbound_receipt: ChannelAcceptedReceipt = serde_json::from_str(&reply_channel_inbound(
        &files_dir,
        &receipt.id,
        r#"{"text":"green"}"#,
    ))
    .unwrap();
    assert!(outbound_receipt.accepted);
    let outbound: Vec<ChannelOutboundMessage> = serde_json::from_str(&lease_channel_outbound(
        &files_dir,
        "feishu",
        Some("main"),
        10,
    ))
    .unwrap();
    assert_eq!(outbound.len(), 1);
    assert_eq!(outbound[0].channel_name, "feishu");
    assert_eq!(outbound[0].account_id, "main");
    assert_eq!(outbound[0].peer.id, "oc_group");
    assert_eq!(outbound[0].reply_to_message_id.as_deref(), Some("om_1"));
    assert_eq!(outbound[0].thread_id.as_deref(), Some("om_root"));
    assert_eq!(
        outbound[0].format.as_deref(),
        Some(CHANNEL_CONTENT_FORMAT_PLAIN_TEXT)
    );
    assert!(ack_channel_outbound(
        &files_dir,
        &outbound_receipt.id,
        r#"{"message_id":"reply_1"}"#
    ));
}

#[test]
fn inbound_can_be_released_or_failed_after_lease() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    let receipt: ChannelAcceptedReceipt = serde_json::from_str(&submit_channel_inbound(
        &files_dir,
        r#"{
          "channel":"qqbot",
          "account_id":"bot-a",
          "platform_message_id":"msg-1",
          "peer":{"kind":"direct","id":"openid-a"},
          "sender":{"id":"openid-a"},
          "text":"hello"
        }"#,
    ))
    .unwrap();
    let leased: Vec<ChannelInboundMessage> =
        serde_json::from_str(&take_channel_inbound(&files_dir, "qqbot", 1)).unwrap();
    assert_eq!(leased.len(), 1);
    assert_eq!(leased[0].status, "leased");

    assert!(release_channel_inbound(&files_dir, &receipt.id));
    let leased_again: Vec<ChannelInboundMessage> =
        serde_json::from_str(&take_channel_inbound(&files_dir, "qqbot", 1)).unwrap();
    assert_eq!(leased_again.len(), 1);
    assert_eq!(leased_again[0].status, "leased");

    assert!(fail_channel_inbound(
        &files_dir,
        &receipt.id,
        "route_missing"
    ));
    let after_fail: Vec<ChannelInboundMessage> =
        serde_json::from_str(&take_channel_inbound(&files_dir, "qqbot", 1)).unwrap();
    assert!(after_fail.is_empty());
    let inbox: Vec<ChannelInboundMessage> = super::load_inbox(&files_dir);
    assert_eq!(inbox[0].status, "failed");
    assert_eq!(inbox[0].error.as_deref(), Some("route_missing"));
}

#[test]
fn queues_explicit_outbound_for_registered_im_adapters() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    let qq: ChannelAcceptedReceipt = serde_json::from_str(&enqueue_channel_outbound(
        &files_dir,
        r#"{
          "channel":"qqbot",
          "account_id":"bot-a",
          "peer":{"kind":"direct","id":"openid-a"},
          "text":"hello",
          "format":"markdown",
          "media":[{"kind":"image","uri":"file:///tmp/a.png","mime_type":"image/png"}]
        }"#,
    ))
    .unwrap();
    assert!(qq.accepted);
    let leased_qq: Vec<ChannelOutboundMessage> = serde_json::from_str(&lease_channel_outbound(
        &files_dir,
        "qqbot",
        Some("bot-a"),
        10,
    ))
    .unwrap();
    assert_eq!(leased_qq.len(), 1);
    assert_eq!(leased_qq[0].media[0].kind, ChannelModality::Image);
    assert_eq!(
        leased_qq[0].format.as_deref(),
        Some(CHANNEL_CONTENT_FORMAT_MARKDOWN)
    );
    assert!(fail_channel_outbound(&files_dir, &qq.id, "rate_limited"));
}
