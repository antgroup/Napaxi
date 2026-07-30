use serde_json::{Map, Value, json};

pub(super) fn map_thread_summary(value: &Value) -> Option<Value> {
    let id = value.get("id")?.as_str()?.trim();
    if id.is_empty() {
        return None;
    }
    Some(json!({
        "id": id,
        "name": string_field(value, "name"),
        "preview": string_field(value, "preview"),
        "createdAt": timestamp_millis(value.get("createdAt")),
        "updatedAt": timestamp_millis(value.get("updatedAt")),
    }))
}

fn timestamp_millis(value: Option<&Value>) -> i64 {
    let raw = value.and_then(Value::as_f64).unwrap_or_default();
    if raw > 1_000_000_000_000.0 {
        raw as i64
    } else {
        (raw * 1000.0) as i64
    }
}

pub(super) fn extract_thread_items(result: Option<&Value>) -> Vec<Value> {
    let Some(result) = result else {
        return Vec::new();
    };
    if let Some(turns) = result.pointer("/thread/turns").and_then(Value::as_array) {
        let items = turns
            .iter()
            .filter_map(|turn| turn.get("items").and_then(Value::as_array))
            .flatten()
            .filter(|item| item.get("type").is_some())
            .cloned()
            .collect::<Vec<_>>();
        if !items.is_empty() {
            return items;
        }
    }
    ["/thread/items", "/thread/content", "/items"]
        .iter()
        .find_map(|pointer| result.pointer(pointer).and_then(Value::as_array))
        .map(|items| {
            items
                .iter()
                .filter(|item| item.get("type").is_some())
                .cloned()
                .collect()
        })
        .unwrap_or_default()
}

pub(super) fn map_history_items(items: &[Value]) -> Vec<Value> {
    let mut messages = Vec::new();
    let mut pending_calls = std::collections::HashMap::<String, PendingHistoryToolCall>::new();
    for item in items {
        let item = history_payload(item);
        let kind = string_field(item, "type");
        match kind.as_str() {
            "function_call" => {
                let call_id = response_call_id(item);
                if !call_id.is_empty() {
                    pending_calls.insert(
                        call_id,
                        PendingHistoryToolCall {
                            id: string_field(item, "id"),
                            name: function_call_tool_name(item),
                            arguments: function_call_arguments(item),
                        },
                    );
                }
            }
            "custom_tool_call" => {
                let call_id = response_call_id(item);
                if !call_id.is_empty() {
                    pending_calls.insert(
                        call_id,
                        PendingHistoryToolCall {
                            id: string_field(item, "id"),
                            name: custom_tool_name(item),
                            arguments: custom_tool_arguments(item),
                        },
                    );
                }
            }
            "function_call_output" => {
                let call_id = response_call_id(item);
                if call_id.is_empty() {
                    if let Some(message) = map_history_payload_item(item) {
                        messages.push(message);
                    }
                    continue;
                }
                let pending = pending_calls.remove(&call_id);
                messages.push(tool_call_history_message(
                    pending
                        .as_ref()
                        .map(|call| call.id.as_str())
                        .filter(|id| !id.is_empty())
                        .unwrap_or(&call_id),
                    pending
                        .as_ref()
                        .map(|call| call.name.as_str())
                        .unwrap_or("shell"),
                    &call_id,
                    pending
                        .as_ref()
                        .map(|call| call.arguments.clone())
                        .unwrap_or_else(|| json!({}).to_string()),
                    string_field(item, "output"),
                    false,
                    "Ran command".to_string(),
                ));
            }
            "custom_tool_call_output" => {
                let call_id = response_call_id(item);
                if call_id.is_empty() {
                    if let Some(message) = map_history_payload_item(item) {
                        messages.push(message);
                    }
                    continue;
                }
                let pending = pending_calls.remove(&call_id);
                let name = pending
                    .as_ref()
                    .map(|call| call.name.as_str())
                    .unwrap_or("custom_tool");
                let arguments = pending
                    .as_ref()
                    .map(|call| call.arguments.clone())
                    .unwrap_or_else(|| json!({}).to_string());
                let output = custom_tool_output(name, &arguments, item);
                messages.push(tool_call_history_message(
                    pending
                        .as_ref()
                        .map(|call| call.id.as_str())
                        .filter(|id| !id.is_empty())
                        .unwrap_or(&call_id),
                    name,
                    &call_id,
                    arguments,
                    output,
                    custom_tool_failed(item),
                    custom_tool_narrative(name),
                ));
            }
            _ => {
                if let Some(message) = map_history_payload_item(item) {
                    messages.push(message);
                }
            }
        }
    }
    for (call_id, pending) in pending_calls {
        messages.push(tool_call_history_message(
            if pending.id.is_empty() {
                &call_id
            } else {
                &pending.id
            },
            &pending.name,
            &call_id,
            pending.arguments,
            String::new(),
            false,
            "Ran command".to_string(),
        ));
    }
    messages
}

#[derive(Debug)]
struct PendingHistoryToolCall {
    id: String,
    name: String,
    arguments: String,
}

fn map_history_item(item: &Value) -> Option<Value> {
    map_history_payload_item(history_payload(item))
}

fn map_history_payload_item(item: &Value) -> Option<Value> {
    let kind = string_field(item, "type");
    let id = item_id(item);
    let (role, content) = match kind.as_str() {
        "message" => match string_field(item, "role").as_str() {
            "user" => {
                let content = response_message_text(item);
                if is_synthetic_codex_context_message(&content) {
                    return None;
                }
                ("user", content)
            }
            "assistant" => ("assistant", response_message_text(item)),
            _ => return None,
        },
        "agentMessage" => ("assistant", string_field(item, "text")),
        "userMessage" => ("user", user_message_text(item)),
        "reasoning" => ("reasoning", reasoning_text(item)),
        "function_call" => (
            "tool_calls",
            tool_call_history_message_content(
                &function_call_tool_name(item),
                &response_call_id(item),
                function_call_arguments(item),
                String::new(),
                false,
                "Ran command".to_string(),
            ),
        ),
        "function_call_output" => (
            "tool_calls",
            tool_call_history_message_content(
                "shell",
                &response_call_id(item),
                json!({}).to_string(),
                string_field(item, "output"),
                false,
                "Ran command".to_string(),
            ),
        ),
        "custom_tool_call" => (
            "tool_calls",
            tool_call_history_message_content(
                &custom_tool_name(item),
                &response_call_id(item),
                custom_tool_arguments(item),
                String::new(),
                custom_tool_failed(item),
                custom_tool_narrative(&custom_tool_name(item)),
            ),
        ),
        "custom_tool_call_output" => (
            "tool_calls",
            tool_call_history_message_content(
                "custom_tool",
                &response_call_id(item),
                json!({}).to_string(),
                string_field(item, "output"),
                custom_tool_failed(item),
                "Called custom_tool".to_string(),
            ),
        ),
        "commandExecution" | "dynamicToolCall" | "mcpToolCall" | "fileChange" | "webSearch" => {
            ("tool_calls", tool_call_content(item, &kind, &id))
        }
        _ => {
            let content = item
                .get("text")
                .or_else(|| item.get("content"))
                .map(value_text)
                .unwrap_or_default();
            let role = if kind.to_ascii_lowercase().contains("user") {
                "user"
            } else {
                "assistant"
            };
            (role, content)
        }
    };
    if content.trim().is_empty() {
        return None;
    }
    let mut message = Map::from_iter([
        ("role".to_string(), Value::String(role.to_string())),
        ("content".to_string(), Value::String(content)),
    ]);
    if !id.is_empty() {
        message.insert("id".to_string(), Value::String(id));
    }
    Some(Value::Object(message))
}

fn history_payload(item: &Value) -> &Value {
    if item.get("type").and_then(Value::as_str) == Some("response_item") {
        item.get("payload").unwrap_or(item)
    } else {
        item
    }
}

fn response_message_text(item: &Value) -> String {
    item.get("content")
        .and_then(Value::as_array)
        .map(|content| {
            content
                .iter()
                .filter_map(|entry| {
                    entry.as_str().map(str::to_string).or_else(|| {
                        first_string(entry, &["text", "content"]).filter(|_| {
                            matches!(
                                string_field(entry, "type").as_str(),
                                "input_text" | "output_text" | "text" | ""
                            )
                        })
                    })
                })
                .filter(|text| !text.trim().is_empty())
                .collect::<Vec<_>>()
                .join("")
        })
        .filter(|text| !text.trim().is_empty())
        .or_else(|| first_string(item, &["text", "output_text", "input_text"]))
        .unwrap_or_default()
}

fn is_synthetic_codex_context_message(content: &str) -> bool {
    let trimmed = content.trim_start();
    trimmed.starts_with("<environment_context>")
        || trimmed.starts_with("<permissions instructions>")
        || trimmed.starts_with("<skills_instructions>")
}

fn user_message_text(item: &Value) -> String {
    if let Some(content) = item.get("content").and_then(Value::as_array) {
        return content
            .iter()
            .filter_map(|entry| {
                if let Some(text) = entry.as_str() {
                    return Some(text.to_string());
                }
                (entry.get("type").and_then(Value::as_str) == Some("text"))
                    .then(|| string_field(entry, "text"))
            })
            .filter(|text| !text.is_empty())
            .collect::<String>()
            .trim()
            .to_string();
    }
    item.get("text")
        .or_else(|| item.get("content"))
        .map(value_text)
        .unwrap_or_default()
}

fn reasoning_text(item: &Value) -> String {
    ["summary", "content", "text"]
        .iter()
        .filter_map(|field| item.get(field))
        .flat_map(reasoning_value_texts)
        .filter(|text| !text.trim().is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

fn reasoning_value_texts(value: &Value) -> Vec<String> {
    match value {
        Value::String(text) => vec![text.clone()],
        Value::Array(items) => items.iter().flat_map(reasoning_value_texts).collect(),
        Value::Object(_) => first_string(value, &["text", "content", "summary", "message"])
            .map(|text| vec![text])
            .unwrap_or_default(),
        Value::Null => Vec::new(),
        other => vec![value_text(other)],
    }
}

fn tool_call_content(item: &Value, kind: &str, id: &str) -> String {
    let (name, arguments, output, failed, narrative) = match kind {
        "commandExecution" => {
            let arguments = json!({
                "cmd": string_field(item, "command"),
                "cwd": string_field(item, "cwd"),
            });
            let status = string_field(item, "status").to_ascii_lowercase();
            let failed = status_failed(&status)
                || item
                    .get("exitCode")
                    .and_then(Value::as_i64)
                    .is_some_and(|code| code != 0);
            (
                "shell".to_string(),
                arguments.to_string(),
                command_execution_output(item),
                failed,
                "Ran command".to_string(),
            )
        }
        "dynamicToolCall" => {
            let namespace = string_field(item, "namespace");
            let tool = string_field(item, "tool");
            let name = if namespace.is_empty() {
                tool
            } else if tool.is_empty() {
                namespace
            } else {
                format!("{namespace}.{tool}")
            };
            let status = string_field(item, "status").to_ascii_lowercase();
            let failed = status_failed(&status)
                || item.get("success").and_then(Value::as_bool) == Some(false);
            let output = item
                .get("contentItems")
                .or_else(|| item.get("result"))
                .or_else(|| item.get("output"))
                .map(value_text)
                .unwrap_or_default();
            (
                name.clone(),
                item.get("arguments")
                    .cloned()
                    .unwrap_or(Value::Null)
                    .to_string(),
                output,
                failed,
                format!("Called {name}"),
            )
        }
        "mcpToolCall" => {
            let name = format!(
                "{}.{}",
                string_field(item, "server"),
                string_field(item, "tool")
            );
            let status = string_field(item, "status").to_ascii_lowercase();
            let failed =
                status_failed(&status) || item.get("error").is_some_and(|value| !value.is_null());
            (
                name.clone(),
                item.get("arguments")
                    .cloned()
                    .unwrap_or_else(|| json!({}))
                    .to_string(),
                item.get("result")
                    .or_else(|| item.get("error"))
                    .map(value_text)
                    .unwrap_or_default(),
                failed,
                format!("Called {name}"),
            )
        }
        "fileChange" => {
            let status = string_field(item, "status").to_ascii_lowercase();
            let failed = status_failed(&status);
            let output = json!({
                "status": if failed { "error" } else { "ok" },
                "files": file_change_files(item),
            })
            .to_string();
            (
                "apply_patch".to_string(),
                file_change_arguments(item),
                output,
                failed,
                if failed {
                    "File change failed"
                } else {
                    "File change"
                }
                .to_string(),
            )
        }
        _ => {
            let query = string_field(item, "query");
            (
                "web_search".to_string(),
                json!({"query": query}).to_string(),
                String::new(),
                false,
                if query.is_empty() {
                    "Searched the web".to_string()
                } else {
                    format!("Searched: {query}")
                },
            )
        }
    };
    tool_call_history_message_content(&name, id, arguments, output, failed, narrative)
}

fn tool_call_history_message(
    id: &str,
    name: &str,
    call_id: &str,
    arguments: String,
    output: String,
    failed: bool,
    narrative: String,
) -> Value {
    let mut message = Map::from_iter([
        ("role".to_string(), Value::String("tool_calls".to_string())),
        (
            "content".to_string(),
            Value::String(tool_call_history_message_content(
                name, call_id, arguments, output, failed, narrative,
            )),
        ),
    ]);
    if !id.is_empty() {
        message.insert("id".to_string(), Value::String(id.to_string()));
    }
    Value::Object(message)
}

fn tool_call_history_message_content(
    name: &str,
    call_id: &str,
    arguments: String,
    output: String,
    failed: bool,
    narrative: String,
) -> String {
    let mut call = json!({"name": name, "call_id": call_id, "arguments": arguments});
    if !output.is_empty() {
        call["result"] = Value::String(output.clone());
        if failed {
            call["error"] = Value::String(output);
        }
    } else if failed {
        call["error"] = Value::String("Tool call failed".to_string());
    }
    json!({"narrative": narrative, "calls": [call]}).to_string()
}

fn function_call_tool_name(item: &Value) -> String {
    match string_field(item, "name").as_str() {
        "exec_command" | "shell" => "shell".to_string(),
        "apply_patch" => "apply_patch".to_string(),
        name if name.trim().is_empty() => "shell".to_string(),
        name => name.to_string(),
    }
}

fn function_call_arguments(item: &Value) -> String {
    let raw = string_field(item, "arguments");
    if raw.trim().is_empty() {
        return json!({}).to_string();
    }
    if function_call_tool_name(item) != "shell" {
        return raw;
    }
    match serde_json::from_str::<Value>(&raw) {
        Ok(Value::Object(mut map)) => {
            if let Some(command) = map.remove("cmd").or_else(|| map.remove("command")) {
                json!({
                    "cmd": command.as_str().map(str::to_string).unwrap_or_else(|| command.to_string()),
                    "cwd": map.remove("cwd").and_then(|value| value.as_str().map(str::to_string)).unwrap_or_default(),
                })
                .to_string()
            } else {
                Value::Object(map).to_string()
            }
        }
        Ok(value) => value.to_string(),
        Err(_) => json!({"cmd": raw, "cwd": ""}).to_string(),
    }
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
    let files = patch_files(&patch);
    json!({
        "status": if custom_tool_failed(item) { "error" } else { "ok" },
        "files": files,
        "output": output,
    })
    .to_string()
}

fn custom_tool_failed(item: &Value) -> bool {
    let status = string_field(item, "status").to_ascii_lowercase();
    status_failed(&status)
        || string_field(item, "output")
            .lines()
            .next()
            .and_then(|line| line.trim().strip_prefix("Exit code:"))
            .and_then(|code| code.trim().parse::<i64>().ok())
            .is_some_and(|code| code != 0)
}

fn custom_tool_narrative(name: &str) -> String {
    if name == "apply_patch" {
        "File change".to_string()
    } else {
        format!("Called {name}")
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
            let path = first_string(change, &["path", "file", "filePath", "oldPath", "newPath"])?;
            let action = first_string(change, &["action", "type", "operation"])
                .unwrap_or_else(|| "updated".to_string());
            Some(json!({
                "action": normalize_file_action(&action),
                "path": path,
                "added_lines": int_field(change, &["added_lines", "addedLines", "additions", "added", "insertions"]),
                "removed_lines": int_field(change, &["removed_lines", "removedLines", "deletions", "removed", "deletes"]),
            }))
        })
        .collect()
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

fn status_failed(status: &str) -> bool {
    matches!(
        status,
        "failed" | "rejected" | "error" | "cancelled" | "canceled"
    )
}

fn first_string(value: &Value, keys: &[&str]) -> Option<String> {
    for key in keys {
        if let Some(s) = value.get(*key).and_then(Value::as_str) {
            return Some(s.to_string());
        }
    }
    None
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
#[cfg(test)]
#[path = "history_tests.rs"]
mod history_tests;
