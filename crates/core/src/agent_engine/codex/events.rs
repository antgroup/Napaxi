use serde_json::Value;

use crate::types::ChatEvent;

#[derive(Debug, Clone, Default)]
pub(crate) struct CodexTurnOutcome {
    pub(crate) event: Option<ChatEvent>,
    pub(crate) completed: bool,
    pub(crate) failed: bool,
    pub(crate) human_request: Option<CodexHumanRequest>,
}

#[derive(Debug, Clone)]
pub(crate) struct CodexHumanRequest {
    pub(crate) request_id: String,
    pub(crate) rpc_id: String,
    pub(crate) question_id: String,
}

pub(crate) fn map_app_server_message(message: &Value) -> CodexTurnOutcome {
    let params = message
        .get("params")
        .or_else(|| message.get("result"))
        .unwrap_or(message);
    let event = params.get("event").unwrap_or(params);
    let method = message.get("method").and_then(Value::as_str);
    let event_type = method
        .filter(|method| {
            method.starts_with("item/")
                || method.starts_with("turn/")
                || method.starts_with("codex/event/")
        })
        .map(str::to_string)
        .or_else(|| event_type(event));
    match event_type.as_deref() {
        Some("item/agentMessage/delta")
        | Some("assistant_delta")
        | Some("response_delta")
        | Some("message_delta") => {
            let content = first_string(event, &["delta", "content", "text"]);
            event_from_text(content, |content| ChatEvent::ResponseDelta { content })
        }
        Some("item/reasoning/textDelta")
        | Some("item/reasoning/summaryTextDelta")
        | Some("reasoning_delta")
        | Some("thinking_delta") => {
            let content = first_string(event, &["delta", "content", "text"]);
            event_from_text(content, |content| ChatEvent::ReasoningDelta { content })
        }
        Some("item/commandExecution/outputDelta")
        | Some("command_output_delta")
        | Some("tool_output_delta")
        | Some("exec_output_delta") => {
            let content = first_string(event, &["delta", "content", "output"]).unwrap_or_default();
            CodexTurnOutcome {
                event: Some(ChatEvent::ToolOutputChunk {
                    call_id: first_string(event, &["call_id", "callId", "itemId", "id"])
                        .unwrap_or_else(|| "codex-command".to_string()),
                    content,
                    stream: first_string(event, &["stream"])
                        .unwrap_or_else(|| "stdout".to_string()),
                }),
                ..CodexTurnOutcome::default()
            }
        }
        Some("turn/completed")
        | Some("codex/event/task_complete")
        | Some("turn_completed")
        | Some("completed")
        | Some("done") => CodexTurnOutcome {
            completed: true,
            ..CodexTurnOutcome::default()
        },
        Some("codex/event/turn_aborted")
        | Some("turn_aborted")
        | Some("aborted")
        | Some("interrupted") => CodexTurnOutcome {
            event: Some(ChatEvent::Interrupted),
            completed: true,
            failed: true,
            ..CodexTurnOutcome::default()
        },
        Some("turn_error") | Some("error") | Some("failed") => CodexTurnOutcome {
            event: Some(ChatEvent::Error {
                message: first_string(event, &["message", "error", "reason"])
                    .unwrap_or_else(|| "Codex agent engine failed".to_string()),
            }),
            completed: true,
            failed: true,
            ..CodexTurnOutcome::default()
        },
        Some("item/tool/requestUserInput")
        | Some("user_input_request")
        | Some("ask_human")
        | Some("input_request") => user_input_outcome(message, event),
        _ => CodexTurnOutcome::default(),
    }
}

fn event_type(value: &Value) -> Option<String> {
    first_string(value, &["type", "event", "kind"]).or_else(|| {
        value
            .get("name")
            .and_then(Value::as_str)
            .map(str::to_string)
    })
}

fn event_from_text(
    text: Option<String>,
    build: impl FnOnce(String) -> ChatEvent,
) -> CodexTurnOutcome {
    let Some(content) = text else {
        return CodexTurnOutcome::default();
    };
    if content.is_empty() {
        return CodexTurnOutcome::default();
    }
    CodexTurnOutcome {
        event: Some(build(content)),
        ..CodexTurnOutcome::default()
    }
}

fn first_string(value: &Value, keys: &[&str]) -> Option<String> {
    for key in keys {
        if let Some(s) = value.get(*key).and_then(Value::as_str) {
            return Some(s.to_string());
        }
    }
    None
}

fn string_array(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn user_input_outcome(message: &Value, event: &Value) -> CodexTurnOutcome {
    let first_question = event
        .get("questions")
        .and_then(Value::as_array)
        .and_then(|questions| questions.first());
    let question = first_question
        .and_then(|question| first_string(question, &["question", "prompt", "message"]))
        .or_else(|| first_string(event, &["question", "prompt", "message"]))
        .unwrap_or_else(|| "Codex needs input".to_string());
    let rpc_id = message.get("id").and_then(|id| {
        id.as_str()
            .map(str::to_string)
            .or_else(|| id.as_u64().map(|id| id.to_string()))
    });
    let is_rpc_request =
        message.get("method").and_then(Value::as_str) == Some("item/tool/requestUserInput");
    let request_id = if is_rpc_request {
        format!("codex:{}", uuid::Uuid::new_v4())
    } else {
        first_string(event, &["request_id", "requestId", "id"])
            .or(rpc_id.clone())
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string())
    };
    let options = first_question
        .and_then(|question| question.get("options"))
        .map(option_labels)
        .filter(|options| !options.is_empty())
        .unwrap_or_else(|| string_array(event.get("options")));
    let context = first_question
        .and_then(|question| first_string(question, &["context", "header"]))
        .or_else(|| first_string(event, &["context", "header"]));
    let question_id = first_question
        .and_then(|question| first_string(question, &["id", "request_id", "requestId"]))
        .or_else(|| first_string(event, &["question_id", "questionId"]))
        .unwrap_or_else(|| "answer".to_string());
    let human_request = rpc_id.map(|rpc_id| CodexHumanRequest {
        request_id: request_id.clone(),
        rpc_id,
        question_id,
    });
    CodexTurnOutcome {
        event: Some(ChatEvent::AskingHuman {
            question,
            request_id,
            options,
            context,
        }),
        human_request,
        ..CodexTurnOutcome::default()
    }
}

fn option_labels(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    item.as_str().map(str::to_string).or_else(|| {
                        item.get("label")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}
