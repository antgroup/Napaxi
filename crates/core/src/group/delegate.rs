//! Higher-level group delegation: send_to_group (coordinator-driven) and
//! send_to_group_agent (direct member dispatch).

use std::sync::Arc;

use crate::types::ChatEvent;

use super::coordinator::{
    append_system_prompt, build_coordinator_prompt_with_language, response_from_events, session_key,
};
use super::messages::{
    add_agent_message, add_delegation_message, add_user_message, is_group_member,
};
use super::state::{DEFAULT_COORDINATOR, normalize_agent_id};
use super::tools::{group_internal_tool_handler, group_tool_descriptors};

pub async fn send_to_group(
    engine: Arc<crate::runtime::Engine>,
    group_id: &str,
    config_json: &str,
    message: &str,
    max_iterations: i32,
) -> Result<Vec<ChatEvent>, String> {
    let files_dir = engine.files_dir().to_string();
    if !add_user_message(&files_dir, group_id, message) {
        return Err("group not found".to_string());
    }

    let response_language = serde_json::from_str::<serde_json::Value>(config_json)
        .ok()
        .and_then(|config| {
            config
                .get("response_language")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
        .unwrap_or_else(|| "en".to_string());
    let config_json =
        build_coordinator_prompt_with_language(&files_dir, group_id, &response_language)
            .map(|prompt| append_system_prompt(config_json, &prompt))
            .unwrap_or_else(|| config_json.to_string());

    let account_id = crate::runtime::DEFAULT_ACCOUNT_ID.to_string();
    let coordinator_workspace_agent_id = format!("group-{group_id}");
    let llm_config = engine.config_with_capabilities(
        serde_json::from_str(&config_json).unwrap_or_else(|_| engine.config()),
    );
    let config_json = serde_json::to_string(&llm_config).unwrap_or(config_json);
    let tool_context = crate::runtime::prepare_session_tool_context_with_config_for_core(
        &engine,
        &account_id,
        &coordinator_workspace_agent_id,
        llm_config,
    );
    let handler = group_internal_tool_handler(
        files_dir.clone(),
        group_id.to_string(),
        config_json.clone(),
        Arc::clone(&engine),
        max_iterations,
        tool_context.internal_tool_handler,
    );
    let mut extra_tools = group_tool_descriptors();
    extra_tools.extend(tool_context.extra_tools);
    let session_key_json = session_key(&files_dir, group_id, DEFAULT_COORDINATOR);
    engine.clear_session_cancellation(&session_key_json);
    let cancellation_key = session_key_json.clone();
    let events = crate::capabilities::with_admission_sink(
        engine.admission_sink(),
        crate::runtime::run_session_turn(
            crate::runtime::SessionTurnInput {
                files_dir: files_dir.clone(),
                workspace_files_dir: tool_context.workspace_files_dir,
                config_json,
                agent_id: DEFAULT_COORDINATOR.to_string(),
                session_key_json,
                message: message.to_string(),
                display_message: None,
                attachments_json: "[]".to_string(),
                tools: Some(engine.tools()),
                max_iterations,
                extra_tools,
                internal_tool_handler: Some(handler),
                is_group_context: true,
                agent_engine: None,
            },
            || engine.is_session_cancelled(&cancellation_key),
        ),
    )
    .await;

    if let Some(content) = response_from_events(&events) {
        let _ = add_agent_message(&files_dir, group_id, DEFAULT_COORDINATOR, &content);
    }

    Ok(events)
}

pub async fn send_to_group_agent(
    engine: Arc<crate::runtime::Engine>,
    group_id: &str,
    agent_id: &str,
    config_json: &str,
    session_key_json: &str,
    message: &str,
    max_iterations: i32,
) -> Result<Vec<ChatEvent>, String> {
    let files_dir = engine.files_dir().to_string();
    let agent_id = normalize_agent_id(agent_id);
    if !is_group_member(&files_dir, group_id, &agent_id) {
        return Err("agent is not a member of the group".to_string());
    }

    let _ = add_delegation_message(&files_dir, group_id, "user", &agent_id, message);
    let session_key_json = if session_key_json.trim().is_empty() {
        session_key(&files_dir, group_id, &agent_id)
    } else {
        session_key_json.to_string()
    };
    let events = crate::agents::send_agent(
        Arc::clone(&engine),
        &agent_id,
        config_json,
        &session_key_json,
        message,
        max_iterations,
    )
    .await?;

    let mut wrapped = Vec::with_capacity(events.len() + 2);
    wrapped.push(ChatEvent::GroupDelegation {
        group_id: group_id.to_string(),
        from_agent: "user".to_string(),
        to_agent: agent_id.clone(),
        task: message.to_string(),
    });

    let content = response_from_events(&events);
    wrapped.extend(events);
    match content {
        Some(content) => {
            let _ = add_agent_message(&files_dir, group_id, &agent_id, &content);
            wrapped.push(ChatEvent::GroupDelegationResult {
                group_id: group_id.to_string(),
                from_agent: agent_id,
                to_agent: "user".to_string(),
                result: content,
                is_error: false,
            });
        }
        None => {
            wrapped.push(ChatEvent::GroupDelegationResult {
                group_id: group_id.to_string(),
                from_agent: agent_id,
                to_agent: "user".to_string(),
                result: "No response event returned".to_string(),
                is_error: true,
            });
        }
    }

    Ok(wrapped)
}
