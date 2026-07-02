//! Stateless QQ-bot protocol helpers: pure JSON-in / JSON-out functions.
//!
//! These mirror the logic previously hand-written in the Flutter adapter
//! (`channel_qqbot_provider.dart`). The adapter now delegates here so iOS and
//! Android can adopt the same protocol without re-implementing it.

use serde_json::{Map, Value, json};

/// Default API host for the production QQ OpenAPI.
pub const QQ_API_BASE: &str = "https://api.sgroup.qq.com";
/// API host used when the credentials declare sandbox mode.
pub const QQ_API_BASE_SANDBOX: &str = "https://sandbox.api.sgroup.qq.com";

/// Endpoint kinds that support QQ Markdown outbound by default (direct + group).
const DEFAULT_MARKDOWN_ENDPOINT_KINDS: &[&str] = &["direct", "group"];

/// Returns the API base host for the given sandbox flag.
pub fn api_base(sandbox: bool) -> &'static str {
    if sandbox {
        QQ_API_BASE_SANDBOX
    } else {
        QQ_API_BASE
    }
}

/// Normalizes a user-declared content format to `markdown` or `plain_text`.
fn normalize_content_format(value: Option<&str>) -> &'static str {
    let normalized = value
        .unwrap_or(crate::channel::CHANNEL_CONTENT_FORMAT_PLAIN_TEXT)
        .trim()
        .to_ascii_lowercase()
        .replace('-', "_");
    match normalized.as_str() {
        "md" | "markdown" => crate::channel::CHANNEL_CONTENT_FORMAT_MARKDOWN,
        _ => crate::channel::CHANNEL_CONTENT_FORMAT_PLAIN_TEXT,
    }
}

/// Returns the first non-empty trimmed string from the candidates.
fn first_string(candidates: &[Option<&Value>]) -> String {
    for candidate in candidates {
        if let Some(value) = candidate
            && let Some(text) = value.as_str()
        {
            let trimmed = text.trim();
            if !trimmed.is_empty() {
                return trimmed.to_string();
            }
        }
    }
    String::new()
}

/// Returns the first non-empty trimmed string, or `None` if all are empty.
fn first_optional_string(candidates: &[Option<&Value>]) -> Option<String> {
    let value = first_string(candidates);
    if value.is_empty() { None } else { Some(value) }
}

/// Whether the QQ Markdown endpoint is supported for the given peer kind.
fn supports_markdown_endpoint(peer_kind: &str, markdown_endpoint_kinds: &[String]) -> bool {
    markdown_endpoint_kinds.iter().any(|kind| kind == peer_kind)
}

/// Resolves the configured Markdown endpoint kinds, defaulting to direct+group.
fn markdown_endpoint_kinds(config_kinds: Option<&Value>) -> Vec<String> {
    let default = || {
        DEFAULT_MARKDOWN_ENDPOINT_KINDS
            .iter()
            .map(|kind| kind.to_string())
            .collect::<Vec<_>>()
    };
    let Some(Value::Array(items)) = config_kinds else {
        return default();
    };
    let values: Vec<String> = items
        .iter()
        .filter_map(|item| item.as_str())
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect();
    if values.is_empty() { default() } else { values }
}

/// Builds the QQ OpenAPI outbound send payload for a channel outbound message.
///
/// `message_json` is a `ChannelOutboundMessage`-shaped object (only `peer`,
/// `text`, `reply_to_message_id`, and `format` are consulted).
/// `markdown_endpoint_kinds_json` is an optional JSON array of endpoint-kind
/// strings; when absent the default direct+group set is used.
///
/// Returns a JSON object:
/// `{ "body": { ...QQ payload... }, "content_format": "...", "used_markdown": bool }`.
pub fn build_outbound_payload(message_json: &str, markdown_endpoint_kinds_json: &str) -> String {
    build_outbound_payload_inner(message_json, markdown_endpoint_kinds_json, false)
}

/// Builds the outbound payload forcing plain text (the Markdown fallback path).
pub fn build_outbound_payload_plain(message_json: &str) -> String {
    build_outbound_payload_inner(message_json, "", true)
}

fn build_outbound_payload_inner(
    message_json: &str,
    markdown_endpoint_kinds_json: &str,
    force_plain_text: bool,
) -> String {
    let message: Value = serde_json::from_str(message_json).unwrap_or_else(|_| json!({}));
    let peer_kind = message
        .get("peer")
        .and_then(|peer| peer.get("kind"))
        .and_then(Value::as_str)
        .unwrap_or("direct");
    let text = message
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    let reply_to = message
        .get("reply_to_message_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let wants_markdown = normalize_content_format(message.get("format").and_then(Value::as_str))
        == crate::channel::CHANNEL_CONTENT_FORMAT_MARKDOWN;

    let kinds = if markdown_endpoint_kinds_json.trim().is_empty() {
        markdown_endpoint_kinds(None)
    } else {
        let parsed: Value =
            serde_json::from_str(markdown_endpoint_kinds_json).unwrap_or(Value::Null);
        markdown_endpoint_kinds(Some(&parsed))
    };

    if !force_plain_text && wants_markdown && supports_markdown_endpoint(peer_kind, &kinds) {
        let mut body = Map::new();
        body.insert("msg_type".to_string(), json!(2));
        body.insert("markdown".to_string(), json!({ "content": text }));
        if let Some(reply) = reply_to {
            body.insert("msg_id".to_string(), json!(reply));
        }
        return json!({
            "body": Value::Object(body),
            "content_format": crate::channel::CHANNEL_CONTENT_FORMAT_MARKDOWN,
            "used_markdown": true,
        })
        .to_string();
    }

    let mut body = Map::new();
    body.insert("content".to_string(), json!(text));
    body.insert("msg_type".to_string(), json!(0));
    if let Some(reply) = reply_to {
        body.insert("msg_id".to_string(), json!(reply));
    }
    json!({
        "body": Value::Object(body),
        "content_format": crate::channel::CHANNEL_CONTENT_FORMAT_PLAIN_TEXT,
        "used_markdown": false,
    })
    .to_string()
}

/// Whether a failed Markdown send should be retried as plain text.
///
/// True for non-throttling 4xx (a Markdown capability/format rejection);
/// false for 429 (throttling) and any non-4xx status.
pub fn should_fallback_from_markdown(status: i64) -> bool {
    (400..500).contains(&status) && status != 429
}

/// Returns the QQ OpenAPI relative path for delivering to the given peer kind.
pub fn outbound_endpoint_path(peer_kind: &str, peer_id: &str) -> String {
    let encoded = urlencode(peer_id);
    match peer_kind {
        "group" => format!("/v2/groups/{encoded}/messages"),
        "room" => format!("/channels/{encoded}/messages"),
        // direct and any unknown kind fall back to the user DM endpoint.
        _ => format!("/v2/users/{encoded}/messages"),
    }
}

/// Percent-encodes a path segment (the QQ peer id), matching Dart's
/// `Uri.encodeComponent`.
fn urlencode(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'-'
            | b'_'
            | b'.'
            | b'!'
            | b'~'
            | b'*'
            | b'\''
            | b'('
            | b')' => encoded.push(byte as char),
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

/// Returns the set of QQ gateway dispatch event types treated as inbound
/// messages.
pub fn is_message_event(event_type: &str) -> bool {
    matches!(
        event_type,
        "C2C_MESSAGE_CREATE"
            | "GROUP_AT_MESSAGE_CREATE"
            | "DIRECT_MESSAGE_CREATE"
            | "AT_MESSAGE_CREATE"
            | "MESSAGE_CREATE"
    )
}

/// Normalizes a QQ gateway message-create event into the shared inbound shape.
///
/// `event_type` is the gateway dispatch event name and `data_json` is the
/// event's `d` payload object. Returns a JSON object with `peer`, `sender`,
/// `text`, `platform_message_id`, `thread_id`, and `raw` — the fields the
/// adapter passes to `submitTextInbound`. Returns `{ "peer": null, ... }` with
/// an `error` when the event has no usable peer id.
pub fn normalize_inbound(event_type: &str, data_json: &str) -> String {
    let data: Value = serde_json::from_str(data_json).unwrap_or_else(|_| json!({}));
    let peer = peer_for_message_event(event_type, &data);
    let peer_id = peer
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if peer_id.is_empty() {
        return json!({
            "peer": Value::Null,
            "error": format!("QQBot message event had no peer id: {event_type}"),
        })
        .to_string();
    }
    let sender = sender_for_message_event(&data);
    let text = first_optional_string(&[data.get("content")]);
    let platform_message_id = first_optional_string(&[data.get("id"), data.get("event_id")]);
    let thread_id = thread_id_for_message_event(&data);

    let mut result = Map::new();
    result.insert("peer".to_string(), peer);
    result.insert("sender".to_string(), sender);
    if let Some(text) = text {
        result.insert("text".to_string(), json!(text));
    }
    if let Some(id) = platform_message_id {
        result.insert("platform_message_id".to_string(), json!(id));
    }
    if let Some(thread) = thread_id {
        result.insert("thread_id".to_string(), json!(thread));
    }
    Value::Object(result).to_string()
}

fn peer_for_message_event(event_type: &str, data: &Value) -> Value {
    if event_type == "GROUP_AT_MESSAGE_CREATE"
        || data.get("group_openid").is_some()
        || data.get("group_id").is_some()
    {
        return peer_value(
            "group",
            first_string(&[data.get("group_openid"), data.get("group_id")]),
            first_optional_string(&[data.get("group_name"), data.get("name")]),
        );
    }
    if event_type == "AT_MESSAGE_CREATE" || data.get("channel_id").is_some() {
        return peer_value(
            "room",
            first_string(&[data.get("channel_id")]),
            first_optional_string(&[data.get("channel_name"), data.get("name")]),
        );
    }
    let author = data.get("author");
    peer_value(
        "direct",
        first_string(&[
            data.get("openid"),
            data.get("user_openid"),
            author.and_then(|a| a.get("user_openid")),
            author.and_then(|a| a.get("id")),
        ]),
        first_optional_string(&[
            author.and_then(|a| a.get("username")),
            author.and_then(|a| a.get("nick")),
            data.get("username"),
        ]),
    )
}

fn peer_value(kind: &str, id: String, display_name: Option<String>) -> Value {
    let mut peer = Map::new();
    peer.insert("kind".to_string(), json!(kind));
    peer.insert("id".to_string(), json!(id));
    if let Some(name) = display_name {
        peer.insert("display_name".to_string(), json!(name));
    }
    Value::Object(peer)
}

fn sender_for_message_event(data: &Value) -> Value {
    let author = data.get("author");
    let mut actor = Map::new();
    actor.insert(
        "id".to_string(),
        json!(first_string(&[
            author.and_then(|a| a.get("user_openid")),
            author.and_then(|a| a.get("id")),
            data.get("openid"),
            data.get("user_openid"),
        ])),
    );
    if let Some(name) = first_optional_string(&[
        author.and_then(|a| a.get("username")),
        author.and_then(|a| a.get("nick")),
        data.get("username"),
    ]) {
        actor.insert("display_name".to_string(), json!(name));
    }
    actor.insert("is_bot".to_string(), json!(false));
    Value::Object(actor)
}

fn thread_id_for_message_event(data: &Value) -> Option<String> {
    first_optional_string(&[
        data.get("channel_id"),
        data.get("group_openid"),
        data.get("guild_id"),
    ])
}
