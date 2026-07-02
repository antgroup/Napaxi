use std::cell::Cell;

use anyhow::{Result, anyhow};
use serde_json::Value;

use crate::session::SessionMessage;
use crate::tool_registry::ToolDescriptor;
use crate::types::PlatformLlmConfig;

use super::http::{
    chat_completions_url, json_client, openai_headers, positive_max_tokens, provider_error_message,
    response_json, stream_client, uses_max_completion_tokens,
};

fn max_tokens_body(model: &str, max_tokens: i32) -> (&'static str, Value) {
    let value = Value::from(positive_max_tokens(max_tokens));
    if uses_max_completion_tokens(model) {
        ("max_completion_tokens", value)
    } else {
        ("max_tokens", value)
    }
}
use super::messages::{openai_messages_from_history, openai_messages_from_raw};
use super::output_cap::parse_available_output_tokens;
use super::sse::{
    OpenAiStreamTurnAccumulator, STREAM_RETRY_ATTEMPTS, accumulator_has_openai_tool_calls,
    can_retry_stream, check_cancelled, guard_sse_buffer, handle_openai_stream_line,
    handle_openai_stream_turn_line, next_stream_chunk, note_stream_retry, send_stream_request,
    sse_headers, stream_body_decode_error,
};
use super::tool_schema::openai_tool_schema;
use super::{LlmStreamEvent, LlmToolCall, LlmTurn};

use super::cache_policy::{CacheLayout, prompt_cache_policy};
use crate::capabilities::LlmProviderRoute;

/// Build the `content` value for the injected system message.
///
/// By default this is the plain prompt string. When the centralized cache
/// policy says this OpenAI-wire request should be cached with the envelope
/// layout, the content is normalized to a single text part carrying an
/// Anthropic-style `cache_control` marker — the form upstreams like OpenRouter
/// (and, once verified, GLM/Zhipu via antchat) honor for prefix caching.
fn openai_system_content(config: &PlatformLlmConfig) -> Value {
    let policy = prompt_cache_policy(LlmProviderRoute::OpenAiCompatible, config);
    if policy.should_cache && policy.layout == CacheLayout::Envelope {
        serde_json::json!([
            {
                "type": "text",
                "text": config.system_prompt,
                "cache_control": { "type": "ephemeral" },
            }
        ])
    } else {
        Value::String(config.system_prompt.clone())
    }
}

pub(super) async fn complete(
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> Result<String> {
    let url = chat_completions_url(config);
    let mut messages = openai_messages_from_history(history);
    if !config.system_prompt.trim().is_empty() {
        messages.insert(
            0,
            serde_json::json!({
                "role": "system",
                "content": openai_system_content(config),
            }),
        );
    }

    let mut body = serde_json::json!({
        "model": config.model,
        "messages": messages,
    });
    {
        let (tok_key, tok_val) = max_tokens_body(&config.model, config.max_tokens);
        body[tok_key] = tok_val;
    }

    let client = json_client();
    let response = client
        .post(&url)
        .headers(openai_headers(config)?)
        .json(&body)
        .send()
        .await?;
    let status = response.status();
    let value = response_json(response, "OpenAI-compatible").await?;
    if !status.is_success() {
        let error_msg = provider_error_message(&value, status.as_u16());
        if status.as_u16() == 400
            && let Some(available) = parse_available_output_tokens(&error_msg)
        {
            let (tok_key, _) = max_tokens_body(&config.model, config.max_tokens);
            body[tok_key] = Value::from(available);
            let retry_response = client
                .post(&url)
                .headers(openai_headers(config)?)
                .json(&body)
                .send()
                .await?;
            let retry_status = retry_response.status();
            let retry_value = response_json(retry_response, "OpenAI-compatible").await?;
            if !retry_status.is_success() {
                anyhow::bail!(
                    "{}",
                    provider_error_message(&retry_value, retry_status.as_u16())
                );
            }
            return retry_value
                .pointer("/choices/0/message/content")
                .and_then(Value::as_str)
                .map(str::to_string)
                .filter(|text| !text.trim().is_empty())
                .ok_or_else(|| {
                    anyhow!("OpenAI-compatible response did not contain assistant content")
                });
        }
        anyhow::bail!("{}", error_msg);
    }
    value
        .pointer("/choices/0/message/content")
        .and_then(Value::as_str)
        .map(str::to_string)
        .filter(|text| !text.trim().is_empty())
        .ok_or_else(|| anyhow!("OpenAI-compatible response did not contain assistant content"))
}

pub(super) async fn complete_raw(
    config: &PlatformLlmConfig,
    messages: &[Value],
    tools: &[ToolDescriptor],
) -> Result<LlmTurn> {
    let url = chat_completions_url(config);
    let mut messages = openai_messages_from_raw(messages);
    if !config.system_prompt.trim().is_empty() {
        messages.insert(
            0,
            serde_json::json!({
                "role": "system",
                "content": openai_system_content(config),
            }),
        );
    }

    let mut body = serde_json::json!({
        "model": config.model,
        "messages": messages,
    });
    {
        let (tok_key, tok_val) = max_tokens_body(&config.model, config.max_tokens);
        body[tok_key] = tok_val;
    }
    if !tools.is_empty() {
        body["tools"] = Value::Array(tools.iter().map(openai_tool_schema).collect());
        body["tool_choice"] = Value::String("auto".to_string());
    }

    let client = json_client();
    let response = client
        .post(&url)
        .headers(openai_headers(config)?)
        .json(&body)
        .send()
        .await?;
    let status = response.status();
    let value = response_json(response, "OpenAI-compatible").await?;
    if !status.is_success() {
        let error_msg = provider_error_message(&value, status.as_u16());
        if status.as_u16() == 400
            && let Some(available) = parse_available_output_tokens(&error_msg)
        {
            let (tok_key, _) = max_tokens_body(&config.model, config.max_tokens);
            body[tok_key] = Value::from(available);
            let retry_response = client
                .post(&url)
                .headers(openai_headers(config)?)
                .json(&body)
                .send()
                .await?;
            let retry_status = retry_response.status();
            let retry_value = response_json(retry_response, "OpenAI-compatible").await?;
            if !retry_status.is_success() {
                anyhow::bail!(
                    "{}",
                    provider_error_message(&retry_value, retry_status.as_u16())
                );
            }
            return parse_turn(&retry_value);
        }
        anyhow::bail!("{}", error_msg);
    }
    parse_turn(&value)
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
    let url = chat_completions_url(config);
    let mut messages = openai_messages_from_history(history);
    if !config.system_prompt.trim().is_empty() {
        messages.insert(
            0,
            serde_json::json!({
                "role": "system",
                "content": openai_system_content(config),
            }),
        );
    }

    let mut body = serde_json::json!({
        "model": config.model,
        "messages": messages,
        "stream": true,
        "stream_options": {
            "include_usage": true,
        },
    });
    {
        let (tok_key, tok_val) = max_tokens_body(&config.model, config.max_tokens);
        body[tok_key] = tok_val;
    }
    let body_without_usage = request_body_without_stream_usage(&body);
    let mut use_usage_stream_options = true;

    let mut last_error = None;
    for attempt in 0..STREAM_RETRY_ATTEMPTS {
        if should_cancel() {
            anyhow::bail!("Chat cancelled");
        }
        let started = Cell::new(false);
        let request_body = if use_usage_stream_options {
            &body
        } else {
            &body_without_usage
        };
        match stream_content_once(
            config,
            &url,
            request_body,
            &mut on_event,
            &started,
            &mut should_cancel,
        )
        .await
        {
            Ok(content) => return Ok(content),
            Err(error)
                if can_retry_stream(attempt, started.get(), &error)
                    && use_usage_stream_options
                    && should_retry_without_stream_usage(&error) =>
            {
                use_usage_stream_options = false;
                let delay = note_stream_retry(attempt, started.get(), &error, &mut on_event);
                last_error = Some(error);
                tokio::time::sleep(delay).await;
            }
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
    let url = chat_completions_url(config);
    let mut messages = openai_messages_from_raw(messages);
    if !config.system_prompt.trim().is_empty() {
        messages.insert(
            0,
            serde_json::json!({
                "role": "system",
                "content": openai_system_content(config),
            }),
        );
    }

    let mut body = serde_json::json!({
        "model": config.model,
        "messages": messages,
        "stream": true,
        "stream_options": {
            "include_usage": true,
        },
    });
    {
        let (tok_key, tok_val) = max_tokens_body(&config.model, config.max_tokens);
        body[tok_key] = tok_val;
    }
    if !tools.is_empty() {
        body["tools"] = Value::Array(tools.iter().map(openai_tool_schema).collect());
        body["tool_choice"] = Value::String("auto".to_string());
    }
    let body_without_usage = request_body_without_stream_usage(&body);
    let mut use_usage_stream_options = true;

    let mut last_error = None;
    for attempt in 0..STREAM_RETRY_ATTEMPTS {
        if should_cancel() {
            anyhow::bail!("Chat cancelled");
        }
        let started = Cell::new(false);
        let request_body = if use_usage_stream_options {
            &body
        } else {
            &body_without_usage
        };
        match stream_turn_once(
            config,
            &url,
            request_body,
            &mut on_event,
            &started,
            &mut should_cancel,
        )
        .await
        {
            Ok(turn) => return Ok(turn),
            Err(error)
                if can_retry_stream(attempt, started.get(), &error)
                    && use_usage_stream_options
                    && should_retry_without_stream_usage(&error) =>
            {
                use_usage_stream_options = false;
                let delay = note_stream_retry(attempt, started.get(), &error, &mut on_event);
                last_error = Some(error);
                tokio::time::sleep(delay).await;
            }
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
    let message = value
        .pointer("/choices/0/message")
        .ok_or_else(|| anyhow!("OpenAI-compatible response did not contain a message"))?;
    let content = message
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let reasoning_content = message
        .get("reasoning_content")
        .and_then(Value::as_str)
        .filter(|text| !text.is_empty())
        .map(str::to_string);
    let tool_calls: Vec<LlmToolCall> = message
        .get("tool_calls")
        .and_then(Value::as_array)
        .map(|calls| {
            calls
                .iter()
                .filter_map(|call| {
                    let id = call.get("id").and_then(Value::as_str)?;
                    let function = call.get("function")?;
                    let name = function.get("name").and_then(Value::as_str)?;
                    let arguments = function
                        .get("arguments")
                        .and_then(Value::as_str)
                        .unwrap_or("{}");
                    Some(LlmToolCall {
                        id: id.to_string(),
                        name: name.to_string(),
                        arguments: arguments.to_string(),
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    if content.trim().is_empty() && tool_calls.is_empty() {
        anyhow::bail!("OpenAI-compatible response did not contain assistant content or tool calls");
    }

    Ok(LlmTurn {
        content,
        reasoning_content,
        tool_calls,
        usage: super::usage::openai_usage(value),
    })
}

fn request_body_without_stream_usage(body: &Value) -> Value {
    let mut fallback = body.clone();
    if let Some(object) = fallback.as_object_mut() {
        object.remove("stream_options");
    }
    fallback
}

fn should_retry_without_stream_usage(error: &anyhow::Error) -> bool {
    let message = error.to_string().to_ascii_lowercase();
    message.contains("stream_options") || message.contains("include_usage")
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
            .headers(sse_headers(openai_headers(config)?))
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
            if handle_openai_stream_line(&line, &mut content, &mut |event| {
                started.set(true);
                on_event(event);
            })? {
                return Ok(content);
            }
        }
    }

    if !buffer.trim().is_empty() {
        check_cancelled(should_cancel)?;
        let line = buffer.trim().to_string();
        if handle_openai_stream_line(&line, &mut content, &mut |event| {
            started.set(true);
            on_event(event);
        })? {
            return Ok(content);
        }
    }
    anyhow::bail!("OpenAI-compatible stream ended before the completion marker")
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
            .headers(sse_headers(openai_headers(config)?))
            .header("Accept", "text/event-stream")
            .json(body),
    )
    .await?;
    let mut stream = response.bytes_stream();
    let mut buffer = String::new();
    let mut accumulator = OpenAiStreamTurnAccumulator::default();

    while let Some(chunk) = next_stream_chunk(&mut stream).await? {
        check_cancelled(should_cancel)?;
        let chunk = chunk.map_err(stream_body_decode_error)?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));
        guard_sse_buffer(&buffer)?;
        while let Some(newline_pos) = buffer.find('\n') {
            check_cancelled(should_cancel)?;
            let line = buffer[..newline_pos].trim().to_string();
            buffer = buffer[newline_pos + 1..].to_string();
            if handle_openai_stream_turn_line(&line, &mut accumulator, &mut |event| {
                started.set(true);
                on_event(event);
            })? {
                return accumulator.finish();
            }
            if accumulator_has_openai_tool_calls(&accumulator) {
                started.set(true);
            }
        }
    }

    if !buffer.trim().is_empty() {
        let line = buffer.trim().to_string();
        if handle_openai_stream_turn_line(&line, &mut accumulator, &mut |event| {
            started.set(true);
            on_event(event);
        })? {
            return accumulator.finish();
        }
    }
    if accumulator.has_finish_reason() {
        return accumulator.finish();
    }
    anyhow::bail!("OpenAI-compatible stream ended before the completion marker")
}

#[cfg(test)]
mod tests {
    use anyhow::anyhow;

    use super::*;

    fn config_for(provider: &str, model: &str) -> PlatformLlmConfig {
        let mut config = PlatformLlmConfig::default();
        config.provider = provider.to_string();
        config.model = model.to_string();
        config.system_prompt = "You are helpful.".to_string();
        config
    }

    #[test]
    fn plain_openai_provider_keeps_string_system_content() {
        // Unrecognized OpenAI-wire provider/model: no cache marker, plain
        // string content preserved (back-compat, no risk of upstream 400).
        let content = openai_system_content(&config_for("openai", "gpt-4o"));
        assert_eq!(content, Value::String("You are helpful.".to_string()));
    }

    #[test]
    fn claude_over_openai_wire_gets_envelope_cache_marker() {
        // Claude model fronted over OpenAI wire (OpenRouter-style) → envelope
        // layout: list-of-parts with cache_control on the text part.
        let content = openai_system_content(&config_for("openrouter", "claude-3-5-sonnet"));
        let parts = content
            .as_array()
            .expect("content should be a list of parts");
        assert_eq!(parts.len(), 1);
        assert_eq!(parts[0]["type"], "text");
        assert_eq!(parts[0]["text"], "You are helpful.");
        assert_eq!(parts[0]["cache_control"]["type"], "ephemeral");
    }

    #[test]
    fn glm_over_openai_wire_relies_on_automatic_caching() {
        // antchat /v1 auto-caches the prefix (verified), so no cache_control
        // is injected — the content stays a plain string.
        let content = openai_system_content(&config_for("glm", "GLM-4.7"));
        assert_eq!(content, Value::String("You are helpful.".to_string()));
    }

    #[test]
    fn stream_usage_fallback_removes_only_stream_options() {
        let body = serde_json::json!({
            "model": "gpt-test",
            "stream": true,
            "messages": [],
            "tools": [{"type": "function"}],
            "stream_options": {"include_usage": true},
        });

        let fallback = request_body_without_stream_usage(&body);

        assert!(fallback.get("stream_options").is_none());
        assert_eq!(fallback.get("tools"), body.get("tools"));
        assert_eq!(fallback.get("messages"), body.get("messages"));
    }

    #[test]
    fn stream_usage_fallback_detects_provider_rejection() {
        assert!(should_retry_without_stream_usage(&anyhow!(
            "LLM provider error (400): unknown field stream_options"
        )));
        assert!(should_retry_without_stream_usage(&anyhow!(
            "include_usage is not supported"
        )));
        assert!(!should_retry_without_stream_usage(&anyhow!(
            "LLM stream request failed"
        )));
    }
}
