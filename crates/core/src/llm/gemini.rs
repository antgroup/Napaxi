use std::cell::Cell;

use anyhow::{Result, anyhow};
use serde_json::Value;

use crate::session::SessionMessage;
use crate::tool_registry::ToolDescriptor;
use crate::types::PlatformLlmConfig;

use super::http::{
    extra_headers, json_client, positive_max_tokens, provider_error_message, response_json,
    stream_client,
};
use super::messages::{gemini_contents_from_history, gemini_contents_from_raw};
use super::sse::{
    GeminiStreamTurnAccumulator, STREAM_RETRY_ATTEMPTS, accumulator_has_gemini_tool_calls,
    can_retry_stream, check_cancelled, guard_sse_buffer, handle_gemini_stream_line,
    handle_gemini_stream_turn_line, next_stream_chunk, note_stream_retry, send_stream_request,
    sse_headers, stream_body_decode_error,
};
use super::tool_schema::gemini_tool_schema;
use super::{LlmStreamEvent, LlmToolCall, LlmTurn};

pub(super) async fn complete(
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> Result<String> {
    let url = generate_url(config);
    let mut body = serde_json::json!({
        "contents": gemini_contents_from_history(history),
        "generationConfig": {
            "maxOutputTokens": positive_max_tokens(config.max_tokens),
        },
    });
    if let Some(instruction) = gemini_system_instruction(config) {
        body["systemInstruction"] = instruction;
    }

    let client = json_client();
    let response = client
        .post(url)
        .headers(extra_headers(config)?)
        .json(&body)
        .send()
        .await?;
    let status = response.status();
    let value = response_json(response, "Gemini").await?;
    if !status.is_success() {
        anyhow::bail!("{}", provider_error_message(&value, status.as_u16()));
    }
    value
        .pointer("/candidates/0/content/parts/0/text")
        .and_then(Value::as_str)
        .map(str::to_string)
        .filter(|text| !text.trim().is_empty())
        .ok_or_else(|| anyhow!("Gemini response did not contain assistant content"))
}

pub(super) async fn complete_raw(
    config: &PlatformLlmConfig,
    messages: &[Value],
    tools: &[ToolDescriptor],
) -> Result<LlmTurn> {
    let url = generate_url(config);
    let mut body = serde_json::json!({
        "contents": gemini_contents_from_raw(messages),
        "generationConfig": {
            "maxOutputTokens": positive_max_tokens(config.max_tokens),
        },
    });
    if let Some(instruction) = gemini_system_instruction(config) {
        body["systemInstruction"] = instruction;
    }
    if !tools.is_empty() {
        body["tools"] = serde_json::json!([{
            "functionDeclarations": tools.iter().map(gemini_tool_schema).collect::<Vec<_>>(),
        }]);
        body["toolConfig"] = serde_json::json!({
            "functionCallingConfig": {
                "mode": "AUTO",
            },
        });
    }

    let client = json_client();
    let response = client
        .post(url)
        .headers(extra_headers(config)?)
        .json(&body)
        .send()
        .await?;
    let status = response.status();
    let value = response_json(response, "Gemini").await?;
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
    let url = stream_url(config);
    let mut body = serde_json::json!({
        "contents": gemini_contents_from_raw(messages),
        "generationConfig": {
            "maxOutputTokens": positive_max_tokens(config.max_tokens),
        },
    });
    if let Some(instruction) = gemini_system_instruction(config) {
        body["systemInstruction"] = instruction;
    }
    if !tools.is_empty() {
        body["tools"] = serde_json::json!([{
            "functionDeclarations": tools.iter().map(gemini_tool_schema).collect::<Vec<_>>(),
        }]);
        body["toolConfig"] = serde_json::json!({
            "functionCallingConfig": {
                "mode": "AUTO",
            },
        });
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
    let url = stream_url(config);
    let mut body = serde_json::json!({
        "contents": gemini_contents_from_history(history),
        "generationConfig": {
            "maxOutputTokens": positive_max_tokens(config.max_tokens),
        },
    });
    if let Some(instruction) = gemini_system_instruction(config) {
        body["systemInstruction"] = instruction;
    }

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
    let parts = value
        .pointer("/candidates/0/content/parts")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("Gemini response did not contain content parts"))?;
    let mut content = String::new();
    let mut tool_calls = Vec::new();
    for part in parts {
        if let Some(text) = part.get("text").and_then(Value::as_str)
            && part.get("thought").and_then(Value::as_bool) != Some(true)
        {
            content.push_str(text);
        }
        if let Some(call) = part.get("functionCall") {
            let Some(name) = call.get("name").and_then(Value::as_str) else {
                continue;
            };
            let arguments = call
                .get("args")
                .cloned()
                .unwrap_or_else(|| serde_json::json!({}))
                .to_string();
            tool_calls.push(LlmToolCall {
                id: name.to_string(),
                name: name.to_string(),
                arguments,
            });
        }
    }
    if content.trim().is_empty() && tool_calls.is_empty() {
        anyhow::bail!("Gemini response did not contain assistant content or tool calls");
    }
    Ok(LlmTurn {
        content,
        reasoning_content: None,
        tool_calls,
        usage: super::usage::gemini_usage(value),
    })
}

pub(super) fn generate_url(config: &PlatformLlmConfig) -> String {
    let base = config
        .base_url
        .as_deref()
        .filter(|url| !url.trim().is_empty())
        .unwrap_or("https://generativelanguage.googleapis.com/v1beta")
        .trim_end_matches('/');
    format!(
        "{base}/models/{}:generateContent?key={}",
        config.model.trim(),
        config.api_key.trim()
    )
}

pub(super) fn stream_url(config: &PlatformLlmConfig) -> String {
    let base = config
        .base_url
        .as_deref()
        .filter(|url| !url.trim().is_empty())
        .unwrap_or("https://generativelanguage.googleapis.com/v1beta")
        .trim_end_matches('/');
    format!(
        "{base}/models/{}:streamGenerateContent?alt=sse&key={}",
        config.model.trim(),
        config.api_key.trim()
    )
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
            .headers(sse_headers(extra_headers(config)?))
            .header("Accept", "text/event-stream")
            .json(body),
    )
    .await?;
    let mut stream = response.bytes_stream();
    let mut buffer = String::new();
    let mut accumulator = GeminiStreamTurnAccumulator::default();

    while let Some(chunk) = next_stream_chunk(&mut stream).await? {
        check_cancelled(should_cancel)?;
        let chunk = chunk.map_err(stream_body_decode_error)?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));
        guard_sse_buffer(&buffer)?;
        while let Some(newline_pos) = buffer.find('\n') {
            check_cancelled(should_cancel)?;
            let line = buffer[..newline_pos].trim().to_string();
            buffer = buffer[newline_pos + 1..].to_string();
            if handle_gemini_stream_turn_line(&line, &mut accumulator, &mut |event| {
                started.set(true);
                on_event(event);
            })? {
                return accumulator.finish();
            }
            if accumulator_has_gemini_tool_calls(&accumulator) {
                started.set(true);
            }
        }
    }

    if !buffer.trim().is_empty() {
        let line = buffer.trim().to_string();
        if handle_gemini_stream_turn_line(&line, &mut accumulator, &mut |event| {
            started.set(true);
            on_event(event);
        })? {
            return accumulator.finish();
        }
    }
    if accumulator.has_finish_reason() {
        return accumulator.finish();
    }
    anyhow::bail!("Gemini stream ended before the completion marker")
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
            .headers(sse_headers(extra_headers(config)?))
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
            if handle_gemini_stream_line(&line, &mut content, &mut |event| {
                started.set(true);
                on_event(event);
            })? {
                return Ok(content);
            }
        }
    }

    if !buffer.trim().is_empty() {
        let line = buffer.trim().to_string();
        if handle_gemini_stream_line(&line, &mut content, &mut |event| {
            started.set(true);
            on_event(event);
        })? {
            return Ok(content);
        }
    }
    anyhow::bail!("Gemini stream ended before the completion marker")
}

fn gemini_system_instruction(config: &PlatformLlmConfig) -> Option<Value> {
    if config.system_prompt.trim().is_empty() {
        return None;
    }
    Some(serde_json::json!({
        "role": "system",
        "parts": [{ "text": config.system_prompt }],
    }))
}

#[cfg(test)]
mod system_instruction_tests {
    use super::*;

    fn config_with_prompt(prompt: &str) -> PlatformLlmConfig {
        let mut config = PlatformLlmConfig::default();
        config.system_prompt = prompt.to_string();
        config
    }

    #[test]
    fn includes_role_field_when_prompt_present() {
        let instruction = gemini_system_instruction(&config_with_prompt("You are helpful."))
            .expect("instruction should be built for a non-empty prompt");
        assert_eq!(instruction["role"], "system");
        assert_eq!(instruction["parts"][0]["text"], "You are helpful.");
    }

    #[test]
    fn omitted_when_prompt_blank() {
        assert!(gemini_system_instruction(&config_with_prompt("   ")).is_none());
    }
}
