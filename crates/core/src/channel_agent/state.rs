use serde_json::{Map, Value};

use super::*;

pub(super) fn upsert_pending_human(files_dir: &str, context: &InboundRunContext, request_id: &str) {
    let mut mappings = load_pending(files_dir);
    let now = Utc::now();
    if let Some(existing) = mappings
        .iter_mut()
        .find(|mapping| mapping.request_id == request_id)
    {
        existing.updated_at = now;
        existing.original_inbound_id = context.inbound.id.clone();
        existing.answer_inbound_id = None;
    } else {
        mappings.push(PendingHumanMapping {
            request_id: request_id.to_string(),
            channel_name: context.resolved.channel_name.clone(),
            agent_id: context.resolved.agent_id.clone(),
            session_key: context.resolved.session_key.clone(),
            original_inbound_id: context.inbound.id.clone(),
            answer_inbound_id: None,
            created_at: now,
            updated_at: now,
        });
    }
    let _ = save_pending(files_dir, &mappings);
}

pub(super) fn replace_pending(files_dir: &str, pending: PendingHumanMapping) {
    let mut mappings = load_pending(files_dir);
    if let Some(existing) = mappings
        .iter_mut()
        .find(|mapping| mapping.request_id == pending.request_id)
    {
        *existing = pending;
    } else {
        mappings.push(pending);
    }
    let _ = save_pending(files_dir, &mappings);
}

pub(super) fn find_pending_by_session(
    files_dir: &str,
    session_key: &SessionKey,
) -> Option<PendingHumanMapping> {
    load_pending(files_dir)
        .into_iter()
        .find(|mapping| &mapping.session_key == session_key)
}

pub(super) fn find_pending_by_request(
    files_dir: &str,
    request_id: &str,
) -> Option<PendingHumanMapping> {
    load_pending(files_dir)
        .into_iter()
        .find(|mapping| mapping.request_id == request_id)
}

pub(super) fn remove_pending_by_session(files_dir: &str, session_key: &SessionKey) {
    let mut mappings = load_pending(files_dir);
    mappings.retain(|mapping| &mapping.session_key != session_key);
    let _ = save_pending(files_dir, &mappings);
}

pub(super) fn remove_pending_by_request(files_dir: &str, request_id: &str) {
    let mut mappings = load_pending(files_dir);
    mappings.retain(|mapping| mapping.request_id != request_id);
    let _ = save_pending(files_dir, &mappings);
}

pub(super) fn channel_event_json(
    event_type: &str,
    inbound: &ChannelInboundMessage,
    resolved: Option<&ResolvedChannelAgentRoute>,
    data: Value,
) -> String {
    let session_key = resolved
        .and_then(|route| serde_json::to_value(&route.session_key).ok())
        .unwrap_or(Value::Null);
    let mut object = Map::new();
    object.insert("type".to_string(), Value::String(event_type.to_string()));
    object.insert(
        "channel_name".to_string(),
        Value::String(inbound.channel_name.clone()),
    );
    object.insert("inbound_id".to_string(), Value::String(inbound.id.clone()));
    object.insert(
        "agent_id".to_string(),
        Value::String(
            resolved
                .map(|route| route.agent_id.clone())
                .unwrap_or_default(),
        ),
    );
    object.insert("session_key".to_string(), session_key);
    object.insert(
        "peer_kind".to_string(),
        Value::String(format!("{:?}", inbound.peer.kind).to_ascii_lowercase()),
    );
    object.insert(
        "peer_id".to_string(),
        Value::String(inbound.peer.id.clone()),
    );
    if let Some(display_name) = inbound.peer.display_name.as_deref() {
        object.insert(
            "peer_display_name".to_string(),
            Value::String(display_name.to_string()),
        );
    }
    object.insert(
        "sender_id".to_string(),
        Value::String(inbound.sender.id.clone()),
    );
    if let Some(display_name) = inbound.sender.display_name.as_deref() {
        object.insert(
            "sender_display_name".to_string(),
            Value::String(display_name.to_string()),
        );
    }
    if let Some(message_id) = inbound.platform_message_id.as_deref() {
        object.insert(
            "platform_message_id".to_string(),
            Value::String(message_id.to_string()),
        );
    }
    if let Some(thread_id) = inbound.thread_id.as_deref() {
        object.insert(
            "platform_thread_id".to_string(),
            Value::String(thread_id.to_string()),
        );
    }
    if let Value::Object(extra) = data {
        for (key, value) in extra {
            object.insert(key, value);
        }
    }
    serde_json::to_string(&Value::Object(object)).unwrap_or_else(|_| {
        r#"{"type":"failed","error":"channel_agent_event_serialize_failed"}"#.to_string()
    })
}

pub(super) fn parse_json_value(raw: &str) -> Value {
    serde_json::from_str::<Value>(raw).unwrap_or(Value::Null)
}
