//! Group tool descriptors, dispatch helper, and the internal tool handler.

use std::sync::Arc;

use crate::tool_loop::{InternalToolHandler, InternalToolResult};
use crate::tool_registry::ToolDescriptor;
use crate::types::ChatEvent;

use super::coordinator::{events_json, extract_response, group_members_text, session_key};
use super::messages::{add_agent_message, add_delegation_message, is_group_member};
use super::state::{DEFAULT_COORDINATOR, normalize_agent_id};
use super::types::{GroupMemberTask, GroupToolExecution};

pub fn group_tool_descriptors() -> Vec<ToolDescriptor> {
    vec![
        ToolDescriptor {
            name: "send_to_group_member".to_string(),
            description: "Send a task to a specific member of the current agent group and return that member's response.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "member_id": {
                        "type": "string",
                        "description": "The group member agent id to send the task to"
                    },
                    "task": {
                        "type": "string",
                        "description": "The task or question for that member"
                    }
                },
                "required": ["member_id", "task"]
            }),
            effect: crate::tool_registry::ToolEffect::Deliver,
        },
        ToolDescriptor {
            name: "list_group_members".to_string(),
            description: "List members of the current agent group.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {}
            }),
            effect: crate::tool_registry::ToolEffect::Read,
        },
    ]
}

pub async fn execute_group_tool<F, Fut>(
    files_dir: &str,
    group_id: &str,
    coordinator_agent_id: &str,
    config_json: &str,
    tool_name: &str,
    params: serde_json::Value,
    delegate_member: F,
) -> Result<GroupToolExecution, String>
where
    F: FnOnce(GroupMemberTask) -> Fut,
    Fut: std::future::Future<Output = Result<String, String>>,
{
    match tool_name {
        "list_group_members" => Ok(GroupToolExecution {
            output: group_members_text(files_dir, group_id),
            events: Vec::new(),
        }),
        "send_to_group_member" => {
            let member_id = params
                .get("member_id")
                .or_else(|| params.get("agent_id"))
                .and_then(serde_json::Value::as_str)
                .map(normalize_agent_id)
                .ok_or_else(|| "send_to_group_member missing member_id".to_string())?;
            let task = params
                .get("task")
                .or_else(|| params.get("message"))
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
                .ok_or_else(|| "send_to_group_member missing task".to_string())?;
            let coordinator_agent_id = normalize_agent_id(coordinator_agent_id);

            if !is_group_member(files_dir, group_id, &member_id) {
                return Err(format!(
                    "Agent '{member_id}' is not a member of group '{group_id}'"
                ));
            }
            let _ = add_delegation_message(
                files_dir,
                group_id,
                &coordinator_agent_id,
                &member_id,
                &task,
            );
            let request = GroupMemberTask {
                session_key_json: session_key(files_dir, group_id, &member_id),
                config_json: crate::agents::overlay_definition_config(
                    files_dir,
                    &member_id,
                    config_json,
                ),
                member_id: member_id.clone(),
                task: task.clone(),
            };
            let events_json = delegate_member(request).await?;
            let content = extract_response(&events_json)
                .unwrap_or_else(|| "No response event returned".to_string());
            let is_error = content == "No response event returned";
            let _ = add_agent_message(files_dir, group_id, &member_id, &content);
            Ok(GroupToolExecution {
                output: content.clone(),
                events: vec![
                    ChatEvent::GroupDelegation {
                        group_id: group_id.to_string(),
                        from_agent: coordinator_agent_id.clone(),
                        to_agent: member_id.clone(),
                        task,
                    },
                    ChatEvent::GroupDelegationResult {
                        group_id: group_id.to_string(),
                        from_agent: member_id,
                        to_agent: coordinator_agent_id,
                        result: content,
                        is_error,
                    },
                ],
            })
        }
        other => Err(format!("Tool not found: {other}")),
    }
}

pub fn group_internal_tool_handler(
    files_dir: String,
    group_id: String,
    config_json: String,
    engine: Arc<crate::runtime::Engine>,
    max_iterations: i32,
    fallback_handler: Option<InternalToolHandler>,
) -> InternalToolHandler {
    Arc::new(move |tool_name, params, _progress| {
        let tool_name = tool_name.to_string();
        let files_dir = files_dir.clone();
        let group_id = group_id.clone();
        let config_json = config_json.clone();
        let engine = Arc::clone(&engine);
        let fallback_handler = fallback_handler.clone();
        match tool_name.as_str() {
            "list_group_members" | "send_to_group_member" => Some(Box::pin(async move {
                let execution = execute_group_tool(
                    &files_dir,
                    &group_id,
                    DEFAULT_COORDINATOR,
                    &config_json,
                    &tool_name,
                    params,
                    |request| {
                        let files_dir = files_dir.clone();
                        let engine = Arc::clone(&engine);
                        async move {
                            let account_id =
                                crate::runtime::session_account_id(&request.session_key_json);
                            let llm_config = engine.config_with_capabilities(
                                serde_json::from_str(&request.config_json)
                                    .unwrap_or_else(|_| engine.config()),
                            );
                            let effective_config_json =
                                serde_json::to_string(&llm_config).unwrap_or(request.config_json);
                            let tool_context =
                                crate::runtime::prepare_session_tool_context_with_config_for_core(
                                    &engine,
                                    &account_id,
                                    &request.member_id,
                                    llm_config,
                                );
                            let session_key_json = request.session_key_json;
                            engine.clear_session_cancellation(&session_key_json);
                            let cancellation_key = session_key_json.clone();
                            let events = crate::capabilities::with_admission_sink(
                                engine.admission_sink(),
                                crate::runtime::run_session_turn(
                                    crate::runtime::SessionTurnInput {
                                        files_dir,
                                        workspace_files_dir: tool_context.workspace_files_dir,
                                        config_json: effective_config_json,
                                        agent_id: request.member_id,
                                        session_key_json,
                                        message: request.task,
                                        display_message: None,
                                        attachments_json: "[]".to_string(),
                                        tools: Some(engine.tools()),
                                        max_iterations,
                                        extra_tools: tool_context.extra_tools,
                                        internal_tool_handler: tool_context.internal_tool_handler,
                                        is_group_context: true,
                                        agent_engine: None,
                                    },
                                    || engine.is_session_cancelled(&cancellation_key),
                                ),
                            )
                            .await;
                            Ok(events_json(&events))
                        }
                    },
                )
                .await?;
                Ok(InternalToolResult {
                    output: execution.output,
                    events: execution.events,
                })
            })),
            _ => fallback_handler.and_then(|handler| handler(&tool_name, params, None)),
        }
    })
}
