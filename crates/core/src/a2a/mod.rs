//! Mobile A2A deep-link peers, task intake, and isolated task execution.

mod local;
pub mod local_pairing_contract;
mod signing;
mod store;
#[cfg(test)]
mod tests;
pub mod types;

use chrono::{SecondsFormat, Utc};
use serde::Serialize;
use serde_json::{Map, Value, json};
use uuid::Uuid;

use crate::runtime::{
    Engine, SessionTurnInput, prepare_session_tool_context_with_config_for_core, run_session_turn,
};
use crate::types::ChatEvent;

use self::types::{
    A2A_LOCAL_CAPABILITY_ID, A2AAgentCard, A2AArtifact, A2ACallback, A2ADeepLinkEnvelope,
    A2AEnvelopeKind, A2AEventRecord, A2AParty, A2APeer, A2APeerTrustLevel, A2AResultLink,
    A2ASessionMode, A2ATaskRecord, A2ATaskResult, A2ATaskStatus, A2ATaskTrust,
};

pub use types::{
    A2A_DEEPLINK_CAPABILITY_ID, A2A_LOCAL_CAPABILITY_ID as A2A_LOCAL_PEER_CAPABILITY_ID,
    A2A_TOOL_CAPABILITY_ID,
};

pub fn is_a2a_tool_name(tool_name: &str) -> bool {
    matches!(
        tool_name,
        "a2a_list_agents"
            | "a2a_start_collaboration"
            | "a2a_send_message"
            | "a2a_wait_messages"
            | "a2a_finish_collaboration"
    )
}

pub use local::{
    create_task_message_handle, create_task_progress_message_handle,
    create_task_result_message_handle, list_delivery_records_handle, list_peer_messages_handle,
    list_peer_sessions_handle, open_peer_session_handle, record_delivery_status_handle,
    record_peer_message_handle,
};

pub fn get_a2a_agent_card_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let normalized_agent = normalize_agent(agent_id);
    let display_name = crate::agents::get_definition(&files_dir, &normalized_agent)
        .map(|definition| {
            if definition.name.trim().is_empty() {
                normalized_agent.clone()
            } else {
                definition.name
            }
        })
        .unwrap_or_else(|| normalized_agent.clone());
    json_string(&A2AAgentCard {
        agent_id: normalized_agent,
        display_name,
        description: "Mobile Agent reachable through host-provided deep links.".to_string(),
        accepted_input_modes: vec![
            "text/plain".to_string(),
            "image/*".to_string(),
            "application/octet-stream".to_string(),
        ],
        accepted_output_modes: vec!["text/plain".to_string(), "application/json".to_string()],
        deep_link_url: "agent-host://a2a/task".to_string(),
        universal_link_url: None,
        capabilities: vec![
            A2A_DEEPLINK_CAPABILITY_ID.to_string(),
            A2A_LOCAL_CAPABILITY_ID.to_string(),
        ],
        requires_user_confirmation: true,
    })
}

pub fn create_peer_invite_handle(handle: i64, agent_id: &str, options_json: &str) -> String {
    let Some(_files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let options = serde_json::from_str::<Value>(options_json).unwrap_or(Value::Null);
    let now = now();
    let expires_at = options
        .get("expiresAt")
        .or_else(|| options.get("expires_at"))
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| {
            (Utc::now() + chrono::Duration::minutes(30))
                .to_rfc3339_opts(SecondsFormat::Millis, true)
        });
    let peer_id = Uuid::new_v4().to_string();
    let shared_secret = Uuid::new_v4().to_string();
    let envelope = A2ADeepLinkEnvelope {
        protocol_version: 1,
        envelope_id: Uuid::new_v4().to_string(),
        kind: A2AEnvelopeKind::PeerInvite,
        sender: A2AParty {
            agent_id: normalize_agent(agent_id),
            peer_id: peer_id.clone(),
            display_name: string_option(&options, "displayName")
                .or_else(|| string_option(&options, "display_name"))
                .unwrap_or_default(),
            deep_link_url: string_option(&options, "deepLinkUrl")
                .or_else(|| string_option(&options, "deep_link_url"))
                .unwrap_or_default(),
        },
        recipient: None,
        task: None,
        result: None,
        callback: callback_from_options(&options),
        created_at: now,
        expires_at,
        nonce: Uuid::new_v4().to_string(),
        idempotency_key: Uuid::new_v4().to_string(),
        signature_algorithm: String::new(),
        signature: None,
    };
    json_string(&json!({
        "peerId": peer_id,
        "sharedSecret": shared_secret,
        "envelope": envelope,
        "deepLinkUrl": deep_link_with_envelope(
            string_option(&options, "deepLinkUrl").as_deref().unwrap_or("agent-host://a2a/peer"),
            &envelope,
        )
    }))
}

pub fn accept_peer_invite_handle(handle: i64, envelope_json: &str) -> String {
    // SAFETY: `handle` is a live engine handle from `create_engine_handle`; an
    // invalid handle yields `None`.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return error_json("invalid engine handle");
    };
    let files_dir = engine.files_dir().to_string();
    if let Err(error) = crate::capabilities::admit_service_for_config(
        A2A_LOCAL_CAPABILITY_ID,
        "a2a.local.accept_peer_invite",
        engine.platform(),
        &engine.capability_profile(),
        &engine.capability_selection(),
    ) {
        return error_json(error.to_string());
    }
    let envelope = match parse_envelope(envelope_json) {
        Ok(envelope) => envelope,
        Err(error) => return error_json(&error),
    };
    if envelope.kind != A2AEnvelopeKind::PeerInvite {
        return error_json("A2A envelope is not a peer invite");
    }
    if envelope_expired(&envelope) {
        return error_json("A2A peer invite expired");
    }
    let now = now();
    let peer = A2APeer {
        peer_id: defaulted(&envelope.sender.peer_id, &envelope.envelope_id),
        agent_id: envelope.sender.agent_id,
        display_name: envelope.sender.display_name,
        deep_link_url: envelope.sender.deep_link_url,
        trust_level: A2APeerTrustLevel::UserConfirmed,
        shared_secret: Uuid::new_v4().to_string(),
        public_key: String::new(),
        endpoints: Vec::new(),
        last_seen_at: Some(now.clone()),
        created_at: now.clone(),
        updated_at: now,
    };
    if !store::save_peer(&files_dir, &peer) {
        return error_json("failed to save A2A peer");
    }
    json_string(&peer)
}

pub fn list_peers_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "[]".to_string();
    };
    let mut peers = store::load_peers(&files_dir);
    if !agent_id.trim().is_empty() {
        let normalized = normalize_agent(agent_id);
        peers.retain(|peer| peer.agent_id == normalized);
    }
    json_string(&peers)
}

pub fn delete_peer_handle(handle: i64, peer_id: &str) -> bool {
    files_dir(handle)
        .map(|files_dir| store::delete_peer(&files_dir, peer_id))
        .unwrap_or(false)
}

pub fn accept_deep_link_handle(handle: i64, envelope_json: &str, source: &str) -> String {
    // SAFETY: `handle` is a live engine handle from `create_engine_handle`; an
    // invalid handle yields `None`.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return error_json("invalid engine handle");
    };
    let files_dir = engine.files_dir().to_string();
    if let Err(error) = crate::capabilities::admit_service_for_config(
        A2A_DEEPLINK_CAPABILITY_ID,
        "a2a.deeplink.accept",
        engine.platform(),
        &engine.capability_profile(),
        &engine.capability_selection(),
    ) {
        return error_json(error.to_string());
    }
    let envelope = match parse_envelope(envelope_json) {
        Ok(envelope) => envelope,
        Err(error) => return error_json(&error),
    };
    if envelope_expired(&envelope) {
        return error_json("A2A envelope expired");
    }
    if store::idempotency_seen(&files_dir, &envelope.idempotency_key) {
        return error_json("A2A envelope already consumed");
    }
    match envelope.kind {
        A2AEnvelopeKind::TaskRequest => accept_task_request(&files_dir, envelope, source),
        A2AEnvelopeKind::TaskResult | A2AEnvelopeKind::TaskUpdate => {
            record_result_envelope(&files_dir, envelope)
        }
        A2AEnvelopeKind::PeerInvite => accept_peer_invite_handle(handle, envelope_json),
        A2AEnvelopeKind::PeerAccept => record_peer_accept(&files_dir, envelope),
    }
}

pub async fn run_task_handle(handle: i64, task_id: &str, mode: &str) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; invalid handles return `None`.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return error_json("invalid engine handle");
    };
    if let Err(error) = crate::capabilities::admit_service_for_config(
        A2A_LOCAL_CAPABILITY_ID,
        "a2a.local.run_task",
        engine.platform(),
        &engine.capability_profile(),
        &engine.capability_selection(),
    ) {
        return error_json(error.to_string());
    }
    let Some(mut task) = store::load_task(engine.files_dir(), task_id) else {
        return error_json("A2A task not found");
    };
    let force = mode.eq_ignore_ascii_case("force");
    if !matches!(
        task.status,
        A2ATaskStatus::PendingUserConfirmation | A2ATaskStatus::Accepted | A2ATaskStatus::Failed
    ) && !force
    {
        return error_json("A2A task is not runnable");
    }
    task.status = A2ATaskStatus::Running;
    task.updated_at = now();
    task.run_id = Some(Uuid::new_v4().to_string());
    if !store::save_task(engine.files_dir(), &task) {
        return error_json("failed to persist A2A task");
    }
    execute_task(&engine, task).await
}

pub fn list_tasks_handle(handle: i64, filter_json: &str, limit: i64, offset: i64) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "[]".to_string();
    };
    let filter = serde_json::from_str::<Value>(filter_json).unwrap_or(Value::Null);
    let limit = usize::try_from(limit.max(1)).unwrap_or(100).min(500);
    let offset = usize::try_from(offset.max(0)).unwrap_or(0);
    let mut tasks = store::latest_tasks(store::list_tasks(&files_dir));
    if let Some(agent_id) =
        string_option(&filter, "agentId").or_else(|| string_option(&filter, "agent_id"))
    {
        tasks.retain(|task| task.agent_id == agent_id);
    }
    if let Some(status) = string_option(&filter, "status") {
        tasks.retain(|task| {
            serde_json::to_value(&task.status)
                .ok()
                .and_then(|v| v.as_str().map(str::to_string))
                == Some(status.clone())
        });
    }
    tasks.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    json_string(
        &tasks
            .into_iter()
            .skip(offset)
            .take(limit)
            .collect::<Vec<_>>(),
    )
}

pub fn get_task_handle(handle: i64, task_id: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "null".to_string();
    };
    store::load_task(&files_dir, task_id)
        .map(|task| json_string(&task))
        .unwrap_or_else(|| "null".to_string())
}

pub fn build_result_link_handle(handle: i64, task_id: &str, callback_url: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let Some(task) = store::load_task(&files_dir, task_id) else {
        return error_json("A2A task not found");
    };
    let result = A2ATaskResult {
        task_id: task.task_id.clone(),
        status: task.status,
        message: task.summary.clone(),
        artifacts: Vec::new(),
        run_id: task.run_id.clone(),
        completed_at: Some(task.updated_at.clone()),
        error: task.error.clone(),
    };
    let envelope = A2ADeepLinkEnvelope {
        protocol_version: 1,
        envelope_id: Uuid::new_v4().to_string(),
        kind: A2AEnvelopeKind::TaskResult,
        sender: A2AParty {
            agent_id: task.agent_id,
            peer_id: String::new(),
            display_name: String::new(),
            deep_link_url: String::new(),
        },
        recipient: Some(task.sender),
        task: None,
        result: Some(result),
        callback: None,
        created_at: now(),
        expires_at: (Utc::now() + chrono::Duration::minutes(30))
            .to_rfc3339_opts(SecondsFormat::Millis, true),
        nonce: Uuid::new_v4().to_string(),
        idempotency_key: Uuid::new_v4().to_string(),
        signature_algorithm: String::new(),
        signature: None,
    };
    json_string(&A2AResultLink {
        task_id: task_id.to_string(),
        deep_link_url: deep_link_with_envelope(callback_url, &envelope),
        envelope,
    })
}

pub fn record_result_envelope_handle(handle: i64, envelope_json: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let envelope = match parse_envelope(envelope_json) {
        Ok(envelope) => envelope,
        Err(error) => return error_json(&error),
    };
    record_result_envelope(&files_dir, envelope)
}

/// Capabilities denied to a peer-driven A2A task. The task runs in the owner's
/// real workspace, so beyond the obvious egress tools this also removes
/// workspace file access, memory read/write, web fetch/search, and skill
/// execution — the confused-deputy surface a paired peer could use to read and
/// leak the owner's files or poison MEMORY.md.
fn peer_task_denied_capabilities() -> &'static [&'static str] {
    &[
        "napaxi.tool.shell",
        "napaxi.tool.http",
        "napaxi.tool.agent_app_action",
        "napaxi.tool.file",
        "napaxi.tool.memory",
        "napaxi.tool.web_fetch",
        "napaxi.tool.web_search",
        "napaxi.tool.skill",
    ]
}

fn attachments_json_from_artifacts(artifacts: &[A2AArtifact]) -> String {
    if artifacts.is_empty() {
        return "[]".to_string();
    }
    let attachments = artifacts
        .iter()
        .take(20)
        .filter_map(attachment_from_artifact)
        .collect::<Vec<_>>();
    serde_json::to_string(&attachments).unwrap_or_else(|_| "[]".to_string())
}

fn attachment_from_artifact(artifact: &A2AArtifact) -> Option<Value> {
    let mime_type = artifact.mime_type.trim();
    let filename = artifact.name.trim();
    let uri = artifact.uri.as_deref().map(str::trim).unwrap_or_default();
    let text = artifact.text.as_deref().map(str::trim).unwrap_or_default();
    if mime_type.is_empty() && filename.is_empty() && uri.is_empty() && text.is_empty() {
        return None;
    }

    let effective_mime = if mime_type.is_empty() && !text.is_empty() {
        "text/plain"
    } else {
        mime_type
    };
    let mut out = Map::new();
    if !artifact.artifact_id.trim().is_empty() {
        out.insert("id".to_string(), json!(artifact.artifact_id.trim()));
    }
    out.insert(
        "kind".to_string(),
        json!(artifact_kind(effective_mime, &artifact.metadata)),
    );
    if !effective_mime.is_empty() {
        out.insert("mime_type".to_string(), json!(effective_mime));
    }
    if !filename.is_empty() {
        out.insert("filename".to_string(), json!(filename));
    }
    if let Some(size) = metadata_u64(&artifact.metadata, &["sizeBytes", "size_bytes"]) {
        out.insert("size_bytes".to_string(), json!(size));
    }
    if let Some(data) = metadata_string(&artifact.metadata, &["dataBase64", "data_base64"])
        && data.len() <= 12 * 1024 * 1024
    {
        out.insert("data_base64".to_string(), json!(data));
    }
    if !text.is_empty() {
        out.insert("extracted_text".to_string(), json!(text));
    }
    if let Some(sandbox_path) =
        metadata_string(&artifact.metadata, &["sandboxPath", "sandbox_path"])
            .or_else(|| uri.strip_prefix("napaxi-sandbox://").map(str::to_string))
            .or_else(|| uri.starts_with("/workspace/").then(|| uri.to_string()))
    {
        out.insert("sandbox_path".to_string(), json!(sandbox_path));
    } else if let Some(local_path) = uri.strip_prefix("file://") {
        out.insert("path".to_string(), json!(local_path));
    } else if !uri.is_empty() {
        out.insert("source_url".to_string(), json!(uri));
    }
    Some(Value::Object(out))
}

fn artifact_kind(mime_type: &str, metadata: &Value) -> &'static str {
    if let Some(kind) = metadata_string(metadata, &["kind"]).as_deref() {
        return match kind {
            "image" => "image",
            "audio" => "audio",
            _ => "document",
        };
    }
    if mime_type.starts_with("image/") {
        "image"
    } else if mime_type.starts_with("audio/") {
        "audio"
    } else {
        "document"
    }
}

fn metadata_string(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(Value::as_str))
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_string)
}

fn metadata_u64(value: &Value, keys: &[&str]) -> Option<u64> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(Value::as_u64))
}

async fn execute_task(engine: &Engine, mut task: A2ATaskRecord) -> String {
    let session_key = match task.request.session_mode {
        A2ASessionMode::Main => crate::session::create_session(
            engine.files_dir(),
            &task.agent_id,
            "app",
            crate::runtime::DEFAULT_ACCOUNT_ID,
            None,
        ),
        A2ASessionMode::Isolated => crate::session::create_session(
            engine.files_dir(),
            &task.agent_id,
            "a2a",
            crate::runtime::DEFAULT_ACCOUNT_ID,
            Some(&task.task_id),
        ),
    };
    task.session_key = Some(session_key.clone());
    let mut config = engine.config_with_capabilities(engine.config());
    // A2A tasks are driven by a *peer*, not the owner, but run in the owner's
    // real workspace under DEFAULT_ACCOUNT_ID — a confused-deputy boundary. Deny
    // not just the obvious egress tools (shell/http/agent_app) but the whole
    // workspace-read / exfiltration / memory-write surface, so a paired peer
    // cannot drive the agent to read and leak the owner's files or poison
    // MEMORY.md. A peer task is reasoning + a response, not filesystem access.
    config.capability_selection.disabled_capabilities.extend(
        peer_task_denied_capabilities()
            .iter()
            .map(|id| id.to_string()),
    );
    config.capability_selection.disabled_capabilities.sort();
    config.capability_selection.disabled_capabilities.dedup();
    let tool_context = prepare_session_tool_context_with_config_for_core(
        engine,
        crate::runtime::DEFAULT_ACCOUNT_ID,
        &task.agent_id,
        config.clone(),
    );
    engine.clear_session_cancellation(&session_key);
    let cancellation_key = session_key.clone();
    let attachments_json = attachments_json_from_artifacts(&task.request.artifacts);
    let events = crate::capabilities::with_admission_sink(
        engine.admission_sink(),
        run_session_turn(
            SessionTurnInput {
                files_dir: engine.files_dir().to_string(),
                workspace_files_dir: tool_context.workspace_files_dir,
                config_json: json_string(&config),
                agent_id: task.agent_id.clone(),
                session_key_json: session_key,
                message: task.request.message.clone(),
                display_message: None,
                attachments_json,
                tools: Some(engine.tools()),
                max_iterations: 0,
                extra_tools: tool_context.extra_tools,
                internal_tool_handler: tool_context.internal_tool_handler,
                is_group_context: false,
                agent_engine: None,
            },
            || engine.is_session_cancelled(&cancellation_key),
        ),
    )
    .await;
    task.summary = final_response(&events);
    task.error = first_error(&events);
    task.status = if task.error.is_some() {
        A2ATaskStatus::Failed
    } else {
        A2ATaskStatus::Succeeded
    };
    task.updated_at = now();
    if !store::save_task(engine.files_dir(), &task) {
        return error_json("failed to persist A2A task result");
    }
    json_string(&task)
}

fn accept_task_request(files_dir: &str, envelope: A2ADeepLinkEnvelope, source: &str) -> String {
    let Some(request) = envelope.task.clone() else {
        return error_json("A2A task request missing task payload");
    };
    if request.task_id.trim().is_empty() || request.message.trim().is_empty() {
        return error_json("A2A task request missing required fields");
    }
    if store::load_task(files_dir, &request.task_id).is_some() {
        return error_json("A2A task already exists");
    }
    let trust = signed_peer_trust(files_dir, &envelope);
    let status = match trust {
        A2ATaskTrust::SignedPeer => A2ATaskStatus::Accepted,
        A2ATaskTrust::Untrusted => A2ATaskStatus::PendingUserConfirmation,
    };
    let agent_id = envelope
        .recipient
        .as_ref()
        .map(|party| normalize_agent(&party.agent_id))
        .unwrap_or_else(|| normalize_agent(""));
    let now = now();
    let record = A2ATaskRecord {
        task_id: request.task_id.clone(),
        envelope_id: envelope.envelope_id.clone(),
        idempotency_key: envelope.idempotency_key.clone(),
        agent_id,
        sender: envelope.sender.clone(),
        callback: envelope.callback.clone(),
        request,
        status,
        trust,
        source: source.trim().to_string(),
        session_id: None,
        peer_message_id: None,
        created_at: now.clone(),
        updated_at: now,
        session_key: None,
        run_id: None,
        summary: None,
        result_artifacts: Vec::new(),
        error: None,
    };
    if !store::save_task(files_dir, &record) {
        return error_json("failed to save A2A task");
    }
    store::append_event(
        files_dir,
        &A2AEventRecord {
            event_id: Uuid::new_v4().to_string(),
            kind: A2AEnvelopeKind::TaskRequest,
            envelope_id: envelope.envelope_id,
            status: "accepted".to_string(),
            created_at: record.created_at.clone(),
            task_id: Some(record.task_id.clone()),
            error: None,
        },
    );
    json_string(&record)
}

fn record_result_envelope(files_dir: &str, envelope: A2ADeepLinkEnvelope) -> String {
    let task_id = envelope
        .result
        .as_ref()
        .map(|result| result.task_id.clone())
        .filter(|value| !value.trim().is_empty());
    let event = A2AEventRecord {
        event_id: Uuid::new_v4().to_string(),
        kind: envelope.kind,
        envelope_id: envelope.envelope_id,
        status: "recorded".to_string(),
        created_at: now(),
        task_id,
        error: None,
    };
    store::append_event(files_dir, &event);
    json_string(&event)
}

fn record_peer_accept(files_dir: &str, envelope: A2ADeepLinkEnvelope) -> String {
    let now = now();
    let peer = A2APeer {
        peer_id: defaulted(&envelope.sender.peer_id, &envelope.envelope_id),
        agent_id: envelope.sender.agent_id,
        display_name: envelope.sender.display_name,
        deep_link_url: envelope.sender.deep_link_url,
        trust_level: A2APeerTrustLevel::Trusted,
        shared_secret: Uuid::new_v4().to_string(),
        public_key: String::new(),
        endpoints: Vec::new(),
        last_seen_at: Some(now.clone()),
        created_at: now.clone(),
        updated_at: now,
    };
    if !store::save_peer(files_dir, &peer) {
        return error_json("failed to save accepted A2A peer");
    }
    json_string(&peer)
}

fn signed_peer_trust(files_dir: &str, envelope: &A2ADeepLinkEnvelope) -> A2ATaskTrust {
    let peer_id = envelope.sender.peer_id.trim();
    if peer_id.is_empty() {
        return A2ATaskTrust::Untrusted;
    }
    let Some(peer) = store::find_peer(files_dir, peer_id) else {
        return A2ATaskTrust::Untrusted;
    };
    if peer.shared_secret.trim().is_empty() {
        return A2ATaskTrust::Untrusted;
    }
    if signing::verify_envelope(envelope, &peer.shared_secret) {
        A2ATaskTrust::SignedPeer
    } else {
        A2ATaskTrust::Untrusted
    }
}

fn parse_envelope(envelope_json: &str) -> Result<A2ADeepLinkEnvelope, String> {
    serde_json::from_str::<A2ADeepLinkEnvelope>(envelope_json)
        .map_err(|error| format!("invalid A2A envelope: {error}"))
        .and_then(|envelope| {
            if envelope.protocol_version == 0
                || envelope.envelope_id.trim().is_empty()
                || envelope.sender.agent_id.trim().is_empty()
                || envelope.created_at.trim().is_empty()
                || envelope.expires_at.trim().is_empty()
                || envelope.nonce.trim().is_empty()
                || envelope.idempotency_key.trim().is_empty()
            {
                return Err("A2A envelope missing required fields".to_string());
            }
            Ok(envelope)
        })
}

fn envelope_expired(envelope: &A2ADeepLinkEnvelope) -> bool {
    chrono::DateTime::parse_from_rfc3339(&envelope.expires_at)
        .map(|expiry| expiry.with_timezone(&Utc) <= Utc::now())
        .unwrap_or(true)
}

fn callback_from_options(options: &Value) -> Option<A2ACallback> {
    let deep_link_url = string_option(options, "callbackDeepLinkUrl")
        .or_else(|| string_option(options, "callback_deep_link_url"))?;
    Some(A2ACallback {
        deep_link_url,
        universal_link_url: string_option(options, "callbackUniversalLinkUrl")
            .or_else(|| string_option(options, "callback_universal_link_url")),
    })
}

fn string_option(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn deep_link_with_envelope(base_url: &str, envelope: &A2ADeepLinkEnvelope) -> String {
    let separator = if base_url.contains('?') { '&' } else { '?' };
    format!(
        "{base_url}{separator}envelope={}",
        percent_encode(&json_string(envelope))
    )
}

fn percent_encode(value: &str) -> String {
    value
        .bytes()
        .map(|byte| {
            if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
                (byte as char).to_string()
            } else {
                format!("%{byte:02X}")
            }
        })
        .collect()
}

fn final_response(events: &[ChatEvent]) -> Option<String> {
    events.iter().rev().find_map(|event| match event {
        ChatEvent::Response { content } if !content.trim().is_empty() => Some(content.clone()),
        _ => None,
    })
}

fn first_error(events: &[ChatEvent]) -> Option<String> {
    events.iter().find_map(|event| match event {
        ChatEvent::Error { message } if !message.trim().is_empty() => Some(message.clone()),
        _ => None,
    })
}

fn files_dir(handle: i64) -> Option<String> {
    crate::runtime::files_dir_from_handle(handle)
}

fn normalize_agent(agent_id: &str) -> String {
    crate::runtime::normalize_agent_id(agent_id)
}

fn defaulted(value: &str, fallback: &str) -> String {
    if value.trim().is_empty() {
        fallback.to_string()
    } else {
        value.trim().to_string()
    }
}

fn now() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true)
}

pub(crate) fn json_string<T: Serialize>(value: &T) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "{}".to_string())
}

pub(crate) fn error_json(message: impl AsRef<str>) -> String {
    json!({ "error": message.as_ref() }).to_string()
}
