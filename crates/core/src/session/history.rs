//! Read-only session history projections: rendered UI history, paginated
//! windows, and LLM-context history queries.

use chrono::{DateTime, Utc};
use serde_json::Value;

use crate::storage;

use super::store::{empty_page, parse_time, read_record};
use super::types::SessionMessage;

const TOOL_HISTORY_PREVIEW_CHARS: usize = 1200;
const TOOL_HISTORY_ARGUMENT_PREVIEW_CHARS: usize = 2000;

pub fn get_history(files_dir: &str, thread_id: &str) -> String {
    let Some(record) = read_record(files_dir, thread_id) else {
        return "[]".to_string();
    };
    let mut items = history_items(&record.messages);
    storage::merge_attachments_into_history(files_dir, thread_id, &mut items);
    trim_incomplete_tail(&mut items);
    serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string())
}

pub fn get_history_handle(handle: i64, thread_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    get_history(&files_dir, thread_id)
}

pub fn llm_history(files_dir: &str, thread_id: &str, max_messages: usize) -> Vec<SessionMessage> {
    let Some(record) = read_record(files_dir, thread_id) else {
        return Vec::new();
    };
    let mut messages: Vec<SessionMessage> = record
        .messages
        .into_iter()
        .filter(|message| {
            matches!(message.role.as_str(), "user" | "assistant")
                && !message.content.trim().is_empty()
        })
        .collect();
    let start = messages.len().saturating_sub(max_messages);
    messages.drain(..start);
    messages
}

#[allow(dead_code)] // Kept for call sites that need the legacy user/assistant-only view.
pub(crate) fn llm_history_all(files_dir: &str, thread_id: &str) -> Vec<SessionMessage> {
    llm_history(files_dir, thread_id, usize::MAX)
}

pub(crate) fn llm_context_history_all(files_dir: &str, thread_id: &str) -> Vec<SessionMessage> {
    let Some(record) = read_record(files_dir, thread_id) else {
        return Vec::new();
    };
    record
        .messages
        .into_iter()
        .filter(|message| match message.role.as_str() {
            "user" | "assistant" => !message.content.trim().is_empty(),
            "tool_calls" => !message.content.trim().is_empty(),
            // Interrupt boundary marker. Kept in the model-facing history so the
            // alternation gap is filled; `messages.rs` maps it to assistant role.
            // Deliberately absent from the UI projection allowlists below.
            "turn_aborted" => !message.content.trim().is_empty(),
            _ => false,
        })
        .collect()
}

pub fn get_history_page(
    files_dir: &str,
    thread_id: &str,
    before: Option<&str>,
    limit: i64,
) -> String {
    let Some(record) = read_record(files_dir, thread_id) else {
        return empty_page();
    };

    let before_ts = before
        .and_then(|raw| DateTime::parse_from_rfc3339(raw).ok())
        .map(|dt| dt.with_timezone(&Utc));
    let bounded_limit = limit.clamp(1, 200) as usize;

    let mut eligible: Vec<&SessionMessage> = record
        .messages
        .iter()
        .filter(|message| {
            if let Some(cursor) = before_ts {
                return parse_time(&message.created_at).is_some_and(|ts| ts < cursor);
            }
            true
        })
        .collect();

    eligible.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    let has_more = eligible.len() > bounded_limit;
    let start = eligible.len().saturating_sub(bounded_limit);
    let page_messages = &eligible[start..];

    let mut items = history_page_items_from_refs(page_messages);
    storage::merge_attachments_into_history(files_dir, thread_id, &mut items);
    if before_ts.is_none() {
        trim_incomplete_tail(&mut items);
    }
    let next_before = if has_more {
        items
            .first()
            .and_then(|item| item.get("created_at"))
            .and_then(Value::as_str)
            .map(str::to_string)
    } else {
        None
    };

    serde_json::json!({
        "messages": items,
        "has_more": has_more,
        "next_before": next_before,
    })
    .to_string()
}

pub fn get_history_page_handle(
    handle: i64,
    thread_id: &str,
    before: Option<&str>,
    limit: i64,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return empty_page();
    };
    get_history_page(&files_dir, thread_id, before, limit)
}

fn history_items(messages: &[SessionMessage]) -> Vec<Value> {
    let refs: Vec<&SessionMessage> = messages.iter().collect();
    history_items_from_refs(&refs)
}

fn history_items_from_refs(messages: &[&SessionMessage]) -> Vec<Value> {
    messages
        .iter()
        .filter(|message| {
            matches!(
                message.role.as_str(),
                "user" | "assistant" | "tool_calls" | "thinking" | "reasoning" | "asking_human"
            )
        })
        .map(|message| {
            let content = if message.interrupted && message.role == "tool_calls" {
                project_tool_calls_interrupted(&message.content)
            } else {
                Value::String(message.content.clone())
            };
            let mut item = serde_json::json!({
                "id": message.id,
                "role": message.role,
                "created_at": message.created_at,
            });
            item["content"] = content;
            if message.interrupted {
                item["interrupted"] = serde_json::Value::Bool(true);
            }
            item
        })
        .collect()
}

fn history_page_items_from_refs(messages: &[&SessionMessage]) -> Vec<Value> {
    messages
        .iter()
        .filter(|message| {
            matches!(
                message.role.as_str(),
                "user" | "assistant" | "tool_calls" | "thinking" | "reasoning" | "asking_human"
            )
        })
        .map(|message| {
            let content = if message.role == "tool_calls" {
                project_tool_calls_for_history_page(&message.content, message.interrupted)
            } else {
                Value::String(message.content.clone())
            };
            let mut item = serde_json::json!({
                "id": message.id,
                "role": message.role,
                "created_at": message.created_at,
            });
            item["content"] = content;
            if message.interrupted {
                item["interrupted"] = serde_json::Value::Bool(true);
            }
            item
        })
        .collect()
}

/// Stamp each call inside a `tool_calls` JSON payload with `interrupted: true`
/// when the wrapping message is interrupted but the call has no terminal
/// result/error. Lets the SDK render per-call interrupted state without
/// having to plumb message-level interrupted into every consumer.
fn project_tool_calls_interrupted(content: &str) -> Value {
    let Ok(mut value) = serde_json::from_str::<Value>(content) else {
        return Value::String(content.to_string());
    };
    if let Some(calls) = value.get_mut("calls").and_then(Value::as_array_mut) {
        for call in calls {
            let Some(map) = call.as_object_mut() else {
                continue;
            };
            let already_finished = map.contains_key("result") || map.contains_key("error");
            if !already_finished {
                map.insert("interrupted".to_string(), Value::Bool(true));
            }
        }
    }
    Value::String(value.to_string())
}

fn project_tool_calls_for_history_page(content: &str, interrupted: bool) -> Value {
    let Ok(mut value) = serde_json::from_str::<Value>(content) else {
        let (preview, truncated, original_chars) =
            preview_text(content, TOOL_HISTORY_PREVIEW_CHARS);
        return Value::String(if truncated {
            serde_json::json!({
                "calls": [{
                    "name": "tool_calls",
                    "call_id": "",
                    "result": preview,
                    "result_truncated": true,
                    "result_chars": original_chars,
                }]
            })
            .to_string()
        } else {
            content.to_string()
        });
    };

    if let Some(calls) = value.get_mut("calls").and_then(Value::as_array_mut) {
        for call in calls {
            compact_tool_call_for_history_page(call, interrupted);
        }
    }
    Value::String(value.to_string())
}

fn compact_tool_call_for_history_page(call: &mut Value, interrupted: bool) {
    let Some(map) = call.as_object_mut() else {
        return;
    };

    for key in ["arguments", "parameters"] {
        if let Some(value) = map.get(key)
            && let Some((preview, original_chars)) =
                compact_value_preview(value, TOOL_HISTORY_ARGUMENT_PREVIEW_CHARS)
        {
            map.insert(key.to_string(), Value::String(preview));
            map.insert(format!("{key}_truncated"), Value::Bool(true));
            map.insert(format!("{key}_chars"), serde_json::json!(original_chars));
        }
    }

    for key in ["result", "error"] {
        if let Some(value) = map.get(key)
            && let Some((preview, original_chars)) =
                compact_value_preview(value, TOOL_HISTORY_PREVIEW_CHARS)
        {
            map.insert(key.to_string(), Value::String(preview));
            map.insert(format!("{key}_truncated"), Value::Bool(true));
            map.insert(format!("{key}_chars"), serde_json::json!(original_chars));
        }
    }

    if interrupted {
        let already_finished = map.contains_key("result") || map.contains_key("error");
        if !already_finished {
            map.insert("interrupted".to_string(), Value::Bool(true));
        }
    }
}

fn compact_value_preview(value: &Value, max_chars: usize) -> Option<(String, usize)> {
    let text = match value {
        Value::String(text) => text.as_str().to_string(),
        other => other.to_string(),
    };
    let (preview, truncated, original_chars) = preview_text(&text, max_chars);
    truncated.then_some((preview, original_chars))
}

fn preview_text(text: &str, max_chars: usize) -> (String, bool, usize) {
    let mut preview = String::new();
    let mut original_chars = 0;
    let mut truncated = false;
    for (index, ch) in text.chars().enumerate() {
        original_chars = index + 1;
        if index >= max_chars {
            truncated = true;
            continue;
        }
        preview.push(ch);
    }
    if truncated {
        (
            format!("{preview}\n\n[truncated: {original_chars} chars]"),
            true,
            original_chars,
        )
    } else {
        (preview, false, original_chars)
    }
}

fn trim_incomplete_tail(items: &mut Vec<Value>) {
    while should_trim_history_tail(items) {
        items.pop();
    }
}

fn should_trim_history_tail(items: &[Value]) -> bool {
    let Some(last) = items.last() else {
        return false;
    };
    if last
        .get("interrupted")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return false;
    }
    let role = last.get("role").and_then(Value::as_str).unwrap_or("");
    match role {
        "assistant" | "asking_human" => false,
        "user" => false,
        "tool_calls" | "thinking" | "reasoning" => true,
        _ => false,
    }
}
