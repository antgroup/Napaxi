use chrono::{SecondsFormat, Utc};
use serde_json::{Value, json};

use super::types::{
    A2ADeliveryRecord, A2ADeliveryStatus, A2AMessageKind, A2APeer, A2APeerMessage, A2APeerSession,
    A2AResultLink, A2ATaskRecord, A2ATaskStatus, A2ATaskTrust,
};
use super::*;

fn engine_handle(files_dir: &str) -> i64 {
    let config_json = json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context_json = json!({
    "platform": "test",
        "files_dir": files_dir,
        "capability_profile": {
            "platform": "test",
            "supported_capabilities": ["napaxi.a2a.deeplink", "napaxi.a2a.local"]
        },
        "capability_selection": {
            "enabled_capabilities": ["napaxi.a2a.deeplink", "napaxi.a2a.local"]
        }
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

fn future_iso() -> String {
    (Utc::now() + chrono::Duration::minutes(30)).to_rfc3339_opts(SecondsFormat::Millis, true)
}

#[test]
fn a2a_service_surface_is_behind_the_policy_chain() {
    // The A2A intake surface (deep-link / peer-invite / run-task) now runs the
    // capability admission chain before doing any work, so a host policy can
    // deny the whole service — not just the tools a task later spins up. This
    // closes the "Service capabilities are declared but not gated" gap.
    //
    // The hook chain is process-global and tests run in parallel, so we must
    // NOT install a deny for the real `a2a.deeplink.accept` subject (other
    // deep-link tests hit it concurrently). Instead the hook only OBSERVES
    // (into a test-local atomic) and always Allows — proving the gate is wired
    // without affecting any concurrent admission. The deny short-circuit
    // itself is covered by the capabilities policy-hook tests.
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};

    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);

    let observed = Arc::new(AtomicBool::new(false));
    let observed_in_hook = Arc::clone(&observed);
    let hook: crate::capabilities::CapabilityPolicyHook = Arc::new(
        move |admission: &crate::capabilities::CapabilityAdmission| {
            if admission.kind == crate::capabilities::CapabilityAdmissionKind::Service
                && admission.capability_id.as_deref() == Some(A2A_DEEPLINK_CAPABILITY_ID)
            {
                observed_in_hook.store(true, Ordering::SeqCst);
            }
            crate::capabilities::CapabilityAdmissionDecision::Allow
        },
    );

    {
        let _guard = crate::capabilities::register_policy_hook(hook);
        // A malformed envelope is fine: the gate fires before parsing, so the
        // observer sees the Service admission regardless of envelope validity.
        let _ = accept_deep_link_handle(handle, "{}", "deep_link");
    }

    assert!(
        observed.load(Ordering::SeqCst),
        "deep-link intake must run the Service admission gate before doing work"
    );

    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn a2a_intake_is_rejected_when_capability_not_enabled() {
    // A2A is Host-activation + default_enabled:false. On a host that neither
    // declares support nor enables the capability (and registers no policy
    // hook), the Service surface must stay CLOSED — not fail open. This is the
    // require_enabled half of the gate that admit_service alone skipped.
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let config_json = json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    // Empty capability profile/selection: nothing supported, nothing enabled.
    let context_json = json!({
        "platform": "test",
        "files_dir": files_dir,
        "capability_profile": { "platform": "test" },
        "capability_selection": {}
    })
    .to_string();
    let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();

    let result = accept_deep_link_handle(handle, "{}", "deep_link");
    assert!(
        result.contains("error"),
        "deep-link intake must be rejected when A2A capability is not enabled, got: {result}"
    );

    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn peer_task_denied_capabilities_cover_workspace_and_egress() {
    // Confused-deputy guard: a peer-driven task must not be able to read/leak
    // the owner's workspace or poison memory. The deny list must cover the
    // egress tools AND the workspace-read / memory-write / fetch surface.
    let denied = super::peer_task_denied_capabilities();
    for required in [
        "napaxi.tool.shell",
        "napaxi.tool.http",
        "napaxi.tool.agent_app_action",
        "napaxi.tool.file",
        "napaxi.tool.memory",
        "napaxi.tool.web_fetch",
        "napaxi.tool.web_search",
        "napaxi.tool.skill",
    ] {
        assert!(
            denied.contains(&required),
            "peer task deny list must include {required}"
        );
    }
}

fn task_envelope() -> Value {
    json!({
        "protocolVersion": 1,
        "envelopeId": "env-1",
        "kind": "task_request",
        "sender": {
            "agentId": "sender.agent",
            "peerId": "peer-1",
            "displayName": "Sender",
            "deepLinkUrl": "agent-sender://a2a/task"
        },
        "recipient": {"agentId": "receiver.agent"},
        "task": {
            "taskId": "task-1",
            "message": "Summarize this",
            "sessionMode": "isolated"
        },
        "callback": {"deepLinkUrl": "agent-sender://a2a/result"},
        "createdAt": now(),
        "expiresAt": future_iso(),
        "nonce": "nonce-1",
        "idempotencyKey": "idem-1"
    })
}

#[test]
fn untrusted_task_is_persisted_pending_confirmation() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let accepted = accept_deep_link_handle(handle, &task_envelope().to_string(), "deep_link");
    let task: A2ATaskRecord = serde_json::from_str(&accepted).unwrap();
    assert_eq!(task.task_id, "task-1");
    assert!(matches!(
        task.status,
        A2ATaskStatus::PendingUserConfirmation
    ));
    assert!(matches!(task.trust, A2ATaskTrust::Untrusted));
    assert!(
        crate::agent_runtime::domain_dir(&temp.path().to_string_lossy(), "a2a")
            .join("tasks/task-1.json")
            .exists()
    );
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn duplicate_idempotency_is_rejected() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let envelope = task_envelope().to_string();
    let first: Value =
        serde_json::from_str(&accept_deep_link_handle(handle, &envelope, "deep_link")).unwrap();
    assert!(first.get("error").and_then(Value::as_str).is_none());
    assert!(accept_deep_link_handle(handle, &envelope, "deep_link").contains("already consumed"));
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn peer_invite_acceptance_persists_peer() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let invite = create_peer_invite_handle(handle, "receiver.agent", "{}");
    let invite_value: Value = serde_json::from_str(&invite).unwrap();
    let envelope = invite_value["envelope"].to_string();
    let peer_json = accept_peer_invite_handle(handle, &envelope);
    let peer: A2APeer = serde_json::from_str(&peer_json).unwrap();
    assert!(!peer.peer_id.is_empty());
    let peers: Vec<A2APeer> = serde_json::from_str(&list_peers_handle(handle, "")).unwrap();
    assert_eq!(peers.len(), 1);
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn result_link_wraps_task_result_envelope() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let accepted = accept_deep_link_handle(handle, &task_envelope().to_string(), "deep_link");
    let task: A2ATaskRecord = serde_json::from_str(&accepted).unwrap();
    let link_json = build_result_link_handle(handle, &task.task_id, "agent-sender://a2a/result");
    let link: A2AResultLink = serde_json::from_str(&link_json).unwrap();
    assert_eq!(link.task_id, "task-1");
    assert!(link.deep_link_url.contains("envelope="));
    assert!(matches!(link.envelope.kind, A2AEnvelopeKind::TaskResult));
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn local_peer_session_creates_outbound_task_message() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let peer_json = json!({
        "peerId": "peer-b",
        "agentId": "agent.b",
        "displayName": "Phone B",
        "trustLevel": "user_confirmed",
        "localPeerId": "phone-a",
        "createdAt": now(),
        "updatedAt": now()
    })
    .to_string();
    let session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        handle,
        &peer_json,
        "lan_websocket",
        "ws://192.168.1.2:38471/a2a",
    ))
    .unwrap();
    assert_eq!(session.remote_peer_id, "peer-b");
    assert_eq!(session.local_peer_id, "phone-a");
    let message: A2APeerMessage = serde_json::from_str(&create_task_message_handle(
        handle,
        &session.session_id,
        "Summarize the note",
        r#"{"taskId":"local-task-1","artifacts":[{"artifactId":"photo-1","mimeType":"image/jpeg","name":"photo.jpg","uri":"/workspace/attachments/media/photo.jpg"}]}"#,
    ))
    .unwrap();
    assert!(matches!(message.kind, A2AMessageKind::TaskRequest));
    assert_eq!(
        message.payload["task"]["artifacts"][0]["artifactId"].as_str(),
        Some("photo-1")
    );
    let messages: Vec<A2APeerMessage> = serde_json::from_str(&list_peer_messages_handle(
        handle,
        &session.session_id,
        100,
        0,
    ))
    .unwrap();
    assert_eq!(messages.len(), 1);
    let deliveries: Vec<A2ADeliveryRecord> = serde_json::from_str(&list_delivery_records_handle(
        handle,
        &session.session_id,
        100,
        0,
    ))
    .unwrap();
    assert_eq!(deliveries.len(), 1);
    assert!(matches!(deliveries[0].status, A2ADeliveryStatus::Created));
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn outbound_local_delivery_status_records_transport_evidence() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let peer_json = json!({
        "peerId": "peer-b",
        "agentId": "agent.b",
        "displayName": "Phone B",
        "trustLevel": "user_confirmed",
        "localPeerId": "phone-a",
        "createdAt": now(),
        "updatedAt": now()
    })
    .to_string();
    let session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        handle,
        &peer_json,
        "lan_tcp",
        "tcp://192.168.1.2:38471/a2a",
    ))
    .unwrap();
    let message: A2APeerMessage = serde_json::from_str(&create_task_message_handle(
        handle,
        &session.session_id,
        "Summarize the note",
        r#"{"taskId":"local-task-transport"}"#,
    ))
    .unwrap();
    let sent: A2ADeliveryRecord = serde_json::from_str(&record_delivery_status_handle(
        handle,
        &serde_json::to_string(&message).unwrap(),
        "sent",
        "",
    ))
    .unwrap();
    assert!(matches!(sent.status, A2ADeliveryStatus::Sent));
    assert_eq!(sent.task_id.as_deref(), Some("local-task-transport"));

    let failed: A2ADeliveryRecord = serde_json::from_str(&record_delivery_status_handle(
        handle,
        &serde_json::to_string(&message).unwrap(),
        "failed",
        "connection refused",
    ))
    .unwrap();
    assert!(matches!(failed.status, A2ADeliveryStatus::Failed));
    assert_eq!(failed.error.as_deref(), Some("connection refused"));
    let task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(handle, "local-task-transport")).unwrap();
    assert!(matches!(task.status, A2ATaskStatus::Failed));
    assert_eq!(task.error.as_deref(), Some("connection refused"));

    let deliveries: Vec<A2ADeliveryRecord> = serde_json::from_str(&list_delivery_records_handle(
        handle,
        &session.session_id,
        100,
        0,
    ))
    .unwrap();
    assert_eq!(deliveries.len(), 3);
    assert!(
        deliveries
            .iter()
            .any(|delivery| matches!(delivery.status, A2ADeliveryStatus::Created))
    );
    assert!(
        deliveries
            .iter()
            .any(|delivery| matches!(delivery.status, A2ADeliveryStatus::Sent))
    );
    assert!(
        deliveries
            .iter()
            .any(|delivery| matches!(delivery.status, A2ADeliveryStatus::Failed))
    );
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn inbound_local_task_message_becomes_pending_task() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let peer_json = json!({
        "peerId": "peer-a",
        "agentId": "agent.a",
        "displayName": "Phone A",
        "trustLevel": "user_confirmed",
        "createdAt": now(),
        "updatedAt": now()
    })
    .to_string();
    let session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        handle,
        &peer_json,
        "lan_websocket",
        "ws://192.168.1.3:38471/a2a",
    ))
    .unwrap();
    let inbound = json!({
        "messageId": "msg-1",
        "sessionId": session.session_id,
        "fromPeerId": "peer-a",
        "toPeerId": session.local_peer_id,
        "kind": "task_request",
        "createdAt": now(),
        "expiresAt": future_iso(),
        "nonce": "nonce-local-1",
        "idempotencyKey": "idem-local-1",
        "payload": {
            "agentId": "receiver.agent",
            "senderAgentId": "sender.agent",
            "task": {
                "taskId": "lan-task-1",
                "message": "Please inspect this local note",
                "sessionMode": "isolated"
            }
        }
    })
    .to_string();
    let delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        handle,
        &inbound,
        "lan_websocket",
    ))
    .unwrap();
    assert!(
        matches!(delivery.status, A2ADeliveryStatus::Delivered),
        "delivery status {:?}: {:?}",
        delivery.status,
        delivery.error
    );
    let task: A2ATaskRecord = serde_json::from_str(&get_task_handle(handle, "lan-task-1")).unwrap();
    assert!(matches!(
        task.status,
        A2ATaskStatus::PendingUserConfirmation
    ));
    assert_eq!(
        task.session_id.as_deref(),
        Some(session.session_id.as_str())
    );
    assert!(matches!(task.trust, A2ATaskTrust::Untrusted));
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn inbound_local_task_message_requires_trusted_peer_when_source_requests_it() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let peer_json = json!({
        "peerId": "peer-a",
        "agentId": "agent.a",
        "displayName": "Phone A",
        "trustLevel": "user_confirmed",
        "createdAt": now(),
        "updatedAt": now()
    })
    .to_string();
    let session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        handle,
        &peer_json,
        "lan_tcp",
        "tcp://192.168.1.3:38471/a2a",
    ))
    .unwrap();
    let inbound = json!({
        "messageId": "msg-untrusted-strict",
        "sessionId": session.session_id,
        "fromPeerId": "peer-a",
        "toPeerId": session.local_peer_id,
        "kind": "task_request",
        "createdAt": now(),
        "expiresAt": future_iso(),
        "nonce": "nonce-local-strict",
        "idempotencyKey": "idem-local-strict",
        "payload": {
            "agentId": "receiver.agent",
            "senderAgentId": "sender.agent",
            "task": {
                "taskId": "lan-task-strict",
                "message": "This must not enter the task ledger",
                "sessionMode": "isolated"
            }
        }
    })
    .to_string();
    let delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        handle,
        &inbound,
        "local_transport_require_trusted",
    ))
    .unwrap();
    assert!(matches!(delivery.status, A2ADeliveryStatus::Failed));
    assert!(
        delivery
            .error
            .as_deref()
            .unwrap_or_default()
            .contains("requires a signed trusted peer")
    );
    let task: Value = serde_json::from_str(&get_task_handle(handle, "lan-task-strict")).unwrap();
    assert!(task.is_null(), "unexpected task: {task}");
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn local_peer_messages_are_signed_and_verified_with_shared_secret() {
    let sender_temp = tempfile::tempdir().unwrap();
    let receiver_temp = tempfile::tempdir().unwrap();
    let sender = engine_handle(&sender_temp.path().to_string_lossy());
    let receiver = engine_handle(&receiver_temp.path().to_string_lossy());

    let sender_peer_for_receiver = json!({
        "peerId": "receiver-peer",
        "agentId": "agent.receiver",
        "displayName": "Receiver",
        "trustLevel": "trusted",
        "sharedSecret": "local-secret",
        "createdAt": now(),
        "updatedAt": now()
    })
    .to_string();
    let sender_session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        sender,
        &sender_peer_for_receiver,
        "lan_tcp",
        "tcp://192.168.1.2:38471/a2a",
    ))
    .unwrap();
    let message: A2APeerMessage = serde_json::from_str(&create_task_message_handle(
        sender,
        &sender_session.session_id,
        "Inspect local state",
        r#"{"taskId":"signed-task-1"}"#,
    ))
    .unwrap();
    assert_eq!(message.signature_algorithm, "hmac-sha256-v1");
    assert!(message.signature.as_deref().unwrap_or_default().len() > 20);
    assert!(message.payload.get("encrypted").is_some());
    assert_eq!(
        message
            .payload
            .get("encrypted")
            .and_then(|encrypted| encrypted.get("algorithm"))
            .and_then(Value::as_str),
        Some("a2a-aes-256-gcm-v1")
    );
    assert!(message.payload.get("task").is_none());

    let receiver_peer_for_sender = json!({
        "peerId": message.from_peer_id,
        "agentId": "agent.sender",
        "displayName": "Sender",
        "trustLevel": "trusted",
        "sharedSecret": "local-secret",
        "createdAt": now(),
        "updatedAt": now()
    })
    .to_string();
    let _receiver_session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        receiver,
        &receiver_peer_for_sender,
        "lan_tcp",
        "tcp://192.168.1.3:38471/a2a",
    ))
    .unwrap();

    let delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        receiver,
        &serde_json::to_string(&message).unwrap(),
        "lan_tcp",
    ))
    .unwrap();
    assert!(
        matches!(delivery.status, A2ADeliveryStatus::Delivered),
        "delivery status {:?}: {:?}",
        delivery.status,
        delivery.error
    );
    let task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(receiver, "signed-task-1")).unwrap();
    assert!(matches!(task.trust, A2ATaskTrust::SignedPeer));
    let stored_messages: Vec<A2APeerMessage> = serde_json::from_str(&list_peer_messages_handle(
        receiver,
        &message.session_id,
        10,
        0,
    ))
    .unwrap();
    assert_eq!(
        stored_messages[0]
            .payload
            .get("task")
            .and_then(|task| task.get("taskId"))
            .and_then(Value::as_str),
        Some("signed-task-1")
    );

    let mut wrong_recipient = A2APeerMessage {
        message_id: "wrong-recipient-message".to_string(),
        session_id: message.session_id.clone(),
        from_peer_id: message.from_peer_id.clone(),
        to_peer_id: "not-the-receiver".to_string(),
        kind: A2AMessageKind::Ping,
        created_at: now(),
        expires_at: future_iso(),
        nonce: "wrong-recipient-nonce".to_string(),
        idempotency_key: "wrong-recipient-idem".to_string(),
        payload: json!({"message":"wrong recipient"}),
        signature_algorithm: String::new(),
        signature: None,
    };
    super::signing::encrypt_peer_message_payload(&mut wrong_recipient, "local-secret");
    super::signing::sign_peer_message(&mut wrong_recipient, "local-secret");
    let recipient_failed: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        receiver,
        &serde_json::to_string(&wrong_recipient).unwrap(),
        "lan_tcp",
    ))
    .unwrap();
    assert!(matches!(recipient_failed.status, A2ADeliveryStatus::Failed));
    assert!(
        recipient_failed
            .error
            .as_deref()
            .unwrap_or_default()
            .contains("recipient mismatch")
    );
    let messages_after_wrong_recipient: Vec<A2APeerMessage> = serde_json::from_str(
        &list_peer_messages_handle(receiver, &message.session_id, 10, 0),
    )
    .unwrap();
    assert_eq!(messages_after_wrong_recipient.len(), 1);

    let mut tampered = message.clone();
    tampered.message_id = "tampered-message".to_string();
    tampered.idempotency_key = "tampered-idem".to_string();
    let failed: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        receiver,
        &serde_json::to_string(&tampered).unwrap(),
        "lan_tcp",
    ))
    .unwrap();
    assert!(matches!(failed.status, A2ADeliveryStatus::Failed));
    assert!(
        failed
            .error
            .as_deref()
            .unwrap_or_default()
            .contains("signature verification failed")
    );

    crate::runtime::dispose_engine_handle(sender);
    crate::runtime::dispose_engine_handle(receiver);
}

#[test]
fn local_peer_message_signed_with_wrong_shared_secret_is_rejected() {
    let sender_temp = tempfile::tempdir().unwrap();
    let receiver_temp = tempfile::tempdir().unwrap();
    let sender = engine_handle(&sender_temp.path().to_string_lossy());
    let receiver = engine_handle(&receiver_temp.path().to_string_lossy());

    let sender_session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        sender,
        &json!({
            "peerId": "phone-b",
            "agentId": "agent.b",
            "displayName": "Phone B",
            "trustLevel": "trusted",
            "sharedSecret": "secret-known-by-phone-a",
            "localPeerId": "phone-a",
            "createdAt": now(),
            "updatedAt": now()
        })
        .to_string(),
        "lan_tcp",
        "tcp://192.168.1.2:38471/a2a",
    ))
    .unwrap();
    let message: A2APeerMessage = serde_json::from_str(&create_task_message_handle(
        sender,
        &sender_session.session_id,
        "Run a trusted local task",
        r#"{"taskId":"wrong-secret-task"}"#,
    ))
    .unwrap();

    let _receiver_session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        receiver,
        &json!({
            "peerId": "phone-a",
            "agentId": "agent.a",
            "displayName": "Phone A",
            "trustLevel": "trusted",
            "sharedSecret": "different-secret-known-by-phone-b",
            "localPeerId": "phone-b",
            "createdAt": now(),
            "updatedAt": now()
        })
        .to_string(),
        "lan_tcp",
        "tcp://192.168.1.3:38471/a2a",
    ))
    .unwrap();

    let delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        receiver,
        &serde_json::to_string(&message).unwrap(),
        "lan_tcp_jsonl",
    ))
    .unwrap();
    assert!(matches!(delivery.status, A2ADeliveryStatus::Failed));
    assert!(
        delivery
            .error
            .as_deref()
            .unwrap_or_default()
            .contains("signature verification failed")
    );
    let task: Value =
        serde_json::from_str(&get_task_handle(receiver, "wrong-secret-task")).unwrap();
    assert!(task.is_null(), "unexpected task: {task}");
    let stored_messages: Vec<A2APeerMessage> = serde_json::from_str(&list_peer_messages_handle(
        receiver,
        &message.session_id,
        10,
        0,
    ))
    .unwrap();
    assert!(stored_messages.is_empty());

    crate::runtime::dispose_engine_handle(sender);
    crate::runtime::dispose_engine_handle(receiver);
}

#[test]
fn two_local_peers_exchange_task_progress_and_result_over_signed_messages() {
    let phone_a_temp = tempfile::tempdir().unwrap();
    let phone_b_temp = tempfile::tempdir().unwrap();
    let phone_a = engine_handle(&phone_a_temp.path().to_string_lossy());
    let phone_b = engine_handle(&phone_b_temp.path().to_string_lossy());
    let shared_secret = "pairing-derived-secret";

    let phone_a_session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        phone_a,
        &json!({
            "peerId": "phone-b",
            "agentId": "agent.b",
            "displayName": "Phone B",
            "trustLevel": "trusted",
            "sharedSecret": shared_secret,
            "localPeerId": "phone-a",
            "createdAt": now(),
            "updatedAt": now()
        })
        .to_string(),
        "lan_tcp",
        "tcp://192.168.1.2:38471/a2a",
    ))
    .unwrap();
    let _phone_b_session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        phone_b,
        &json!({
            "peerId": "phone-a",
            "agentId": "agent.a",
            "displayName": "Phone A",
            "trustLevel": "trusted",
            "sharedSecret": shared_secret,
            "localPeerId": "phone-b",
            "createdAt": now(),
            "updatedAt": now()
        })
        .to_string(),
        "lan_tcp",
        "tcp://192.168.1.3:38471/a2a",
    ))
    .unwrap();

    let task_message: A2APeerMessage = serde_json::from_str(&create_task_message_handle(
        phone_a,
        &phone_a_session.session_id,
        "Check the local note and report back",
        r#"{"taskId":"roundtrip-task-1"}"#,
    ))
    .unwrap();
    assert_eq!(task_message.from_peer_id, "phone-a");
    assert_eq!(task_message.to_peer_id, "phone-b");
    assert!(task_message.payload.get("task").is_none());
    let phone_a_outbound_task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(phone_a, "roundtrip-task-1")).unwrap();
    assert_eq!(phone_a_outbound_task.task_id, "roundtrip-task-1");
    assert_eq!(
        phone_a_outbound_task.session_id.as_deref(),
        Some(phone_a_session.session_id.as_str())
    );
    assert!(matches!(
        phone_a_outbound_task.trust,
        A2ATaskTrust::SignedPeer
    ));
    assert!(matches!(
        phone_a_outbound_task.status,
        A2ATaskStatus::Accepted
    ));

    let b_task_delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        phone_b,
        &serde_json::to_string(&task_message).unwrap(),
        "lan_tcp_jsonl",
    ))
    .unwrap();
    assert!(
        matches!(b_task_delivery.status, A2ADeliveryStatus::Delivered),
        "phone B task delivery {:?}: {:?}",
        b_task_delivery.status,
        b_task_delivery.error
    );
    let b_task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(phone_b, "roundtrip-task-1")).unwrap();
    assert!(matches!(b_task.trust, A2ATaskTrust::SignedPeer));
    assert_eq!(
        b_task.session_id.as_deref(),
        Some(phone_a_session.session_id.as_str())
    );

    let receipt_message: A2APeerMessage =
        serde_json::from_str(&create_task_progress_message_handle(
            phone_b,
            &phone_a_session.session_id,
            "roundtrip-task-1",
            "Peer recorded the task",
            r#"{"status":"accepted"}"#,
        ))
        .unwrap();
    assert_eq!(receipt_message.from_peer_id, "phone-b");
    assert_eq!(receipt_message.to_peer_id, "phone-a");
    assert!(receipt_message.payload.get("progress").is_none());

    let a_receipt_delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        phone_a,
        &serde_json::to_string(&receipt_message).unwrap(),
        "lan_tcp_jsonl",
    ))
    .unwrap();
    assert!(
        matches!(a_receipt_delivery.status, A2ADeliveryStatus::Accepted),
        "phone A receipt delivery {:?}: {:?}",
        a_receipt_delivery.status,
        a_receipt_delivery.error
    );
    let phone_a_receipt_task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(phone_a, "roundtrip-task-1")).unwrap();
    assert!(matches!(
        phone_a_receipt_task.status,
        A2ATaskStatus::Accepted
    ));
    assert_eq!(
        phone_a_receipt_task.summary.as_deref(),
        Some("Peer recorded the task")
    );

    let progress_message: A2APeerMessage =
        serde_json::from_str(&create_task_progress_message_handle(
            phone_b,
            &phone_a_session.session_id,
            "roundtrip-task-1",
            "Reading local state",
            r#"{"percent":50}"#,
        ))
        .unwrap();
    assert_eq!(progress_message.from_peer_id, "phone-b");
    assert_eq!(progress_message.to_peer_id, "phone-a");
    assert!(progress_message.payload.get("progress").is_none());

    let a_progress_delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        phone_a,
        &serde_json::to_string(&progress_message).unwrap(),
        "lan_tcp_jsonl",
    ))
    .unwrap();
    assert!(
        matches!(a_progress_delivery.status, A2ADeliveryStatus::Running),
        "phone A progress delivery {:?}: {:?}",
        a_progress_delivery.status,
        a_progress_delivery.error
    );
    let phone_a_progress_task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(phone_a, "roundtrip-task-1")).unwrap();
    assert!(matches!(
        phone_a_progress_task.status,
        A2ATaskStatus::Running
    ));
    assert_eq!(
        phone_a_progress_task.summary.as_deref(),
        Some("Reading local state")
    );

    let result_message: A2APeerMessage = serde_json::from_str(&create_task_result_message_handle(
        phone_b,
        &phone_a_session.session_id,
        "roundtrip-task-1",
        r#"{"message":"Local check complete","runId":"run-b-1"}"#,
    ))
    .unwrap();
    assert_eq!(result_message.from_peer_id, "phone-b");
    assert_eq!(result_message.to_peer_id, "phone-a");
    assert!(result_message.payload.get("result").is_none());
    let phone_b_result_task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(phone_b, "roundtrip-task-1")).unwrap();
    assert!(matches!(
        phone_b_result_task.status,
        A2ATaskStatus::Succeeded
    ));
    assert_eq!(
        phone_b_result_task.summary.as_deref(),
        Some("Local check complete")
    );
    assert_eq!(phone_b_result_task.run_id.as_deref(), Some("run-b-1"));

    let a_result_delivery: A2ADeliveryRecord = serde_json::from_str(&record_peer_message_handle(
        phone_a,
        &serde_json::to_string(&result_message).unwrap(),
        "lan_tcp_jsonl",
    ))
    .unwrap();
    assert!(
        matches!(a_result_delivery.status, A2ADeliveryStatus::Succeeded),
        "phone A result delivery {:?}: {:?}",
        a_result_delivery.status,
        a_result_delivery.error
    );
    let phone_a_result_task: A2ATaskRecord =
        serde_json::from_str(&get_task_handle(phone_a, "roundtrip-task-1")).unwrap();
    assert!(matches!(
        phone_a_result_task.status,
        A2ATaskStatus::Succeeded
    ));
    assert_eq!(
        phone_a_result_task.summary.as_deref(),
        Some("Local check complete")
    );
    assert_eq!(phone_a_result_task.run_id.as_deref(), Some("run-b-1"));

    let phone_a_messages: Vec<A2APeerMessage> = serde_json::from_str(&list_peer_messages_handle(
        phone_a,
        &phone_a_session.session_id,
        10,
        0,
    ))
    .unwrap();
    assert_eq!(phone_a_messages.len(), 4);
    assert!(phone_a_messages.iter().any(|message| {
        matches!(message.kind, A2AMessageKind::TaskProgress)
            && message
                .payload
                .get("progress")
                .and_then(|progress| progress.get("status"))
                .and_then(Value::as_str)
                == Some("accepted")
    }));
    assert!(phone_a_messages.iter().any(|message| {
        matches!(message.kind, A2AMessageKind::TaskProgress)
            && message
                .payload
                .get("progress")
                .and_then(|progress| progress.get("taskId"))
                .and_then(Value::as_str)
                == Some("roundtrip-task-1")
    }));
    assert!(phone_a_messages.iter().any(|message| {
        matches!(message.kind, A2AMessageKind::TaskResult)
            && message
                .payload
                .get("result")
                .and_then(|result| result.get("message"))
                .and_then(Value::as_str)
                == Some("Local check complete")
    }));

    let phone_a_deliveries: Vec<A2ADeliveryRecord> = serde_json::from_str(
        &list_delivery_records_handle(phone_a, &phone_a_session.session_id, 10, 0),
    )
    .unwrap();
    assert_eq!(phone_a_deliveries.len(), 4);
    assert!(phone_a_deliveries.iter().any(|delivery| {
        matches!(delivery.kind, A2AMessageKind::TaskRequest)
            && matches!(delivery.status, A2ADeliveryStatus::Created)
    }));
    assert!(phone_a_deliveries.iter().any(|delivery| {
        matches!(delivery.kind, A2AMessageKind::TaskProgress)
            && matches!(delivery.status, A2ADeliveryStatus::Accepted)
    }));
    assert!(phone_a_deliveries.iter().any(|delivery| {
        matches!(delivery.kind, A2AMessageKind::TaskProgress)
            && matches!(delivery.status, A2ADeliveryStatus::Running)
    }));
    assert!(phone_a_deliveries.iter().any(|delivery| {
        matches!(delivery.kind, A2AMessageKind::TaskResult)
            && matches!(delivery.status, A2ADeliveryStatus::Succeeded)
    }));

    crate::runtime::dispose_engine_handle(phone_a);
    crate::runtime::dispose_engine_handle(phone_b);
}

#[test]
fn local_peer_session_creates_progress_and_result_messages() {
    let temp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&temp.path().to_string_lossy());
    let peer_json = json!({
        "peerId": "peer-b",
        "agentId": "agent.b",
        "displayName": "Phone B",
        "trustLevel": "user_confirmed",
        "createdAt": now(),
        "updatedAt": now()
    })
    .to_string();
    let session: A2APeerSession = serde_json::from_str(&open_peer_session_handle(
        handle,
        &peer_json,
        "lan_tcp",
        "tcp://192.168.1.2:38471/a2a",
    ))
    .unwrap();

    let progress: A2APeerMessage = serde_json::from_str(&create_task_progress_message_handle(
        handle,
        &session.session_id,
        "task-1",
        "Halfway",
        r#"{"percent":50}"#,
    ))
    .unwrap();
    assert!(matches!(progress.kind, A2AMessageKind::TaskProgress));
    assert_eq!(
        progress
            .payload
            .get("progress")
            .and_then(|value| value.get("taskId"))
            .and_then(Value::as_str),
        Some("task-1")
    );

    let result: A2APeerMessage = serde_json::from_str(&create_task_result_message_handle(
        handle,
        &session.session_id,
        "task-1",
        r#"{"message":"Done","artifacts":[{"artifactId":"bundle-1","mimeType":"application/json","name":"bundle.json","text":"{}"}]}"#,
    ))
    .unwrap();
    assert!(matches!(result.kind, A2AMessageKind::TaskResult));
    assert_eq!(
        result.payload["result"]["artifacts"][0]["artifactId"].as_str(),
        Some("bundle-1")
    );

    let deliveries: Vec<A2ADeliveryRecord> = serde_json::from_str(&list_delivery_records_handle(
        handle,
        &session.session_id,
        10,
        0,
    ))
    .unwrap();
    assert_eq!(deliveries.len(), 2);
    assert_eq!(deliveries[0].task_id.as_deref(), Some("task-1"));
    assert_eq!(deliveries[1].task_id.as_deref(), Some("task-1"));
    crate::runtime::dispose_engine_handle(handle);
}
