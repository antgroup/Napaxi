use std::cell::Cell;

use anyhow::{Result, anyhow};
use reqwest::header::{CONTENT_TYPE, HeaderMap, HeaderValue};
use serde_json::Value;

use crate::session::SessionMessage;
use crate::tool_registry::ToolDescriptor;
use crate::types::PlatformLlmConfig;

use super::http::{
    extra_headers, json_client, positive_max_tokens, provider_error_message, response_json,
    stream_client,
};
use super::messages::{anthropic_messages_from_history, anthropic_messages_from_raw};
use super::sse::{
    AnthropicStreamTurnAccumulator, STREAM_RETRY_ATTEMPTS, accumulator_has_anthropic_tool_calls,
    can_retry_stream, check_cancelled, guard_sse_buffer, handle_anthropic_stream_line,
    handle_anthropic_stream_turn_line, next_stream_chunk, note_stream_retry, send_stream_request,
    sse_headers, stream_body_decode_error,
};
use super::tool_schema::anthropic_tool_schema;
use super::{LlmStreamEvent, LlmToolCall, LlmTurn};

/// Build the Anthropic `system` field as a single text block carrying a
/// `cache_control` breakpoint. Anthropic prompt caching is opt-in: a plain
/// string system prompt is never cached. Marking the block caches the entire
/// (stable-prefix-first) system prompt up to this point. The native Anthropic
/// transport always speaks the native-block layout, so the marker goes on the
/// inner content block.
fn anthropic_system_blocks(config: &PlatformLlmConfig) -> Value {
    serde_json::json!([
        {
            "type": "text",
            "text": config.system_prompt,
            "cache_control": { "type": "ephemeral" },
        }
    ])
}

/// Convert tool descriptors to Anthropic schemas and place a `cache_control`
/// breakpoint on the LAST tool. Anthropic caches the entire `tools` array up to
/// the marked tool, so a single marker on the final entry caches the whole tool
/// schema block cross-turn. Returns an empty array when there are no tools.
fn anthropic_tools_with_cache(tools: &[ToolDescriptor]) -> Vec<Value> {
    let mut schemas: Vec<Value> = tools.iter().map(anthropic_tool_schema).collect();
    if let Some(obj) = schemas.last_mut().and_then(Value::as_object_mut) {
        obj.insert(
            "cache_control".to_string(),
            serde_json::json!({ "type": "ephemeral" }),
        );
    }
    schemas
}

pub(super) async fn complete(
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> Result<String> {
    let url = messages_url(config);
    let body = serde_json::json!({
        "model": config.model,
        "max_tokens": positive_max_tokens(config.max_tokens),
        "system": anthropic_system_blocks(config),
        "messages": anthropic_messages_from_history(history),
    });

    let client = json_client();
    let response = client
        .post(url)
        .headers(headers(config)?)
        .json(&body)
        .send()
        .await?;
    let status = response.status();
    let value = response_json(response, "Anthropic").await?;
    if !status.is_success() {
        anyhow::bail!("{}", provider_error_message(&value, status.as_u16()));
    }
    value
        .get("content")
        .and_then(Value::as_array)
        .and_then(|items| {
            items
                .iter()
                .find(|item| item.get("type").and_then(Value::as_str) == Some("text"))
        })
        .and_then(|item| item.get("text"))
        .and_then(Value::as_str)
        .map(str::to_string)
        .filter(|text| !text.trim().is_empty())
        .ok_or_else(|| anyhow!("Anthropic response did not contain assistant content"))
}

pub(super) async fn complete_raw(
    config: &PlatformLlmConfig,
    messages: &[Value],
    tools: &[ToolDescriptor],
) -> Result<LlmTurn> {
    let url = messages_url(config);
    let mut body = serde_json::json!({
        "model": config.model,
        "max_tokens": positive_max_tokens(config.max_tokens),
        "system": anthropic_system_blocks(config),
        "messages": anthropic_messages_from_raw(messages),
    });
    if !tools.is_empty() {
        body["tools"] = Value::Array(anthropic_tools_with_cache(tools));
    }

    let client = json_client();
    let response = client
        .post(url)
        .headers(headers(config)?)
        .json(&body)
        .send()
        .await?;
    let status = response.status();
    let value = response_json(response, "Anthropic").await?;
    if !status.is_success() {
        anyhow::bail!("{}", provider_error_message(&value, status.as_u16()));
    }
    parse_turn(&value)
}

pub(super) async fn stream_raw_cancelable<F, C>(
    config: &PlatformLlmConfig,
    messages: &[Value],
    tools: &[ToolDescriptor],
    mut on_event: F,
    mut should_cancel: C,
) -> Result<LlmTurn>
where
    F: FnMut(LlmStreamEvent),
    C: FnMut() -> bool,
{
    let url = messages_url(config);
    let mut body = serde_json::json!({
        "model": config.model,
        "max_tokens": positive_max_tokens(config.max_tokens),
        "system": anthropic_system_blocks(config),
        "messages": anthropic_messages_from_raw(messages),
        "stream": true,
    });
    if !tools.is_empty() {
        body["tools"] = Value::Array(anthropic_tools_with_cache(tools));
    }

    let mut last_error = None;
    for attempt in 0..STREAM_RETRY_ATTEMPTS {
        if should_cancel() {
            anyhow::bail!("Chat cancelled");
        }
        let started = Cell::new(false);
        match stream_turn_once(
            config,
            &url,
            &body,
            &mut on_event,
            &started,
            &mut should_cancel,
        )
        .await
        {
            Ok(turn) => return Ok(turn),
            Err(error) if can_retry_stream(attempt, started.get(), &error) => {
                let delay = note_stream_retry(attempt, started.get(), &error, &mut on_event);
                last_error = Some(error);
                tokio::time::sleep(delay).await;
            }
            Err(error) => return Err(error),
        }
    }
    Err(last_error.unwrap_or_else(|| anyhow!("LLM stream failed before it started")))
}

pub(super) async fn stream_cancelable<F, C>(
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
    mut on_event: F,
    mut should_cancel: C,
) -> Result<String>
where
    F: FnMut(LlmStreamEvent),
    C: FnMut() -> bool,
{
    let url = messages_url(config);
    let body = serde_json::json!({
        "model": config.model,
        "max_tokens": positive_max_tokens(config.max_tokens),
        "system": anthropic_system_blocks(config),
        "messages": anthropic_messages_from_history(history),
        "stream": true,
    });

    let mut last_error = None;
    for attempt in 0..STREAM_RETRY_ATTEMPTS {
        if should_cancel() {
            anyhow::bail!("Chat cancelled");
        }
        let started = Cell::new(false);
        match stream_content_once(
            config,
            &url,
            &body,
            &mut on_event,
            &started,
            &mut should_cancel,
        )
        .await
        {
            Ok(content) => return Ok(content),
            Err(error) if can_retry_stream(attempt, started.get(), &error) => {
                let delay = note_stream_retry(attempt, started.get(), &error, &mut on_event);
                last_error = Some(error);
                tokio::time::sleep(delay).await;
            }
            Err(error) => return Err(error),
        }
    }
    Err(last_error.unwrap_or_else(|| anyhow!("LLM stream failed before it started")))
}

pub(super) fn parse_turn(value: &Value) -> Result<LlmTurn> {
    let content_items = value
        .get("content")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("Anthropic response did not contain content blocks"))?;
    let mut content = String::new();
    let mut tool_calls = Vec::new();
    for item in content_items {
        match item.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(text) = item.get("text").and_then(Value::as_str) {
                    content.push_str(text);
                }
            }
            Some("tool_use") => {
                let Some(id) = item.get("id").and_then(Value::as_str) else {
                    continue;
                };
                let Some(name) = item.get("name").and_then(Value::as_str) else {
                    continue;
                };
                let arguments = item
                    .get("input")
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!({}))
                    .to_string();
                tool_calls.push(LlmToolCall {
                    id: id.to_string(),
                    name: name.to_string(),
                    arguments,
                });
            }
            _ => {}
        }
    }
    if content.trim().is_empty() && tool_calls.is_empty() {
        anyhow::bail!("Anthropic response did not contain assistant content or tool calls");
    }
    Ok(LlmTurn {
        content,
        reasoning_content: None,
        tool_calls,
        usage: super::usage::anthropic_usage(value),
    })
}

pub(super) fn messages_url(config: &PlatformLlmConfig) -> String {
    let base = config
        .base_url
        .as_deref()
        .filter(|url| !url.trim().is_empty())
        .unwrap_or("https://api.anthropic.com")
        .trim_end_matches('/');
    if base.ends_with("/v1/messages") {
        base.to_string()
    } else {
        format!("{base}/v1/messages")
    }
}

fn headers(config: &PlatformLlmConfig) -> Result<HeaderMap> {
    let mut headers = extra_headers(config)?;
    headers.insert("x-api-key", HeaderValue::from_str(config.api_key.trim())?);
    headers.insert("anthropic-version", HeaderValue::from_static("2023-06-01"));
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    Ok(headers)
}

async fn stream_turn_once<F, C>(
    config: &PlatformLlmConfig,
    url: &str,
    body: &Value,
    on_event: &mut F,
    started: &Cell<bool>,
    should_cancel: &mut C,
) -> Result<LlmTurn>
where
    F: FnMut(LlmStreamEvent),
    C: FnMut() -> bool,
{
    let response = send_stream_request(
        stream_client()
            .post(url)
            .headers(sse_headers(headers(config)?))
            .header("Accept", "text/event-stream")
            .json(body),
    )
    .await?;
    let mut stream = response.bytes_stream();
    let mut buffer = String::new();
    let mut accumulator = AnthropicStreamTurnAccumulator::default();

    while let Some(chunk) = next_stream_chunk(&mut stream).await? {
        check_cancelled(should_cancel)?;
        let chunk = chunk.map_err(stream_body_decode_error)?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));
        guard_sse_buffer(&buffer)?;
        while let Some(newline_pos) = buffer.find('\n') {
            check_cancelled(should_cancel)?;
            let line = buffer[..newline_pos].trim().to_string();
            buffer = buffer[newline_pos + 1..].to_string();
            if handle_anthropic_stream_turn_line(&line, &mut accumulator, &mut |event| {
                started.set(true);
                on_event(event);
            })? {
                return accumulator.finish();
            }
            if accumulator_has_anthropic_tool_calls(&accumulator) {
                started.set(true);
            }
        }
    }

    if !buffer.trim().is_empty() {
        let line = buffer.trim().to_string();
        if handle_anthropic_stream_turn_line(&line, &mut accumulator, &mut |event| {
            started.set(true);
            on_event(event);
        })? {
            return accumulator.finish();
        }
    }
    if accumulator.has_stop_reason() {
        return accumulator.finish();
    }
    anyhow::bail!("Anthropic stream ended before the completion marker")
}

async fn stream_content_once<F, C>(
    config: &PlatformLlmConfig,
    url: &str,
    body: &Value,
    on_event: &mut F,
    started: &Cell<bool>,
    should_cancel: &mut C,
) -> Result<String>
where
    F: FnMut(LlmStreamEvent),
    C: FnMut() -> bool,
{
    let response = send_stream_request(
        stream_client()
            .post(url)
            .headers(sse_headers(headers(config)?))
            .header("Accept", "text/event-stream")
            .json(body),
    )
    .await?;
    let mut stream = response.bytes_stream();
    let mut buffer = String::new();
    let mut content = String::new();

    while let Some(chunk) = next_stream_chunk(&mut stream).await? {
        check_cancelled(should_cancel)?;
        let chunk = chunk.map_err(stream_body_decode_error)?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));
        guard_sse_buffer(&buffer)?;
        while let Some(newline_pos) = buffer.find('\n') {
            check_cancelled(should_cancel)?;
            let line = buffer[..newline_pos].trim().to_string();
            buffer = buffer[newline_pos + 1..].to_string();
            if handle_anthropic_stream_line(&line, &mut content, &mut |event| {
                started.set(true);
                on_event(event);
            })? {
                return Ok(content);
            }
        }
    }

    if !buffer.trim().is_empty() {
        let line = buffer.trim().to_string();
        if handle_anthropic_stream_line(&line, &mut content, &mut |event| {
            started.set(true);
            on_event(event);
        })? {
            return Ok(content);
        }
    }
    anyhow::bail!("Anthropic stream ended before the completion marker")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn descriptor(name: &str) -> ToolDescriptor {
        ToolDescriptor {
            name: name.to_string(),
            description: format!("{name} tool"),
            parameters: serde_json::json!({"type": "object", "properties": {}}),
            effect: crate::tool_registry::ToolEffect::External,
        }
    }

    #[test]
    fn system_blocks_carry_cache_control() {
        let mut config = PlatformLlmConfig::default();
        config.system_prompt = "You are helpful.".to_string();

        let blocks = anthropic_system_blocks(&config);
        let arr = blocks.as_array().expect("system should be a block array");
        assert_eq!(arr.len(), 1);
        assert_eq!(arr[0]["type"], "text");
        assert_eq!(arr[0]["text"], "You are helpful.");
        assert_eq!(arr[0]["cache_control"]["type"], "ephemeral");
    }

    #[test]
    fn only_last_tool_is_cache_marked() {
        let tools = [
            descriptor("first"),
            descriptor("second"),
            descriptor("third"),
        ];
        let schemas = anthropic_tools_with_cache(&tools);

        assert_eq!(schemas.len(), 3);
        assert!(schemas[0].get("cache_control").is_none());
        assert!(schemas[1].get("cache_control").is_none());
        assert_eq!(schemas[2]["cache_control"]["type"], "ephemeral");
        // Names are preserved in order.
        assert_eq!(schemas[0]["name"], "first");
        assert_eq!(schemas[2]["name"], "third");
    }

    #[test]
    fn empty_tools_produce_empty_array() {
        assert!(anthropic_tools_with_cache(&[]).is_empty());
    }
}
