//! File-backed mobile channel registry and adapter message queues.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub mod qqbot;

/// Capability id for host-carried instant-messaging channel adapters.
pub const CHANNEL_IM_CAPABILITY_ID: &str = "napaxi.channel.im";
/// Capability id for host-carried local device and peripheral channel adapters.
pub const CHANNEL_DEVICE_CAPABILITY_ID: &str = "napaxi.channel.device";
pub const CHANNEL_CONTENT_FORMAT_PLAIN_TEXT: &str = "plain_text";
pub const CHANNEL_CONTENT_FORMAT_MARKDOWN: &str = "markdown";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChannelSurfaceKind {
    Im,
    Device,
    App,
    System,
    Custom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChannelEndpointKind {
    Direct,
    Group,
    Room,
    Thread,
    Broadcast,
    Device,
    Custom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChannelModality {
    Text,
    Audio,
    Image,
    File,
    Control,
    Sensor,
    Presence,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelConfig {
    pub name: String,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub channel_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub surface_kind: Option<ChannelSurfaceKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub endpoint_kind: Option<ChannelEndpointKind>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub modalities: Vec<ChannelModality>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub content_formats: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transport: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capability_id: Option<String>,
    pub config: serde_json::Value,
    pub registered_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelPeer {
    pub kind: ChannelEndpointKind,
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelActor {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_bot: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelMedia {
    pub kind: ChannelModality,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub uri: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mime_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub raw: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelInboundMessage {
    pub id: String,
    pub channel_name: String,
    #[serde(default)]
    pub account_id: String,
    pub peer: ChannelPeer,
    pub sender: ChannelActor,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub media: Vec<ChannelMedia>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub raw: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub status: String,
    pub received_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelOutboundMessage {
    pub id: String,
    pub channel_name: String,
    #[serde(default)]
    pub account_id: String,
    pub peer: ChannelPeer,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reply_to_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub media: Vec<ChannelMedia>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub raw: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lease_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform_receipt: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelAcceptedReceipt {
    pub accepted: bool,
    pub id: String,
    #[serde(default)]
    pub duplicate: bool,
}

fn store_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join("channels.json")
}

fn inbox_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join("napaxi")
        .join("channel_inbox.json")
}

fn outbox_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join("napaxi")
        .join("channel_outbox.json")
}

fn load_json_vec<T>(path: PathBuf) -> Vec<T>
where
    T: for<'de> Deserialize<'de>,
{
    let Ok(content) = fs::read_to_string(path) else {
        return Vec::new();
    };
    serde_json::from_str(&content).unwrap_or_default()
}

fn save_json_vec<T>(path: PathBuf, items: &[T]) -> bool
where
    T: Serialize,
{
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    serde_json::to_string_pretty(items)
        .ok()
        .and_then(|content| fs::write(path, content).ok())
        .is_some()
}

fn load_channels(files_dir: &str) -> Vec<ChannelConfig> {
    load_json_vec(store_path(files_dir))
}

fn save_channels(files_dir: &str, channels: &[ChannelConfig]) -> bool {
    save_json_vec(store_path(files_dir), channels)
}

fn load_inbox(files_dir: &str) -> Vec<ChannelInboundMessage> {
    load_json_vec(inbox_path(files_dir))
}

fn save_inbox(files_dir: &str, messages: &[ChannelInboundMessage]) -> bool {
    save_json_vec(inbox_path(files_dir), messages)
}

fn load_outbox(files_dir: &str) -> Vec<ChannelOutboundMessage> {
    load_json_vec(outbox_path(files_dir))
}

fn save_outbox(files_dir: &str, messages: &[ChannelOutboundMessage]) -> bool {
    save_json_vec(outbox_path(files_dir), messages)
}

fn channel_name(config: &serde_json::Value) -> Option<String> {
    ["name", "channel_name", "channelName", "id", "type"]
        .iter()
        .find_map(|key| {
            config
                .get(key)
                .and_then(serde_json::Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string)
        })
}

fn channel_type(config: &serde_json::Value) -> Option<String> {
    ["type", "channel_type", "channelType"]
        .iter()
        .find_map(|key| {
            config
                .get(key)
                .and_then(serde_json::Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string)
        })
}

fn optional_string(config: &serde_json::Value, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        config
            .get(key)
            .and_then(serde_json::Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
    })
}

fn parse_enum<T>(value: &str) -> Option<T>
where
    T: for<'de> Deserialize<'de>,
{
    serde_json::from_value(serde_json::Value::String(value.to_string())).ok()
}

fn surface_kind(
    config: &serde_json::Value,
    channel_type: Option<&str>,
) -> Option<ChannelSurfaceKind> {
    if let Some(value) = optional_string(
        config,
        &["surface_kind", "surfaceKind", "channel_kind", "channelKind"],
    ) {
        return parse_enum(&value);
    }
    channel_type.and_then(|value| {
        if is_known_im_channel(value) {
            Some(ChannelSurfaceKind::Im)
        } else {
            None
        }
    })
}

fn endpoint_kind(config: &serde_json::Value) -> Option<ChannelEndpointKind> {
    optional_string(
        config,
        &["endpoint_kind", "endpointKind", "peer_kind", "peerKind"],
    )
    .and_then(|value| parse_enum(&value))
}

fn modalities(config: &serde_json::Value) -> Vec<ChannelModality> {
    let Some(values) = config
        .get("modalities")
        .or_else(|| config.get("supported_modalities"))
        .or_else(|| config.get("supportedModalities"))
        .and_then(serde_json::Value::as_array)
    else {
        return Vec::new();
    };
    values
        .iter()
        .filter_map(serde_json::Value::as_str)
        .filter_map(parse_enum)
        .collect()
}

fn normalize_content_format(value: &str) -> String {
    match value.trim().to_ascii_lowercase().replace('-', "_").as_str() {
        "" | "text" | "plain" | "plain_text" => CHANNEL_CONTENT_FORMAT_PLAIN_TEXT.to_string(),
        "md" | "markdown" => CHANNEL_CONTENT_FORMAT_MARKDOWN.to_string(),
        other => other.to_string(),
    }
}

fn content_formats(config: &serde_json::Value) -> Vec<String> {
    let Some(values) = config
        .get("content_formats")
        .or_else(|| config.get("contentFormats"))
        .or_else(|| config.get("supported_content_formats"))
        .or_else(|| config.get("supportedContentFormats"))
        .and_then(serde_json::Value::as_array)
    else {
        return Vec::new();
    };
    let mut formats = Vec::new();
    for format in values.iter().filter_map(serde_json::Value::as_str) {
        let normalized = normalize_content_format(format);
        if !normalized.is_empty() && !formats.contains(&normalized) {
            formats.push(normalized);
        }
    }
    formats
}

fn transport(config: &serde_json::Value) -> Option<String> {
    optional_string(config, &["transport", "transport_kind", "transportKind"])
}

fn capability_id(surface_kind: Option<ChannelSurfaceKind>) -> Option<String> {
    match surface_kind {
        Some(ChannelSurfaceKind::Im) => Some(CHANNEL_IM_CAPABILITY_ID.to_string()),
        Some(ChannelSurfaceKind::Device) => Some(CHANNEL_DEVICE_CAPABILITY_ID.to_string()),
        _ => None,
    }
}

fn is_known_im_channel(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "discord"
            | "feishu"
            | "lark"
            | "googlechat"
            | "google_chat"
            | "imessage"
            | "irc"
            | "line"
            | "matrix"
            | "mattermost"
            | "msteams"
            | "microsoft_teams"
            | "nextcloud-talk"
            | "nextcloud_talk"
            | "nostr"
            | "qq"
            | "signal"
            | "slack"
            | "sms"
            | "synology_chat"
            | "telegram"
            | "tlon"
            | "twitch"
            | "voice_call"
            | "webchat"
            | "wechat"
            | "whatsapp"
            | "zalo"
            | "zalo_personal"
            | "zalouser"
    )
}

fn json_error(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

fn json_string(value: &impl Serialize, fallback: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| fallback.to_string())
}

fn default_account_id(value: Option<String>) -> String {
    value.unwrap_or_else(|| "default".to_string())
}

fn parse_peer(value: &serde_json::Value) -> Option<ChannelPeer> {
    let peer = value.get("peer").unwrap_or(value);
    let kind = optional_string(peer, &["kind", "peer_kind", "peerKind", "endpoint_kind"])
        .and_then(|value| parse_enum(&value))
        .or_else(|| endpoint_kind(value))
        .unwrap_or(ChannelEndpointKind::Direct);
    let id = optional_string(peer, &["id", "peer_id", "peerId", "to", "target"])?;
    Some(ChannelPeer {
        kind,
        id,
        display_name: optional_string(peer, &["display_name", "displayName", "name"]),
    })
}

fn parse_actor(value: &serde_json::Value, fallback_id: &str) -> ChannelActor {
    let actor = value.get("sender").unwrap_or(value);
    ChannelActor {
        id: optional_string(actor, &["id", "sender_id", "senderId"])
            .unwrap_or_else(|| fallback_id.to_string()),
        display_name: optional_string(actor, &["display_name", "displayName", "name"]),
        is_bot: actor
            .get("is_bot")
            .or_else(|| actor.get("isBot"))
            .and_then(serde_json::Value::as_bool),
    }
}

fn parse_media(value: &serde_json::Value) -> Vec<ChannelMedia> {
    let Some(items) = value.get("media").and_then(serde_json::Value::as_array) else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| {
            let kind = optional_string(item, &["kind", "type", "modality"])
                .and_then(|value| parse_enum(&value))?;
            Some(ChannelMedia {
                kind,
                uri: optional_string(item, &["uri", "url", "path"]),
                mime_type: optional_string(item, &["mime_type", "mimeType"]),
                name: optional_string(item, &["name", "filename", "fileName"]),
                size_bytes: item
                    .get("size_bytes")
                    .or_else(|| item.get("sizeBytes"))
                    .and_then(serde_json::Value::as_u64),
                raw: item.get("raw").cloned(),
            })
        })
        .collect()
}

fn next_id(prefix: &str, len: usize) -> String {
    format!("{}_{}_{}", prefix, Utc::now().timestamp_micros(), len + 1)
}

fn inbound_dedupe_key(message: &ChannelInboundMessage) -> Option<String> {
    message.platform_message_id.as_ref().map(|platform_id| {
        format!(
            "{}:{}:{}:{}:{}",
            message.channel_name,
            message.account_id,
            message.peer.kind as u8,
            message.peer.id,
            platform_id
        )
    })
}

fn outbox_filter(
    message: &ChannelOutboundMessage,
    channel_name: &str,
    account_id: Option<&str>,
) -> bool {
    message.channel_name == channel_name
        && account_id
            .map(|value| message.account_id == value)
            .unwrap_or(true)
}

fn parse_limit(limit: usize) -> usize {
    if limit == 0 { 20 } else { limit.min(100) }
}

pub fn list_channels(files_dir: &str) -> String {
    serde_json::to_string(&load_channels(files_dir)).unwrap_or_else(|_| "[]".to_string())
}

pub fn register_channel(files_dir: &str, config_json: &str) -> bool {
    let Ok(config) = serde_json::from_str::<serde_json::Value>(config_json) else {
        return false;
    };
    let Some(name) = channel_name(&config) else {
        return false;
    };
    let channel_type = channel_type(&config);
    let surface_kind = surface_kind(&config, channel_type.as_deref());
    let endpoint_kind = endpoint_kind(&config);
    let modalities = modalities(&config);
    let content_formats = content_formats(&config);
    let transport = transport(&config);
    let capability_id = capability_id(surface_kind);
    let mut channels = load_channels(files_dir);
    let now = Utc::now();
    if let Some(existing) = channels.iter_mut().find(|channel| channel.name == name) {
        existing.channel_type = channel_type;
        existing.surface_kind = surface_kind;
        existing.endpoint_kind = endpoint_kind;
        existing.modalities = modalities;
        existing.content_formats = content_formats;
        existing.transport = transport;
        existing.capability_id = capability_id;
        existing.config = config;
        existing.updated_at = now;
    } else {
        channels.push(ChannelConfig {
            name,
            channel_type,
            surface_kind,
            endpoint_kind,
            modalities,
            content_formats,
            transport,
            capability_id,
            config,
            registered_at: now,
            updated_at: now,
        });
    }
    save_channels(files_dir, &channels)
}

pub fn unregister_channel(files_dir: &str, channel_name: &str) -> bool {
    let mut channels = load_channels(files_dir);
    let old_len = channels.len();
    channels.retain(|channel| channel.name != channel_name);
    channels.len() != old_len && save_channels(files_dir, &channels)
}

pub fn submit_channel_inbound(files_dir: &str, envelope_json: &str) -> String {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(envelope_json) else {
        return json_error("invalid_json");
    };
    let Some(channel_name) =
        optional_string(&value, &["channel_name", "channelName", "channel", "name"])
    else {
        return json_error("missing_channel_name");
    };
    let Some(peer) = parse_peer(&value) else {
        return json_error("missing_peer");
    };
    let account_id = default_account_id(optional_string(&value, &["account_id", "accountId"]));
    let sender = parse_actor(&value, &peer.id);
    let platform_message_id = optional_string(
        &value,
        &[
            "platform_message_id",
            "platformMessageId",
            "message_id",
            "messageId",
        ],
    );
    let now = Utc::now();
    let mut inbox = load_inbox(files_dir);
    let candidate = ChannelInboundMessage {
        id: optional_string(&value, &["id", "event_id", "eventId"])
            .unwrap_or_else(|| next_id("in", inbox.len())),
        channel_name,
        account_id,
        peer,
        sender,
        platform_message_id,
        thread_id: optional_string(&value, &["thread_id", "threadId"]),
        text: optional_string(&value, &["text", "message"]),
        media: parse_media(&value),
        raw: value.get("raw").cloned(),
        error: None,
        status: "queued".to_string(),
        received_at: now,
        updated_at: now,
    };
    if let Some(key) = inbound_dedupe_key(&candidate)
        && let Some(existing) = inbox
            .iter()
            .find(|message| inbound_dedupe_key(message).as_deref() == Some(key.as_str()))
    {
        return json_string(
            &ChannelAcceptedReceipt {
                accepted: true,
                id: existing.id.clone(),
                duplicate: true,
            },
            r#"{"accepted":true,"duplicate":true}"#,
        );
    }
    let id = candidate.id.clone();
    inbox.push(candidate);
    if !save_inbox(files_dir, &inbox) {
        return json_error("save_failed");
    }
    json_string(
        &ChannelAcceptedReceipt {
            accepted: true,
            id,
            duplicate: false,
        },
        r#"{"accepted":true}"#,
    )
}

pub fn take_channel_inbound(files_dir: &str, channel_name: &str, limit: usize) -> String {
    let limit = parse_limit(limit);
    let mut inbox = load_inbox(files_dir);
    let now = Utc::now();
    let mut selected = Vec::new();
    for message in inbox.iter_mut() {
        if selected.len() >= limit {
            break;
        }
        if message.channel_name == channel_name && message.status == "queued" {
            message.status = "leased".to_string();
            message.updated_at = now;
            selected.push(message.clone());
        }
    }
    if !save_inbox(files_dir, &inbox) {
        return json_error("save_failed");
    }
    json_string(&selected, "[]")
}

pub fn ack_channel_inbound(files_dir: &str, inbound_id: &str) -> bool {
    let mut inbox = load_inbox(files_dir);
    let now = Utc::now();
    let Some(message) = inbox.iter_mut().find(|message| message.id == inbound_id) else {
        return false;
    };
    message.status = "acknowledged".to_string();
    message.error = None;
    message.updated_at = now;
    save_inbox(files_dir, &inbox)
}

pub fn fail_channel_inbound(files_dir: &str, inbound_id: &str, error: &str) -> bool {
    let mut inbox = load_inbox(files_dir);
    let now = Utc::now();
    let Some(message) = inbox.iter_mut().find(|message| message.id == inbound_id) else {
        return false;
    };
    message.status = "failed".to_string();
    message.error = Some(error.to_string());
    message.updated_at = now;
    save_inbox(files_dir, &inbox)
}

pub fn release_channel_inbound(files_dir: &str, inbound_id: &str) -> bool {
    let mut inbox = load_inbox(files_dir);
    let now = Utc::now();
    let Some(message) = inbox.iter_mut().find(|message| message.id == inbound_id) else {
        return false;
    };
    message.status = "queued".to_string();
    message.error = None;
    message.updated_at = now;
    save_inbox(files_dir, &inbox)
}

pub fn enqueue_channel_outbound(files_dir: &str, outbound_json: &str) -> String {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(outbound_json) else {
        return json_error("invalid_json");
    };
    let Some(channel_name) =
        optional_string(&value, &["channel_name", "channelName", "channel", "name"])
    else {
        return json_error("missing_channel_name");
    };
    let Some(peer) = parse_peer(&value) else {
        return json_error("missing_peer");
    };
    if optional_string(&value, &["text", "message"]).is_none() && parse_media(&value).is_empty() {
        return json_error("missing_payload");
    }
    let now = Utc::now();
    let mut outbox = load_outbox(files_dir);
    let message = ChannelOutboundMessage {
        id: optional_string(&value, &["id", "client_message_id", "clientMessageId"])
            .unwrap_or_else(|| next_id("out", outbox.len())),
        channel_name,
        account_id: default_account_id(optional_string(&value, &["account_id", "accountId"])),
        peer,
        reply_to_message_id: optional_string(
            &value,
            &[
                "reply_to_message_id",
                "replyToMessageId",
                "reply_to",
                "replyTo",
            ],
        ),
        thread_id: optional_string(&value, &["thread_id", "threadId"]),
        text: optional_string(&value, &["text", "message"]),
        format: Some(normalize_content_format(
            optional_string(&value, &["format", "content_format", "contentFormat"])
                .as_deref()
                .unwrap_or(CHANNEL_CONTENT_FORMAT_PLAIN_TEXT),
        )),
        media: parse_media(&value),
        raw: value.get("raw").cloned(),
        lease_id: None,
        platform_receipt: None,
        error: None,
        status: "queued".to_string(),
        created_at: now,
        updated_at: now,
    };
    let id = message.id.clone();
    outbox.push(message);
    if !save_outbox(files_dir, &outbox) {
        return json_error("save_failed");
    }
    json_string(
        &ChannelAcceptedReceipt {
            accepted: true,
            id,
            duplicate: false,
        },
        r#"{"accepted":true}"#,
    )
}

pub fn reply_channel_inbound(files_dir: &str, inbound_id: &str, reply_json: &str) -> String {
    let inbox = load_inbox(files_dir);
    let Some(inbound) = inbox.iter().find(|message| message.id == inbound_id) else {
        return json_error("missing_inbound");
    };
    let Ok(mut value) = serde_json::from_str::<serde_json::Value>(reply_json) else {
        return json_error("invalid_json");
    };
    if !value.is_object() {
        return json_error("invalid_json");
    }
    let Some(object) = value.as_object_mut() else {
        return json_error("invalid_json");
    };
    object.insert(
        "channel_name".to_string(),
        serde_json::Value::String(inbound.channel_name.clone()),
    );
    object.insert(
        "account_id".to_string(),
        serde_json::Value::String(inbound.account_id.clone()),
    );
    object.insert(
        "peer".to_string(),
        serde_json::to_value(&inbound.peer).unwrap_or(serde_json::Value::Null),
    );
    if let Some(message_id) = inbound.platform_message_id.as_ref() {
        object.insert(
            "reply_to_message_id".to_string(),
            serde_json::Value::String(message_id.clone()),
        );
    }
    if let Some(thread_id) = inbound.thread_id.as_ref() {
        object.insert(
            "thread_id".to_string(),
            serde_json::Value::String(thread_id.clone()),
        );
    }
    enqueue_channel_outbound(files_dir, &value.to_string())
}

pub fn lease_channel_outbound(
    files_dir: &str,
    channel_name: &str,
    account_id: Option<&str>,
    limit: usize,
) -> String {
    let limit = parse_limit(limit);
    let mut outbox = load_outbox(files_dir);
    let now = Utc::now();
    let lease_id = next_id("lease", outbox.len());
    let mut selected = Vec::new();
    for message in outbox.iter_mut() {
        if selected.len() >= limit {
            break;
        }
        if outbox_filter(message, channel_name, account_id) && message.status == "queued" {
            message.status = "leased".to_string();
            message.lease_id = Some(lease_id.clone());
            message.updated_at = now;
            selected.push(message.clone());
        }
    }
    if !save_outbox(files_dir, &outbox) {
        return json_error("save_failed");
    }
    json_string(&selected, "[]")
}

pub fn ack_channel_outbound(files_dir: &str, outbound_id: &str, receipt_json: &str) -> bool {
    let receipt = serde_json::from_str::<serde_json::Value>(receipt_json).ok();
    let mut outbox = load_outbox(files_dir);
    let now = Utc::now();
    let Some(message) = outbox.iter_mut().find(|message| message.id == outbound_id) else {
        return false;
    };
    message.status = "sent".to_string();
    message.platform_receipt = receipt;
    message.error = None;
    message.updated_at = now;
    save_outbox(files_dir, &outbox)
}

pub fn fail_channel_outbound(files_dir: &str, outbound_id: &str, error: &str) -> bool {
    let mut outbox = load_outbox(files_dir);
    let now = Utc::now();
    let Some(message) = outbox.iter_mut().find(|message| message.id == outbound_id) else {
        return false;
    };
    message.status = "failed".to_string();
    message.error = Some(error.to_string());
    message.updated_at = now;
    save_outbox(files_dir, &outbox)
}

fn channel_files_dir_from_handle(handle: i64, subject: &str) -> Result<String, String> {
    // SAFETY: The handle comes from the public engine API. Invalid or disposed
    // handles are represented as `None` and surfaced as `invalid_handle`.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return Err("invalid_handle".to_string());
    };
    let profile = engine.capability_profile();
    let selection = engine.capability_selection();
    let im_result = crate::capabilities::admit_service_for_config(
        CHANNEL_IM_CAPABILITY_ID,
        subject,
        engine.platform(),
        &profile,
        &selection,
    );
    if im_result.is_err() {
        crate::capabilities::admit_service_for_config(
            CHANNEL_DEVICE_CAPABILITY_ID,
            subject,
            engine.platform(),
            &profile,
            &selection,
        )
        .map_err(|device_error| {
            format!(
                "{}; {}",
                im_result
                    .err()
                    .map(|error| error.to_string())
                    .unwrap_or_else(|| "channel im capability denied".to_string()),
                device_error
            )
        })?;
    }
    Ok(engine.files_dir().to_string())
}

fn channel_files_dir_for_bool(handle: i64, subject: &str) -> Option<String> {
    channel_files_dir_from_handle(handle, subject).ok()
}

pub fn list_channels_handle(handle: i64) -> String {
    let Ok(files_dir) = channel_files_dir_from_handle(handle, "channel.list") else {
        return "[]".to_string();
    };
    list_channels(&files_dir)
}

pub fn register_channel_handle(handle: i64, config_json: &str) -> bool {
    let Some(files_dir) = channel_files_dir_for_bool(handle, "channel.register") else {
        return false;
    };
    register_channel(&files_dir, config_json)
}

pub fn unregister_channel_handle(handle: i64, channel_name: &str) -> bool {
    let Some(files_dir) = channel_files_dir_for_bool(handle, "channel.unregister") else {
        return false;
    };
    unregister_channel(&files_dir, channel_name)
}

pub fn submit_channel_inbound_handle(handle: i64, envelope_json: &str) -> String {
    let files_dir = match channel_files_dir_from_handle(handle, "channel.submit_inbound") {
        Ok(files_dir) => files_dir,
        Err(error) => return json_error(&error),
    };
    submit_channel_inbound(&files_dir, envelope_json)
}

pub fn take_channel_inbound_handle(handle: i64, channel_name: &str, limit: usize) -> String {
    let Ok(files_dir) = channel_files_dir_from_handle(handle, "channel.take_inbound") else {
        return "[]".to_string();
    };
    take_channel_inbound(&files_dir, channel_name, limit)
}

pub fn ack_channel_inbound_handle(handle: i64, inbound_id: &str) -> bool {
    let Some(files_dir) = channel_files_dir_for_bool(handle, "channel.ack_inbound") else {
        return false;
    };
    ack_channel_inbound(&files_dir, inbound_id)
}

pub fn fail_channel_inbound_handle(handle: i64, inbound_id: &str, error: &str) -> bool {
    let Some(files_dir) = channel_files_dir_for_bool(handle, "channel.fail_inbound") else {
        return false;
    };
    fail_channel_inbound(&files_dir, inbound_id, error)
}

pub fn release_channel_inbound_handle(handle: i64, inbound_id: &str) -> bool {
    let Some(files_dir) = channel_files_dir_for_bool(handle, "channel.release_inbound") else {
        return false;
    };
    release_channel_inbound(&files_dir, inbound_id)
}

pub fn enqueue_channel_outbound_handle(handle: i64, outbound_json: &str) -> String {
    let files_dir = match channel_files_dir_from_handle(handle, "channel.enqueue_outbound") {
        Ok(files_dir) => files_dir,
        Err(error) => return json_error(&error),
    };
    enqueue_channel_outbound(&files_dir, outbound_json)
}

pub fn reply_channel_inbound_handle(handle: i64, inbound_id: &str, reply_json: &str) -> String {
    let files_dir = match channel_files_dir_from_handle(handle, "channel.reply_inbound") {
        Ok(files_dir) => files_dir,
        Err(error) => return json_error(&error),
    };
    reply_channel_inbound(&files_dir, inbound_id, reply_json)
}

pub fn lease_channel_outbound_handle(
    handle: i64,
    channel_name: &str,
    account_id: Option<&str>,
    limit: usize,
) -> String {
    let Ok(files_dir) = channel_files_dir_from_handle(handle, "channel.lease_outbound") else {
        return "[]".to_string();
    };
    lease_channel_outbound(&files_dir, channel_name, account_id, limit)
}

pub fn ack_channel_outbound_handle(handle: i64, outbound_id: &str, receipt_json: &str) -> bool {
    let Some(files_dir) = channel_files_dir_for_bool(handle, "channel.ack_outbound") else {
        return false;
    };
    ack_channel_outbound(&files_dir, outbound_id, receipt_json)
}

pub fn fail_channel_outbound_handle(handle: i64, outbound_id: &str, error: &str) -> bool {
    let Some(files_dir) = channel_files_dir_for_bool(handle, "channel.fail_outbound") else {
        return false;
    };
    fail_channel_outbound(&files_dir, outbound_id, error)
}

#[cfg(test)]
mod tests;
