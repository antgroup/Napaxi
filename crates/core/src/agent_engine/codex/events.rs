use serde_json::{Value, json};

use crate::types::ChatEvent;

#[derive(Debug, Clone, Default)]
pub(crate) struct CodexTurnOutcome {
    pub(crate) event: Option<ChatEvent>,
    pub(crate) extra_events: Vec<ChatEvent>,
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
                || *method == "error"
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
        Some("item/started") => item_started_outcome(event),
        Some("item/completed") => item_completed_outcome(event),
        Some("item/commandExecution/outputDelta")
        | Some("item/commandExecution/terminalInteraction")
        | Some("command_output_delta")
        | Some("tool_output_delta")
        | Some("exec_output_delta") => {
            let content =
                first_string(event, &["delta", "stdin", "content", "output"]).unwrap_or_default();
            CodexTurnOutcome {
                event: Some(ChatEvent::ToolOutputChunk {
                    call_id: first_string(event, &["call_id", "callId", "itemId", "id"])
                        .unwrap_or_else(|| "codex-command".to_string()),
                    content,
                    stream: first_string(event, &["stream"]).unwrap_or_else(|| {
                        if event_type.as_deref()
                            == Some("item/commandExecution/terminalInteraction")
                        {
                            "stdin".to_string()
                        } else {
                            "stdout".to_string()
                        }
                    }),
                }),
                ..CodexTurnOutcome::default()
            }
        }
        Some("turn/completed")
        | Some("codex/event/task_complete")
        | Some("turn_completed")
        | Some("completed")
        | Some("done") => completed_outcome(event),
        Some("codex/event/turn_aborted")
        | Some("turn_aborted")
        | Some("aborted")
        | Some("interrupted") => CodexTurnOutcome {
            event: Some(ChatEvent::Interrupted),
            completed: true,
            failed: true,
            ..CodexTurnOutcome::default()
        },
        Some("turn_error") | Some("error") | Some("failed") => error_outcome(event),
        Some("item/tool/requestUserInput")
        | Some("user_input_request")
        | Some("ask_human")
        | Some("input_request") => user_input_outcome(message, event),
        _ => CodexTurnOutcome::default(),
    }
}

fn item_started_outcome(event: &Value) -> CodexTurnOutcome {
    let item = thread_item(event);
    let Some((call_id, name, arguments)) = tool_call_start(&item) else {
        return CodexTurnOutcome::default();
    };
    let extra_events = apply_patch_progress_events(&call_id, &name, &item);
    CodexTurnOutcome {
        event: Some(ChatEvent::ToolCall {
            call_id,
            name,
            arguments,
        }),
        extra_events,
        ..CodexTurnOutcome::default()
    }
}

fn item_completed_outcome(event: &Value) -> CodexTurnOutcome {
    let item = thread_item(event);
    let kind = string_field(&item, "type");
    match kind.as_str() {
        // Codex streams assistant/reasoning text through delta notifications.
        // The completed item repeats the full text, so do not map it here or
        // the existing frontend renderer would display duplicate content.
        "agentMessage" | "reasoning" => CodexTurnOutcome::default(),
        "imageGeneration" => image_generation_outcome(&item),
        "imageView" => image_view_outcome(&item),
        _ => {
            let Some((call_id, name, output, is_error)) = tool_call_result(&item) else {
                return CodexTurnOutcome::default();
            };
            CodexTurnOutcome {
                event: Some(ChatEvent::ToolResult {
                    call_id,
                    name,
                    output,
                    is_error,
                }),
                ..CodexTurnOutcome::default()
            }
        }
    }
}

fn thread_item(event: &Value) -> Value {
    event.get("item").cloned().unwrap_or_else(|| event.clone())
}

fn tool_call_start(item: &Value) -> Option<(String, String, String)> {
    let kind = string_field(item, "type");
    let call_id = if is_custom_tool_kind(&kind) {
        response_call_id(item)
    } else {
        item_id(item)
    };
    if call_id.is_empty() {
        return None;
    }
    let (name, arguments) = match kind.as_str() {
        "commandExecution" => ("shell".to_string(), command_execution_arguments(item)),
        "dynamicToolCall" => (dynamic_tool_name(item), dynamic_tool_arguments(item)),
        "mcpToolCall" => (mcp_tool_name(item)?, json_arguments(item.get("arguments"))),
        "fileChange" => ("apply_patch".to_string(), file_change_arguments(item)),
        "custom_tool_call" | "customToolCall" => {
            (custom_tool_name(item), custom_tool_arguments(item))
        }
        "webSearch" => (
            "web_search".to_string(),
            json!({"query": string_field(item, "query")}).to_string(),
        ),
        _ => return None,
    };
    if name.trim().is_empty() {
        None
    } else {
        Some((call_id, name, arguments))
    }
}

fn tool_call_result(item: &Value) -> Option<(String, String, String, bool)> {
    let kind = string_field(item, "type");
    let call_id = if is_custom_tool_kind(&kind) || is_custom_tool_output_kind(&kind) {
        response_call_id(item)
    } else {
        item_id(item)
    };
    if call_id.is_empty() {
        return None;
    }
    match kind.as_str() {
        "commandExecution" => Some((
            call_id,
            "shell".to_string(),
            command_execution_output(item),
            status_failed(item)
                || item
                    .get("exitCode")
                    .and_then(Value::as_i64)
                    .is_some_and(|code| code != 0),
        )),
        "dynamicToolCall" => {
            let name = dynamic_tool_name(item);
            if name.trim().is_empty() {
                return None;
            }
            Some((
                call_id,
                name,
                dynamic_tool_output(item),
                status_failed(item) || item.get("success").and_then(Value::as_bool) == Some(false),
            ))
        }
        "mcpToolCall" => Some((
            call_id,
            mcp_tool_name(item)?,
            item.get("result")
                .or_else(|| item.get("error"))
                .map(value_text)
                .unwrap_or_default(),
            status_failed(item) || item.get("error").is_some_and(|value| !value.is_null()),
        )),
        "fileChange" => Some((
            call_id,
            "apply_patch".to_string(),
            file_change_output(item),
            status_failed(item),
        )),
        "custom_tool_call" | "customToolCall" => {
            let name = custom_tool_name(item);
            Some((
                call_id,
                name.clone(),
                custom_tool_output(&name, &custom_tool_arguments(item), item),
                custom_tool_failed(item),
            ))
        }
        "custom_tool_call_output" | "customToolCallOutput" => Some((
            call_id,
            custom_tool_name(item),
            string_field(item, "output"),
            custom_tool_failed(item),
        )),
        "webSearch" => Some((call_id, "web_search".to_string(), String::new(), false)),
        _ => None,
    }
}

fn command_execution_arguments(item: &Value) -> String {
    json!({
        "cmd": string_field(item, "command"),
        "cwd": string_field(item, "cwd"),
    })
    .to_string()
}

fn command_execution_output(item: &Value) -> String {
    first_string(item, &["aggregatedOutput", "output", "stdout", "stderr"])
        .or_else(|| item.get("contentItems").map(value_text))
        .unwrap_or_default()
}

fn item_id(item: &Value) -> String {
    first_string(item, &["id", "call_id", "callId", "itemId"]).unwrap_or_default()
}

fn response_call_id(item: &Value) -> String {
    first_string(item, &["call_id", "callId", "itemId", "id"]).unwrap_or_default()
}

fn is_custom_tool_kind(kind: &str) -> bool {
    matches!(kind, "custom_tool_call" | "customToolCall")
}

fn is_custom_tool_output_kind(kind: &str) -> bool {
    matches!(kind, "custom_tool_call_output" | "customToolCallOutput")
}

fn custom_tool_name(item: &Value) -> String {
    let name = string_field(item, "name");
    if name.trim().is_empty() {
        "custom_tool".to_string()
    } else {
        name
    }
}

fn custom_tool_arguments(item: &Value) -> String {
    let input = first_string(item, &["input", "arguments", "content"]).unwrap_or_default();
    if custom_tool_name(item) == "apply_patch" {
        json!({"patch": input}).to_string()
    } else if input.trim().is_empty() {
        json!({}).to_string()
    } else {
        input
    }
}

fn custom_tool_output(name: &str, arguments: &str, item: &Value) -> String {
    let output = string_field(item, "output");
    if name != "apply_patch" {
        return output;
    }
    let patch = serde_json::from_str::<Value>(arguments)
        .ok()
        .and_then(|value| first_string(&value, &["patch"]))
        .unwrap_or_default();
    json!({
        "status": if custom_tool_failed(item) { "error" } else { "ok" },
        "files": patch_files(&patch),
        "output": output,
    })
    .to_string()
}

fn custom_tool_failed(item: &Value) -> bool {
    status_failed(item)
        || string_field(item, "output")
            .lines()
            .next()
            .and_then(|line| line.trim().strip_prefix("Exit code:"))
            .and_then(|code| code.trim().parse::<i64>().ok())
            .is_some_and(|code| code != 0)
}

fn dynamic_tool_name(item: &Value) -> String {
    let namespace = string_field(item, "namespace");
    let tool = string_field(item, "tool");
    if namespace.is_empty() {
        tool
    } else if tool.is_empty() {
        namespace
    } else {
        format!("{namespace}.{tool}")
    }
}

fn dynamic_tool_arguments(item: &Value) -> String {
    json_arguments(item.get("arguments"))
}

fn dynamic_tool_output(item: &Value) -> String {
    item.get("contentItems")
        .or_else(|| item.get("result"))
        .or_else(|| item.get("output"))
        .map(value_text)
        .unwrap_or_default()
}

fn mcp_tool_name(item: &Value) -> Option<String> {
    let server = string_field(item, "server");
    let tool = string_field(item, "tool");
    if server.is_empty() || tool.is_empty() {
        None
    } else {
        Some(format!("{server}.{tool}"))
    }
}

fn file_change_arguments(item: &Value) -> String {
    let patch = file_change_patch(item);
    if patch.is_empty() {
        json!({"changes": item.get("changes").cloned().unwrap_or(Value::Null)}).to_string()
    } else {
        json!({"patch": patch}).to_string()
    }
}

fn file_change_output(item: &Value) -> String {
    json!({
        "status": if status_failed(item) { "error" } else { "ok" },
        "files": file_change_files(item),
    })
    .to_string()
}

fn apply_patch_progress_events(call_id: &str, name: &str, item: &Value) -> Vec<ChatEvent> {
    if name != "apply_patch" {
        return Vec::new();
    }
    let files = if is_custom_tool_kind(&string_field(item, "type")) {
        let arguments = custom_tool_arguments(item);
        let patch = serde_json::from_str::<Value>(&arguments)
            .ok()
            .and_then(|value| first_string(&value, &["patch"]))
            .unwrap_or_default();
        patch_files(&patch)
    } else {
        file_change_files(item)
    };
    patch_progress_events(call_id, files)
}

fn patch_progress_events(call_id: &str, files: Vec<Value>) -> Vec<ChatEvent> {
    files
        .into_iter()
        .filter(|file| {
            file.get("path")
                .and_then(Value::as_str)
                .is_some_and(|path| !path.trim().is_empty())
        })
        .map(|file| ChatEvent::ToolOutputChunk {
            call_id: call_id.to_string(),
            stream: "patch".to_string(),
            content: json!({
                "type": "apply_patch_progress",
                "path": file.get("path").and_then(Value::as_str).unwrap_or_default(),
                "action": file.get("action").and_then(Value::as_str).unwrap_or("updated"),
                "added_lines": file.get("added_lines").and_then(Value::as_i64).unwrap_or_default(),
                "removed_lines": file.get("removed_lines").and_then(Value::as_i64).unwrap_or_default(),
            })
            .to_string(),
        })
        .collect()
}

fn patch_files(patch: &str) -> Vec<Value> {
    #[derive(Debug)]
    struct PatchFile {
        action: String,
        path: String,
        added: i64,
        removed: i64,
    }

    let mut files = Vec::<PatchFile>::new();
    let mut current: Option<PatchFile> = None;
    for line in patch.lines() {
        if let Some(path) = line.strip_prefix("*** Add File: ") {
            if let Some(file) = current.take() {
                files.push(file);
            }
            current = Some(PatchFile {
                action: "added".to_string(),
                path: path.trim().to_string(),
                added: 0,
                removed: 0,
            });
            continue;
        }
        if let Some(path) = line.strip_prefix("*** Delete File: ") {
            if let Some(file) = current.take() {
                files.push(file);
            }
            current = Some(PatchFile {
                action: "deleted".to_string(),
                path: path.trim().to_string(),
                added: 0,
                removed: 0,
            });
            continue;
        }
        if let Some(path) = line.strip_prefix("*** Update File: ") {
            if let Some(file) = current.take() {
                files.push(file);
            }
            current = Some(PatchFile {
                action: "updated".to_string(),
                path: path.trim().to_string(),
                added: 0,
                removed: 0,
            });
            continue;
        }
        let Some(file) = current.as_mut() else {
            continue;
        };
        if line.starts_with('+') && !line.starts_with("+++") {
            file.added += 1;
        } else if line.starts_with('-') && !line.starts_with("---") {
            file.removed += 1;
        }
    }
    if let Some(file) = current {
        files.push(file);
    }
    files
        .into_iter()
        .filter(|file| !file.path.is_empty())
        .map(|file| {
            json!({
                "action": file.action,
                "path": file.path,
                "added_lines": file.added,
                "removed_lines": file.removed,
            })
        })
        .collect()
}

fn file_change_patch(item: &Value) -> String {
    if let Some(patch) = first_string(item, &["patch", "diff"]) {
        return patch;
    }
    file_change_files(item)
        .into_iter()
        .map(|file| {
            let action = file
                .get("action")
                .and_then(Value::as_str)
                .unwrap_or("updated");
            let path = file.get("path").and_then(Value::as_str).unwrap_or_default();
            let header = match action {
                "added" => "Add",
                "deleted" => "Delete",
                _ => "Update",
            };
            format!("*** {header} File: {path}")
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn file_change_files(item: &Value) -> Vec<Value> {
    let Some(changes) = item.get("changes").and_then(Value::as_array) else {
        let path = first_string(item, &["path", "file", "filePath"]).unwrap_or_default();
        return if path.is_empty() {
            Vec::new()
        } else {
            vec![json!({"action": "updated", "path": path, "added_lines": 0, "removed_lines": 0})]
        };
    };
    changes
        .iter()
        .filter_map(|change| {
            let path = first_string(change, &["path", "file", "filePath", "oldPath", "newPath"])
                .or_else(|| first_string(change, &["oldPath", "newPath"]))?;
            let action = file_change_action(change);
            let (diff_added, diff_removed) = file_change_diff_counts(change, &action);
            Some(json!({
                "action": action,
                "path": path,
                "added_lines": int_field(change, &["added_lines", "addedLines", "additions", "added", "insertions"]).max(diff_added),
                "removed_lines": int_field(change, &["removed_lines", "removedLines", "deletions", "removed", "deletes"]).max(diff_removed),
            }))
        })
        .collect()
}

fn file_change_action(change: &Value) -> String {
    first_string(change, &["action", "type", "operation"])
        .or_else(|| {
            change
                .get("kind")
                .and_then(|kind| first_string(kind, &["type", "action", "operation"]))
        })
        .map(|action| normalize_file_action(&action).to_string())
        .unwrap_or_else(|| "updated".to_string())
}

fn file_change_diff_counts(change: &Value, action: &str) -> (i64, i64) {
    let diff = first_string(change, &["diff", "patch", "content"]).unwrap_or_default();
    if diff.is_empty() {
        return (0, 0);
    }
    let mut added = 0;
    let mut removed = 0;
    let mut saw_patch_markers = false;
    for line in diff.lines() {
        if line.starts_with("+++") || line.starts_with("---") {
            saw_patch_markers = true;
            continue;
        }
        if line.starts_with('+') {
            saw_patch_markers = true;
            added += 1;
        } else if line.starts_with('-') {
            saw_patch_markers = true;
            removed += 1;
        }
    }
    if saw_patch_markers || action == "updated" {
        return (added, removed);
    }
    let line_count = diff.lines().count() as i64;
    match action {
        "added" => (line_count, 0),
        "deleted" => (0, line_count),
        _ => (added, removed),
    }
}

fn normalize_file_action(action: &str) -> &str {
    match action.trim() {
        value
            if value.eq_ignore_ascii_case("add")
                || value.eq_ignore_ascii_case("added")
                || value.eq_ignore_ascii_case("create")
                || value.eq_ignore_ascii_case("created") =>
        {
            "added"
        }
        value
            if value.eq_ignore_ascii_case("delete")
                || value.eq_ignore_ascii_case("deleted")
                || value.eq_ignore_ascii_case("remove")
                || value.eq_ignore_ascii_case("removed") =>
        {
            "deleted"
        }
        _ => "updated",
    }
}

fn int_field(value: &Value, keys: &[&str]) -> i64 {
    for key in keys {
        if let Some(number) = value.get(*key).and_then(Value::as_i64) {
            return number;
        }
        if let Some(text) = value.get(*key).and_then(Value::as_str)
            && let Ok(number) = text.parse::<i64>()
        {
            return number;
        }
    }
    0
}

fn status_failed(item: &Value) -> bool {
    matches!(
        string_field(item, "status").to_ascii_lowercase().as_str(),
        "failed" | "rejected" | "error" | "cancelled" | "canceled"
    )
}

fn image_generation_outcome(item: &Value) -> CodexTurnOutcome {
    if !string_field(item, "status").eq_ignore_ascii_case("completed") {
        return CodexTurnOutcome::default();
    }
    let path = first_string(item, &["savedPath", "saved_path", "path"]);
    let result = string_field(item, "result");
    if result.starts_with("data:image/") {
        return CodexTurnOutcome {
            event: Some(ChatEvent::ImageGenerated {
                data_url: result,
                path,
            }),
            ..CodexTurnOutcome::default()
        };
    }
    event_from_text(
        path.map(|path| format!("\n![Image]({path})\n")),
        |content| ChatEvent::ResponseDelta { content },
    )
}

fn image_view_outcome(item: &Value) -> CodexTurnOutcome {
    event_from_text(first_string(item, &["path"]), |path| {
        ChatEvent::ResponseDelta {
            content: format!("\n![Image]({path})\n"),
        }
    })
}

fn string_field(value: &Value, key: &str) -> String {
    match value.get(key) {
        Some(Value::String(value)) => value.clone(),
        Some(Value::Null) | None => String::new(),
        Some(value) => value_text(value),
    }
}

fn value_text(value: &Value) -> String {
    value
        .as_str()
        .map(str::to_string)
        .unwrap_or_else(|| value.to_string())
}

fn json_arguments(value: Option<&Value>) -> String {
    value.cloned().unwrap_or_else(|| json!({})).to_string()
}

fn completed_outcome(event: &Value) -> CodexTurnOutcome {
    let turn = event.get("turn").unwrap_or(event);
    let status = turn.get("status").and_then(Value::as_str);
    let error = turn.get("error").filter(|value| !value.is_null());
    if status == Some("failed") || error.is_some() {
        return CodexTurnOutcome {
            event: Some(ChatEvent::Error {
                message: error
                    .and_then(error_message)
                    .or_else(|| error_message(turn))
                    .unwrap_or_else(|| "Codex agent engine failed".to_string()),
            }),
            completed: true,
            failed: true,
            ..CodexTurnOutcome::default()
        };
    }
    CodexTurnOutcome {
        completed: true,
        ..CodexTurnOutcome::default()
    }
}

fn error_outcome(event: &Value) -> CodexTurnOutcome {
    let message = event
        .get("error")
        .and_then(error_message)
        .or_else(|| error_message(event))
        .unwrap_or_else(|| "Codex agent engine failed".to_string());
    if event
        .get("willRetry")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return CodexTurnOutcome {
            event: Some(ChatEvent::StreamReset {
                reason: retry_error_reason(&message, event),
            }),
            ..CodexTurnOutcome::default()
        };
    }
    CodexTurnOutcome {
        event: Some(ChatEvent::Error { message }),
        completed: true,
        failed: true,
        ..CodexTurnOutcome::default()
    }
}

fn retry_error_reason(message: &str, event: &Value) -> String {
    let details = event
        .get("error")
        .and_then(error_details)
        .or_else(|| error_details(event));
    match details {
        Some(details) if !details.is_empty() && details != message => {
            format!("{message}: {details}")
        }
        _ => message.to_string(),
    }
}

fn error_details(value: &Value) -> Option<String> {
    first_string(value, &["additionalDetails", "details"]).or_else(|| {
        value
            .pointer("/error/additionalDetails")
            .and_then(Value::as_str)
            .map(str::to_string)
    })
}

fn error_message(value: &Value) -> Option<String> {
    first_string(value, &["message", "error", "reason", "additionalDetails"]).or_else(|| {
        value
            .pointer("/error/message")
            .or_else(|| value.pointer("/error/additionalDetails"))
            .and_then(Value::as_str)
            .map(str::to_string)
    })
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
