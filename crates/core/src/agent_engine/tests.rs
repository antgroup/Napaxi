use super::*;

#[test]
fn normalize_engine_id_accepts_codex_aliases() {
    assert_eq!(normalize_engine_id("codex"), CODEX_ENGINE_ID);
    assert_eq!(
        normalize_engine_id("napaxi.agent_engine.codex"),
        CODEX_ENGINE_ID
    );
}

#[tokio::test]
async fn external_host_turn_plan_preserves_raw_attachment_payload() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().join("files");
    let workspace_dir = dir.path().join("workspace-files");
    std::fs::create_dir_all(&files_dir).unwrap();
    std::fs::create_dir_all(&workspace_dir).unwrap();
    let source = dir.path().join("private-photo.png");
    std::fs::write(&source, b"png").unwrap();
    let mut config = crate::types::PlatformLlmConfig::default();
    config.capability_profile = crate::capabilities::CapabilityProfile {
        platform: Some("android".to_string()),
        supported_capabilities: vec![
            "napaxi.agent_engine.external_host".to_string(),
            "napaxi.tool.custom_host".to_string(),
        ],
        ..crate::capabilities::CapabilityProfile::default()
    };
    config.capability_selection = crate::capabilities::CapabilitySelection {
        enabled_capabilities: vec![
            "napaxi.agent_engine.external_host".to_string(),
            "napaxi.tool.custom_host".to_string(),
        ],
        ..crate::capabilities::CapabilitySelection::default()
    };
    let descriptor = ToolDescriptor {
        name: "custom_echo".to_string(),
        description: "Echo a value".to_string(),
        parameters: json!({"type":"object"}),
        effect: ToolEffect::External,
    };
    let tools = Arc::new(crate::tool_registry::ToolRegistry::new());
    assert!(tools.set_dispatcher(Arc::new(|_, _, _, _| {})));
    let config_json = serde_json::to_string(&config).unwrap();
    let session_key_json =
        crate::session::create_session(files_dir.to_str().unwrap(), "agent", "app", "acct", None);
    let attachments_json = format!(
        r#"[{{"kind":"image","mime_type":"image/png","filename":"photo.png","path":"{}"}}]"#,
        source.display()
    );
    let prepared = crate::turn::prepare_turn(
        files_dir.to_str().unwrap(),
        workspace_dir.to_str().unwrap(),
        &config_json,
        "agent",
        &session_key_json,
        "describe",
        None,
        &attachments_json,
        Some(&tools),
        std::slice::from_ref(&descriptor),
        false,
    )
    .await
    .expect("prepared turn");
    let selection = AgentEngineSelection {
        engine_id: "external_host".to_string(),
        engine_profile_id: "profile".to_string(),
        engine_config: json!({}),
    };

    let plan = external_host_turn_plan(
        Some(&selection),
        &prepared,
        Some(&tools),
        files_dir.to_str().unwrap(),
        workspace_dir.to_str().unwrap(),
        "agent",
        &session_key_json,
        "describe",
        &attachments_json,
        "{}",
    )
    .unwrap()
    .expect("external host plan");

    assert_eq!(plan.request.engine_id, EXTERNAL_HOST_ENGINE_ID);
    assert_eq!(plan.request.attachments_json, attachments_json);
    assert!(
        plan.request
            .attachments_json
            .contains(source.to_str().unwrap()),
        "legacy external-host engines keep receiving the raw adapter attachment payload"
    );
    assert!(
        codex_turn_plan(
            Some(&selection),
            &prepared,
            Some(&tools),
            None,
            files_dir.to_str().unwrap(),
            workspace_dir.to_str().unwrap(),
            "agent",
            &session_key_json,
            "describe",
            "{}",
        )
        .unwrap()
        .is_none(),
        "external-host selection must not be routed through the Codex planner"
    );
}

#[tokio::test]
async fn codex_turn_plan_uses_prepared_attachment_metadata_and_tools() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().join("files");
    let workspace_dir = dir.path().join("workspace-files");
    std::fs::create_dir_all(&files_dir).unwrap();
    std::fs::create_dir_all(&workspace_dir).unwrap();
    let source = dir.path().join("private-photo.png");
    std::fs::write(&source, b"png").unwrap();
    let mut config = crate::types::PlatformLlmConfig::default();
    config.capability_profile = crate::capabilities::CapabilityProfile {
        platform: Some("android".to_string()),
        supported_capabilities: vec![
            "napaxi.agent_engine.codex".to_string(),
            "napaxi.tool.custom_host".to_string(),
        ],
        ..crate::capabilities::CapabilityProfile::default()
    };
    config.capability_selection = crate::capabilities::CapabilitySelection {
        enabled_capabilities: vec![
            "napaxi.agent_engine.codex".to_string(),
            "napaxi.tool.custom_host".to_string(),
        ],
        ..crate::capabilities::CapabilitySelection::default()
    };
    let descriptor = ToolDescriptor {
        name: "custom_echo".to_string(),
        description: "Echo a value".to_string(),
        parameters: json!({"type":"object"}),
        effect: ToolEffect::External,
    };
    let config_json = serde_json::to_string(&config).unwrap();
    let session_key_json =
        crate::session::create_session(files_dir.to_str().unwrap(), "agent", "app", "acct", None);
    let thread_id = serde_json::from_str::<Value>(&session_key_json).unwrap()["thread_id"]
        .as_str()
        .unwrap()
        .to_string();
    let attachments_json = format!(
        r#"[{{"kind":"image","mime_type":"image/png","filename":"photo.png","path":"{}"}}]"#,
        source.display()
    );
    let prepared = crate::turn::prepare_turn(
        files_dir.to_str().unwrap(),
        workspace_dir.to_str().unwrap(),
        &config_json,
        "agent",
        &session_key_json,
        "describe",
        None,
        &attachments_json,
        None,
        std::slice::from_ref(&descriptor),
        false,
    )
    .await
    .expect("prepared turn");
    let selection = AgentEngineSelection {
        engine_id: "codex".to_string(),
        engine_profile_id: "profile".to_string(),
        engine_config: json!({"effort":"low"}),
    };

    let plan = codex_turn_plan(
        Some(&selection),
        &prepared,
        None,
        None,
        files_dir.to_str().unwrap(),
        workspace_dir.to_str().unwrap(),
        "agent",
        &session_key_json,
        "describe",
        "{}",
    )
    .unwrap()
    .expect("codex plan");
    let attachments: Value = serde_json::from_str(&plan.request.attachments_json).unwrap();

    assert_eq!(plan.request.engine_id, CODEX_ENGINE_ID);
    assert_eq!(plan.tool_descriptors, vec![descriptor]);
    let expected_sandbox_path = format!("/workspace/attachments/{thread_id}/photo.png");
    assert_eq!(
        attachments[0]["sandbox_path"].as_str(),
        Some(expected_sandbox_path.as_str())
    );
    assert!(
        attachments[0].get("path").is_none(),
        "Codex receives prepared workspace metadata, not raw host picker paths"
    );
}

#[tokio::test]
async fn codex_turn_plan_applies_agent_tool_allowlist_with_capability_ids() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().join("files");
    let workspace_dir = dir.path().join("workspace-files");
    std::fs::create_dir_all(&files_dir).unwrap();
    std::fs::create_dir_all(&workspace_dir).unwrap();
    let mut config = crate::types::PlatformLlmConfig::default();
    config.capability_profile = crate::capabilities::CapabilityProfile {
        platform: Some("android".to_string()),
        supported_capabilities: vec![
            "napaxi.agent_engine.codex".to_string(),
            "napaxi.tool.custom_host".to_string(),
            "napaxi.platform_tool.open_url".to_string(),
        ],
        ..crate::capabilities::CapabilityProfile::default()
    };
    config.capability_selection = crate::capabilities::CapabilitySelection {
        enabled_capabilities: vec![
            "napaxi.agent_engine.codex".to_string(),
            "napaxi.tool.custom_host".to_string(),
            "napaxi.platform_tool.open_url".to_string(),
        ],
        ..crate::capabilities::CapabilitySelection::default()
    };
    let custom = ToolDescriptor {
        name: "custom_ping".to_string(),
        description: "Ping host".to_string(),
        parameters: json!({"type":"object"}),
        effect: ToolEffect::External,
    };
    let platform = ToolDescriptor {
        name: "open_url".to_string(),
        description: "Open URL".to_string(),
        parameters: json!({"type":"object"}),
        effect: ToolEffect::External,
    };
    let config_json = serde_json::to_string(&config).unwrap();
    let agent_id = "codex-filter-agent";
    let mut definition = crate::agent_definitions::AgentDefinition::new(
        "codex filter".to_string(),
        "model".to_string(),
    );
    definition.id = agent_id.to_string();
    definition.engine_id = "codex".to_string();
    definition.tool_filter = crate::agent_definitions::ToolFilter::Allowlist(vec![
        "custom_ping".to_string(),
        "napaxi.platform_tool.open_url".to_string(),
    ]);
    crate::agents::create_definition_value(files_dir.to_str().unwrap(), definition);
    let session_key_json =
        crate::session::create_session(files_dir.to_str().unwrap(), agent_id, "app", "acct", None);
    let prepared = crate::turn::prepare_turn(
        files_dir.to_str().unwrap(),
        workspace_dir.to_str().unwrap(),
        &config_json,
        agent_id,
        &session_key_json,
        "probe",
        None,
        "[]",
        None,
        &[custom.clone(), platform.clone()],
        false,
    )
    .await
    .expect("prepared turn");
    let blocked = ToolDescriptor {
        name: "blocked_tool".to_string(),
        description: "Should not be advertised".to_string(),
        parameters: json!({"type":"object"}),
        effect: ToolEffect::External,
    };
    let mut prepared = prepared;
    prepared.tool_descriptors.push(blocked);
    let selection = AgentEngineSelection {
        engine_id: "codex".to_string(),
        engine_profile_id: "profile".to_string(),
        engine_config: json!({}),
    };

    let plan = codex_turn_plan(
        Some(&selection),
        &prepared,
        None,
        None,
        files_dir.to_str().unwrap(),
        workspace_dir.to_str().unwrap(),
        agent_id,
        &session_key_json,
        "probe",
        "{}",
    )
    .unwrap()
    .expect("codex plan");
    let names: Vec<_> = plan
        .tool_descriptors
        .iter()
        .map(|descriptor| descriptor.name.as_str())
        .collect();

    assert_eq!(names, vec!["custom_ping", "open_url"]);
}

#[test]
fn run_event_maps_host_completed_event_to_chat_event() {
    let raw = json!({
        "run_id": "run-1",
        "event": {
            "type": "completed",
            "status": "completed",
            "tool_call_count": 2
        }
    })
    .to_string();

    let decoded: Value = serde_json::from_str(&run_event_json(&raw)).unwrap();
    assert_eq!(decoded["completed"], true);
    assert_eq!(decoded["is_error"], false);
    assert_eq!(decoded["event"]["type"], "run_completed");
    assert_eq!(decoded["event"]["run_id"], "run-1");
    assert_eq!(decoded["event"]["evidence_kind"], "agent_engine");
    assert_eq!(decoded["event"]["verification"], "host_reported");
    assert_eq!(decoded["event"]["tool_call_count"], 2);
}

#[test]
fn run_event_accepts_object_tool_call_arguments() {
    let raw = json!({
        "run_id": "run-1",
        "event": {
            "type": "tool_call",
            "call_id": "call-1",
            "name": "shell",
            "arguments": {"cmd": "pwd"}
        }
    })
    .to_string();

    let decoded: Value = serde_json::from_str(&run_event_json(&raw)).unwrap();
    assert_eq!(decoded["event"]["type"], "tool_call");
    assert_eq!(decoded["event"]["arguments"], r#"{"cmd":"pwd"}"#);
}

#[test]
fn host_turn_event_decoder_uses_run_event_protocol() {
    let events = decode_host_events(
        "run-2",
        &json!({
            "events": [
                {"type": "thinking", "content": "planning"},
                {"type": "completed"}
            ]
        })
        .to_string(),
    );

    assert!(matches!(
        events.first(),
        Some(ChatEvent::Thinking { content }) if content == "planning"
    ));
    assert!(matches!(
        events.get(1),
        Some(ChatEvent::RunCompleted { run_id, evidence_kind, .. })
            if run_id == "run-2" && evidence_kind == "agent_engine"
    ));
}

#[tokio::test]
async fn tool_broker_list_respects_tool_capability_selection() {
    let dir = tempfile::tempdir().unwrap();
    let config = crate::types::PlatformLlmConfig {
        provider: "test".to_string(),
        api_key: "test".to_string(),
        model: "test-model".to_string(),
        ..crate::types::PlatformLlmConfig::default()
    };
    let config_json = serde_json::to_string(&config).unwrap();
    let context_json = json!({
        "platform": "test",
        "files_dir": dir.path().to_str().unwrap(),
        "native_library_dir": null,
        "capability_selection": {
            "disabled_capabilities": ["napaxi.tool.shell"]
        }
    })
    .to_string();
    let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { crate::runtime::handle_to_arc(handle) }.unwrap();
    let merged_config = engine.config_with_capabilities(engine.config());
    assert!(
        merged_config
            .capability_selection
            .disabled_capabilities
            .contains(&"napaxi.tool.shell".to_string())
    );
    drop(engine);

    let raw = list_tools_json_handle(handle, "{}").await;
    let tools: Vec<crate::tool_registry::ToolDescriptor> = serde_json::from_str(&raw).unwrap();
    assert!(
        !tools.iter().any(|tool| tool.name == "shell"),
        "disabled shell capability must not be listed for external engines"
    );

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[tokio::test]
async fn tool_broker_shell_call_uses_existing_approval_policy() {
    let dir = tempfile::tempdir().unwrap();
    let config = crate::types::PlatformLlmConfig {
        provider: "test".to_string(),
        api_key: "test".to_string(),
        model: "test-model".to_string(),
        ..crate::types::PlatformLlmConfig::default()
    };
    let config_json = serde_json::to_string(&config).unwrap();
    let context_json = json!({
        "platform": "test",
        "files_dir": dir.path().to_str().unwrap(),
        "native_library_dir": null
    })
    .to_string();
    let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();

    let raw = call_tool_json_handle(
        handle,
        &json!({
            "call_id": "call-1",
            "name": "shell",
            "arguments": {
                "cmd": "git push --force origin main"
            }
        })
        .to_string(),
    )
    .await;
    let result: Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(result["is_error"], true);
    assert!(
        result["output"]
            .as_str()
            .unwrap_or_default()
            .contains("approval"),
        "expected shell approval policy error, got {result}"
    );

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}
