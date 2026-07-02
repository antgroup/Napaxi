use chrono::{SecondsFormat, Utc};
use serde_json::{Value, json};
use uuid::Uuid;

use super::signing;
use super::store;
use super::types::{
    A2AArtifact, A2ADeliveryRecord, A2ADeliveryStatus, A2AMessageDirection, A2AMessageKind,
    A2AParty, A2APeer, A2APeerEndpoint, A2APeerMessage, A2APeerSession, A2APeerSessionStatus,
    A2ASessionMode, A2ATaskRecord, A2ATaskRequest, A2ATaskResult, A2ATaskStatus, A2ATaskTrust,
    A2ATransportKind,
};
use super::{error_json, files_dir, json_string, normalize_agent, now, string_option};

pub fn open_peer_session_handle(
    handle: i64,
    peer_json: &str,
    transport: &str,
    endpoint: &str,
) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let peer_value = serde_json::from_str::<Value>(peer_json).unwrap_or(Value::Null);
    let local_peer_id_override = string_option(&peer_value, "localPeerId")
        .or_else(|| string_option(&peer_value, "local_peer_id"))
        .filter(|value| !value.trim().is_empty());
    let mut peer = match serde_json::from_value::<A2APeer>(peer_value) {
        Ok(peer) => peer,
        Err(error) => return error_json(format!("invalid A2A peer: {error}")),
    };
    let now = now();
    if peer.peer_id.trim().is_empty() {
        peer.peer_id = Uuid::new_v4().to_string();
    }
    if peer.created_at.trim().is_empty() {
        peer.created_at = now.clone();
    }
    peer.updated_at = now.clone();
    peer.last_seen_at = Some(now.clone());
    if !endpoint.trim().is_empty() {
        peer.endpoints.push(A2APeerEndpoint {
            transport: parse_transport(transport),
            uri: endpoint.to_string(),
            priority: 0,
            last_seen_at: Some(now.clone()),
        });
    }
    if !store::save_peer(&files_dir, &peer) {
        return error_json("failed to save A2A peer");
    }
    let session = A2APeerSession {
        session_id: Uuid::new_v4().to_string(),
        local_peer_id: local_peer_id_override.unwrap_or_else(|| local_peer_id(&files_dir)),
        remote_peer_id: peer.peer_id,
        remote_agent_id: peer.agent_id,
        status: A2APeerSessionStatus::Active,
        transport: parse_transport(transport),
        endpoint: endpoint.to_string(),
        created_at: now.clone(),
        updated_at: now,
        last_message_at: None,
    };
    if !store::save_session(&files_dir, &session) {
        return error_json("failed to save A2A peer session");
    }
    json_string(&session)
}

pub fn list_peer_sessions_handle(handle: i64, peer_id: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "[]".to_string();
    };
    let mut sessions = store::list_sessions(&files_dir);
    if !peer_id.trim().is_empty() {
        sessions.retain(|session| {
            session.remote_peer_id == peer_id || session.local_peer_id == peer_id
        });
    }
    json_string(&sessions)
}

pub fn create_task_message_handle(
    handle: i64,
    session_id: &str,
    message: &str,
    options_json: &str,
) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let Some(mut session) = store::load_session(&files_dir, session_id) else {
        return error_json("A2A peer session not found");
    };
    if session.status != A2APeerSessionStatus::Active {
        return error_json("A2A peer session is not active");
    }
    let options = serde_json::from_str::<Value>(options_json).unwrap_or(Value::Null);
    let task = A2ATaskRequest {
        task_id: string_option(&options, "taskId")
            .or_else(|| string_option(&options, "task_id"))
            .unwrap_or_else(|| Uuid::new_v4().to_string()),
        message: message.to_string(),
        artifacts: artifacts_from_options(&options),
        context: options.get("context").cloned().unwrap_or(Value::Null),
        requested_output_modes: string_array_option(&options, "requestedOutputModes")
            .or_else(|| string_array_option(&options, "requested_output_modes"))
            .unwrap_or_default(),
        risk_hint: string_option(&options, "riskHint")
            .or_else(|| string_option(&options, "risk_hint"))
            .unwrap_or_default(),
        session_mode: session_mode_from_options(&options),
        parent_task_id: string_option(&options, "parentTaskId")
            .or_else(|| string_option(&options, "parent_task_id")),
    };
    let payload = json!({ "task": task });
    let peer_message = create_outbound_peer_message(
        &files_dir,
        &mut session,
        A2AMessageKind::TaskRequest,
        payload,
        expiry_from_options(&options),
    );
    record_outbound_task_request(&files_dir, &session, &peer_message, &task);
    json_string(&peer_message)
}

pub fn create_task_progress_message_handle(
    handle: i64,
    session_id: &str,
    task_id: &str,
    message: &str,
    progress_json: &str,
) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let Some(mut session) = active_session(&files_dir, session_id) else {
        return error_json("A2A peer session not found or inactive");
    };
    let progress = serde_json::from_str::<Value>(progress_json).unwrap_or(Value::Null);
    let expires_at = expiry_from_options(&progress);
    let payload = json!({
        "progress": {
            "taskId": task_id,
            "message": message,
            "status": string_option(&progress, "status").unwrap_or_else(|| "running".to_string()),
            "percent": progress.get("percent").cloned().unwrap_or(Value::Null),
            "updatedAt": now(),
        }
    });
    json_string(&create_outbound_peer_message(
        &files_dir,
        &mut session,
        A2AMessageKind::TaskProgress,
        payload,
        expires_at,
    ))
}

pub fn create_task_result_message_handle(
    handle: i64,
    session_id: &str,
    task_id: &str,
    result_json: &str,
) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let Some(mut session) = active_session(&files_dir, session_id) else {
        return error_json("A2A peer session not found or inactive");
    };
    let options = serde_json::from_str::<Value>(result_json).unwrap_or(Value::Null);
    let status = match string_option(&options, "status").as_deref() {
        Some("failed") => A2ATaskStatus::Failed,
        Some("cancelled") => A2ATaskStatus::Cancelled,
        Some("rejected") => A2ATaskStatus::Rejected,
        Some("running") => A2ATaskStatus::Running,
        _ => A2ATaskStatus::Succeeded,
    };
    let result = A2ATaskResult {
        task_id: task_id.to_string(),
        status,
        message: string_option(&options, "message"),
        artifacts: artifacts_from_options(&options),
        run_id: string_option(&options, "runId").or_else(|| string_option(&options, "run_id")),
        completed_at: Some(now()),
        error: string_option(&options, "error"),
    };
    update_local_task_from_created_result(&files_dir, &result);
    let expires_at = expiry_from_options(&options);
    json_string(&create_outbound_peer_message(
        &files_dir,
        &mut session,
        A2AMessageKind::TaskResult,
        json!({ "result": result }),
        expires_at,
    ))
}

fn artifacts_from_options(options: &Value) -> Vec<A2AArtifact> {
    options
        .get("artifacts")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| serde_json::from_value::<A2AArtifact>(item.clone()).ok())
                .filter(|artifact| {
                    !artifact.artifact_id.trim().is_empty()
                        || !artifact.mime_type.trim().is_empty()
                        || !artifact.name.trim().is_empty()
                        || artifact
                            .uri
                            .as_deref()
                            .map(str::trim)
                            .filter(|value| !value.is_empty())
                            .is_some()
                        || artifact
                            .text
                            .as_deref()
                            .map(str::trim)
                            .filter(|value| !value.is_empty())
                            .is_some()
                })
                .collect()
        })
        .unwrap_or_default()
}

fn string_array_option(value: &Value, key: &str) -> Option<Vec<String>> {
    let items = value.get(key)?.as_array()?;
    Some(
        items
            .iter()
            .filter_map(Value::as_str)
            .map(str::trim)
            .filter(|item| !item.is_empty())
            .map(str::to_string)
            .collect(),
    )
}

fn session_mode_from_options(options: &Value) -> A2ASessionMode {
    match string_option(options, "sessionMode")
        .or_else(|| string_option(options, "session_mode"))
        .as_deref()
    {
        Some("main") => A2ASessionMode::Main,
        _ => A2ASessionMode::Isolated,
    }
}

fn update_local_task_from_created_result(files_dir: &str, result: &A2ATaskResult) {
    let Some(mut task) = store::load_task(files_dir, &result.task_id) else {
        return;
    };
    task.status = result.status.clone();
    task.summary = result.message.clone();
    task.result_artifacts = result.artifacts.clone();
    task.run_id = result.run_id.clone();
    task.error = result.error.clone();
    task.updated_at = now();
    let _ = store::save_task(files_dir, &task);
}

pub fn record_peer_message_handle(handle: i64, message_json: &str, source: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let mut peer_message = match serde_json::from_str::<A2APeerMessage>(message_json) {
        Ok(message) => message,
        Err(error) => return error_json(format!("invalid A2A peer message: {error}")),
    };
    if peer_message_expired(&peer_message) {
        return json_string(&append_delivery_status(
            &files_dir,
            &peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Expired,
            Some("A2A peer message expired".to_string()),
        ));
    }
    if store::message_seen(
        &files_dir,
        &peer_message.session_id,
        &peer_message.message_id,
        &peer_message.idempotency_key,
    ) {
        return json_string(&append_delivery_status(
            &files_dir,
            &peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Duplicate,
            None,
        ));
    }
    let trust = match peer_message_trust(&files_dir, &peer_message) {
        PeerMessageTrust::InvalidSignature(error) => {
            return json_string(&append_delivery_status(
                &files_dir,
                &peer_message,
                A2AMessageDirection::Inbound,
                A2ADeliveryStatus::Failed,
                Some(error),
            ));
        }
        PeerMessageTrust::SignedPeer(shared_secret) => {
            if !signing::decrypt_peer_message_payload(&mut peer_message, &shared_secret) {
                return json_string(&append_delivery_status(
                    &files_dir,
                    &peer_message,
                    A2AMessageDirection::Inbound,
                    A2ADeliveryStatus::Failed,
                    Some("A2A peer message payload decryption failed".to_string()),
                ));
            }
            A2ATaskTrust::SignedPeer
        }
        PeerMessageTrust::Untrusted if source_requires_trusted_peer(source) => {
            return json_string(&append_delivery_status(
                &files_dir,
                &peer_message,
                A2AMessageDirection::Inbound,
                A2ADeliveryStatus::Failed,
                Some("A2A peer message requires a signed trusted peer".to_string()),
            ));
        }
        PeerMessageTrust::Untrusted => A2ATaskTrust::Untrusted,
    };
    if let Some(error) = existing_session_recipient_error(&files_dir, &peer_message) {
        return json_string(&append_delivery_status(
            &files_dir,
            &peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Failed,
            Some(error),
        ));
    }
    ensure_inbound_session(&files_dir, &peer_message, source);
    let _ = store::append_message(&files_dir, &peer_message);
    if let Some(mut session) = store::load_session(&files_dir, &peer_message.session_id) {
        let now = now();
        session.updated_at = now.clone();
        session.last_message_at = Some(now);
        let _ = store::save_session(&files_dir, &session);
    }
    match peer_message.kind {
        A2AMessageKind::TaskRequest => {
            record_task_request(&files_dir, &peer_message, source, trust)
        }
        A2AMessageKind::TaskResult | A2AMessageKind::TaskProgress => {
            let status = if peer_message.kind == A2AMessageKind::TaskResult {
                A2ADeliveryStatus::Succeeded
            } else if progress_status(&peer_message.payload).as_deref() == Some("accepted") {
                A2ADeliveryStatus::Accepted
            } else {
                A2ADeliveryStatus::Running
            };
            update_task_from_peer_message(&files_dir, &peer_message, &status);
            json_string(&append_delivery_status(
                &files_dir,
                &peer_message,
                A2AMessageDirection::Inbound,
                status,
                None,
            ))
        }
        A2AMessageKind::TaskReject => json_string(&append_delivery_status(
            &files_dir,
            &peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Rejected,
            None,
        )),
        _ => json_string(&append_delivery_status(
            &files_dir,
            &peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Delivered,
            None,
        )),
    }
}

pub fn record_delivery_status_handle(
    handle: i64,
    message_json: &str,
    status: &str,
    error: &str,
) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let peer_message = match serde_json::from_str::<A2APeerMessage>(message_json) {
        Ok(message) => message,
        Err(error) => return error_json(format!("invalid A2A peer message: {error}")),
    };
    let Some(status) = parse_delivery_status(status) else {
        return error_json("invalid A2A delivery status");
    };
    update_outbound_task_delivery(
        &files_dir,
        &peer_message,
        &status,
        (!error.trim().is_empty()).then(|| error.to_string()),
    );
    json_string(&append_delivery_status(
        &files_dir,
        &peer_message,
        A2AMessageDirection::Outbound,
        status,
        (!error.trim().is_empty()).then(|| error.to_string()),
    ))
}

fn source_requires_trusted_peer(source: &str) -> bool {
    let normalized = source.trim().to_ascii_lowercase();
    normalized.contains("require_trusted")
        || normalized.contains("trusted_only")
        || normalized.contains("signed_peer_required")
}

fn existing_session_recipient_error(files_dir: &str, message: &A2APeerMessage) -> Option<String> {
    let session = store::load_session(files_dir, &message.session_id)?;
    if session.local_peer_id.trim().is_empty() || message.to_peer_id == session.local_peer_id {
        return None;
    }
    Some(format!(
        "A2A peer message recipient mismatch: expected {}, got {}",
        session.local_peer_id, message.to_peer_id
    ))
}

pub fn list_peer_messages_handle(handle: i64, session_id: &str, limit: i64, offset: i64) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "[]".to_string();
    };
    let limit = usize::try_from(limit.max(1)).unwrap_or(100).min(500);
    let offset = usize::try_from(offset.max(0)).unwrap_or(0);
    let mut messages = store::read_messages(&files_dir, session_id);
    messages.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    json_string(
        &messages
            .into_iter()
            .skip(offset)
            .take(limit)
            .collect::<Vec<_>>(),
    )
}

pub fn list_delivery_records_handle(
    handle: i64,
    session_id: &str,
    limit: i64,
    offset: i64,
) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "[]".to_string();
    };
    let limit = usize::try_from(limit.max(1)).unwrap_or(100).min(500);
    let offset = usize::try_from(offset.max(0)).unwrap_or(0);
    let mut deliveries = store::read_deliveries(&files_dir, session_id);
    deliveries.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    json_string(
        &deliveries
            .into_iter()
            .skip(offset)
            .take(limit)
            .collect::<Vec<_>>(),
    )
}

fn record_task_request(
    files_dir: &str,
    peer_message: &A2APeerMessage,
    source: &str,
    trust: A2ATaskTrust,
) -> String {
    let Some(task_request) = task_request_from_payload(&peer_message.payload) else {
        return json_string(&append_delivery_status(
            files_dir,
            peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Failed,
            Some("A2A task_request payload missing task".to_string()),
        ));
    };
    if store::load_task(files_dir, &task_request.task_id).is_some() {
        return json_string(&append_delivery_status(
            files_dir,
            peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Duplicate,
            None,
        ));
    }
    let now = now();
    let task = A2ATaskRecord {
        task_id: task_request.task_id.clone(),
        envelope_id: peer_message.message_id.clone(),
        idempotency_key: peer_message.idempotency_key.clone(),
        agent_id: normalize_agent(
            peer_message
                .payload
                .get("agentId")
                .or_else(|| peer_message.payload.get("agent_id"))
                .and_then(Value::as_str)
                .unwrap_or_default(),
        ),
        sender: A2AParty {
            agent_id: peer_message
                .payload
                .get("senderAgentId")
                .or_else(|| peer_message.payload.get("sender_agent_id"))
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            peer_id: peer_message.from_peer_id.clone(),
            display_name: String::new(),
            deep_link_url: String::new(),
        },
        callback: None,
        request: task_request,
        status: A2ATaskStatus::PendingUserConfirmation,
        trust,
        source: source.to_string(),
        session_id: Some(peer_message.session_id.clone()),
        peer_message_id: Some(peer_message.message_id.clone()),
        created_at: now.clone(),
        updated_at: now,
        session_key: None,
        run_id: None,
        summary: None,
        result_artifacts: Vec::new(),
        error: None,
    };
    if !store::save_task(files_dir, &task) {
        return json_string(&append_delivery_status(
            files_dir,
            peer_message,
            A2AMessageDirection::Inbound,
            A2ADeliveryStatus::Failed,
            Some("failed to persist A2A task".to_string()),
        ));
    }
    json_string(&append_delivery_status(
        files_dir,
        peer_message,
        A2AMessageDirection::Inbound,
        A2ADeliveryStatus::Delivered,
        None,
    ))
}

fn record_outbound_task_request(
    files_dir: &str,
    session: &A2APeerSession,
    peer_message: &A2APeerMessage,
    task_request: &A2ATaskRequest,
) {
    let trust = store::find_peer(files_dir, &session.remote_peer_id)
        .filter(|peer| !peer.shared_secret.trim().is_empty())
        .map(|_| A2ATaskTrust::SignedPeer)
        .unwrap_or(A2ATaskTrust::Untrusted);
    let task = A2ATaskRecord {
        task_id: task_request.task_id.clone(),
        envelope_id: peer_message.message_id.clone(),
        idempotency_key: peer_message.idempotency_key.clone(),
        agent_id: session.remote_agent_id.clone(),
        sender: A2AParty {
            agent_id: String::new(),
            peer_id: session.local_peer_id.clone(),
            display_name: String::new(),
            deep_link_url: String::new(),
        },
        callback: None,
        request: task_request.clone(),
        status: A2ATaskStatus::Accepted,
        trust,
        source: "local_transport_outbound".to_string(),
        session_id: Some(session.session_id.clone()),
        peer_message_id: Some(peer_message.message_id.clone()),
        created_at: peer_message.created_at.clone(),
        updated_at: peer_message.created_at.clone(),
        session_key: None,
        run_id: None,
        summary: None,
        result_artifacts: Vec::new(),
        error: None,
    };
    let _ = store::save_task(files_dir, &task);
}

fn update_task_from_peer_message(
    files_dir: &str,
    peer_message: &A2APeerMessage,
    delivery_status: &A2ADeliveryStatus,
) {
    let Some(task_id) = task_id_from_payload(&peer_message.payload) else {
        return;
    };
    let Some(mut task) = store::load_task(files_dir, &task_id) else {
        return;
    };
    match peer_message.kind {
        A2AMessageKind::TaskProgress => {
            task.status = match delivery_status {
                A2ADeliveryStatus::Accepted => A2ATaskStatus::Accepted,
                _ => A2ATaskStatus::Running,
            };
            if let Some(message) = progress_message(&peer_message.payload) {
                task.summary = Some(message);
            }
        }
        A2AMessageKind::TaskResult => {
            if let Some(result) = task_result_from_payload(&peer_message.payload) {
                task.status = result.status;
                task.summary = result.message;
                task.result_artifacts = result.artifacts;
                task.run_id = result.run_id;
                task.error = result.error;
            } else {
                task.status = A2ATaskStatus::Succeeded;
            }
        }
        _ => return,
    }
    task.updated_at = now();
    let _ = store::save_task(files_dir, &task);
}

fn update_outbound_task_delivery(
    files_dir: &str,
    peer_message: &A2APeerMessage,
    delivery_status: &A2ADeliveryStatus,
    error: Option<String>,
) {
    let Some(task_id) = task_id_from_payload(&peer_message.payload) else {
        return;
    };
    let Some(mut task) = store::load_task(files_dir, &task_id) else {
        return;
    };
    if matches!(delivery_status, A2ADeliveryStatus::Failed) {
        task.status = A2ATaskStatus::Failed;
        task.error = error;
        task.updated_at = now();
        let _ = store::save_task(files_dir, &task);
    }
}

fn local_peer_id(files_dir: &str) -> String {
    format!(
        "local:{}",
        uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_URL, files_dir.as_bytes())
    )
}

fn parse_transport(transport: &str) -> A2ATransportKind {
    match transport.trim().to_ascii_lowercase().as_str() {
        "lan_websocket" | "websocket" | "ws" => A2ATransportKind::LanWebSocket,
        "lan_tcp" | "tcp" => A2ATransportKind::LanTcp,
        "ble" | "bluetooth" => A2ATransportKind::Ble,
        "deep_link" | "deeplink" => A2ATransportKind::DeepLink,
        "host_provided" | "host" => A2ATransportKind::HostProvided,
        _ => A2ATransportKind::Unknown,
    }
}

fn parse_delivery_status(status: &str) -> Option<A2ADeliveryStatus> {
    match status.trim().to_ascii_lowercase().as_str() {
        "created" => Some(A2ADeliveryStatus::Created),
        "sent" => Some(A2ADeliveryStatus::Sent),
        "delivered" => Some(A2ADeliveryStatus::Delivered),
        "accepted" => Some(A2ADeliveryStatus::Accepted),
        "rejected" => Some(A2ADeliveryStatus::Rejected),
        "running" => Some(A2ADeliveryStatus::Running),
        "succeeded" => Some(A2ADeliveryStatus::Succeeded),
        "failed" => Some(A2ADeliveryStatus::Failed),
        "expired" => Some(A2ADeliveryStatus::Expired),
        "duplicate" => Some(A2ADeliveryStatus::Duplicate),
        _ => None,
    }
}

fn active_session(files_dir: &str, session_id: &str) -> Option<A2APeerSession> {
    let session = store::load_session(files_dir, session_id)?;
    (session.status == A2APeerSessionStatus::Active).then_some(session)
}

fn expiry_from_options(options: &Value) -> String {
    options
        .get("expiresAt")
        .or_else(|| options.get("expires_at"))
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| {
            (Utc::now() + chrono::Duration::minutes(30))
                .to_rfc3339_opts(SecondsFormat::Millis, true)
        })
}

fn create_outbound_peer_message(
    files_dir: &str,
    session: &mut A2APeerSession,
    kind: A2AMessageKind,
    payload: Value,
    expires_at: String,
) -> A2APeerMessage {
    let now = now();
    let task_id = task_id_from_payload(&payload);
    let mut peer_message = A2APeerMessage {
        message_id: Uuid::new_v4().to_string(),
        session_id: session.session_id.clone(),
        from_peer_id: session.local_peer_id.clone(),
        to_peer_id: session.remote_peer_id.clone(),
        kind,
        created_at: now.clone(),
        expires_at,
        nonce: Uuid::new_v4().to_string(),
        idempotency_key: Uuid::new_v4().to_string(),
        payload,
        signature_algorithm: String::new(),
        signature: None,
    };
    if let Some(peer) = store::find_peer(files_dir, &session.remote_peer_id) {
        signing::encrypt_peer_message_payload(&mut peer_message, &peer.shared_secret);
        signing::sign_peer_message(&mut peer_message, &peer.shared_secret);
    }
    let _ = store::append_message(files_dir, &peer_message);
    let _ = store::append_delivery(
        files_dir,
        &A2ADeliveryRecord {
            message_id: peer_message.message_id.clone(),
            session_id: session.session_id.clone(),
            direction: A2AMessageDirection::Outbound,
            kind: peer_message.kind.clone(),
            status: A2ADeliveryStatus::Created,
            created_at: now.clone(),
            updated_at: now.clone(),
            task_id,
            error: None,
        },
    );
    session.updated_at = now.clone();
    session.last_message_at = Some(now);
    let _ = store::save_session(files_dir, session);
    peer_message
}

enum PeerMessageTrust {
    SignedPeer(String),
    Untrusted,
    InvalidSignature(String),
}

fn peer_message_trust(files_dir: &str, message: &A2APeerMessage) -> PeerMessageTrust {
    let signature_present =
        !message.signature_algorithm.trim().is_empty() || message.signature.is_some();
    let Some(peer) = store::find_peer(files_dir, &message.from_peer_id) else {
        return if signature_present {
            PeerMessageTrust::InvalidSignature(
                "A2A peer message signed by unknown peer".to_string(),
            )
        } else {
            PeerMessageTrust::Untrusted
        };
    };
    if !signature_present {
        return PeerMessageTrust::Untrusted;
    }
    if signing::verify_peer_message(message, &peer.shared_secret) {
        PeerMessageTrust::SignedPeer(peer.shared_secret)
    } else {
        PeerMessageTrust::InvalidSignature(
            "A2A peer message signature verification failed".to_string(),
        )
    }
}

fn ensure_inbound_session(files_dir: &str, message: &A2APeerMessage, source: &str) {
    if store::load_session(files_dir, &message.session_id).is_some() {
        return;
    }
    let now = now();
    let session = A2APeerSession {
        session_id: message.session_id.clone(),
        local_peer_id: message.to_peer_id.clone(),
        remote_peer_id: message.from_peer_id.clone(),
        remote_agent_id: String::new(),
        status: A2APeerSessionStatus::Active,
        transport: A2ATransportKind::HostProvided,
        endpoint: source.to_string(),
        created_at: now.clone(),
        updated_at: now,
        last_message_at: Some(message.created_at.clone()),
    };
    let _ = store::save_session(files_dir, &session);
}

fn peer_message_expired(message: &A2APeerMessage) -> bool {
    chrono::DateTime::parse_from_rfc3339(&message.expires_at)
        .map(|expiry| expiry.with_timezone(&Utc) <= Utc::now())
        .unwrap_or(true)
}

fn task_request_from_payload(payload: &Value) -> Option<A2ATaskRequest> {
    payload
        .get("task")
        .cloned()
        .and_then(|value| serde_json::from_value::<A2ATaskRequest>(value).ok())
}

fn task_id_from_payload(payload: &Value) -> Option<String> {
    payload
        .get("task")
        .and_then(|task| task.get("taskId").or_else(|| task.get("task_id")))
        .and_then(Value::as_str)
        .map(str::to_string)
        .or_else(|| {
            payload
                .get("result")
                .and_then(|result| result.get("taskId").or_else(|| result.get("task_id")))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .or_else(|| {
            payload
                .get("progress")
                .and_then(|progress| progress.get("taskId").or_else(|| progress.get("task_id")))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
}

fn progress_status(payload: &Value) -> Option<String> {
    payload
        .get("progress")
        .and_then(|progress| progress.get("status"))
        .and_then(Value::as_str)
        .map(|status| status.trim().to_ascii_lowercase())
        .filter(|status| !status.is_empty())
}

fn progress_message(payload: &Value) -> Option<String> {
    payload
        .get("progress")
        .and_then(|progress| progress.get("message"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|message| !message.is_empty())
        .map(str::to_string)
}

fn task_result_from_payload(payload: &Value) -> Option<A2ATaskResult> {
    payload
        .get("result")
        .cloned()
        .and_then(|value| serde_json::from_value::<A2ATaskResult>(value).ok())
}

fn append_delivery_status(
    files_dir: &str,
    message: &A2APeerMessage,
    direction: A2AMessageDirection,
    status: A2ADeliveryStatus,
    error: Option<String>,
) -> A2ADeliveryRecord {
    let now = now();
    let delivery = A2ADeliveryRecord {
        message_id: message.message_id.clone(),
        session_id: message.session_id.clone(),
        direction,
        kind: message.kind.clone(),
        status,
        created_at: now.clone(),
        updated_at: now,
        task_id: task_id_from_payload(&message.payload),
        error,
    };
    let _ = store::append_delivery(files_dir, &delivery);
    delivery
}
