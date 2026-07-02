use std::collections::{HashMap, HashSet};

use serde_json::Value;

use crate::session::SessionMessage;

pub fn openai_messages_from_mobile_history(history: &[SessionMessage]) -> Vec<Value> {
    openai_messages_from_context_history(history)
}

pub(super) fn openai_messages_from_raw(messages: &[Value]) -> Vec<Value> {
    let mut out = Vec::new();
    for message in messages {
        match message.get("role").and_then(Value::as_str) {
            Some("user") => {
                if let Some(content) = message.get("content").and_then(Value::as_str)
                    && !content.is_empty()
                {
                    out.push(serde_json::json!({
                        "role": "user",
                        "content": content,
                    }));
                } else if let Some(items) = message.get("content").and_then(Value::as_array)
                    && !items.is_empty()
                {
                    out.push(serde_json::json!({
                        "role": "user",
                        "content": items,
                    }));
                }
            }
            Some("assistant") => {
                let mut mapped = serde_json::Map::new();
                mapped.insert("role".to_string(), Value::String("assistant".to_string()));

                let content = message.get("content").cloned().unwrap_or(Value::Null);
                if !content.is_null() {
                    mapped.insert("content".to_string(), content);
                }

                if let Some(tool_calls) = message.get("tool_calls").and_then(Value::as_array) {
                    let mapped_tool_calls: Vec<Value> = tool_calls
                        .iter()
                        .filter_map(|call| {
                            let id = call.get("id").and_then(Value::as_str)?;
                            let function = call.get("function")?;
                            let name = function.get("name").and_then(Value::as_str)?;
                            let arguments = function
                                .get("arguments")
                                .and_then(Value::as_str)
                                .unwrap_or("{}");
                            Some(serde_json::json!({
                                "id": id,
                                "type": "function",
                                "function": {
                                    "name": name,
                                    "arguments": arguments,
                                }
                            }))
                        })
                        .collect();
                    if !mapped_tool_calls.is_empty() {
                        mapped.insert("tool_calls".to_string(), Value::Array(mapped_tool_calls));
                        mapped.entry("content".to_string()).or_insert(Value::Null);
                    }
                }

                if mapped.contains_key("content") || mapped.contains_key("tool_calls") {
                    out.push(Value::Object(mapped));
                }
            }
            Some("tool") => {
                let Some(tool_call_id) = message.get("tool_call_id").and_then(Value::as_str) else {
                    continue;
                };
                let content = message
                    .get("content")
                    .and_then(Value::as_str)
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .unwrap_or("[tool completed with no output]");
                out.push(serde_json::json!({
                    "role": "tool",
                    "tool_call_id": tool_call_id,
                    "content": content,
                }));
            }
            _ => {}
        }
    }
    out
}

pub(super) fn openai_messages_from_history(history: &[SessionMessage]) -> Vec<Value> {
    history
        .iter()
        .filter_map(|message| match message.role.as_str() {
            "user" | "assistant" => Some(serde_json::json!({
                "role": message.role,
                "content": message.content,
            })),
            "turn_aborted" => Some(serde_json::json!({
                "role": "assistant",
                "content": message.content,
            })),
            _ => None,
        })
        .collect()
}

fn openai_messages_from_context_history(history: &[SessionMessage]) -> Vec<Value> {
    let mut out = Vec::new();
    for message in history {
        match message.role.as_str() {
            "user" | "assistant" if !message.content.trim().is_empty() => {
                out.push(serde_json::json!({
                    "role": message.role,
                    "content": message.content,
                }));
            }
            "turn_aborted" if !message.content.trim().is_empty() => {
                out.push(serde_json::json!({
                    "role": "assistant",
                    "content": message.content,
                }));
            }
            "tool_calls" => {
                out.extend(openai_messages_from_tool_trace(
                    &message.content,
                    message.interrupted,
                ));
            }
            _ => {}
        }
    }
    out
}

fn openai_messages_from_tool_trace(content: &str, interrupted: bool) -> Vec<Value> {
    let Ok(value) = serde_json::from_str::<Value>(content) else {
        return Vec::new();
    };
    let Some(calls) = value.get("calls").and_then(Value::as_array) else {
        return Vec::new();
    };

    let mut out = Vec::new();
    let mut pending_tool_calls = Vec::new();
    let mut pending_results = Vec::new();
    let mut seen_ids = HashSet::new();

    for call in calls {
        let call_id = string_field(call, "call_id")
            .or_else(|| string_field(call, "id"))
            .unwrap_or_default();
        let name = string_field(call, "name").unwrap_or_default();
        if crate::skills::is_hidden_skill_tool(&name) {
            continue;
        }
        if call_id.is_empty() || name.is_empty() || !is_context_tool_name(&name) {
            flush_tool_context_messages(&mut out, &mut pending_tool_calls, &mut pending_results);
            if let Some(observation) = text_observation_from_trace_call(call, interrupted) {
                out.push(serde_json::json!({
                    "role": "assistant",
                    "content": observation,
                }));
            }
            continue;
        }
        if !seen_ids.insert(call_id.clone()) {
            continue;
        }

        let arguments = trace_call_arguments(call);
        pending_tool_calls.push(serde_json::json!({
            "id": call_id,
            "type": "function",
            "function": {
                "name": name,
                "arguments": arguments,
            }
        }));
        pending_results.push(serde_json::json!({
            "role": "tool",
            "tool_call_id": call_id,
            "content": trace_call_result_content(call, interrupted),
        }));
    }
    flush_tool_context_messages(&mut out, &mut pending_tool_calls, &mut pending_results);
    out
}

fn flush_tool_context_messages(
    out: &mut Vec<Value>,
    pending_tool_calls: &mut Vec<Value>,
    pending_results: &mut Vec<Value>,
) {
    if pending_tool_calls.is_empty() {
        return;
    }
    out.push(serde_json::json!({
        "role": "assistant",
        "content": Value::Null,
        "tool_calls": std::mem::take(pending_tool_calls),
    }));
    out.append(pending_results);
}

fn text_observation_from_trace_call(call: &Value, interrupted: bool) -> Option<String> {
    let name = string_field(call, "name").unwrap_or_else(|| "unknown".to_string());
    if name.trim().is_empty() {
        return None;
    }
    let arguments = trace_call_arguments(call);
    let result = trace_call_result_content(call, interrupted);
    Some(compact_text_preview(
        &format!("Prior tool observation\nTool: {name}\nArguments: {arguments}\nResult: {result}"),
        4_000,
    ))
}

fn trace_call_arguments(call: &Value) -> String {
    if let Some(arguments) = call.get("arguments").and_then(Value::as_str) {
        return arguments.to_string();
    }
    call.get("arguments")
        .filter(|value| !value.is_null())
        .map(Value::to_string)
        .unwrap_or_else(|| "{}".to_string())
}

fn trace_call_result_content(call: &Value, interrupted: bool) -> String {
    let content = if let Some(result) = call.get("result").and_then(Value::as_str) {
        result.to_string()
    } else if let Some(result) = call.get("result").filter(|value| !value.is_null()) {
        result.to_string()
    } else if let Some(error) = call.get("error").and_then(Value::as_str) {
        format!("[tool error]\n{error}")
    } else if let Some(error) = call.get("error").filter(|value| !value.is_null()) {
        format!("[tool error]\n{error}")
    } else if interrupted
        || call
            .get("interrupted")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    {
        "[tool interrupted before returning a result]".to_string()
    } else {
        "[tool result missing from persisted transcript]".to_string()
    };
    compact_text_preview(&content, 24_000)
}

fn string_field(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(ToString::to_string)
}

fn is_context_tool_name(name: &str) -> bool {
    let name = name.trim();
    !name.is_empty()
        && name
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-' | '.'))
}

fn compact_text_preview(text: &str, max_chars: usize) -> String {
    let compact = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() <= max_chars {
        compact
    } else {
        let preview: String = compact.chars().take(max_chars).collect();
        format!("{preview}...")
    }
}

pub(super) fn anthropic_messages_from_history(history: &[SessionMessage]) -> Vec<Value> {
    history
        .iter()
        .filter_map(|message| match message.role.as_str() {
            "user" | "assistant" if !message.content.trim().is_empty() => Some(serde_json::json!({
                "role": message.role,
                "content": message.content,
            })),
            "turn_aborted" if !message.content.trim().is_empty() => Some(serde_json::json!({
                "role": "assistant",
                "content": message.content,
            })),
            _ => None,
        })
        .collect()
}

pub(super) fn anthropic_messages_from_raw(messages: &[Value]) -> Vec<Value> {
    let mut out = Vec::new();
    for message in messages {
        match message.get("role").and_then(Value::as_str) {
            Some("user") => {
                if let Some(content) = message.get("content").and_then(Value::as_str)
                    && !content.is_empty()
                {
                    out.push(serde_json::json!({
                        "role": "user",
                        "content": content,
                    }));
                } else if let Some(items) = message.get("content").and_then(Value::as_array) {
                    let blocks = raw_content_to_anthropic_blocks(items);
                    if !blocks.is_empty() {
                        out.push(serde_json::json!({
                            "role": "user",
                            "content": blocks,
                        }));
                    }
                }
            }
            Some("assistant") => {
                let mut blocks = Vec::new();
                if let Some(content) = message.get("content").and_then(Value::as_str)
                    && !content.is_empty()
                {
                    blocks.push(serde_json::json!({
                        "type": "text",
                        "text": content,
                    }));
                }
                if let Some(tool_calls) = message.get("tool_calls").and_then(Value::as_array) {
                    for call in tool_calls {
                        let Some(id) = call.get("id").and_then(Value::as_str) else {
                            continue;
                        };
                        let Some(function) = call.get("function") else {
                            continue;
                        };
                        let Some(name) = function.get("name").and_then(Value::as_str) else {
                            continue;
                        };
                        let input = function
                            .get("arguments")
                            .and_then(Value::as_str)
                            .and_then(|raw| serde_json::from_str::<Value>(raw).ok())
                            .unwrap_or_else(|| serde_json::json!({}));
                        blocks.push(serde_json::json!({
                            "type": "tool_use",
                            "id": id,
                            "name": name,
                            "input": input,
                        }));
                    }
                }
                if !blocks.is_empty() {
                    out.push(serde_json::json!({
                        "role": "assistant",
                        "content": blocks,
                    }));
                }
            }
            Some("tool") => {
                let Some(tool_use_id) = message.get("tool_call_id").and_then(Value::as_str) else {
                    continue;
                };
                let content = message
                    .get("content")
                    .and_then(Value::as_str)
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .unwrap_or("[tool completed with no output]");
                out.push(serde_json::json!({
                    "role": "user",
                    "content": [{
                        "type": "tool_result",
                        "tool_use_id": tool_use_id,
                        "content": content,
                    }],
                }));
            }
            _ => {}
        }
    }
    out
}

pub(super) fn gemini_contents_from_history(history: &[SessionMessage]) -> Vec<Value> {
    history
        .iter()
        .filter_map(|message| {
            let role = match message.role.as_str() {
                "user" => "user",
                "assistant" => "model",
                "turn_aborted" => "model",
                _ => return None,
            };
            Some(serde_json::json!({
                "role": role,
                "parts": [{ "text": message.content }],
            }))
        })
        .collect()
}

pub(super) fn gemini_contents_from_raw(messages: &[Value]) -> Vec<Value> {
    let mut out = Vec::new();
    let mut tool_names_by_id = HashMap::new();
    for message in messages {
        match message.get("role").and_then(Value::as_str) {
            Some("user") => {
                if let Some(content) = message.get("content").and_then(Value::as_str)
                    && !content.is_empty()
                {
                    out.push(serde_json::json!({
                        "role": "user",
                        "parts": [{ "text": content }],
                    }));
                } else if let Some(items) = message.get("content").and_then(Value::as_array) {
                    let parts = raw_content_to_gemini_parts(items);
                    if !parts.is_empty() {
                        out.push(serde_json::json!({
                            "role": "user",
                            "parts": parts,
                        }));
                    }
                }
            }
            Some("assistant") => {
                let mut parts = Vec::new();
                if let Some(content) = message.get("content").and_then(Value::as_str)
                    && !content.is_empty()
                {
                    parts.push(serde_json::json!({ "text": content }));
                }
                if let Some(tool_calls) = message.get("tool_calls").and_then(Value::as_array) {
                    for call in tool_calls {
                        let Some(id) = call.get("id").and_then(Value::as_str) else {
                            continue;
                        };
                        let Some(function) = call.get("function") else {
                            continue;
                        };
                        let Some(name) = function.get("name").and_then(Value::as_str) else {
                            continue;
                        };
                        tool_names_by_id.insert(id.to_string(), name.to_string());
                        let args = function
                            .get("arguments")
                            .and_then(Value::as_str)
                            .and_then(|raw| serde_json::from_str::<Value>(raw).ok())
                            .unwrap_or_else(|| serde_json::json!({}));
                        parts.push(serde_json::json!({
                            "functionCall": {
                                "name": name,
                                "args": args,
                            }
                        }));
                    }
                }
                if !parts.is_empty() {
                    out.push(serde_json::json!({
                        "role": "model",
                        "parts": parts,
                    }));
                }
            }
            Some("tool") => {
                let Some(tool_call_id) = message.get("tool_call_id").and_then(Value::as_str) else {
                    continue;
                };
                let name = tool_names_by_id
                    .get(tool_call_id)
                    .cloned()
                    .unwrap_or_else(|| tool_call_id.to_string());
                let content = message
                    .get("content")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                out.push(serde_json::json!({
                    "role": "user",
                    "parts": [{
                        "functionResponse": {
                            "name": name,
                            "response": {
                                "content": content,
                            }
                        }
                    }],
                }));
            }
            _ => {}
        }
    }
    out
}

fn raw_content_to_anthropic_blocks(items: &[Value]) -> Vec<Value> {
    let mut blocks = Vec::new();
    for item in items {
        match item.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(text) = item.get("text").and_then(Value::as_str)
                    && !text.is_empty()
                {
                    blocks.push(serde_json::json!({
                        "type": "text",
                        "text": text,
                    }));
                }
            }
            Some("image_url") => {
                let Some(url) = item.pointer("/image_url/url").and_then(Value::as_str) else {
                    continue;
                };
                let Some((media_type, data)) = parse_data_url(url) else {
                    continue;
                };
                blocks.push(serde_json::json!({
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": media_type,
                        "data": data,
                    },
                }));
            }
            _ => {}
        }
    }
    blocks
}

fn raw_content_to_gemini_parts(items: &[Value]) -> Vec<Value> {
    let mut parts = Vec::new();
    for item in items {
        match item.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(text) = item.get("text").and_then(Value::as_str)
                    && !text.is_empty()
                {
                    parts.push(serde_json::json!({ "text": text }));
                }
            }
            Some("image_url") => {
                let Some(url) = item.pointer("/image_url/url").and_then(Value::as_str) else {
                    continue;
                };
                let Some((mime_type, data)) = parse_data_url(url) else {
                    continue;
                };
                parts.push(serde_json::json!({
                    "inline_data": {
                        "mime_type": mime_type,
                        "data": data,
                    },
                }));
            }
            _ => {}
        }
    }
    parts
}

fn parse_data_url(url: &str) -> Option<(&str, &str)> {
    let rest = url.strip_prefix("data:")?;
    let (media_type, data) = rest.split_once(";base64,")?;
    if media_type.trim().is_empty() || data.trim().is_empty() {
        return None;
    }
    Some((media_type, data))
}
