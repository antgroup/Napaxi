use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use futures::{Stream, StreamExt};
use reqwest::Response;
use reqwest::header::{ACCEPT_ENCODING, HeaderMap, HeaderValue};
use serde_json::Value;

use super::http::provider_error_message;
use super::{LlmStreamEvent, LlmToolCall, LlmTurn, usage};

/// Total attempts (initial try + retries) for a single streaming LLM request.
pub(super) const STREAM_RETRY_ATTEMPTS: usize = 3;
pub(super) const RESPONSE_BODY_PREVIEW_CHARS: usize = 500;
/// If no stream bytes arrive for this long the request is treated as stalled
/// and reconnected. Generous enough for slow reasoning models to emit a first
/// token, short enough that a silently dropped socket does not hang the turn.
pub(super) const STREAM_STALL_TIMEOUT: Duration = Duration::from_secs(60);
/// Hard cap on bytes buffered while waiting for a complete SSE event line. A
/// well-behaved provider flushes newline-delimited events continuously, so the
/// buffer stays small; this guards against a stream that keeps sending bytes
/// with no newline, which would otherwise grow the buffer until OOM. The stall
/// timeout cannot catch this case because bytes keep arriving.
pub(super) const MAX_SSE_BUFFER: usize = 10 * 1024 * 1024;

/// Provider HTTP failure that is worth retrying (429 rate limit, 5xx), with an
/// optional server-advised wait parsed from the `Retry-After` header. The HTTP
/// status is already embedded in `message` by `provider_error_message`.
#[derive(Debug)]
pub(super) struct RetryableHttpError {
    pub(super) message: String,
    pub(super) retry_after: Option<Duration>,
}

impl std::fmt::Display for RetryableHttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for RetryableHttpError {}

/// Await the next stream chunk, bounding the wait by [`STREAM_STALL_TIMEOUT`].
/// A timeout is surfaced as a retryable transport error so the caller can
/// reconnect instead of blocking forever on a dead socket.
pub(super) async fn next_stream_chunk<S, T>(stream: &mut S) -> Result<Option<T>>
where
    S: Stream<Item = T> + Unpin,
{
    match tokio::time::timeout(STREAM_STALL_TIMEOUT, stream.next()).await {
        Ok(item) => Ok(item),
        Err(_elapsed) => Err(anyhow!(
            "LLM stream stalled: no data received for {} seconds; reconnecting",
            STREAM_STALL_TIMEOUT.as_secs()
        )),
    }
}

#[derive(Debug, Default)]
pub(super) struct OpenAiStreamTurnAccumulator {
    content: String,
    reasoning_content: String,
    tool_calls: Vec<PartialOpenAiToolCall>,
    finish_reason: Option<String>,
    usage: Option<super::LlmUsage>,
}

#[derive(Debug, Default)]
struct PartialOpenAiToolCall {
    id: String,
    name: String,
    arguments: String,
}

impl OpenAiStreamTurnAccumulator {
    pub(super) fn has_finish_reason(&self) -> bool {
        self.finish_reason.is_some()
    }

    pub(super) fn finish(self) -> Result<LlmTurn> {
        let tool_calls: Vec<LlmToolCall> = self
            .tool_calls
            .into_iter()
            .filter(|call| !call.name.trim().is_empty())
            .enumerate()
            .map(|(index, call)| LlmToolCall {
                id: if call.id.trim().is_empty() {
                    format!("call_{index}")
                } else {
                    call.id
                },
                name: call.name,
                arguments: if call.arguments.trim().is_empty() {
                    "{}".to_string()
                } else {
                    call.arguments
                },
            })
            .collect();
        if let Some(reason) = self.finish_reason.as_deref() {
            match reason {
                // A length stop is only fatal when the model produced nothing
                // usable. If it emitted tool calls or partial content, that work
                // is durable and must be preserved rather than discarded.
                "length" if tool_calls.is_empty() && self.content.trim().is_empty() => {
                    anyhow::bail!(
                        "OpenAI-compatible stream was truncated because the model reached the output token limit"
                    );
                }
                "content_filter" => {
                    anyhow::bail!(
                        "OpenAI-compatible stream was stopped by the provider content filter"
                    );
                }
                "tool_calls" if tool_calls.is_empty() => {
                    anyhow::bail!(
                        "OpenAI-compatible stream ended for tool calls but did not include a complete tool call"
                    );
                }
                _ => {}
            }
        }
        if self.content.trim().is_empty() && tool_calls.is_empty() {
            anyhow::bail!(
                "OpenAI-compatible stream did not contain assistant content or tool calls"
            );
        }
        Ok(LlmTurn {
            content: self.content,
            reasoning_content: if self.reasoning_content.is_empty() {
                None
            } else {
                Some(self.reasoning_content)
            },
            tool_calls,
            usage: self.usage,
        })
    }
}

#[derive(Debug, Default)]
pub(super) struct AnthropicStreamTurnAccumulator {
    content: String,
    tool_calls: Vec<PartialAnthropicToolCall>,
    stop_reason: Option<String>,
    usage: Option<super::LlmUsage>,
}

#[derive(Debug, Default)]
struct PartialAnthropicToolCall {
    id: String,
    name: String,
    input_json: String,
}

impl AnthropicStreamTurnAccumulator {
    pub(super) fn has_stop_reason(&self) -> bool {
        self.stop_reason.is_some()
    }

    pub(super) fn finish(self) -> Result<LlmTurn> {
        let tool_calls: Vec<LlmToolCall> = self
            .tool_calls
            .into_iter()
            .filter(|call| !call.name.trim().is_empty())
            .enumerate()
            .map(|(index, call)| {
                let arguments = if call.input_json.trim().is_empty() {
                    serde_json::json!({}).to_string()
                } else {
                    serde_json::from_str::<Value>(&call.input_json)
                        .map(|value| value.to_string())
                        .unwrap_or(call.input_json)
                };
                LlmToolCall {
                    id: if call.id.is_empty() {
                        format!("toolu_{}", index)
                    } else {
                        call.id
                    },
                    name: call.name,
                    arguments,
                }
            })
            .collect();
        if let Some(reason) = self.stop_reason.as_deref() {
            match reason {
                // A max_tokens stop is only fatal when nothing usable was
                // produced. Preserve tool calls or partial content so durable
                // work is not discarded on a length stop.
                "max_tokens" if tool_calls.is_empty() && self.content.trim().is_empty() => {
                    anyhow::bail!(
                        "Anthropic stream was truncated because the model reached the output token limit"
                    );
                }
                "tool_use" if tool_calls.is_empty() => {
                    anyhow::bail!(
                        "Anthropic stream ended for tool use but did not include a complete tool call"
                    );
                }
                _ => {}
            }
        }
        if self.content.trim().is_empty() && tool_calls.is_empty() {
            anyhow::bail!("Anthropic response did not contain assistant content or tool calls");
        }
        Ok(LlmTurn {
            content: self.content,
            reasoning_content: None,
            tool_calls,
            usage: self.usage,
        })
    }
}

#[derive(Debug, Default)]
pub(super) struct GeminiStreamTurnAccumulator {
    content: String,
    tool_calls: Vec<LlmToolCall>,
    finish_reason: Option<String>,
    usage: Option<super::LlmUsage>,
}

impl GeminiStreamTurnAccumulator {
    pub(super) fn has_finish_reason(&self) -> bool {
        self.finish_reason.is_some()
    }

    pub(super) fn finish(self) -> Result<LlmTurn> {
        if let Some(reason) = self.finish_reason.as_deref() {
            match reason {
                // A MAX_TOKENS stop is only fatal when nothing usable was
                // produced. Preserve tool calls or partial content so durable
                // work is not discarded on a length stop.
                "MAX_TOKENS" if self.tool_calls.is_empty() && self.content.trim().is_empty() => {
                    anyhow::bail!(
                        "Gemini stream was truncated because the model reached the output token limit"
                    );
                }
                "SAFETY" | "RECITATION" | "MALFORMED_FUNCTION_CALL" | "UNEXPECTED_TOOL_CALL" => {
                    anyhow::bail!("Gemini stream stopped with finish reason: {reason}");
                }
                _ => {}
            }
        }
        if self.content.trim().is_empty() && self.tool_calls.is_empty() {
            anyhow::bail!("Gemini response did not contain assistant content or tool calls");
        }
        Ok(LlmTurn {
            content: self.content,
            reasoning_content: None,
            tool_calls: self.tool_calls,
            usage: self.usage,
        })
    }
}

/// Fail the stream if the unparsed buffer has grown past [`MAX_SSE_BUFFER`].
/// Called after each chunk is appended and before searching for a newline, so a
/// provider that never emits a line separator cannot grow the buffer without
/// bound.
pub(super) fn guard_sse_buffer(buffer: &str) -> Result<()> {
    if buffer.len() > MAX_SSE_BUFFER {
        anyhow::bail!(
            "LLM stream exceeded the maximum buffered size of {MAX_SSE_BUFFER} bytes without a complete event"
        );
    }
    Ok(())
}

pub(super) fn handle_openai_stream_turn_line<F>(
    line: &str,
    accumulator: &mut OpenAiStreamTurnAccumulator,
    on_event: &mut F,
) -> Result<bool>
where
    F: FnMut(LlmStreamEvent),
{
    if line.is_empty() || line.starts_with(':') {
        return Ok(false);
    }
    let Some(data) = line.strip_prefix("data:") else {
        return Ok(false);
    };
    let data = data.trim();
    if data == "[DONE]" {
        return Ok(true);
    }
    let value: Value = serde_json::from_str(data)?;
    if let Some(next_usage) = usage::openai_usage(&value) {
        accumulator.usage = Some(next_usage);
    }
    if let Some(choices) = value.get("choices").and_then(Value::as_array) {
        for choice in choices {
            if let Some(reason) = choice.get("finish_reason").and_then(Value::as_str) {
                accumulator.finish_reason = Some(reason.to_string());
            }
            let Some(delta) = choice.get("delta") else {
                continue;
            };
            if let Some(piece) = delta.get("content").and_then(Value::as_str)
                && !piece.is_empty()
            {
                accumulator.content.push_str(piece);
                on_event(LlmStreamEvent::ResponseDelta(piece.to_string()));
            }
            if let Some(piece) = delta.get("reasoning_content").and_then(Value::as_str)
                && !piece.is_empty()
            {
                accumulator.reasoning_content.push_str(piece);
                on_event(LlmStreamEvent::ReasoningDelta(piece.to_string()));
            }
            if let Some(tool_calls) = delta.get("tool_calls").and_then(Value::as_array) {
                for call in tool_calls {
                    let index = call.get("index").and_then(Value::as_u64).unwrap_or(0) as usize;
                    while accumulator.tool_calls.len() <= index {
                        accumulator
                            .tool_calls
                            .push(PartialOpenAiToolCall::default());
                    }
                    let slot = &mut accumulator.tool_calls[index];
                    let id_delta = call
                        .get("id")
                        .and_then(Value::as_str)
                        .filter(|id| !id.is_empty())
                        .map(str::to_string);
                    if let Some(id) = id_delta.as_deref() {
                        slot.id = id.to_string();
                    }
                    let mut name_delta = None;
                    let mut arguments_delta = String::new();
                    if let Some(function) = call.get("function") {
                        if let Some(name) = function.get("name").and_then(Value::as_str)
                            && !name.is_empty()
                        {
                            slot.name.push_str(name);
                            name_delta = Some(name.to_string());
                        }
                        if let Some(arguments) = function.get("arguments").and_then(Value::as_str)
                            && !arguments.is_empty()
                        {
                            slot.arguments.push_str(arguments);
                            arguments_delta.push_str(arguments);
                        }
                    }
                    if id_delta.is_some() || name_delta.is_some() || !arguments_delta.is_empty() {
                        on_event(LlmStreamEvent::ToolCallDelta {
                            index,
                            id: id_delta,
                            name: name_delta,
                            arguments_delta,
                        });
                    }
                }
            }
        }
    }
    Ok(false)
}

pub(super) fn handle_anthropic_stream_turn_line<F>(
    line: &str,
    accumulator: &mut AnthropicStreamTurnAccumulator,
    on_event: &mut F,
) -> Result<bool>
where
    F: FnMut(LlmStreamEvent),
{
    if line.is_empty() || line.starts_with(':') || line.starts_with("event:") {
        return Ok(false);
    }
    let Some(data) = line.strip_prefix("data:") else {
        return Ok(false);
    };
    let data = data.trim();
    if data == "[DONE]" {
        return Ok(true);
    }
    let value: Value = serde_json::from_str(data)?;
    if let Some(next_usage) = usage::anthropic_stream_usage(&value) {
        match accumulator.usage.as_mut() {
            Some(current) => current.merge_present(next_usage),
            None => accumulator.usage = Some(next_usage),
        }
    }
    match value.get("type").and_then(Value::as_str) {
        Some("content_block_start") => {
            let index = value.get("index").and_then(Value::as_u64).unwrap_or(0) as usize;
            let Some(block) = value.get("content_block") else {
                return Ok(false);
            };
            if block.get("type").and_then(Value::as_str) == Some("tool_use") {
                while accumulator.tool_calls.len() <= index {
                    accumulator
                        .tool_calls
                        .push(PartialAnthropicToolCall::default());
                }
                let slot = &mut accumulator.tool_calls[index];
                let id_delta = block
                    .get("id")
                    .and_then(Value::as_str)
                    .filter(|id| !id.is_empty())
                    .map(str::to_string);
                if let Some(id) = block.get("id").and_then(Value::as_str) {
                    slot.id.push_str(id);
                }
                let name_delta = block
                    .get("name")
                    .and_then(Value::as_str)
                    .filter(|name| !name.is_empty())
                    .map(str::to_string);
                if let Some(name) = block.get("name").and_then(Value::as_str) {
                    slot.name.push_str(name);
                }
                if id_delta.is_some() || name_delta.is_some() {
                    on_event(LlmStreamEvent::ToolCallDelta {
                        index,
                        id: id_delta,
                        name: name_delta,
                        arguments_delta: String::new(),
                    });
                }
            }
        }
        Some("content_block_delta") => {
            let Some(delta) = value.get("delta") else {
                return Ok(false);
            };
            match delta.get("type").and_then(Value::as_str) {
                Some("text_delta") => {
                    if let Some(text) = delta.get("text").and_then(Value::as_str)
                        && !text.is_empty()
                    {
                        accumulator.content.push_str(text);
                        on_event(LlmStreamEvent::ResponseDelta(text.to_string()));
                    }
                }
                Some("thinking_delta") => {
                    if let Some(text) = delta.get("thinking").and_then(Value::as_str)
                        && !text.is_empty()
                    {
                        on_event(LlmStreamEvent::ReasoningDelta(text.to_string()));
                    }
                }
                Some("input_json_delta") => {
                    let index = value.get("index").and_then(Value::as_u64).unwrap_or(0) as usize;
                    while accumulator.tool_calls.len() <= index {
                        accumulator
                            .tool_calls
                            .push(PartialAnthropicToolCall::default());
                    }
                    if let Some(partial) = delta.get("partial_json").and_then(Value::as_str) {
                        accumulator.tool_calls[index].input_json.push_str(partial);
                        if !partial.is_empty() {
                            on_event(LlmStreamEvent::ToolCallDelta {
                                index,
                                id: None,
                                name: None,
                                arguments_delta: partial.to_string(),
                            });
                        }
                    }
                }
                _ => {}
            }
        }
        Some("message_delta") => {
            if let Some(reason) = value.pointer("/delta/stop_reason").and_then(Value::as_str) {
                accumulator.stop_reason = Some(reason.to_string());
            }
        }
        Some("message_stop") => return Ok(true),
        Some("error") => {
            anyhow::bail!("{}", provider_error_message(&value, 200));
        }
        _ => {}
    }
    Ok(false)
}

pub(super) fn handle_gemini_stream_turn_line<F>(
    line: &str,
    accumulator: &mut GeminiStreamTurnAccumulator,
    on_event: &mut F,
) -> Result<bool>
where
    F: FnMut(LlmStreamEvent),
{
    if line.is_empty() || line.starts_with(':') || line.starts_with("event:") {
        return Ok(false);
    }
    let data = line.strip_prefix("data:").map(str::trim).unwrap_or(line);
    if data == "[DONE]" {
        return Ok(true);
    }
    if data.is_empty() {
        return Ok(false);
    }
    let value: Value = serde_json::from_str(data)?;
    if let Some(next_usage) = usage::gemini_usage(&value) {
        accumulator.usage = Some(next_usage);
    }
    if let Some(candidates) = value.get("candidates").and_then(Value::as_array) {
        for candidate in candidates {
            if let Some(reason) = candidate.get("finishReason").and_then(Value::as_str) {
                accumulator.finish_reason = Some(reason.to_string());
            }
            let Some(parts) = candidate
                .pointer("/content/parts")
                .and_then(Value::as_array)
            else {
                continue;
            };
            for part in parts {
                if let Some(text) = part.get("text").and_then(Value::as_str)
                    && !text.is_empty()
                {
                    if part.get("thought").and_then(Value::as_bool) == Some(true) {
                        on_event(LlmStreamEvent::ReasoningDelta(text.to_string()));
                    } else {
                        accumulator.content.push_str(text);
                        on_event(LlmStreamEvent::ResponseDelta(text.to_string()));
                    }
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
                    let index = accumulator.tool_calls.len();
                    accumulator.tool_calls.push(LlmToolCall {
                        id: name.to_string(),
                        name: name.to_string(),
                        arguments: arguments.clone(),
                    });
                    on_event(LlmStreamEvent::ToolCallDelta {
                        index,
                        id: Some(name.to_string()),
                        name: Some(name.to_string()),
                        arguments_delta: arguments,
                    });
                }
            }
        }
    }
    Ok(false)
}

pub(super) fn handle_openai_stream_line<F>(
    line: &str,
    content: &mut String,
    on_event: &mut F,
) -> Result<bool>
where
    F: FnMut(LlmStreamEvent),
{
    if line.is_empty() || line.starts_with(':') {
        return Ok(false);
    }
    let Some(data) = line.strip_prefix("data:") else {
        return Ok(false);
    };
    let data = data.trim();
    if data == "[DONE]" {
        return Ok(true);
    }
    let value: Value = serde_json::from_str(data)?;
    if let Some(choices) = value.get("choices").and_then(Value::as_array) {
        for choice in choices {
            let finish_reason = choice.get("finish_reason").and_then(Value::as_str);
            let Some(delta) = choice.get("delta") else {
                if let Some(reason) = finish_reason {
                    return openai_stream_finish_reason_result(reason);
                }
                continue;
            };
            if let Some(piece) = delta.get("content").and_then(Value::as_str)
                && !piece.is_empty()
            {
                content.push_str(piece);
                on_event(LlmStreamEvent::ResponseDelta(piece.to_string()));
            }
            if let Some(piece) = delta.get("reasoning_content").and_then(Value::as_str)
                && !piece.is_empty()
            {
                on_event(LlmStreamEvent::ReasoningDelta(piece.to_string()));
            }
            if let Some(reason) = finish_reason {
                return openai_stream_finish_reason_result(reason);
            }
        }
    }
    Ok(false)
}

fn openai_stream_finish_reason_result(reason: &str) -> Result<bool> {
    match reason {
        "length" => anyhow::bail!(
            "OpenAI-compatible stream was truncated because the model reached the output token limit"
        ),
        "content_filter" => {
            anyhow::bail!("OpenAI-compatible stream was stopped by the provider content filter")
        }
        _ => Ok(true),
    }
}

pub(super) fn handle_anthropic_stream_line<F>(
    line: &str,
    content: &mut String,
    on_event: &mut F,
) -> Result<bool>
where
    F: FnMut(LlmStreamEvent),
{
    if line.is_empty() || line.starts_with(':') || line.starts_with("event:") {
        return Ok(false);
    }
    let Some(data) = line.strip_prefix("data:") else {
        return Ok(false);
    };
    let data = data.trim();
    if data == "[DONE]" {
        return Ok(true);
    }
    let value: Value = serde_json::from_str(data)?;
    match value.get("type").and_then(Value::as_str) {
        Some("content_block_delta") => {
            let Some(delta) = value.get("delta") else {
                return Ok(false);
            };
            match delta.get("type").and_then(Value::as_str) {
                Some("text_delta") => {
                    if let Some(text) = delta.get("text").and_then(Value::as_str)
                        && !text.is_empty()
                    {
                        content.push_str(text);
                        on_event(LlmStreamEvent::ResponseDelta(text.to_string()));
                    }
                }
                Some("thinking_delta") => {
                    if let Some(text) = delta.get("thinking").and_then(Value::as_str)
                        && !text.is_empty()
                    {
                        on_event(LlmStreamEvent::ReasoningDelta(text.to_string()));
                    }
                }
                _ => {}
            }
        }
        Some("message_delta") => {
            if let Some(reason) = value.pointer("/delta/stop_reason").and_then(Value::as_str) {
                match reason {
                    "max_tokens" => anyhow::bail!(
                        "Anthropic stream was truncated because the model reached the output token limit"
                    ),
                    _ => return Ok(true),
                }
            }
        }
        Some("message_stop") => return Ok(true),
        Some("error") => {
            anyhow::bail!("{}", provider_error_message(&value, 200));
        }
        _ => {}
    }
    Ok(false)
}

pub(super) fn handle_gemini_stream_line<F>(
    line: &str,
    content: &mut String,
    on_event: &mut F,
) -> Result<bool>
where
    F: FnMut(LlmStreamEvent),
{
    if line.is_empty() || line.starts_with(':') || line.starts_with("event:") {
        return Ok(false);
    }
    let data = line.strip_prefix("data:").map(str::trim).unwrap_or(line);
    if data == "[DONE]" {
        return Ok(true);
    }
    if data.is_empty() {
        return Ok(false);
    }
    let value: Value = serde_json::from_str(data)?;
    if let Some(candidates) = value.get("candidates").and_then(Value::as_array) {
        for candidate in candidates {
            let finish_reason = candidate.get("finishReason").and_then(Value::as_str);
            let Some(parts) = candidate
                .pointer("/content/parts")
                .and_then(Value::as_array)
            else {
                if let Some(reason) = finish_reason {
                    return gemini_stream_finish_reason_result(reason);
                }
                continue;
            };
            for part in parts {
                if let Some(text) = part.get("text").and_then(Value::as_str)
                    && !text.is_empty()
                {
                    if part.get("thought").and_then(Value::as_bool) == Some(true) {
                        on_event(LlmStreamEvent::ReasoningDelta(text.to_string()));
                    } else {
                        content.push_str(text);
                        on_event(LlmStreamEvent::ResponseDelta(text.to_string()));
                    }
                }
            }
            if let Some(reason) = finish_reason {
                return gemini_stream_finish_reason_result(reason);
            }
        }
    }
    Ok(false)
}

fn gemini_stream_finish_reason_result(reason: &str) -> Result<bool> {
    match reason {
        "MAX_TOKENS" => {
            anyhow::bail!(
                "Gemini stream was truncated because the model reached the output token limit"
            )
        }
        "SAFETY" | "RECITATION" | "MALFORMED_FUNCTION_CALL" | "UNEXPECTED_TOOL_CALL" => {
            anyhow::bail!("Gemini stream stopped with finish reason: {reason}")
        }
        _ => Ok(true),
    }
}

pub(super) fn sse_headers(mut headers: HeaderMap) -> HeaderMap {
    headers.insert(ACCEPT_ENCODING, HeaderValue::from_static("identity"));
    headers
}

pub(super) async fn send_stream_request(request: reqwest::RequestBuilder) -> Result<Response> {
    let response = request.send().await.context("LLM stream request failed")?;
    let status = response.status();
    if !status.is_success() {
        return Err(provider_error_from_response(response, status.as_u16()).await);
    }
    Ok(response)
}

async fn provider_error_from_response(response: Response, status: u16) -> anyhow::Error {
    let retry_after = retry_after_from_headers(response.headers());
    let text = response.text().await.unwrap_or_default();
    let message = if let Ok(value) = serde_json::from_str::<Value>(&text) {
        provider_error_message(&value, status)
    } else {
        format!(
            "LLM provider error ({}): {}",
            status,
            response_body_preview(&text)
        )
    };
    if is_retryable_http_status(status) {
        anyhow::Error::new(RetryableHttpError {
            message,
            retry_after,
        })
    } else {
        anyhow!(message)
    }
}

/// HTTP statuses worth retrying: rate limiting and transient server errors.
fn is_retryable_http_status(status: u16) -> bool {
    status == 429 || (500..=599).contains(&status)
}

/// Parse a `Retry-After` header (delta-seconds form) into a wait duration.
fn retry_after_from_headers(headers: &HeaderMap) -> Option<Duration> {
    let value = headers.get(reqwest::header::RETRY_AFTER)?;
    let seconds: u64 = value.to_str().ok()?.trim().parse().ok()?;
    Some(Duration::from_secs(seconds.min(120)))
}

pub(super) fn check_cancelled<C>(should_cancel: &mut C) -> Result<()>
where
    C: FnMut() -> bool,
{
    if should_cancel() {
        anyhow::bail!("Chat cancelled");
    }
    Ok(())
}

/// Decide whether a failed streaming attempt should be retried.
///
/// Retries are allowed when attempts remain, the error is not a cancellation,
/// and either output had not started yet (any error) or the error is a
/// transport-level drop/stall or a retryable HTTP status (in which case a
/// mid-stream reconnect is safe — partial deltas are discarded via
/// `StreamReset` before the retried stream resumes).
pub(super) fn can_retry_stream(attempt: usize, started: bool, error: &anyhow::Error) -> bool {
    if attempt + 1 >= STREAM_RETRY_ATTEMPTS || is_cancelled_error(error) {
        return false;
    }
    if !started {
        return true;
    }
    is_retryable_transport_error(error)
}

fn is_cancelled_error(error: &anyhow::Error) -> bool {
    error.to_string() == "Chat cancelled"
}

/// True when the error is a transport-level failure (connection reset, early
/// EOF, body decode error, stall timeout) or a retryable HTTP status, i.e. one
/// where replaying the same request is likely to succeed.
pub(super) fn is_retryable_transport_error(error: &anyhow::Error) -> bool {
    if is_cancelled_error(error) {
        return false;
    }
    if error.downcast_ref::<RetryableHttpError>().is_some() {
        return true;
    }
    if let Some(reqwest_error) = error.downcast_ref::<reqwest::Error>()
        && (reqwest_error.is_timeout()
            || reqwest_error.is_connect()
            || reqwest_error.is_decode()
            || reqwest_error.is_request())
    {
        return true;
    }
    let lower = error.to_string().to_ascii_lowercase();
    const TRANSPORT_NEEDLES: &[&str] = &[
        "stalled",
        "connection reset",
        "connection closed",
        "connection aborted",
        "broken pipe",
        "unexpected eof",
        "early eof",
        "end of file",
        "could not be decoded",
        "stream request failed",
        "before it started",
        "before the completion marker",
        "timed out",
        "timeout",
        "os error 54",
        "os error 104",
    ];
    if TRANSPORT_NEEDLES
        .iter()
        .any(|needle| lower.contains(needle))
    {
        return true;
    }
    // Non-streaming provider errors arrive as plain strings like
    // "LLM provider error (429): ...". Retry rate limits and 5xx here too.
    message_reports_retryable_status(&lower)
}

/// Detect a retryable HTTP status embedded in a provider error message such as
/// "LLM provider error (503): upstream unavailable".
fn message_reports_retryable_status(lower: &str) -> bool {
    let Some(rest) = lower.split("error (").nth(1) else {
        return false;
    };
    let Some(code) = rest.split(')').next() else {
        return false;
    };
    code.trim()
        .parse::<u16>()
        .map(is_retryable_http_status)
        .unwrap_or(false)
}

/// Backoff before the next streaming retry: server-advised `Retry-After` wins;
/// otherwise exponential (250ms · 2^attempt) capped at 8s, plus jitter.
pub(super) fn stream_retry_delay_for(attempt: usize, error: Option<&anyhow::Error>) -> Duration {
    if let Some(retry_after) = error
        .and_then(|error| error.downcast_ref::<RetryableHttpError>())
        .and_then(|http| http.retry_after)
    {
        return retry_after;
    }
    let base = 250u64.saturating_mul(1u64 << attempt.min(5));
    let base = base.min(8_000);
    let jitter = rand::random::<u64>() % (base / 4 + 1);
    Duration::from_millis(base + jitter)
}

/// Bookkeeping for a streaming retry: when output had already started, tell the
/// consumer to discard the aborted attempt's partial deltas via `StreamReset`,
/// then return the backoff delay. Call only after `can_retry_stream` is true.
pub(super) fn note_stream_retry<F>(
    attempt: usize,
    started: bool,
    error: &anyhow::Error,
    on_event: &mut F,
) -> Duration
where
    F: FnMut(LlmStreamEvent),
{
    if started {
        on_event(LlmStreamEvent::StreamReset {
            reason: error.to_string(),
        });
    }
    stream_retry_delay_for(attempt, Some(error))
}

pub(super) fn accumulator_has_openai_tool_calls(accumulator: &OpenAiStreamTurnAccumulator) -> bool {
    accumulator.tool_calls.iter().any(|call| {
        !call.id.trim().is_empty()
            || !call.name.trim().is_empty()
            || !call.arguments.trim().is_empty()
    })
}

pub(super) fn accumulator_has_anthropic_tool_calls(
    accumulator: &AnthropicStreamTurnAccumulator,
) -> bool {
    accumulator.tool_calls.iter().any(|call| {
        !call.id.trim().is_empty()
            || !call.name.trim().is_empty()
            || !call.input_json.trim().is_empty()
    })
}

pub(super) fn accumulator_has_gemini_tool_calls(accumulator: &GeminiStreamTurnAccumulator) -> bool {
    !accumulator.tool_calls.is_empty()
}

pub(super) fn response_body_preview(text: &str) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return "<empty body>".to_string();
    }
    let mut preview: String = trimmed.chars().take(RESPONSE_BODY_PREVIEW_CHARS).collect();
    if trimmed.chars().count() > RESPONSE_BODY_PREVIEW_CHARS {
        preview.push_str("...");
    }
    preview
}

pub(super) fn stream_body_decode_error(error: reqwest::Error) -> anyhow::Error {
    if error.is_decode() {
        anyhow!(
            "LLM stream response body could not be decoded. The provider or a proxy may have compressed or truncated the event stream; retrying usually helps. Details: {error}"
        )
    } else {
        error.into()
    }
}

#[cfg(test)]
mod tests;
