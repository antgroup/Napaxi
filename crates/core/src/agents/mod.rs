//! File-backed mobile agent definition store.

pub(crate) mod agent_app;

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use uuid::Uuid;

use crate::agent_definitions::{AgentDefinition, parse_agent_md};
use crate::types::{ChatEvent, PlatformLlmConfig};

fn store_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join("napaxi")
        .join("agent_definitions.json")
}

fn now() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

fn normalize_agent_id(agent_id: &str) -> String {
    let trimmed = agent_id.trim();
    if trimmed.is_empty() {
        crate::runtime::DEFAULT_AGENT_ID.to_string()
    } else {
        trimmed.to_string()
    }
}

fn load_definitions(files_dir: &str) -> Vec<AgentDefinition> {
    let path = store_path(files_dir);
    let Ok(content) = fs::read_to_string(path) else {
        return Vec::new();
    };
    serde_json::from_str(&content).unwrap_or_default()
}

fn save_definitions(files_dir: &str, definitions: &[AgentDefinition]) -> bool {
    let path = store_path(files_dir);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    let Ok(content) = serde_json::to_string_pretty(definitions) else {
        return false;
    };
    fs::write(path, content).is_ok()
}

fn prepare_definition(mut def: AgentDefinition) -> AgentDefinition {
    if def.id.trim().is_empty() {
        def.id = Uuid::new_v4().to_string();
    }
    let ts = now();
    if def.created_at.trim().is_empty() {
        def.created_at = ts.clone();
    }
    if def.updated_at.trim().is_empty() {
        def.updated_at = ts;
    }
    def
}

fn invalid_handle_json() -> String {
    r#"{"error":"invalid engine handle"}"#.to_string()
}

pub fn create_definition(files_dir: &str, def_json: &str) -> String {
    match serde_json::from_str::<AgentDefinition>(def_json) {
        Ok(def) => create_definition_value(files_dir, def),
        Err(e) => format!(r#"{{"error":"Invalid agent definition: {e}"}}"#),
    }
}

pub fn create_definition_handle(handle: i64, def_json: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    create_definition(&files_dir, def_json)
}

pub fn create_definition_value(files_dir: &str, def: AgentDefinition) -> String {
    let def = prepare_definition(def);
    let mut definitions = load_definitions(files_dir);
    definitions.retain(|existing| existing.id != def.id);
    definitions.push(def.clone());
    if !save_definitions(files_dir, &definitions) {
        return r#"{"error":"Failed to save agent definition"}"#.to_string();
    }
    serde_json::to_string(&def)
        .unwrap_or_else(|_| r#"{"error":"serialization failed"}"#.to_string())
}

pub fn list_definitions(files_dir: &str) -> String {
    serde_json::to_string(&load_definitions(files_dir)).unwrap_or_else(|_| "[]".to_string())
}

pub fn list_definitions_handle(handle: i64) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_definitions(&files_dir)
}

pub fn get_definition(files_dir: &str, def_id: &str) -> Option<AgentDefinition> {
    load_definitions(files_dir)
        .into_iter()
        .find(|definition| definition.id == def_id)
}

pub fn get_definition_json(files_dir: &str, def_id: &str) -> String {
    get_definition(files_dir, def_id)
        .and_then(|definition| serde_json::to_string(&definition).ok())
        .unwrap_or_else(|| "null".to_string())
}

pub fn get_definition_json_handle(handle: i64, def_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "null".to_string();
    };
    get_definition_json(&files_dir, def_id)
}

pub fn update_definition(files_dir: &str, def_json: &str) -> bool {
    let Ok(mut def) = serde_json::from_str::<AgentDefinition>(def_json) else {
        return false;
    };
    if def.id.trim().is_empty() {
        return false;
    }
    let mut definitions = load_definitions(files_dir);
    let Some(index) = definitions
        .iter()
        .position(|existing| existing.id == def.id)
    else {
        return false;
    };
    if def.created_at.trim().is_empty() {
        def.created_at = definitions[index].created_at.clone();
    }
    def.updated_at = now();
    definitions[index] = def;
    save_definitions(files_dir, &definitions)
}

pub fn update_definition_handle(handle: i64, def_json: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    update_definition(&files_dir, def_json)
}

pub fn delete_definition(files_dir: &str, def_id: &str) -> bool {
    let mut definitions = load_definitions(files_dir);
    let original_len = definitions.len();
    definitions.retain(|definition| definition.id != def_id);
    if definitions.len() == original_len {
        return false;
    }
    save_definitions(files_dir, &definitions)
}

pub fn delete_definition_for_engine(engine: &crate::runtime::Engine, def_id: &str) -> bool {
    let _ = engine.delete_agent(def_id);
    delete_definition(engine.files_dir(), def_id)
}

pub fn delete_definition_handle(handle: i64, def_id: &str) -> bool {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return false;
    };
    delete_definition_for_engine(&engine, def_id)
}

pub fn create_agent_from_definition_for_engine(
    engine: &crate::runtime::Engine,
    def_id: &str,
) -> bool {
    get_definition(engine.files_dir(), def_id)
        .map(|_| engine.ensure_agent(def_id))
        .unwrap_or(false)
}

pub fn create_agent_from_definition_handle(handle: i64, def_id: &str) -> bool {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return false;
    };
    create_agent_from_definition_for_engine(&engine, def_id)
}

pub fn import_agent_md(files_dir: &str, content: &str) -> String {
    match parse_agent_md(content) {
        Ok(def) => create_definition_value(files_dir, def),
        Err(e) => format!(r#"{{"error":"AGENT.md parse error: {e}"}}"#),
    }
}

pub fn import_agent_md_handle(handle: i64, content: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    import_agent_md(&files_dir, content)
}

pub fn overlay_definition_config(files_dir: &str, agent_id: &str, config_json: &str) -> String {
    let Ok(mut config) = serde_json::from_str::<PlatformLlmConfig>(config_json) else {
        return config_json.to_string();
    };
    if let Some(def) = get_definition(files_dir, agent_id) {
        if !def.provider.trim().is_empty() {
            config.provider = def.provider;
        }
        if !def.model.trim().is_empty() {
            config.model = def.model;
        }
        if !def.system_prompt.trim().is_empty() {
            config.system_prompt = def.system_prompt;
        }
        config.max_tokens = def.max_tokens;
    }
    serde_json::to_string(&config).unwrap_or_else(|_| config_json.to_string())
}

pub fn transform_chat_events_for_agent(events: Vec<ChatEvent>, agent_id: &str) -> Vec<ChatEvent> {
    let agent_id = normalize_agent_id(agent_id);
    events
        .into_iter()
        .map(|event| match event {
            ChatEvent::ToolCall {
                call_id,
                name,
                arguments,
            } => ChatEvent::AgentToolCall {
                call_id,
                name,
                arguments,
                agent_id: agent_id.clone(),
            },
            ChatEvent::ToolCallDelta {
                call_id,
                name,
                arguments_delta,
                arguments_so_far,
            } => ChatEvent::AgentToolCallDelta {
                call_id,
                name,
                arguments_delta,
                arguments_so_far,
                agent_id: agent_id.clone(),
            },
            ChatEvent::ToolResult {
                call_id,
                name,
                output,
                is_error,
            } => ChatEvent::AgentToolResult {
                call_id,
                name,
                output,
                is_error,
                agent_id: agent_id.clone(),
            },
            other => other,
        })
        .collect()
}

pub async fn send_agent(
    engine: Arc<crate::runtime::Engine>,
    agent_id: &str,
    config_json: &str,
    session_key_json: &str,
    message: &str,
    max_iterations: i32,
) -> Result<Vec<ChatEvent>, String> {
    let files_dir = engine.files_dir().to_string();
    let agent_id = normalize_agent_id(agent_id);
    let _ = engine.ensure_agent(&agent_id);
    let account_id = crate::runtime::session_account_id(session_key_json);
    let config_json = overlay_definition_config(&files_dir, &agent_id, config_json);
    let llm_config = engine.config_with_capabilities(
        serde_json::from_str(&config_json).unwrap_or_else(|_| engine.config()),
    );
    let config_json = serde_json::to_string(&llm_config).unwrap_or(config_json);
    let tool_context = crate::runtime::prepare_session_tool_context_with_config_for_core(
        &engine,
        &account_id,
        &agent_id,
        llm_config,
    );
    let session_key_json = session_key_json.to_string();
    engine.clear_session_cancellation(&session_key_json);
    let cancellation_key = session_key_json.clone();
    let events = crate::capabilities::with_admission_sink(
        engine.admission_sink(),
        crate::runtime::run_session_turn(
            crate::runtime::SessionTurnInput {
                files_dir: files_dir.clone(),
                workspace_files_dir: tool_context.workspace_files_dir,
                config_json,
                agent_id: agent_id.clone(),
                session_key_json,
                message: message.to_string(),
                display_message: None,
                attachments_json: "[]".to_string(),
                tools: Some(engine.tools()),
                max_iterations,
                extra_tools: tool_context.extra_tools,
                internal_tool_handler: tool_context.internal_tool_handler,
                is_group_context: false,
                agent_engine: crate::agent_engine::selection_from_definition(
                    get_definition(&files_dir, &agent_id).as_ref(),
                )
                .into(),
            },
            || engine.is_session_cancelled(&cancellation_key),
        ),
    )
    .await;
    Ok(transform_chat_events_for_agent(events, &agent_id))
}

pub async fn send_agent_handle(
    handle: i64,
    agent_id: &str,
    config_json: &str,
    session_key_json: &str,
    message: &str,
    max_iterations: i32,
) -> Result<Vec<ChatEvent>, String> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return Err("engine handle is not available".to_string());
    };
    send_agent(
        engine,
        agent_id,
        config_json,
        session_key_json,
        message,
        max_iterations,
    )
    .await
}

fn events_array_json(events: Vec<ChatEvent>) -> String {
    serde_json::to_string(&events).unwrap_or_else(|_| "[]".to_string())
}

fn error_array_json(message: impl Into<String>) -> String {
    format!(
        "[{}]",
        serde_json::json!({
            "type": "error",
            "message": message.into()
        })
    )
}

pub async fn send_agent_json_handle(
    handle: i64,
    agent_id: &str,
    config_json: &str,
    session_key_json: &str,
    message: &str,
    max_iterations: i32,
) -> String {
    match send_agent_handle(
        handle,
        agent_id,
        config_json,
        session_key_json,
        message,
        max_iterations,
    )
    .await
    {
        Ok(events) => events_array_json(events),
        Err(message) => error_array_json(message),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent_definitions::AgentSource;

    #[test]
    fn stores_agent_definitions() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_string_lossy();
        let def = AgentDefinition::new("coder".to_string(), "model".to_string());
        let created = create_definition_value(&files_dir, def.clone());
        let created: AgentDefinition = serde_json::from_str(&created).unwrap();
        assert_eq!(created.name, "coder");
        assert_eq!(
            get_definition(&files_dir, &created.id).unwrap().model,
            "model"
        );
        assert_eq!(
            serde_json::from_str::<Vec<AgentDefinition>>(&list_definitions(&files_dir))
                .unwrap()
                .len(),
            1
        );
        assert!(delete_definition(&files_dir, &created.id));
        assert_eq!(list_definitions(&files_dir), "[]");
    }

    #[test]
    fn imports_agent_md() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_string_lossy();
        let json = import_agent_md(&files_dir, "---\nname: helper\n---\n\nHelp.");
        let def: AgentDefinition = serde_json::from_str(&json).unwrap();
        assert_eq!(def.name, "helper");
        assert_eq!(def.source, AgentSource::AgentMd);
    }

    #[test]
    fn definition_handle_helpers_sync_agent_state() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_string_lossy();
        let config_json = serde_json::json!({
            "provider": "openai",
            "api_key": "test",
            "base_url": null,
            "model": "test-model",
            "system_prompt": "",
            "max_tokens": 128
        })
        .to_string();
        let context_json = serde_json::json!({
            "platform": "test",
            "files_dir": files_dir,
            "native_library_dir": null
        })
        .to_string();
        let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();

        let mut def = AgentDefinition::new("helper".to_string(), "model".to_string());
        def.id = "helper".to_string();
        let created = create_definition_handle(handle, &serde_json::to_string(&def).unwrap());
        assert!(created.contains(r#""id":"helper""#));
        assert!(create_definition_handle(0, "{}").contains("invalid engine handle"));
        assert!(list_definitions_handle(handle).contains("helper"));
        assert!(get_definition_json_handle(handle, "helper").contains("model"));

        def.model = "updated-model".to_string();
        assert!(update_definition_handle(
            handle,
            &serde_json::to_string(&def).unwrap()
        ));
        assert!(get_definition_json_handle(handle, "helper").contains("updated-model"));

        assert!(create_agent_from_definition_handle(handle, "helper"));
        assert!(crate::runtime::list_agents_handle(handle).contains("helper"));
        assert!(delete_definition_handle(handle, "helper"));
        assert!(!crate::runtime::list_agents_handle(handle).contains("helper"));
        assert_eq!(get_definition(&files_dir, "helper").map(|def| def.id), None);
        assert_eq!(list_definitions_handle(0), "[]");
        assert_eq!(get_definition_json_handle(0, "helper"), "null");
        assert!(!update_definition_handle(0, "{}"));

        let imported = import_agent_md_handle(handle, "---\nname: imported\n---\n\nHelp.");
        assert!(imported.contains("imported"));
        assert!(import_agent_md_handle(0, "").contains("invalid engine handle"));

        // SAFETY: `handle` is an engine handle owned by this call site and consumed exactly once here, satisfying `handle_consume`'s contract.
        let _ = unsafe { crate::runtime::handle_consume(handle) };
    }

    #[test]
    fn overlays_definition_config_and_transforms_tool_events() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_string_lossy();
        let mut def = AgentDefinition::new("helper".to_string(), "agent-model".to_string());
        def.id = "helper".to_string();
        def.provider = "openai".to_string();
        def.system_prompt = "Agent prompt".to_string();
        def.max_tokens = 123;
        create_definition_value(&files_dir, def);

        let base = PlatformLlmConfig {
            provider: "anthropic".to_string(),
            api_key: "k".to_string(),
            base_url: None,
            model: "base-model".to_string(),
            system_prompt: "Base prompt".to_string(),
            max_tokens: 10,
            max_tool_iterations: 0,
            extra_headers: None,
            allowed_models: None,
            image_model: None,
            image_analysis_model: None,
            capability_configs: None,
            scene_prompt_config: None,
            ..PlatformLlmConfig::default()
        };
        let overlaid =
            overlay_definition_config(&files_dir, "helper", &serde_json::to_string(&base).unwrap());
        assert!(overlaid.contains("agent-model"));
        assert!(overlaid.contains("Agent prompt"));

        let events = transform_chat_events_for_agent(
            vec![
                ChatEvent::ToolCall {
                    call_id: "call-1".to_string(),
                    name: "x".to_string(),
                    arguments: "{}".to_string(),
                },
                ChatEvent::ToolResult {
                    call_id: "call-1".to_string(),
                    name: "x".to_string(),
                    output: "ok".to_string(),
                    is_error: false,
                },
            ],
            "helper",
        );
        assert!(matches!(
            events.first(),
            Some(ChatEvent::AgentToolCall { agent_id, .. }) if agent_id == "helper"
        ));
        assert!(matches!(
            events.get(1),
            Some(ChatEvent::AgentToolResult { agent_id, .. }) if agent_id == "helper"
        ));
    }

    #[tokio::test]
    async fn send_agent_json_handle_reports_invalid_handle() {
        let response = send_agent_json_handle(0, "helper", "{}", "{}", "hello", 1).await;
        assert!(response.contains("engine handle is not available"));
        assert!(response.starts_with('['));
    }
}
