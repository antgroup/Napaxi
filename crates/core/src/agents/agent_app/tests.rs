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
fn registers_package_and_agent_definition() {
    let temp = tempfile::tempdir().unwrap();
    let files_dir = temp.path().to_string_lossy();
    let registered = register_package(&files_dir, &package_json());
    let package: AgentAppPackage = serde_json::from_str(&registered).unwrap();
    assert_eq!(package.agent_id, "provider.agent");
    assert!(super::super::get_definition(&files_dir, "provider.agent").is_some());
    let tools = descriptors_for_package(&package);
    assert_eq!(tools[0].name, "app_action_order_create");
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
