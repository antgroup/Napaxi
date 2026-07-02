//! Pluggable Agent Engine host protocol.
//!
//! Core owns the capability and tool-broker boundary. Host-carried engines
//! implement the agent loop, but they call back into this module for Napaxi
//! tools so mobile policy, workspace scope, approvals, and evidence remain
//! core-controlled.

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::tool_registry::{ToolEffect, ToolExecutionContext, ToolRequestBridge};
use crate::types::ChatEvent;

pub const NAPAXI_CORE_ENGINE_ID: &str = "napaxi_core";
pub const EXTERNAL_HOST_ENGINE_ID: &str = "external_host";
pub(crate) const HOST_ENGINE_TURN_TOOL: &str = "__napaxi_agent_engine_turn__";
const HOST_ENGINE_TIMEOUT: Duration = Duration::from_secs(60 * 60);

#[allow(dead_code)]
pub(crate) type AgentEngineStartFuture<'a> = Pin<Box<dyn Future<Output = Vec<ChatEvent>> + 'a>>;

#[allow(dead_code)]
pub(crate) trait AgentEngineAdapter: Send + Sync {
    fn start_turn<'a>(
        &'a self,
        request: AgentEngineTurnRequest,
        emit: &'a mut dyn FnMut(ChatEvent),
    ) -> AgentEngineStartFuture<'a>;

    fn cancel(&self, _run_id: &str, _session_key_json: &str) -> bool {
        false
    }

    fn resume<'a>(
        &'a self,
        request: AgentEngineTurnRequest,
        emit: &'a mut dyn FnMut(ChatEvent),
    ) -> AgentEngineStartFuture<'a> {
        Box::pin(async move {
            let event = ChatEvent::Error {
                message: format!(
                    "Agent engine resume is unsupported for run {}",
                    request.run_id
                ),
            };
            emit(event.clone());
            vec![event]
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentEngineSelection {
    pub engine_id: String,
    #[serde(default)]
    pub engine_profile_id: String,
    #[serde(default)]
    pub engine_config: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentEngineTurnRequest {
    pub engine_id: String,
    #[serde(default)]
    pub engine_profile_id: String,
    #[serde(default)]
    pub engine_config: Value,
    pub run_id: String,
    pub files_dir: String,
    pub workspace_files_dir: String,
    pub account_id: String,
    pub agent_id: String,
    pub session_key_json: String,
    pub message: String,
    pub attachments_json: String,
    pub config_json: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ToolBrokerListRequest {
    #[serde(default)]
    pub account_id: String,
    #[serde(default)]
    pub agent_id: String,
    #[serde(default)]
    pub session_key_json: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolBrokerCallRequest {
    pub call_id: String,
    pub name: String,
    pub arguments: Value,
    #[serde(default)]
    pub account_id: String,
    #[serde(default)]
    pub agent_id: String,
    #[serde(default)]
    pub session_key_json: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ToolBrokerCallResult {
    pub output: String,
    pub is_error: bool,
    pub events: Vec<ChatEvent>,
    pub effect: ToolEffect,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentEngineRunEventRequest {
    pub run_id: String,
    #[serde(default)]
    pub session_key_json: String,
    pub event: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct AgentEngineRunEventResult {
    pub event: ChatEvent,
    pub final_content: String,
    pub is_error: bool,
    pub completed: bool,
}

pub(crate) fn normalize_engine_id(engine_id: &str) -> String {
    let normalized = crate::capabilities::normalize_agent_engine_id(engine_id);
    match normalized.as_str() {
        "napaxi.agent_engine.napaxi_core" => NAPAXI_CORE_ENGINE_ID.to_string(),
        "napaxi.agent_engine.external_host" => EXTERNAL_HOST_ENGINE_ID.to_string(),
        "" => NAPAXI_CORE_ENGINE_ID.to_string(),
        _ => normalized,
    }
}

pub(crate) fn selection_from_definition(
    definition: Option<&crate::agent_definitions::AgentDefinition>,
) -> AgentEngineSelection {
    let Some(definition) = definition else {
        return AgentEngineSelection {
            engine_id: NAPAXI_CORE_ENGINE_ID.to_string(),
            engine_profile_id: String::new(),
            engine_config: json!({}),
        };
    };
    AgentEngineSelection {
        engine_id: normalize_engine_id(&definition.engine_id),
        engine_profile_id: definition.engine_profile_id.clone(),
        engine_config: definition.engine_config.clone(),
    }
}

pub(crate) struct ExternalHostTurnPlan {
    pub(crate) request: AgentEngineTurnRequest,
    pub(crate) bridge: ToolRequestBridge,
}

pub(crate) fn external_host_turn_plan(
    selection: Option<&AgentEngineSelection>,
    prepared: &crate::turn::PreparedTurn,
    tools: Option<&Arc<crate::tool_registry::ToolRegistry>>,
    files_dir: &str,
    workspace_files_dir: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    attachments_json: &str,
    fallback_config_json: &str,
) -> Result<Option<ExternalHostTurnPlan>, String> {
    let Some(selection) = selection else {
        return Ok(None);
    };
    let engine_id = normalize_engine_id(&selection.engine_id);
    if engine_id == NAPAXI_CORE_ENGINE_ID {
        return Ok(None);
    }
    let platform = prepared
        .config
        .capability_profile
        .platform
        .as_deref()
        .unwrap_or("unknown");
    crate::capabilities::require_agent_engine_enabled_for_config(
        &engine_id,
        platform,
        &prepared.config.capability_profile,
        &prepared.config.capability_selection,
    )?;
    let bridge = host_bridge_for_tools(tools)
        .ok_or_else(|| "No host agent engine executor registered".to_string())?;
    Ok(Some(ExternalHostTurnPlan {
        request: AgentEngineTurnRequest {
            engine_id,
            engine_profile_id: selection.engine_profile_id.clone(),
            engine_config: selection.engine_config.clone(),
            run_id: uuid::Uuid::new_v4().to_string(),
            files_dir: files_dir.to_string(),
            workspace_files_dir: workspace_files_dir.to_string(),
            account_id: crate::runtime::session_account_id(session_key_json),
            agent_id: agent_id.to_string(),
            session_key_json: session_key_json.to_string(),
            message: message.to_string(),
            attachments_json: attachments_json.to_string(),
            config_json: serde_json::to_string(&prepared.config)
                .unwrap_or_else(|_| fallback_config_json.to_string()),
        },
        bridge,
    }))
}

pub(crate) fn final_content_from_events(events: &[ChatEvent]) -> String {
    let mut delta_content = String::new();
    let mut response_content = None;
    for event in events {
        match event {
            ChatEvent::ResponseDelta { content } => delta_content.push_str(content),
            ChatEvent::Response { content } => response_content = Some(content.clone()),
            _ => {}
        }
    }
    if delta_content.trim().is_empty() {
        response_content.unwrap_or_default()
    } else {
        delta_content
    }
}

pub(crate) fn visible_external_events(events: Vec<ChatEvent>) -> Vec<ChatEvent> {
    events
        .into_iter()
        .filter(|event| !matches!(event, ChatEvent::Response { .. }))
        .collect()
}

pub(crate) fn host_bridge_for_tools(
    tools: Option<&Arc<crate::tool_registry::ToolRegistry>>,
) -> Option<ToolRequestBridge> {
    tools.and_then(|tools| tools.request_bridge()).or_else(|| {
        crate::runtime::tool_request_dispatcher().map(ToolRequestBridge::process_scoped)
    })
}

pub(crate) async fn run_external_host_turn<F, C>(
    request: AgentEngineTurnRequest,
    bridge: ToolRequestBridge,
    mut emit: F,
    mut is_cancelled: C,
) -> Vec<ChatEvent>
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool,
{
    if is_cancelled() {
        return vec![ChatEvent::Interrupted];
    }
    let params = match serde_json::to_value(&request) {
        Ok(params) => params,
        Err(error) => {
            return vec![ChatEvent::Error {
                message: format!("Agent engine request serialization failed: {error}"),
            }];
        }
    };
    let context = ToolExecutionContext {
        files_dir: request.files_dir.clone(),
        workspace_files_dir: request.workspace_files_dir.clone(),
        agent_id: request.agent_id.clone(),
        session_key_json: Some(request.session_key_json.clone()),
    };
    let output = crate::tool_registry::request_host_tool_execution_with_context(
        bridge,
        HOST_ENGINE_TURN_TOOL,
        params,
        HOST_ENGINE_TIMEOUT,
        Some(&context),
    )
    .await;
    if is_cancelled() {
        return vec![ChatEvent::Interrupted];
    }
    let output = match output {
        Ok(output) => output,
        Err(error) => {
            return vec![ChatEvent::Error {
                message: format!("Agent engine execution failed: {error}"),
            }];
        }
    };
    let events = decode_host_events(&request.run_id, &output);
    for event in &events {
        emit(event.clone());
    }
    events
}

pub(crate) fn run_event_json(request_json: &str) -> String {
    match run_event_json_inner(request_json) {
        Ok(result) => serde_json::to_string(&result).unwrap_or_else(|error| {
            error_json(format!(
                "Agent engine run event serialization failed: {error}"
            ))
        }),
        Err(error) => error_json(error),
    }
}

fn run_event_json_inner(request_json: &str) -> Result<AgentEngineRunEventResult, String> {
    let request: AgentEngineRunEventRequest = serde_json::from_str(request_json)
        .map_err(|error| format!("Invalid agent engine run/event JSON: {error}"))?;
    let event = decode_run_event_value(&request.run_id, request.event)?;
    Ok(AgentEngineRunEventResult {
        final_content: final_content_from_events(std::slice::from_ref(&event)),
        is_error: matches!(event, ChatEvent::Error { .. }),
        completed: matches!(event, ChatEvent::RunCompleted { .. }),
        event,
    })
}

fn decode_host_events(run_id: &str, output: &str) -> Vec<ChatEvent> {
    if output.trim().is_empty() {
        return vec![ChatEvent::Error {
            message: "Agent engine returned an empty response".to_string(),
        }];
    }
    let value = match serde_json::from_str::<Value>(output) {
        Ok(value) => value,
        Err(error) => {
            return vec![ChatEvent::Error {
                message: format!("Agent engine returned invalid JSON: {error}"),
            }];
        }
    };
    let event_values = value
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_else(|| match value {
            Value::Array(items) => items,
            other => vec![other],
        });
    let mut events = Vec::new();
    for event in event_values {
        match decode_run_event_value(run_id, event) {
            Ok(event) => events.push(event),
            Err(error) => events.push(ChatEvent::Error {
                message: format!("Agent engine event decode failed: {error}"),
            }),
        }
    }
    if events.is_empty() {
        events.push(ChatEvent::Error {
            message: "Agent engine returned no events".to_string(),
        });
    }
    events
}

fn decode_run_event_value(run_id: &str, event: Value) -> Result<ChatEvent, String> {
    let normalized = normalize_run_event_value(run_id, event)?;
    serde_json::from_value::<ChatEvent>(normalized).map_err(|error| error.to_string())
}

fn normalize_run_event_value(run_id: &str, event: Value) -> Result<Value, String> {
    let mut event = match event {
        Value::Object(map) => map,
        other => return Err(format!("expected run event object, got {other}")),
    };
    let event_type = event
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    match event_type.as_str() {
        "completed" => {
            event.insert(
                "type".to_string(),
                Value::String("run_completed".to_string()),
            );
            event
                .entry("run_id".to_string())
                .or_insert_with(|| Value::String(run_id.to_string()));
            event
                .entry("status".to_string())
                .or_insert_with(|| Value::String("completed".to_string()));
            event
                .entry("evidence_kind".to_string())
                .or_insert_with(|| Value::String("agent_engine".to_string()));
            event
                .entry("verification".to_string())
                .or_insert_with(|| Value::String("host_reported".to_string()));
            event
                .entry("tool_call_count".to_string())
                .or_insert_with(|| Value::Number(0.into()));
        }
        "tool_call" | "agent_tool_call" => {
            stringify_event_field(&mut event, "arguments");
        }
        "tool_call_delta" | "agent_tool_call_delta" => {
            stringify_event_field(&mut event, "arguments_delta");
            stringify_event_field(&mut event, "arguments_so_far");
        }
        _ => {}
    }
    Ok(Value::Object(event))
}

fn stringify_event_field(event: &mut serde_json::Map<String, Value>, field: &str) {
    let Some(value) = event.get(field) else {
        return;
    };
    if value.is_string() {
        return;
    }
    let stringified = serde_json::to_string(value).unwrap_or_else(|_| value.to_string());
    event.insert(field.to_string(), Value::String(stringified));
}

pub(crate) async fn list_tools_json_handle(handle: i64, request_json: &str) -> String {
    match list_tools_json_handle_inner(handle, request_json).await {
        Ok(value) => value,
        Err(error) => error_json(error),
    }
}

async fn list_tools_json_handle_inner(handle: i64, request_json: &str) -> Result<String, String> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { crate::runtime::handle_to_arc(handle) }
        .ok_or_else(|| "invalid engine handle".to_string())?;
    let request: ToolBrokerListRequest = parse_or_default(request_json);
    let account_id = effective_account_id(&request.account_id, request.session_key_json.as_deref());
    let agent_id = effective_agent_id(&request.agent_id);
    let config = engine.config_with_capabilities(engine.config());
    let tool_context = crate::runtime::prepare_session_tool_context_with_config_and_thread_for_core(
        &engine,
        &account_id,
        &agent_id,
        config.clone(),
        thread_id_from_session_key(request.session_key_json.as_deref()),
    );
    let descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
        &config,
        Some(&engine.tools()),
        tool_context.extra_tools,
    )
    .await;
    serde_json::to_string(&descriptors).map_err(|e| e.to_string())
}

pub(crate) async fn call_tool_json_handle(handle: i64, request_json: &str) -> String {
    match call_tool_json_handle_inner(handle, request_json).await {
        Ok(value) => value,
        Err(error) => error_json(error),
    }
}

async fn call_tool_json_handle_inner(handle: i64, request_json: &str) -> Result<String, String> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { crate::runtime::handle_to_arc(handle) }
        .ok_or_else(|| "invalid engine handle".to_string())?;
    let request: ToolBrokerCallRequest =
        serde_json::from_str(request_json).map_err(|e| format!("Invalid tool call JSON: {e}"))?;
    let account_id = effective_account_id(&request.account_id, request.session_key_json.as_deref());
    let agent_id = effective_agent_id(&request.agent_id);
    let config = engine.config_with_capabilities(engine.config());
    let current_thread_id = thread_id_from_session_key(request.session_key_json.as_deref());
    let tool_context = crate::runtime::prepare_session_tool_context_with_config_and_thread_for_core(
        &engine,
        &account_id,
        &agent_id,
        config.clone(),
        current_thread_id,
    );
    let descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
        &config,
        Some(&engine.tools()),
        tool_context.extra_tools.clone(),
    )
    .await;
    let execution_context = ToolExecutionContext {
        files_dir: engine.files_dir().to_string(),
        workspace_files_dir: tool_context.workspace_files_dir,
        agent_id,
        session_key_json: request.session_key_json,
    };
    let arguments = serde_json::to_string(&request.arguments).map_err(|e| e.to_string())?;
    let mut events = Vec::new();
    let mut should_cancel = || false;
    let (output, is_error, emitted_events, effect) =
        crate::tool_loop::execute_single_tool_call_for_broker(
            &request.call_id,
            &config,
            Some(&engine.tools()),
            tool_context.internal_tool_handler.as_ref(),
            &descriptors,
            &request.name,
            &arguments,
            Some(&execution_context),
            &mut should_cancel,
            &mut |event| events.push(event),
        )
        .await;
    events.extend(emitted_events);
    let result = ToolBrokerCallResult {
        output,
        is_error,
        events,
        effect,
    };
    serde_json::to_string(&result).map_err(|e| e.to_string())
}

fn parse_or_default<T>(raw: &str) -> T
where
    T: for<'de> Deserialize<'de> + Default,
{
    if raw.trim().is_empty() {
        return T::default();
    }
    serde_json::from_str(raw).unwrap_or_default()
}

fn effective_account_id(account_id: &str, session_key_json: Option<&str>) -> String {
    if !account_id.trim().is_empty() {
        return account_id.trim().to_string();
    }
    session_key_json
        .map(crate::runtime::session_account_id)
        .unwrap_or_else(|| crate::runtime::DEFAULT_ACCOUNT_ID.to_string())
}

fn effective_agent_id(agent_id: &str) -> String {
    if agent_id.trim().is_empty() {
        crate::runtime::DEFAULT_AGENT_ID.to_string()
    } else {
        agent_id.trim().to_string()
    }
}

fn thread_id_from_session_key(session_key_json: Option<&str>) -> Option<String> {
    let key = session_key_json?;
    serde_json::from_str::<Value>(key).ok().and_then(|value| {
        value
            .get("thread_id")
            .and_then(Value::as_str)
            .map(str::to_string)
    })
}

fn error_json(message: String) -> String {
    json!({"error": message}).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
