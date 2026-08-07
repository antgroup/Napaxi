//! Behavioral coverage for the Agent App runtime: package registration,
//! action proposals, signing, persistence, and triggers.

use super::*;

fn package_json() -> String {
    json!({
        "provider_id": "provider",
        "agent_id": "provider.agent",
        "display_name": "Provider Agent",
        "description": "Provider-backed agent",
        "system_prompt": "You are a provider agent.",
        "actions": [{
            "action_id": "provider.order.create",
            "tool_name": "app_action_order_create",
            "description": "Create an order proposal.",
            "parameters": {
                "type": "object",
                "properties": {
                    "amount": {"type": "number"}
                },
                "required": ["amount"]
            },
            "result_schema": {"type": "object"},
            "risk": "high",
            "confirmation_policy": "provider_required",
            "execution_modes": ["app_handoff"],
            "timeout_seconds": 600
        }],
        "handoff": {"mode": "app_handoff"},
        "result": {"mode": "callback"}
    })
    .to_string()
}

#[test]
fn registers_provider_without_creating_switchable_agent_definition() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let registered = register_package(&files_dir, &package_json());
    let package: AgentAppPackage = serde_json::from_str(&registered).unwrap();
    assert_eq!(package.agent_id, "provider.agent");
    assert!(super::super::get_definition(&files_dir, "provider.agent").is_none());
    assert!(get_package_json(&files_dir, "provider").contains("provider.agent"));
    assert!(get_package_json(&files_dir, "provider.agent").contains("provider.agent"));
    let tools = descriptors_for_package(&package);
    assert_eq!(tools[0].name, "app_action_order_create");
}

#[test]
fn provider_cannot_enable_automatic_invocation_during_registration() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut manifest: Value = serde_json::from_str(&package_json()).unwrap();
    manifest["auto_invoke_enabled"] = json!(true);
    manifest["last_used_at"] = json!("2099-01-01T00:00:00Z");
    manifest["use_count"] = json!(99);

    let package: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &manifest.to_string())).unwrap();

    assert!(!package.auto_invoke_enabled);
    assert!(package.last_used_at.is_empty());
    assert_eq!(package.use_count, 0);
}

#[test]
fn legacy_provider_confirmation_policy_is_normalized_fail_closed() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut manifest: Value = serde_json::from_str(&package_json()).unwrap();
    manifest["actions"][0]["risk"] = json!("medium");
    manifest["actions"][0]["confirmation_policy"] = json!("provider");

    let package: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &manifest.to_string())).unwrap();

    assert_eq!(package.actions[0].confirmation_policy, "provider_required");
}

#[test]
fn unsupported_confirmation_policy_is_rejected() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut manifest: Value = serde_json::from_str(&package_json()).unwrap();
    manifest["actions"][0]["confirmation_policy"] = json!("host_optional");

    let error = register_package(&files_dir, &manifest.to_string());

    assert!(error.contains("unsupported value 'host_optional'"));
}

#[test]
fn resolves_canonical_and_display_name_provider_mentions() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();

    let canonical =
        resolve_explicit_provider_message(&files_dir, "@{provider:provider} create an order")
            .unwrap()
            .unwrap();
    assert_eq!(canonical.provider_id, "provider");
    assert_eq!(canonical.message, "create an order");
    assert_eq!(canonical.display_message, "@Provider Agent create an order");

    let display =
        resolve_explicit_provider_message(&files_dir, "@Provider Agent: create another order")
            .unwrap()
            .unwrap();
    assert_eq!(display.provider_id, "provider");
    assert_eq!(display.message, "create another order");

    let used: AgentAppPackage =
        serde_json::from_str(&get_package_json(&files_dir, "provider")).unwrap();
    assert_eq!(used.use_count, 2);
    assert!(!used.last_used_at.is_empty());

    assert!(
        resolve_explicit_provider_message(&files_dir, "@someone hello")
            .unwrap()
            .is_none()
    );
}

#[test]
fn duplicate_display_name_is_ambiguous_but_canonical_provider_id_is_stable() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();
    let mut duplicate: Value = serde_json::from_str(&package_json()).unwrap();
    duplicate["provider_id"] = json!("provider.other");
    duplicate["agent_id"] = json!("provider.other.agent");
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &duplicate.to_string())).unwrap();

    let ambiguous =
        resolve_explicit_provider_message(&files_dir, "@Provider Agent create an order")
            .unwrap_err();
    assert_eq!(
        ambiguous,
        ExplicitProviderSelectionError::AmbiguousName {
            label: "Provider Agent".to_string(),
            provider_ids: vec!["provider".to_string(), "provider.other".to_string()],
        }
    );

    let canonical =
        resolve_explicit_provider_message(&files_dir, "@{provider:provider.other} create an order")
            .unwrap()
            .unwrap();
    assert_eq!(canonical.provider_id, "provider.other");

    assert_eq!(
        resolve_explicit_provider_message(&files_dir, "@{provider:missing} create an order")
            .unwrap_err(),
        ExplicitProviderSelectionError::ProviderNotFound {
            provider_id: "missing".to_string(),
        }
    );
}

#[tokio::test]
async fn ambiguous_display_name_returns_chat_error_before_model_execution() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let config = json!({
        "provider": "openai",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context = json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null
    })
    .to_string();
    let handle = crate::runtime::create_engine_handle(&config, &context).unwrap();
    let _ = register_package_handle(handle, &package_json());
    let mut duplicate: Value = serde_json::from_str(&package_json()).unwrap();
    duplicate["provider_id"] = json!("provider.other");
    duplicate["agent_id"] = json!("provider.other.agent");
    let _ = register_package_handle(handle, &duplicate.to_string());
    let session = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

    let events = crate::runtime::send_to_session_events_handle(
        handle,
        &config,
        "napaxi",
        &session,
        "@Provider Agent create an order",
        "[]",
        0,
        false,
    )
    .await;

    assert_eq!(events.len(), 1);
    assert!(events[0].contains("ambiguous"));
    assert!(events[0].contains("provider.other"));

    let unknown = crate::runtime::send_to_session_events_handle(
        handle,
        &config,
        "napaxi",
        &session,
        "@{provider:missing} create an order",
        "[]",
        0,
        false,
    )
    .await;
    assert_eq!(unknown.len(), 1);
    assert!(unknown[0].contains("not installed or enabled"));
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn migrates_legacy_agent_keyed_package_and_generated_definition() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let package: AgentAppPackage = serde_json::from_str(&package_json()).unwrap();
    let legacy_path = persistence::package_file(&files_dir, &package.agent_id);
    std::fs::create_dir_all(legacy_path.parent().unwrap()).unwrap();
    std::fs::write(
        &legacy_path,
        serde_json::to_string_pretty(&package).unwrap(),
    )
    .unwrap();

    let mut definition =
        crate::agent_definitions::AgentDefinition::new(package.display_name.clone(), String::new());
    definition.id = package.agent_id.clone();
    definition.description = package.description.clone();
    definition.provider = String::new();
    definition.model = String::new();
    definition.system_prompt = package.system_prompt.clone();
    definition.tool_filter = crate::agent_definitions::ToolFilter::AllTools;
    definition.source = crate::agent_definitions::AgentSource::UserCreated;
    let _ = super::super::create_definition_value(&files_dir, definition);

    let listed: Vec<AgentAppPackage> =
        serde_json::from_str(&list_packages_json(&files_dir)).unwrap();

    assert_eq!(listed.len(), 1);
    assert!(persistence::package_file(&files_dir, &package.provider_id).exists());
    assert!(!legacy_path.exists());
    assert!(super::super::get_definition(&files_dir, &package.agent_id).is_none());
}

#[test]
fn migration_does_not_delete_a_distinct_user_agent_with_same_legacy_id() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut definition = crate::agent_definitions::AgentDefinition::new(
        "My custom Agent".to_string(),
        "custom-model".to_string(),
    );
    definition.id = "provider.agent".to_string();
    let _ = super::super::create_definition_value(&files_dir, definition);

    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();

    let preserved = super::super::get_definition(&files_dir, "provider.agent").unwrap();
    assert_eq!(preserved.name, "My custom Agent");
    assert_eq!(preserved.model, "custom-model");
}

#[test]
fn explicitly_selected_provider_exposes_actions_to_default_agent() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();

    let (without_selection, _) = action_tools_and_handler_for_provider(
        &files_dir,
        "engine.codex",
        None,
        Some(ToolRequestBridge::process_scoped(Arc::new(|_, _, _, _| {}))),
        None,
    );
    assert!(without_selection.is_empty());

    let (with_selection, _) = action_tools_and_handler_for_provider(
        &files_dir,
        "engine.codex",
        Some("provider"),
        Some(ToolRequestBridge::process_scoped(Arc::new(|_, _, _, _| {}))),
        None,
    );
    assert_eq!(with_selection.len(), 1);
    assert_eq!(with_selection[0].name, "app_action_order_create");

    let enabled: AgentAppPackage =
        serde_json::from_str(&set_auto_invoke(&files_dir, "provider", true)).unwrap();
    assert!(enabled.auto_invoke_enabled);
    let (automatic, _) = action_tools_and_handler_for_provider(
        &files_dir,
        "engine.codex",
        None,
        Some(ToolRequestBridge::process_scoped(Arc::new(|_, _, _, _| {}))),
        None,
    );
    assert_eq!(automatic.len(), 1);
    assert_eq!(automatic[0].name, "app_action_order_create");

    let disabled: AgentAppPackage =
        serde_json::from_str(&set_auto_invoke(&files_dir, "provider", false)).unwrap();
    assert!(!disabled.auto_invoke_enabled);
}

#[test]
fn trusted_manifest_refresh_preserves_host_owned_auto_invoke_state() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();
    let _: AgentAppPackage =
        serde_json::from_str(&set_auto_invoke(&files_dir, "provider", true)).unwrap();

    let mut refreshed: Value = serde_json::from_str(&package_json()).unwrap();
    refreshed["actions"].as_array_mut().unwrap().push(json!({
        "action_id": "order.cancel",
        "tool_name": "app_action_order_cancel",
        "description": "Cancel an order."
    }));
    refreshed["install_binding"] = json!({
        "platform": "android",
        "app_package_name": "com.provider.app",
        "activity_name": "com.provider.app.AgentActionActivity",
        "signing_cert_sha256": "provider123",
        "app_version_code": 2,
        "app_last_update_time_ms": 123456,
        "trusted_refresh_supported": true,
        "installed_at": "2026-08-05T00:00:00Z",
        "install_request_id": "refresh-2",
        "protocol_version": 2
    });

    let registered: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &refreshed.to_string())).unwrap();

    assert!(registered.auto_invoke_enabled);
    assert_eq!(registered.actions.len(), 2);
    let binding = registered.install_binding.unwrap();
    assert_eq!(binding.app_version_code, 2);
    assert!(binding.trusted_refresh_supported);
}

#[test]
fn automatic_invocation_rejects_cross_provider_tool_name_collisions() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();
    let _: AgentAppPackage =
        serde_json::from_str(&set_auto_invoke(&files_dir, "provider", true)).unwrap();

    let mut duplicate: Value = serde_json::from_str(&package_json()).unwrap();
    duplicate["provider_id"] = json!("provider.other");
    duplicate["agent_id"] = json!("provider.other.agent");
    duplicate["display_name"] = json!("Other Provider");
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &duplicate.to_string())).unwrap();

    let error = set_auto_invoke(&files_dir, "provider.other", true);
    assert!(error.contains("conflicts"));
    let other: AgentAppPackage =
        serde_json::from_str(&get_package_json(&files_dir, "provider.other")).unwrap();
    assert!(!other.auto_invoke_enabled);
}

#[test]
fn generated_cross_domain_examples_are_valid_provider_packages() {
    let notes_raw = include_str!(
        "../../../../../examples/provider_app/android_generated_notes/app/src/main/assets/agent-app.json"
    );
    let tasks_raw = include_str!(
        "../../../../../examples/provider_app/android_generated_tasks/app/src/main/assets/agent-app.json"
    );
    let notes: AgentAppPackage = prepare_package(serde_json::from_str(notes_raw).unwrap()).unwrap();
    let tasks: AgentAppPackage = prepare_package(serde_json::from_str(tasks_raw).unwrap()).unwrap();

    assert_eq!(notes.provider_id, "demo.generated_notes_provider");
    assert_eq!(notes.actions.len(), 5);
    let note_delete = notes
        .actions
        .iter()
        .find(|action| action.action_id == "note.delete")
        .unwrap();
    assert_eq!(note_delete.risk, "high");
    assert_eq!(note_delete.confirmation_policy, "provider_required");

    assert_eq!(tasks.provider_id, "demo.generated_tasks_provider");
    assert_eq!(tasks.actions.len(), 4);
    assert!(
        tasks
            .actions
            .iter()
            .all(|action| action.action_id.starts_with("task."))
    );
    let task_delete = tasks
        .actions
        .iter()
        .find(|action| action.action_id == "task.delete")
        .unwrap();
    assert_eq!(task_delete.risk, "high");
    assert_eq!(task_delete.confirmation_policy, "provider_required");
}

#[tokio::test]
async fn selected_provider_action_completes_proposal_result_round_trip() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy().to_string();
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();
    let dispatcher: crate::tool_registry::ToolRequestDispatcher =
        Arc::new(|request_id, tool_name, params_json, _context| {
            assert_eq!(tool_name, ACTION_DISPATCH_TOOL_NAME);
            let payload: Value = serde_json::from_str(params_json).unwrap();
            let proposal_request_id = payload["proposal"]["request_id"].as_str().unwrap();
            let result = json!({
                "request_id": proposal_request_id,
                "status": "succeeded",
                "result": {"note_id": "note-1"},
                "completed_at": now()
            });
            assert!(crate::tool_registry::resolve_tool_execution(
                request_id,
                result.to_string(),
                false,
            ));
        });
    let (_, handler) = action_tools_and_handler_for_provider(
        &files_dir,
        "napaxi",
        Some("provider"),
        Some(ToolRequestBridge::process_scoped(dispatcher)),
        None,
    );

    let output = handler.unwrap()("app_action_order_create", json!({"amount": 12}), None)
        .unwrap()
        .await
        .unwrap();

    assert!(output.output.contains("note-1"));
    assert!(output.events.iter().any(|event| matches!(
        event,
        ChatEvent::ActionResultReceived { status, .. } if status == "succeeded"
    )));
    let records: Value = serde_json::from_str(&list_proposals_json(&files_dir, "")).unwrap();
    assert_eq!(records[0]["status"], "succeeded");
}

#[test]
fn package_install_binding_round_trips() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut value: Value = serde_json::from_str(&package_json()).unwrap();
    value["install_binding"] = json!({
        "platform": "android",
        "app_package_name": "com.provider.app",
        "activity_name": "com.provider.app.AgentActionActivity",
        "signing_cert_sha256": "abc123",
        "installed_at": "2026-05-26T00:00:00Z",
        "install_request_id": "install-1",
        "protocol_version": 1
    });

    let registered = register_package(&files_dir, &value.to_string());
    let package: AgentAppPackage = serde_json::from_str(&registered).unwrap();

    let binding = package.install_binding.unwrap();
    assert_eq!(binding.platform, "android");
    assert_eq!(binding.app_package_name, "com.provider.app");
    assert_eq!(
        binding.activity_name,
        "com.provider.app.AgentActionActivity"
    );
    assert!(get_package_json(&files_dir, "provider.agent").contains("install_binding"));
}

#[test]
fn ios_package_install_binding_round_trips() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut value: Value = serde_json::from_str(&package_json()).unwrap();
    value["install_binding"] = json!({
        "platform": "ios",
        "app_package_name": "",
        "activity_name": "",
        "signing_cert_sha256": "",
        "installed_at": "2026-05-26T00:00:00Z",
        "install_request_id": "install-ios-1",
        "protocol_version": 2,
        "ios_bundle_id": "demo.wallet.provider",
        "ios_team_id": "TEAM123456",
        "install_url": "https://wallet.example.com/agent/install",
        "action_url": "https://wallet.example.com/agent/action",
        "universal_link_domain": "wallet.example.com",
        "host_bundle_id": "host.app",
        "host_team_id": "HOST123456",
        "host_callback_scheme": "agent-host",
        "host_instance_id": "host-instance-1",
        "host_shared_secret": "secret-1"
    });

    let registered = register_package(&files_dir, &value.to_string());
    let package: AgentAppPackage = serde_json::from_str(&registered).unwrap();

    let binding = package.install_binding.unwrap();
    assert_eq!(binding.platform, "ios");
    assert_eq!(binding.ios_bundle_id, "demo.wallet.provider");
    assert_eq!(
        binding.install_url,
        "https://wallet.example.com/agent/install"
    );
    assert_eq!(
        binding.action_url,
        "https://wallet.example.com/agent/action"
    );
    assert_eq!(binding.host_callback_scheme, "agent-host");
}

#[test]
fn signed_proposal_uses_trusted_install_binding() {
    let mut package: AgentAppPackage = serde_json::from_str(&package_json()).unwrap();
    package.install_binding = Some(AgentAppInstallBinding {
        platform: "android".to_string(),
        app_package_name: "com.provider.app".to_string(),
        activity_name: "com.provider.app.AgentActionActivity".to_string(),
        signing_cert_sha256: "provider123".to_string(),
        app_version_code: 1,
        app_last_update_time_ms: 0,
        trusted_refresh_supported: true,
        installed_at: "2026-05-26T00:00:00Z".to_string(),
        install_request_id: "install-1".to_string(),
        protocol_version: 2,
        host_package_name: "com.host.app".to_string(),
        host_signing_cert_sha256: "host123".to_string(),
        host_instance_id: "host-instance-1".to_string(),
        host_shared_secret: "secret-1".to_string(),
        ios_bundle_id: String::new(),
        ios_team_id: String::new(),
        install_url: String::new(),
        action_url: String::new(),
        universal_link_domain: String::new(),
        host_bundle_id: String::new(),
        host_team_id: String::new(),
        host_callback_scheme: String::new(),
        background_trigger_supported: false,
        host_background_trigger_service: String::new(),
    });

    let proposal = create_proposal(&package, &package.actions[0], json!({"amount": 12.5}));

    assert_eq!(proposal.host_instance_id, "host-instance-1");
    assert_eq!(
        proposal.signature_algorithm,
        SIGNATURE_ALGORITHM_HMAC_SHA256_V1
    );
    assert!(proposal.signature.is_some());
}

#[test]
fn public_dispatch_payload_strips_trust_secret_for_ios_binding() {
    let mut package: AgentAppPackage = serde_json::from_str(&package_json()).unwrap();
    package.install_binding = Some(AgentAppInstallBinding {
        platform: "ios".to_string(),
        app_package_name: String::new(),
        activity_name: String::new(),
        signing_cert_sha256: String::new(),
        app_version_code: 0,
        app_last_update_time_ms: 0,
        trusted_refresh_supported: false,
        installed_at: "2026-05-26T00:00:00Z".to_string(),
        install_request_id: "install-ios-1".to_string(),
        protocol_version: 2,
        host_package_name: String::new(),
        host_signing_cert_sha256: String::new(),
        host_instance_id: "host-instance-1".to_string(),
        host_shared_secret: "secret-1".to_string(),
        ios_bundle_id: "demo.wallet.provider".to_string(),
        ios_team_id: "TEAM123456".to_string(),
        install_url: "https://wallet.example.com/agent/install".to_string(),
        action_url: "https://wallet.example.com/agent/action".to_string(),
        universal_link_domain: "wallet.example.com".to_string(),
        host_bundle_id: "host.app".to_string(),
        host_team_id: "HOST123456".to_string(),
        host_callback_scheme: "agent-host".to_string(),
        background_trigger_supported: false,
        host_background_trigger_service: String::new(),
    });

    let binding = public_install_binding(package.install_binding.as_ref());

    assert_eq!(binding["platform"].as_str(), Some("ios"));
    assert_eq!(
        binding["action_url"].as_str(),
        Some("https://wallet.example.com/agent/action")
    );
    assert!(binding["host_shared_secret"].is_null());
}

#[test]
fn rejects_non_reserved_tool_name() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut value: Value = serde_json::from_str(&package_json()).unwrap();
    value["actions"][0]["tool_name"] = json!("order_create");
    let response = register_package(&files_dir, &value.to_string());
    assert!(response.contains("must start"));
}

#[test]
fn stores_and_updates_proposal_result() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let package: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &package_json())).unwrap();
    let proposal = create_proposal(&package, &package.actions[0], json!({"amount": 12.5}));
    persist_proposal(&files_dir, &proposal).unwrap();
    let result = ActionResult {
        request_id: proposal.request_id.clone(),
        status: "succeeded".to_string(),
        result: json!({"ok": true}),
        error: None,
        provider_trace_id: Some("trace".to_string()),
        completed_at: now(),
        signature: None,
    };
    let response = submit_result(&files_dir, &serde_json::to_string(&result).unwrap());
    assert!(response.contains("\"succeeded\""));
    assert!(get_proposal_json(&files_dir, &proposal.request_id).contains("\"trace\""));
    let duplicate = submit_result(&files_dir, &serde_json::to_string(&result).unwrap());
    assert!(duplicate.contains("already completed"));
}

#[test]
fn action_result_accepts_structured_provider_error() {
    let result: ActionResult = serde_json::from_value(json!({
        "request_id": "request-1",
        "status": "failed",
        "result": {},
        "error": {
            "code": "host_not_bound",
            "message": "No trusted Host binding exists.",
            "phase": "pre_execution",
            "retryable": true
        },
        "completed_at": "2026-08-05T00:00:00Z"
    }))
    .unwrap();

    assert_eq!(
        result.error.as_deref(),
        Some("host_not_bound: No trusted Host binding exists.")
    );
}

#[test]
fn accepts_signed_agent_trigger_and_rejects_replay() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut value: Value = serde_json::from_str(&package_json()).unwrap();
    value["install_binding"] = json!({
        "platform": "android",
        "app_package_name": "com.provider.app",
        "activity_name": "com.provider.app.AgentActionActivity",
        "signing_cert_sha256": "provider123",
        "installed_at": "2026-05-27T00:00:00Z",
        "install_request_id": "install-1",
        "protocol_version": 2,
        "host_package_name": "com.host.app",
        "host_signing_cert_sha256": "host123",
        "host_instance_id": "host-instance-1",
        "host_shared_secret": "secret-1"
    });
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &value.to_string())).unwrap();
    let mut trigger = AgentTriggerRequest {
        protocol_version: 2,
        request_id: "trigger-1".to_string(),
        provider_id: "provider".to_string(),
        agent_id: "provider.agent".to_string(),
        message: "Desk button pressed.".to_string(),
        source: "virtual_sensor".to_string(),
        event_type: "button_pressed".to_string(),
        payload: json!({"button": "desk"}),
        created_at: "2026-05-27T00:00:00Z".to_string(),
        expires_at: "2030-01-01T00:00:00Z".to_string(),
        nonce: "nonce-trigger".to_string(),
        idempotency_key: "trigger-1".to_string(),
        host_instance_id: "host-instance-1".to_string(),
        signature_algorithm: SIGNATURE_ALGORITHM_HMAC_SHA256_V1.to_string(),
        signature: None,
    };
    trigger.signature = Some(hmac_sha256_base64_no_pad(
        b"secret-1",
        trigger_signature_payload(&trigger).as_bytes(),
    ));
    let trigger_json = serde_json::to_string(&trigger).unwrap();

    let accepted = accept_trigger(&files_dir, &trigger_json);
    assert!(accepted.contains("\"accepted\""));

    let replay = accept_trigger(&files_dir, &trigger_json);
    assert!(replay.contains("already consumed"));
}

#[test]
fn rejects_tampered_agent_trigger_signature() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let mut value: Value = serde_json::from_str(&package_json()).unwrap();
    value["install_binding"] = json!({
        "platform": "android",
        "app_package_name": "com.provider.app",
        "activity_name": "com.provider.app.AgentActionActivity",
        "signing_cert_sha256": "provider123",
        "installed_at": "2026-05-27T00:00:00Z",
        "install_request_id": "install-1",
        "protocol_version": 2,
        "host_instance_id": "host-instance-1",
        "host_shared_secret": "secret-1"
    });
    let _: AgentAppPackage =
        serde_json::from_str(&register_package(&files_dir, &value.to_string())).unwrap();
    let trigger = json!({
        "protocol_version": 2,
        "request_id": "trigger-2",
        "provider_id": "provider",
        "agent_id": "provider.agent",
        "message": "tampered",
        "source": "virtual_sensor",
        "event_type": "button_pressed",
        "payload": {"button": "desk"},
        "created_at": "2026-05-27T00:00:00Z",
        "expires_at": "2030-01-01T00:00:00Z",
        "nonce": "nonce-trigger",
        "idempotency_key": "trigger-2",
        "host_instance_id": "host-instance-1",
        "signature_algorithm": SIGNATURE_ALGORITHM_HMAC_SHA256_V1,
        "signature": "bad"
    });

    let rejected = accept_trigger(&files_dir, &trigger.to_string());

    assert!(rejected.contains("signature is invalid"));
}
