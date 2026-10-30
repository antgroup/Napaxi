//! Read-only session history projections: rendered UI history, paginated
//! windows, and LLM-context history queries.

use chrono::{DateTime, Utc};
use serde_json::Value;

use crate::storage;

use super::store::{empty_page, parse_time, read_record};
use super::types::SessionMessage;

const TOOL_HISTORY_PREVIEW_CHARS: usize = 1200;
const TOOL_HISTORY_ARGUMENT_PREVIEW_CHARS: usize = 2000;

/// Maximum Object/Array nesting depth allowed in a tool-result
/// `serde_json::Value` persisted to or projected from session history. Subtrees
/// deeper than this level are replaced with the marker object
/// `{"result_depth_truncated": true, "original_depth": N}` so the on-disk
/// record never carries unbounded recursion, mirroring the
/// `result_truncated` text-cap mechanism that the depth cap complements (idea
/// reference: OpenClaw #186481 `c7bd622b95`; self-implemented under
/// GPL-3.0-or-later without copying upstream source).
///
/// The cap is set two below serde_json's default parse-time recursion limit
/// (128): the marker object that replaces an over-cap subtree itself lives
/// at the cap depth, so its leaves sit at `cap + 1`. Setting the cap to 126
/// keeps the deepest possible output at 127, which still round-trips through
/// `serde_json::from_str` without the `unbounded_depth` cargo feature. Inputs
/// deeper than serde_json's parse-time limit are handled by the streaming
/// depth-truncation path in [`cap_tool_result_string`], which does not
/// materialize the full tree and so is bounded regardless of input depth.
const TOOL_RESULT_MAX_DEPTH: usize = 126;

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
    model_context_history(record.messages)
}

/// Project the durable UI transcript into model-facing history.
///
/// Reasoning is normally omitted from subsequent requests. The exception is a
/// reasoning segment that produced tool calls: thinking-capable OpenAI-wire
/// providers require that exact `reasoning_content` to be replayed on the
/// assistant tool-call message. The durable transcript stores reasoning and
/// tool calls as adjacent UI messages, so enrich the tool trace in memory
/// without duplicating private reasoning in the on-disk record or exposing a
/// standalone non-standard `reasoning` role to providers.
fn model_context_history(messages: Vec<SessionMessage>) -> Vec<SessionMessage> {
    let mut out = Vec::new();
    let mut pending_reasoning: Option<(Option<String>, String)> = None;

    for mut message in messages {
        match message.role.as_str() {
            "reasoning" if !message.content.trim().is_empty() => {
                let same_turn = pending_reasoning
                    .as_ref()
                    .is_some_and(|(turn_id, _)| turn_id == &message.turn_id);
                if same_turn {
                    if let Some((_, content)) = pending_reasoning.as_mut() {
                        content.push_str(&message.content);
                    }
                } else {
                    pending_reasoning = Some((message.turn_id.clone(), message.content));
                }
            }
            "tool_calls" if !message.content.trim().is_empty() => {
                if let Some((reasoning_turn_id, reasoning)) = pending_reasoning.take()
                    && trace_turns_match(reasoning_turn_id.as_deref(), message.turn_id.as_deref())
                {
                    message.content = tool_trace_with_reasoning(&message.content, &reasoning);
                }
                out.push(message);
            }
            "user" | "assistant" if !message.content.trim().is_empty() => {
                pending_reasoning = None;
                out.push(message);
            }
            // Interrupt boundary marker. Kept in the model-facing history so the
            // alternation gap is filled; `messages.rs` maps it to assistant role.
            // Deliberately absent from the UI projection allowlists below.
            "turn_aborted" if !message.content.trim().is_empty() => {
                pending_reasoning = None;
                out.push(message);
            }
            _ => {
                pending_reasoning = None;
            }
        }
    }
    out
}

fn trace_turns_match(reasoning_turn_id: Option<&str>, tool_turn_id: Option<&str>) -> bool {
    match (reasoning_turn_id, tool_turn_id) {
        (Some(reasoning), Some(tool)) => reasoning == tool,
        // Older transcripts predate turn ids but still persist the pair
        // adjacently. Adjacency is sufficient for their compatibility path.
        (None, None) => true,
        _ => false,
    }
}

fn tool_trace_with_reasoning(content: &str, reasoning: &str) -> String {
    let Ok(mut value) = serde_json::from_str::<Value>(content) else {
        return content.to_string();
    };
    let Some(object) = value.as_object_mut() else {
        return content.to_string();
    };
    if object
        .get("reasoning_content")
        .and_then(Value::as_str)
        .is_some_and(|text| !text.is_empty())
    {
        return content.to_string();
    }
    object.insert(
        "reasoning_content".to_string(),
        Value::String(reasoning.to_string()),
    );
    value.to_string()
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
            let content = if message.role == "tool_calls" {
                if message.interrupted {
                    project_tool_calls_interrupted(&message.content)
                } else {
                    // Apply only the depth cap to the full (non-page) view: the
                    // on-disk record may carry arbitrarily-deep tool results
                    // (e.g. adversarial or unbounded nested output) and the
                    // full-history projection must keep the persisted tree
                    // bounded. We deliberately do NOT run the preview-length
                    // compaction here — that is a page-projection concern —
                    // so the full view preserves content length while still
                    // capping nesting depth (idea reference: OpenClaw #186481).
                    project_tool_calls_depth_only(&message.content)
                }
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
    cap_calls_payload(&mut value);
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

/// Full-history projection for `tool_calls` content (idea reference:
/// OpenClaw #186481). Unlike [`project_tool_calls_for_history_page`] this only
/// applies the depth cap ([`cap_calls_payload`]) and does NOT run the
/// preview-length text compaction — the full view preserves content length
/// while still bounding nesting depth. Parse failures (malformed content)
/// fall through to the raw string so the on-disk record is never silently
/// dropped; the embedded result/arguments strings are themselves depth-capped
/// by [`cap_tool_result_string`] inside [`cap_calls_payload`], which handles
/// arbitrarily-deep inputs via its streaming path.
fn project_tool_calls_depth_only(content: &str) -> Value {
    let Ok(mut value) = serde_json::from_str::<Value>(content) else {
        return Value::String(content.to_string());
    };
    cap_calls_payload(&mut value);
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

    cap_calls_payload(&mut value);
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

/// Recursively cap the nesting depth of a [`serde_json::Value`] subtree so the
/// resulting Object/Array nesting never exceeds [`TOOL_RESULT_MAX_DEPTH`].
/// Returns `true` if at least one subtree was replaced with a marker. Subtrees
/// whose Object/Array nesting would push the depth past the cap are replaced
/// with the marker object `{"result_depth_truncated": true, "original_depth":
/// N}`, where `N` is the local depth of the replaced subtree (counted from the
/// replacement point). Leaves (`String` / `Number` / `Bool` / `Null`) never
/// trip the cap on their own — only the `Object`/`Array` wrapping them counts,
/// so flat large plaintext tool results are preserved untouched.
///
/// This complements the existing `result_truncated` text-level cap (see
/// `compact_tool_call_for_history_page`): the text-cap keeps previews bounded
/// in length, while this cap keeps the persisted tree bounded in depth.
fn cap_result_depth(value: &mut Value) -> bool {
    let mut replaced = false;
    cap_result_depth_at(value, 1, &mut replaced);
    replaced
}

fn cap_result_depth_at(value: &mut Value, depth: usize, replaced: &mut bool) {
    match value {
        Value::Object(map) => {
            if depth >= TOOL_RESULT_MAX_DEPTH {
                let original_depth = subtree_depth(value);
                *value = depth_truncation_marker(original_depth);
                *replaced = true;
                return;
            }
            for (_, child) in map.iter_mut() {
                cap_result_depth_at(child, depth + 1, replaced);
            }
        }
        Value::Array(items) => {
            if depth >= TOOL_RESULT_MAX_DEPTH {
                let original_depth = subtree_depth(value);
                *value = depth_truncation_marker(original_depth);
                *replaced = true;
                return;
            }
            for child in items.iter_mut() {
                cap_result_depth_at(child, depth + 1, replaced);
            }
        }
        _ => {}
    }
}

/// Local Object/Array nesting depth of `value`, counting only `Object` and
/// `Array` levels (`String`/`Number`/`Bool`/`Null` leaves contribute `0`).
fn subtree_depth(value: &Value) -> usize {
    match value {
        Value::Object(map) => {
            let max = map.values().map(subtree_depth).max().unwrap_or(0);
            max + 1
        }
        Value::Array(items) => {
            let max = items.iter().map(subtree_depth).max().unwrap_or(0);
            max + 1
        }
        _ => 0,
    }
}

fn depth_truncation_marker(original_depth: usize) -> Value {
    serde_json::json!({
        "result_depth_truncated": true,
        "original_depth": original_depth,
    })
}

/// Cap an embedded JSON tool-result string. If `s` parses as JSON and any
/// subtree exceeds the depth cap, returns the re-serialized (compactly
/// formatted) capped JSON; otherwise returns `s` unchanged. Non-JSON strings
/// (e.g. plain text tool outputs) are returned untouched so flat plaintext
/// results are never re-formatted.
///
/// Inputs whose Object/Array nesting exceeds serde_json's default parse-time
/// recursion limit (128) cannot be round-tripped through `serde_json::from_str`
/// — the parser rejects them before the in-memory depth cap can run. To keep
/// the cap effective for arbitrarily deep (including adversarial) inputs, the
/// fall-back path runs a streaming depth-truncation directly over the raw
/// bytes (see [`truncate_deep_json_string`]) that replaces over-cap subtrees
/// with the `result_depth_truncated` marker without ever materializing the
/// full tree. The two paths produce structurally equivalent output.
pub(crate) fn cap_tool_result_string(s: &str) -> String {
    // Fast path: parseable JSON (depth within serde_json's 128-element limit).
    // Apply the in-memory cap and re-serialize only when it actually replaced
    // a subtree, so shallow / non-JSON inputs round-trip byte-for-byte.
    if let Ok(mut value) = serde_json::from_str::<Value>(s) {
        if !cap_result_depth(&mut value) {
            return s.to_string();
        }
        return value.to_string();
    }
    // Slow path: serde_json rejected the input (e.g. recursion limit
    // exceeded on deeply-nested JSON). Run the streaming depth-truncation so
    // the persisted record is still bounded. Returns `None` when the input
    // is not valid JSON at all (or no truncation was needed), in which case we
    // leave the original string untouched.
    match truncate_deep_json_string(s) {
        Some(truncated) => truncated,
        None => s.to_string(),
    }
}

/// Streaming depth-truncation of a raw JSON document. Walks `s` byte-by-byte
/// tracking structural depth (counting only `Object`/`Array` nesting — string
/// literals and escapes never trip the cap). Whenever an opening `{` / `[`
/// would push the depth past [`TOOL_RESULT_MAX_DEPTH`], the matching close is
/// located and the whole over-cap subtree is replaced in the output with the
/// marker object `{"result_depth_truncated":true,"original_depth":N}`, where
/// `N` is the replaced subtree's local Object/Array depth (counted from the
/// replacement point). The result is valid JSON whose maximum depth never
/// exceeds the cap. Returns `Some(new_string)` if at least one subtree was
/// replaced; `None` if the input is not valid JSON or no replacement happened
/// (caller should preserve the original string in that case).
fn truncate_deep_json_string(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let cap = TOOL_RESULT_MAX_DEPTH;
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0usize;
    // Skip a leading non-JSON prefix (e.g. our own marker text wouldn't be
    // here, but be defensive): validate the document begins with an opening
    // brace/bracket so the depth tracker has a sensible anchor.
    let mut depth: i64 = 0;
    let mut in_string = false;
    let mut escape = false;
    let mut replaced = false;
    let mut valid = false;
    while i < bytes.len() {
        let b = bytes[i];
        if in_string {
            out.push(b);
            if escape {
                escape = false;
            } else if b == b'\\' {
                escape = true;
            } else if b == b'"' {
                in_string = false;
            }
            i += 1;
            continue;
        }
        match b {
            b'"' => {
                in_string = true;
                out.push(b);
                i += 1;
            }
            b'{' | b'[' => {
                // Would opening this container push the depth past the cap?
                // `depth` here is the depth of the ENCLOSING scope (0 at the
                // document root); the new container lives at `depth + 1`.
                let new_depth = depth + 1;
                if (new_depth as usize) > cap {
                    // Replace this over-cap subtree with the marker. Find the
                    // matching close by scanning the remainder with local
                    // depth tracking (strings + escapes respected), and
                    // compute the local subtree depth while we walk.
                    let subtree_end = match find_matching_close(bytes, i) {
                        Some((end, local_depth)) => {
                            let marker = depth_truncation_marker_string(local_depth);
                            out.extend_from_slice(marker.as_bytes());
                            replaced = true;
                            // Skip the entire subtree; `end` is the index
                            // just past the matching close.
                            end
                        }
                        None => {
                            // Malformed JSON: bail out and let the caller
                            // preserve the original string.
                            return None;
                        }
                    };
                    i = subtree_end;
                    // depth is unchanged: we did not enter the subtree.
                } else {
                    depth += 1;
                    out.push(b);
                    i += 1;
                }
            }
            b'}' | b']' => {
                if depth == 0 {
                    // Unbalanced; not valid JSON.
                    return None;
                }
                depth -= 1;
                out.push(b);
                i += 1;
                if depth == 0 {
                    // Top-level container closed; the document is valid JSON.
                    valid = true;
                }
            }
            _ => {
                out.push(b);
                i += 1;
            }
        }
    }
    if in_string || depth != 0 || !valid {
        // Unterminated string / unbalanced braces / never saw a top-level
        // container close → not valid JSON; leave to the caller.
        return None;
    }
    if !replaced {
        return None;
    }
    // Safety: the marker text is ASCII and the surviving bytes were copied
    // verbatim from a valid UTF-8 input, so the concatenation is still UTF-8.
    Some(String::from_utf8(out).unwrap_or_else(|_| s.to_string()))
}

/// Locate the matching close bracket for the opening `{` / `[` at
/// `bytes[start]`, returning `(end, local_depth)` where `end` is the index
/// just past the matching close and `local_depth` is the maximum Object/Array
/// nesting depth within the subtree, counted from the opening bracket
/// (the opening itself contributes depth 1). Returns `None` if the input is
/// malformed (unbalanced brackets). String literals and escape sequences are
/// respected so brackets inside strings do not affect tracking.
fn find_matching_close(bytes: &[u8], start: usize) -> Option<(usize, usize)> {
    let open = bytes[start];
    let _ = open; // opening char already validated by caller; tracked via depth.
    let mut depth: i64 = 0;
    let mut max_depth: usize = 0;
    let mut in_string = false;
    let mut escape = false;
    let mut i = start;
    while i < bytes.len() {
        let b = bytes[i];
        if in_string {
            if escape {
                escape = false;
            } else if b == b'\\' {
                escape = true;
            } else if b == b'"' {
                in_string = false;
            }
            i += 1;
            continue;
        }
        match b {
            b'"' => in_string = true,
            b'{' | b'[' => {
                depth += 1;
                if (depth as usize) > max_depth {
                    max_depth = depth as usize;
                }
            }
            b'}' | b']' => {
                depth -= 1;
                if depth == 0 {
                    return Some((i + 1, max_depth));
                }
                if depth < 0 {
                    return None;
                }
            }
            _ => {}
        }
        i += 1;
    }
    None
}

/// Serialize the depth-truncation marker to its compact JSON string form.
/// Kept in sync with [`depth_truncation_marker`] (the `Value` variant) so the
/// streaming and in-memory paths emit identical markers.
fn depth_truncation_marker_string(original_depth: usize) -> String {
    format!(r#"{{"result_depth_truncated":true,"original_depth":{original_depth}}}"#)
}

/// Cap depth of every call inside a parsed `{"calls": [...]}` tool-call
/// payload. For each call, the `result` / `error` / `arguments` fields are
/// string-capped via [`cap_tool_result_string`] (parse-or-skip), and the call
/// object itself is depth-capped defensively so any deeply nested structured
/// arguments are bounded before the record is persisted or projected.
pub(crate) fn cap_calls_payload(value: &mut Value) {
    let Some(calls) = value.get_mut("calls").and_then(Value::as_array_mut) else {
        return;
    };
    for call in calls.iter_mut() {
        cap_call_entry(call);
    }
}

fn cap_call_entry(call: &mut Value) {
    let Some(map) = call.as_object_mut() else {
        return;
    };
    for key in ["result", "error", "arguments"] {
        if let Some(field) = map.get(key)
            && let Some(text) = field.as_str()
        {
            let capped = cap_tool_result_string(text);
            if capped != text {
                map.insert(key.to_string(), Value::String(capped));
            }
        }
    }
    // Defensive depth cap on the call object itself (covers any deeply-nested
    // structured value the per-key string cap above did not reach).
    cap_result_depth(call);
}
