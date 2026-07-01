//! Core-owned channel-to-agent runtime orchestration.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

use crate::channel::{self, ChannelEndpointKind, ChannelInboundMessage, ChannelMedia, ChannelPeer};
use crate::session::SessionKey;

const ROUTES_FILE: &str = "channel_agent_routes.json";
const PENDING_FILE: &str = "channel_agent_pending_human.json";
const DEFAULT_EMPTY_RESPONSE: &str = "napaxi 已收到，但这次没有生成可发送的文本回复。";
const DEFAULT_HUMAN_ANSWER_REQUIRED: &str = "这条 napaxi 提问需要文本回复，请直接发送文字。";
const DEFAULT_HUMAN_ANSWER_FAILED: &str = "napaxi 没有找到可继续的人工确认请求，请重新发起。";

mod media;
mod state;
mod text;

use media::{append_tool_result_media, attachments_json_from_channel_media};
use state::{
    channel_event_json, find_pending_by_request, find_pending_by_session, parse_json_value,
    remove_pending_by_request, remove_pending_by_session, replace_pending, upsert_pending_human,
};
use text::{agent_input, display_text, human_question_text};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChannelSessionPolicy {
    StableByPeerOrThread,
}

impl Default for ChannelSessionPolicy {
    fn default() -> Self {
        Self::StableByPeerOrThread
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelAgentRoute {
    #[serde(default, alias = "routeId")]
    pub id: String,
    #[serde(default, alias = "channelName", alias = "channel")]
    pub channel_name: String,
    #[serde(
        default,
        alias = "channelAccountId",
        alias = "account_id",
        alias = "accountId",
        skip_serializing_if = "Option::is_none"
    )]
    pub channel_account_id: Option<String>,
    #[serde(default, alias = "peerKind", skip_serializing_if = "Option::is_none")]
    pub peer_kind: Option<ChannelEndpointKind>,
    #[serde(default, alias = "peerId", skip_serializing_if = "Option::is_none")]
    pub peer_id: Option<String>,
    #[serde(default, alias = "threadId", skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
    #[serde(default, alias = "sessionAccountId")]
    pub session_account_id: String,
    #[serde(default, alias = "agentId")]
    pub agent_id: String,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default, alias = "sessionPolicy")]
    pub session_policy: ChannelSessionPolicy,
    #[serde(default = "now_utc")]
    pub created_at: DateTime<Utc>,
    #[serde(default = "now_utc")]
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelAgentBridgeConfig {
    #[serde(default, alias = "channelName", alias = "channel")]
    pub channel_name: String,
    #[serde(default, alias = "sessionAccountId", alias = "accountId")]
    pub session_account_id: String,
    #[serde(default, alias = "defaultAgentId", alias = "agentId")]
    pub default_agent_id: String,
    #[serde(default, alias = "inboundLimit")]
    pub inbound_limit: usize,
    #[serde(default, alias = "maxIterations")]
    pub max_iterations: i32,
    #[serde(default, alias = "emptyResponseText")]
    pub empty_response_text: Option<String>,
    #[serde(default, alias = "humanAnswerRequiredText")]
    pub human_answer_required_text: Option<String>,
    #[serde(default, alias = "humanAnswerFailedText")]
    pub human_answer_failed_text: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResolvedChannelAgentRoute {
    pub channel_name: String,
    pub channel_account_id: String,
    pub session_account_id: String,
    pub agent_id: String,
    pub session_policy: ChannelSessionPolicy,
    pub session_key: SessionKey,
    pub route_id: Option<String>,
    pub route_source: String,
    pub display_text: String,
    pub agent_input: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PendingHumanMapping {
    request_id: String,
    channel_name: String,
    agent_id: String,
    session_key: SessionKey,
    original_inbound_id: String,
    answer_inbound_id: Option<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone)]
struct InboundRunContext {
    inbound: ChannelInboundMessage,
    resolved: ResolvedChannelAgentRoute,
    session_key_json: String,
}

fn default_enabled() -> bool {
    true
}

fn now_utc() -> DateTime<Utc> {
    Utc::now()
}

fn routes_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join(ROUTES_FILE)
}

fn pending_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join(PENDING_FILE)
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

fn load_routes(files_dir: &str) -> Vec<ChannelAgentRoute> {
    load_json_vec(routes_path(files_dir))
}

fn save_routes(files_dir: &str, routes: &[ChannelAgentRoute]) -> bool {
    save_json_vec(routes_path(files_dir), routes)
}

fn load_pending(files_dir: &str) -> Vec<PendingHumanMapping> {
    load_json_vec(pending_path(files_dir))
}

fn save_pending(files_dir: &str, mappings: &[PendingHumanMapping]) -> bool {
    save_json_vec(pending_path(files_dir), mappings)
}

fn json_error(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

fn json_string<T: Serialize>(value: &T, fallback: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| fallback.to_string())
}

fn normalize_text(value: impl Into<String>, fallback: &str) -> String {
    let value = value.into();
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

fn normalize_option(value: Option<String>) -> Option<String> {
    value.and_then(|item| {
        let trimmed = item.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

fn normalize_config(mut config: ChannelAgentBridgeConfig) -> ChannelAgentBridgeConfig {
    config.channel_name = normalize_text(config.channel_name, "");
    config.session_account_id = normalize_text(
        config.session_account_id,
        crate::runtime::DEFAULT_ACCOUNT_ID,
    );
    config.default_agent_id =
        normalize_text(config.default_agent_id, crate::runtime::DEFAULT_AGENT_ID);
    config.inbound_limit = if config.inbound_limit == 0 {
        1
    } else {
        config.inbound_limit.min(20)
    };
    config
}

fn normalize_route(
    mut route: ChannelAgentRoute,
    fallback_session_account_id: &str,
    fallback_agent_id: &str,
) -> Option<ChannelAgentRoute> {
    route.channel_name = normalize_text(route.channel_name, "");
    if route.channel_name.is_empty() {
        return None;
    }
    route.channel_account_id = normalize_option(route.channel_account_id);
    route.peer_id = normalize_option(route.peer_id);
    route.thread_id = normalize_option(route.thread_id);
    route.session_account_id =
        normalize_text(route.session_account_id, fallback_session_account_id);
    route.agent_id = normalize_text(route.agent_id, fallback_agent_id);
    if route.id.trim().is_empty() {
        route.id = route_id(&route);
    } else {
        route.id = route.id.trim().to_string();
    }
    Some(route)
}

fn route_id(route: &ChannelAgentRoute) -> String {
    let seed = format!(
        "napaxi.channel_agent.route.v1|{}|{}|{}|{}|{}|{}",
        route.channel_name,
        route.channel_account_id.as_deref().unwrap_or("*"),
        route.peer_id.as_deref().unwrap_or("*"),
        route.thread_id.as_deref().unwrap_or("*"),
        route.session_account_id,
        route.agent_id
    );
    format!(
        "route_{}",
        Uuid::new_v5(&Uuid::NAMESPACE_OID, seed.as_bytes()).simple()
    )
}

fn parse_bridge_config(config_json: &str) -> Result<ChannelAgentBridgeConfig, String> {
    let config = serde_json::from_str::<ChannelAgentBridgeConfig>(config_json)
        .map_err(|error| format!("invalid_bridge_config: {error}"))?;
    let config = normalize_config(config);
    if config.channel_name.is_empty() {
        Err("missing_channel_name".to_string())
    } else {
        Ok(config)
    }
}

pub fn register_channel_agent_route(files_dir: &str, route_json: &str) -> String {
    let Ok(route) = serde_json::from_str::<ChannelAgentRoute>(route_json) else {
        return json_error("invalid_json");
    };
    let Some(mut route) = normalize_route(
        route,
        crate::runtime::DEFAULT_ACCOUNT_ID,
        crate::runtime::DEFAULT_AGENT_ID,
    ) else {
        return json_error("missing_channel_name");
    };
    let mut routes = load_routes(files_dir);
    let now = Utc::now();
    if let Some(existing) = routes.iter_mut().find(|existing| existing.id == route.id) {
        route.created_at = existing.created_at;
        route.updated_at = now;
        *existing = route.clone();
    } else {
        route.created_at = now;
        route.updated_at = now;
        routes.push(route.clone());
    }
    if !save_routes(files_dir, &routes) {
        return json_error("save_failed");
    }
    json_string(&route, r#"{"error":"serialize_failed"}"#)
}

pub fn list_channel_agent_routes(files_dir: &str, channel_name: Option<&str>) -> String {
    let channel_name = channel_name
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let routes: Vec<_> = load_routes(files_dir)
        .into_iter()
        .filter(|route| {
            channel_name
                .map(|name| route.channel_name == name)
                .unwrap_or(true)
        })
        .collect();
    json_string(&routes, "[]")
}

pub fn remove_channel_agent_route(files_dir: &str, route_id: &str) -> bool {
    let mut routes = load_routes(files_dir);
    let old_len = routes.len();
    routes.retain(|route| route.id != route_id);
    routes.len() != old_len && save_routes(files_dir, &routes)
}

pub fn resolve_channel_agent_route(
    files_dir: &str,
    bridge_config_json: &str,
    inbound_json: &str,
) -> String {
    let Ok(config) = parse_bridge_config(bridge_config_json) else {
        return json_error("invalid_bridge_config");
    };
    let Ok(inbound) = serde_json::from_str::<ChannelInboundMessage>(inbound_json) else {
        return json_error("invalid_inbound");
    };
    match resolve_route(files_dir, &config, &inbound) {
        Some(route) => json_string(&route, r#"{"error":"serialize_failed"}"#),
        None => json_error("route_not_found"),
    }
}

pub fn channel_agent_status(files_dir: &str, channel_name: Option<&str>) -> String {
    let channel_name = channel_name
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let routes: Vec<_> = load_routes(files_dir)
        .into_iter()
        .filter(|route| {
            channel_name
                .map(|name| route.channel_name == name)
                .unwrap_or(true)
        })
        .collect();
    let pending: Vec<_> = load_pending(files_dir)
        .into_iter()
        .filter(|mapping| {
            channel_name
                .map(|name| mapping.channel_name == name)
                .unwrap_or(true)
        })
        .collect();
    serde_json::json!({
        "routes": routes,
        "pending_human": pending,
    })
    .to_string()
}

fn channel_agent_files_dir_from_handle(handle: i64, subject: &str) -> Result<String, String> {
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return Err("invalid_handle".to_string());
    };
    let profile = engine.capability_profile();
    let selection = engine.capability_selection();
    let im_result = crate::capabilities::admit_service_for_config(
        channel::CHANNEL_IM_CAPABILITY_ID,
        subject,
        engine.platform(),
        &profile,
        &selection,
    );
    if im_result.is_err() {
        crate::capabilities::admit_service_for_config(
            channel::CHANNEL_DEVICE_CAPABILITY_ID,
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

fn channel_agent_files_dir_for_bool(handle: i64, subject: &str) -> Option<String> {
    channel_agent_files_dir_from_handle(handle, subject).ok()
}

pub fn register_channel_agent_route_handle(handle: i64, route_json: &str) -> String {
    let files_dir =
        match channel_agent_files_dir_from_handle(handle, "channel_agent.register_route") {
            Ok(files_dir) => files_dir,
            Err(error) => return json_error(&error),
        };
    register_channel_agent_route(&files_dir, route_json)
}

pub fn list_channel_agent_routes_handle(handle: i64, channel_name: Option<&str>) -> String {
    let Ok(files_dir) = channel_agent_files_dir_from_handle(handle, "channel_agent.list_routes")
    else {
        return "[]".to_string();
    };
    list_channel_agent_routes(&files_dir, channel_name)
}

pub fn remove_channel_agent_route_handle(handle: i64, route_id: &str) -> bool {
    let Some(files_dir) = channel_agent_files_dir_for_bool(handle, "channel_agent.remove_route")
    else {
        return false;
    };
    remove_channel_agent_route(&files_dir, route_id)
}

pub fn resolve_channel_agent_route_handle(
    handle: i64,
    bridge_config_json: &str,
    inbound_json: &str,
) -> String {
    let files_dir = match channel_agent_files_dir_from_handle(handle, "channel_agent.resolve_route")
    {
        Ok(files_dir) => files_dir,
        Err(error) => return json_error(&error),
    };
    resolve_channel_agent_route(&files_dir, bridge_config_json, inbound_json)
}

pub fn channel_agent_status_handle(handle: i64, channel_name: Option<&str>) -> String {
    let files_dir = match channel_agent_files_dir_from_handle(handle, "channel_agent.status") {
        Ok(files_dir) => files_dir,
        Err(error) => return json_error(&error),
    };
    channel_agent_status(&files_dir, channel_name)
}

pub async fn stream_channel_agent_pump_handle<F>(
    handle: i64,
    config_json: &str,
    bridge_config_json: &str,
    mut emit: F,
) where
    F: FnMut(String),
{
    let files_dir = match channel_agent_files_dir_from_handle(handle, "channel_agent.stream_pump") {
        Ok(files_dir) => files_dir,
        Err(error) => {
            emit(json_error(&error));
            return;
        }
    };
    let config = match parse_bridge_config(bridge_config_json) {
        Ok(config) => config,
        Err(error) => {
            emit(json_error(&error));
            return;
        }
    };
    let inbound_json =
        channel::take_channel_inbound(&files_dir, &config.channel_name, config.inbound_limit);
    let inbounds =
        serde_json::from_str::<Vec<ChannelInboundMessage>>(&inbound_json).unwrap_or_default();
    if inbounds.is_empty() {
        return;
    };

    for inbound in inbounds {
        let Some(resolved) = resolve_route(&files_dir, &config, &inbound) else {
            let _ = channel::fail_channel_inbound(&files_dir, &inbound.id, "route_not_found");
            emit(channel_event_json(
                "failed",
                &inbound,
                None,
                serde_json::json!({"error":"route_not_found"}),
            ));
            continue;
        };
        let _ = crate::runtime::get_or_create_agent_handle(handle, &resolved.agent_id);
        let session_key_json = crate::session::create_session(
            &files_dir,
            &resolved.agent_id,
            &resolved.channel_name,
            &resolved.session_account_id,
            Some(&resolved.session_key.thread_id),
        );
        if serde_json::from_str::<SessionKey>(&session_key_json).is_err() {
            let _ = channel::fail_channel_inbound(&files_dir, &inbound.id, "session_create_failed");
            emit(channel_event_json(
                "failed",
                &inbound,
                Some(&resolved),
                serde_json::json!({"error":"session_create_failed"}),
            ));
            continue;
        }
        let context = InboundRunContext {
            inbound,
            resolved,
            session_key_json,
        };
        if handle_pending_answer(&files_dir, &config, &context, &mut emit) {
            continue;
        }
        drive_agent_for_inbound(handle, &files_dir, config_json, &config, context, &mut emit).await;
    }
}

async fn drive_agent_for_inbound<F>(
    handle: i64,
    files_dir: &str,
    config_json: &str,
    config: &ChannelAgentBridgeConfig,
    context: InboundRunContext,
    emit: &mut F,
) where
    F: FnMut(String),
{
    let mut reply_target_id = context.inbound.id.clone();
    let mut response_buffer = String::new();
    let mut saw_delta = false;
    let mut final_response: Option<String> = None;
    let mut failure_reason: Option<String> = None;
    let mut response_media: Vec<ChannelMedia> = Vec::new();
    emit(channel_event_json(
        "inbound_received",
        &context.inbound,
        Some(&context.resolved),
        serde_json::json!({
            "display_text": context.resolved.display_text,
            "route_source": context.resolved.route_source,
        }),
    ));
    let attachments_json = attachments_json_from_channel_media(&context.inbound.media);
    crate::runtime::stream_to_session_with_display_handle(
        handle,
        config_json,
        &context.resolved.agent_id,
        &context.session_key_json,
        &context.resolved.agent_input,
        Some(&context.resolved.display_text),
        &attachments_json,
        config.max_iterations,
        |chat_event_json| {
            let chat_event =
                serde_json::from_str::<Value>(&chat_event_json).unwrap_or(Value::Null);
            let chat_type = chat_event
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or("");
            match chat_type {
                "response_delta" => {
                    saw_delta = true;
                    if let Some(content) = chat_event.get("content").and_then(Value::as_str) {
                        response_buffer.push_str(content);
                    }
                }
                "response" => {
                    if !saw_delta {
                        final_response = chat_event
                            .get("content")
                            .and_then(Value::as_str)
                            .map(str::to_string);
                    }
                }
                "stream_reset" => {
                    saw_delta = false;
                    response_buffer.clear();
                    final_response = None;
                }
                "asking_human" => {
                    if let Some(request_id) = chat_event.get("request_id").and_then(Value::as_str) {
                        let question = human_question_text(&chat_event);
                        upsert_pending_human(files_dir, &context, request_id);
                        let receipt = channel::reply_channel_inbound(
                            files_dir,
                            &context.inbound.id,
                            &serde_json::json!({
                                "text": question,
                                "format": channel::CHANNEL_CONTENT_FORMAT_MARKDOWN,
                                "raw": {"status":"asking_human","request_id":request_id}
                            })
                            .to_string(),
                        );
                        let _ = channel::ack_channel_inbound(files_dir, &context.inbound.id);
                        emit(channel_event_json(
                            "human_question_queued",
                            &context.inbound,
                            Some(&context.resolved),
                            serde_json::json!({
                                "chat_event": chat_event,
                                "human_request_id": request_id,
                                "human_question": question,
                                "human_options": chat_event.get("options").cloned().unwrap_or(Value::Null),
                                "human_context": chat_event.get("context").cloned().unwrap_or(Value::Null),
                                "outbound_receipt": parse_json_value(&receipt),
                            }),
                        ));
                    }
                }
                "human_response" => {
                    if let Some(request_id) = chat_event.get("request_id").and_then(Value::as_str)
                    {
                        if let Some(pending) = find_pending_by_request(files_dir, request_id) {
                            if let Some(answer_id) = pending.answer_inbound_id {
                                reply_target_id = answer_id;
                            }
                        }
                    }
                    saw_delta = false;
                    response_buffer.clear();
                    final_response = None;
                }
                "tool_result" => append_tool_result_media(&mut response_media, &chat_event),
                "error" => failure_reason = Some(chat_error_message(&chat_event)),
                _ => {}
            }
            emit(channel_event_json(
                "chat_event",
                &context.inbound,
                Some(&context.resolved),
                serde_json::json!({"chat_event": chat_event}),
            ));
        },
    )
    .await;

    if let Some(reason) = failure_reason {
        let _ = channel::fail_channel_inbound(files_dir, &context.inbound.id, "agent_run_failed");
        let _ = channel::reply_channel_inbound(
            files_dir,
            &reply_target_id,
            &serde_json::json!({
                "text":"napaxi 执行失败，请稍后重试。",
                "format": channel::CHANNEL_CONTENT_FORMAT_PLAIN_TEXT,
                "raw":{"status":"failed","error":reason}
            })
            .to_string(),
        );
        remove_pending_by_session(files_dir, &context.resolved.session_key);
        emit(channel_event_json(
            "failed",
            &context.inbound,
            Some(&context.resolved),
            serde_json::json!({"error":reason}),
        ));
        return;
    }

    let response = if saw_delta {
        response_buffer.trim().to_string()
    } else {
        final_response.unwrap_or_default().trim().to_string()
    };
    let response_is_empty = response.is_empty();
    let reply = if response_is_empty {
        config
            .empty_response_text
            .clone()
            .unwrap_or_else(|| DEFAULT_EMPTY_RESPONSE.to_string())
    } else {
        response
    };
    let reply_format = if response_is_empty {
        channel::CHANNEL_CONTENT_FORMAT_PLAIN_TEXT
    } else {
        channel::CHANNEL_CONTENT_FORMAT_MARKDOWN
    };
    let response_media_count = response_media.len();
    let receipt = channel::reply_channel_inbound(
        files_dir,
        &reply_target_id,
        &serde_json::json!({
            "text": reply,
            "format": reply_format,
            "media": response_media,
            "raw": {
                "status": "final",
                "media_count": response_media_count,
            }
        })
        .to_string(),
    );
    let _ = channel::ack_channel_inbound(files_dir, &reply_target_id);
    remove_pending_by_session(files_dir, &context.resolved.session_key);
    emit(channel_event_json(
        "outbound_queued",
        &context.inbound,
        Some(&context.resolved),
        serde_json::json!({
            "response_text": reply,
            "reply_inbound_id": reply_target_id,
            "outbound_receipt": parse_json_value(&receipt),
        }),
    ));
    emit(channel_event_json(
        "completed",
        &context.inbound,
        Some(&context.resolved),
        serde_json::json!({"reply_inbound_id": reply_target_id}),
    ));
}

fn handle_pending_answer<F>(
    files_dir: &str,
    config: &ChannelAgentBridgeConfig,
    context: &InboundRunContext,
    emit: &mut F,
) -> bool
where
    F: FnMut(String),
{
    let Some(mut pending) = find_pending_by_session(files_dir, &context.resolved.session_key)
    else {
        return false;
    };
    let answer = context.inbound.text.as_deref().unwrap_or("").trim();
    if answer.is_empty() {
        let reply = config
            .human_answer_required_text
            .clone()
            .unwrap_or_else(|| DEFAULT_HUMAN_ANSWER_REQUIRED.to_string());
        let _ = channel::reply_channel_inbound(
            files_dir,
            &context.inbound.id,
            &serde_json::json!({
                "text": reply,
                "format": channel::CHANNEL_CONTENT_FORMAT_PLAIN_TEXT,
                "raw":{"status":"human_answer_rejected"}
            })
            .to_string(),
        );
        let _ = channel::ack_channel_inbound(files_dir, &context.inbound.id);
        emit(channel_event_json(
            "human_answer_received",
            &context.inbound,
            Some(&context.resolved),
            serde_json::json!({
                "human_request_id": pending.request_id,
                "accepted": false,
                "error": "empty_answer",
            }),
        ));
        return true;
    }
    pending.answer_inbound_id = Some(context.inbound.id.clone());
    pending.updated_at = Utc::now();
    replace_pending(files_dir, pending.clone());
    let ok = crate::human_loop::answer_human_request(&pending.request_id, answer);
    if ok {
        let _ = channel::ack_channel_inbound(files_dir, &context.inbound.id);
        emit(channel_event_json(
            "human_answer_received",
            &context.inbound,
            Some(&context.resolved),
            serde_json::json!({
                "human_request_id": pending.request_id,
                "accepted": true,
            }),
        ));
    } else {
        remove_pending_by_request(files_dir, &pending.request_id);
        let reply = config
            .human_answer_failed_text
            .clone()
            .unwrap_or_else(|| DEFAULT_HUMAN_ANSWER_FAILED.to_string());
        let _ = channel::reply_channel_inbound(
            files_dir,
            &context.inbound.id,
            &serde_json::json!({
                "text": reply,
                "format": channel::CHANNEL_CONTENT_FORMAT_PLAIN_TEXT,
                "raw":{"status":"human_answer_failed"}
            })
            .to_string(),
        );
        let _ = channel::fail_channel_inbound(files_dir, &context.inbound.id, "human_request_gone");
        emit(channel_event_json(
            "human_answer_received",
            &context.inbound,
            Some(&context.resolved),
            serde_json::json!({
                "human_request_id": pending.request_id,
                "accepted": false,
                "error": "human_request_gone",
            }),
        ));
    }
    true
}

fn resolve_route(
    files_dir: &str,
    config: &ChannelAgentBridgeConfig,
    inbound: &ChannelInboundMessage,
) -> Option<ResolvedChannelAgentRoute> {
    if inbound.channel_name != config.channel_name {
        return None;
    }
    let routes = load_routes(files_dir);
    let best = routes
        .iter()
        .filter(|route| route.enabled && route.channel_name == inbound.channel_name)
        .filter(|route| {
            route
                .channel_account_id
                .as_deref()
                .map(|account| account == inbound.account_id)
                .unwrap_or(true)
        })
        .filter_map(|route| route_score(route, inbound).map(|score| (score, route)))
        .max_by_key(|(score, _)| *score)
        .map(|(_, route)| route.clone());
    let (agent_id, session_account_id, session_policy, route_id, route_source) =
        if let Some(route) = best {
            let source = route_source(&route);
            (
                normalize_text(route.agent_id, &config.default_agent_id),
                normalize_text(route.session_account_id, &config.session_account_id),
                route.session_policy,
                Some(route.id),
                source,
            )
        } else {
            (
                config.default_agent_id.clone(),
                config.session_account_id.clone(),
                ChannelSessionPolicy::StableByPeerOrThread,
                None,
                "bridge_default".to_string(),
            )
        };
    let thread_id = stable_session_thread_id(
        &inbound.channel_name,
        &session_account_id,
        &agent_id,
        &inbound.account_id,
        &inbound.peer,
        conversation_thread_id(&inbound),
        &inbound.sender.id,
    );
    let session_key = SessionKey {
        channel_type: inbound.channel_name.clone(),
        account_id: session_account_id.clone(),
        thread_id,
    };
    Some(ResolvedChannelAgentRoute {
        channel_name: inbound.channel_name.clone(),
        channel_account_id: inbound.account_id.clone(),
        session_account_id,
        agent_id,
        session_policy,
        session_key,
        route_id,
        route_source,
        display_text: display_text(inbound),
        agent_input: agent_input(inbound),
    })
}

fn route_score(route: &ChannelAgentRoute, inbound: &ChannelInboundMessage) -> Option<u8> {
    let account_bonus = if route.channel_account_id.is_some() {
        1
    } else {
        0
    };
    if let Some(thread_id) = route.thread_id.as_deref() {
        if inbound.thread_id.as_deref() == Some(thread_id) {
            return Some(30 + account_bonus);
        }
        return None;
    }
    if let Some(peer_id) = route.peer_id.as_deref() {
        if peer_id != inbound.peer.id {
            return None;
        }
        if route
            .peer_kind
            .map(|kind| kind == inbound.peer.kind)
            .unwrap_or(true)
        {
            return Some(20 + account_bonus);
        }
        return None;
    }
    Some(10 + account_bonus)
}

fn route_source(route: &ChannelAgentRoute) -> String {
    if route.thread_id.is_some() {
        "thread_route".to_string()
    } else if route.peer_id.is_some() {
        "peer_route".to_string()
    } else {
        "channel_default_route".to_string()
    }
}
fn chat_error_message(chat_event: &Value) -> String {
    chat_event
        .get("message")
        .and_then(Value::as_str)
        .filter(|message| !message.trim().is_empty())
        .unwrap_or("agent_run_failed")
        .to_string()
}
fn conversation_thread_id(inbound: &ChannelInboundMessage) -> Option<&str> {
    let thread_id = inbound.thread_id.as_deref()?.trim();
    if thread_id.is_empty() {
        return None;
    }
    let message_id = inbound.platform_message_id.as_deref().map(str::trim);
    if message_id == Some(thread_id) {
        return None;
    }
    Some(thread_id)
}

pub fn stable_session_thread_id(
    channel_name: &str,
    session_account_id: &str,
    agent_id: &str,
    channel_account_id: &str,
    peer: &ChannelPeer,
    thread_id: Option<&str>,
    sender_id: &str,
) -> String {
    let target = thread_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            let peer_id = peer.id.trim();
            if peer_id.is_empty() {
                sender_id.trim()
            } else {
                peer_id
            }
        });
    let seed = format!(
        "napaxi.channel_agent.session.v1|channel={}|session_account={}|agent={}|channel_account={}|peer_kind={:?}|target={}",
        channel_name.trim(),
        session_account_id.trim(),
        agent_id.trim(),
        channel_account_id.trim(),
        peer.kind,
        target
    );
    Uuid::new_v5(&Uuid::NAMESPACE_OID, seed.as_bytes()).to_string()
}

#[cfg(test)]
mod tests;
