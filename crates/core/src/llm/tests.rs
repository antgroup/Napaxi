use super::*;
use anyhow::anyhow;
use reqwest::header::{ACCEPT_ENCODING, HeaderMap, HeaderValue};

use super::anthropic::{
    messages_url as anthropic_messages_url, parse_turn as parse_anthropic_turn,
};
use super::gemini::{
    generate_url as gemini_generate_url, parse_turn as parse_gemini_turn,
    stream_url as gemini_stream_url,
};
use super::http::{chat_completions_url, extra_headers};
use super::messages::{
    anthropic_messages_from_history, anthropic_messages_from_raw, gemini_contents_from_history,
    gemini_contents_from_raw, openai_messages_from_history,
};
use super::openai_compatible::parse_turn as parse_openai_turn;
use super::sse::{
    AnthropicStreamTurnAccumulator, GeminiStreamTurnAccumulator, OpenAiStreamTurnAccumulator,
    RESPONSE_BODY_PREVIEW_CHARS, STREAM_RETRY_ATTEMPTS, can_retry_stream,
    handle_anthropic_stream_line, handle_anthropic_stream_turn_line, handle_gemini_stream_line,
    handle_gemini_stream_turn_line, handle_openai_stream_line, handle_openai_stream_turn_line,
    is_retryable_transport_error, response_body_preview, sse_headers,
};
use crate::error::LlmError;
use crate::session::SessionMessage;
use crate::types::PlatformLlmConfig;
use serde_json::Value;

#[test]
fn llm_error_from_anyhow_classifies_cancelled() {
    let err = LlmError::from_anyhow(anyhow::anyhow!("Chat cancelled"));
    assert_eq!(err.code(), "llm_cancelled");
}

#[test]
fn llm_error_from_anyhow_classifies_stream_truncated() {
    let err = LlmError::from_anyhow(anyhow::anyhow!(
        "Gemini stream ended before the completion marker"
    ));
    assert_eq!(err.code(), "llm_stream_truncated");
}

#[test]
fn llm_error_from_anyhow_classifies_decode() {
    let err = LlmError::from_anyhow(anyhow::anyhow!(
        "OpenAI-compatible response did not contain assistant content"
    ));
    assert_eq!(err.code(), "llm_decode");
}

#[test]
fn llm_error_from_anyhow_defaults_to_provider() {
    let err = LlmError::from_anyhow(anyhow::anyhow!("LLM provider error (500): boom"));
    assert_eq!(err.code(), "llm_provider");
}

#[test]
fn context_overflow_classifier_matches_common_provider_messages() {
    assert!(is_context_overflow_error(
        "LLM provider error (400): context_length_exceeded: maximum context length is 128000 tokens"
    ));
    assert!(is_context_overflow_error(
        "Gemini returned 413 request too large: prompt too long"
    ));
    assert!(is_context_overflow_error(
        "input tokens exceed the configured model limit"
    ));
    assert!(!is_context_overflow_error("LLM API key is required"));
}

fn config(provider: &str, base_url: Option<&str>) -> PlatformLlmConfig {
    PlatformLlmConfig {
        provider: provider.to_string(),
        api_key: "key".to_string(),
        base_url: base_url.map(str::to_string),
        model: "model".to_string(),
        system_prompt: String::new(),
        max_tokens: 1024,
        max_tool_iterations: 0,
        extra_headers: None,
        allowed_models: None,
        image_model: None,
        image_analysis_model: None,
        capability_configs: None,
        scene_prompt_config: None,
        ..PlatformLlmConfig::default()
    }
}

fn msg(role: &str, content: &str) -> SessionMessage {
    SessionMessage {
        id: String::new(),
        role: role.to_string(),
        content: content.to_string(),
        created_at: String::new(),
        interrupted: false,
        turn_id: None,
    }
}

#[test]
fn builds_provider_urls() {
    assert_eq!(
        chat_completions_url(&config("openai", None)),
        "https://api.openai.com/v1/chat/completions"
    );
    assert_eq!(
        anthropic_messages_url(&config("anthropic", Some("https://api.anthropic.com"))),
        "https://api.anthropic.com/v1/messages"
    );
    assert_eq!(
        gemini_generate_url(&config("gemini", Some("https://gemini.test/v1"))),
        "https://gemini.test/v1/models/model:generateContent?key=key"
    );
    assert_eq!(
        gemini_stream_url(&config("gemini", Some("https://gemini.test/v1"))),
        "https://gemini.test/v1/models/model:streamGenerateContent?alt=sse&key=key"
    );
}

#[test]
fn parses_extra_headers() {
    let mut config = config("openai", None);
    config.extra_headers = Some("X-Test: yes, X-Other: value".to_string());
    let headers = extra_headers(&config).unwrap();
    assert_eq!(headers.get("x-test").unwrap(), "yes");
    assert_eq!(headers.get("x-other").unwrap(), "value");
}

#[test]
fn sse_headers_request_identity_encoding() {
    let mut headers = HeaderMap::new();
    headers.insert("x-test", HeaderValue::from_static("yes"));
    let headers = sse_headers(headers);

    assert_eq!(headers.get("x-test").unwrap(), "yes");
    assert_eq!(headers.get(ACCEPT_ENCODING).unwrap(), "identity");
}

#[test]
fn response_body_preview_handles_empty_and_truncates() {
    assert_eq!(response_body_preview("   "), "<empty body>");
    let long = "a".repeat(RESPONSE_BODY_PREVIEW_CHARS + 1);
    let preview = response_body_preview(&long);

    assert_eq!(preview.len(), RESPONSE_BODY_PREVIEW_CHARS + 3);
    assert!(preview.ends_with("..."));
}

#[test]
fn stream_retry_allows_reconnect_on_transport_drop() {
    // A generic (non-transport) error only retries before output starts.
    let generic = anyhow!("model produced an unexpected response shape");
    assert!(can_retry_stream(0, false, &generic));
    assert!(!can_retry_stream(0, true, &generic));

    // A transport-level drop retries even after output has started — this is
    // the mid-stream reconnect that keeps a half-finished turn alive.
    let dropped = anyhow!("connection reset by peer");
    assert!(can_retry_stream(0, true, &dropped));

    // Budget and cancellation always stop retries.
    assert!(!can_retry_stream(
        STREAM_RETRY_ATTEMPTS - 1,
        false,
        &dropped
    ));
    assert!(!can_retry_stream(0, false, &anyhow!("Chat cancelled")));
    assert!(!can_retry_stream(0, true, &anyhow!("Chat cancelled")));
}

#[test]
fn classifies_retryable_transport_and_status_errors() {
    assert!(is_retryable_transport_error(&anyhow!(
        "LLM stream stalled: no data received for 60 seconds; reconnecting"
    )));
    assert!(is_retryable_transport_error(&anyhow!("unexpected EOF")));
    assert!(is_retryable_transport_error(&anyhow!(
        "LLM provider error (429): rate limited"
    )));
    assert!(is_retryable_transport_error(&anyhow!(
        "LLM provider error (503): upstream unavailable"
    )));

    // Non-transient failures must not be retried.
    assert!(!is_retryable_transport_error(&anyhow!(
        "LLM provider error (400): invalid request"
    )));
    assert!(!is_retryable_transport_error(&anyhow!("Chat cancelled")));
    assert!(!is_retryable_transport_error(&anyhow!(
        "input is too long for the context window"
    )));
}

#[test]
fn maps_history_for_provider_payloads() {
    let history = vec![msg("user", "hello"), msg("assistant", "hi")];
    let openai = openai_messages_from_history(&history);
    assert_eq!(openai[0]["role"], "user");
    assert_eq!(openai[1]["role"], "assistant");

    let anthropic = anthropic_messages_from_history(&history);
    assert_eq!(anthropic[1]["content"], "hi");

    let gemini = gemini_contents_from_history(&history);
    assert_eq!(gemini[0]["role"], "user");
    assert_eq!(gemini[1]["role"], "model");
}

#[test]
fn renders_turn_aborted_marker_as_assistant_and_preserves_alternation() {
    // The marker sits between two user turns; rendering it as assistant/model
    // keeps strict user/assistant alternation that the providers require.
    let marker = "<turn_aborted>interrupted</turn_aborted>";
    let history = vec![
        msg("user", "first"),
        msg("turn_aborted", marker),
        msg("user", "second"),
    ];

    let openai = openai_messages_from_history(&history);
    assert_eq!(openai.len(), 3);
    assert_eq!(openai[0]["role"], "user");
    assert_eq!(openai[1]["role"], "assistant");
    assert_eq!(openai[1]["content"], marker);
    assert_eq!(openai[2]["role"], "user");

    let openai_ctx = openai_messages_from_mobile_history(&history);
    assert_eq!(openai_ctx.len(), 3);
    assert_eq!(openai_ctx[1]["role"], "assistant");
    assert_eq!(openai_ctx[1]["content"], marker);

    let anthropic = anthropic_messages_from_history(&history);
    assert_eq!(anthropic[1]["role"], "assistant");
    assert_eq!(anthropic[1]["content"], marker);

    let gemini = gemini_contents_from_history(&history);
    assert_eq!(gemini[1]["role"], "model");
    assert_eq!(gemini[1]["parts"][0]["text"], marker);
}

#[test]
fn parses_openai_stream_lines() {
    let mut content = String::new();
    let mut events = Vec::new();
    let done = handle_openai_stream_line(
        r#"data: {"choices":[{"delta":{"content":"hel"}}]}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_openai_stream_line(
        r#"data: {"choices":[{"delta":{"content":"lo","reasoning_content":"r"}}]}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_openai_stream_line("data: [DONE]", &mut content, &mut |event| {
        events.push(event)
    })
    .unwrap();

    assert!(done);
    assert_eq!(content, "hello");
    assert_eq!(
        events,
        vec![
            LlmStreamEvent::ResponseDelta("hel".to_string()),
            LlmStreamEvent::ResponseDelta("lo".to_string()),
            LlmStreamEvent::ReasoningDelta("r".to_string()),
        ]
    );
}

#[test]
fn parses_anthropic_stream_lines() {
    let mut content = String::new();
    let mut events = Vec::new();
    let done = handle_anthropic_stream_line(
        r#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hel"}}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_anthropic_stream_line(
        r#"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"why"}}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_anthropic_stream_line(
        r#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"lo"}}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_anthropic_stream_line(
        r#"data: {"type":"message_stop"}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();

    assert!(done);
    assert_eq!(content, "hello");
    assert_eq!(
        events,
        vec![
            LlmStreamEvent::ResponseDelta("hel".to_string()),
            LlmStreamEvent::ReasoningDelta("why".to_string()),
            LlmStreamEvent::ResponseDelta("lo".to_string()),
        ]
    );
}

#[test]
fn parses_gemini_stream_lines() {
    let mut content = String::new();
    let mut events = Vec::new();
    handle_gemini_stream_line(
        r#"data: {"candidates":[{"content":{"parts":[{"text":"hel"},{"text":"why","thought":true}]}}]}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();
    handle_gemini_stream_line(
        r#"data: {"candidates":[{"content":{"parts":[{"text":"lo"}]}}]}"#,
        &mut content,
        &mut |event| events.push(event),
    )
    .unwrap();

    assert_eq!(content, "hello");
    assert_eq!(
        events,
        vec![
            LlmStreamEvent::ResponseDelta("hel".to_string()),
            LlmStreamEvent::ReasoningDelta("why".to_string()),
            LlmStreamEvent::ResponseDelta("lo".to_string()),
        ]
    );
}

#[test]
fn parses_openai_tool_calls() {
    let turn = parse_openai_turn(&serde_json::json!({
        "choices": [{
            "message": {
                "role": "assistant",
                "content": null,
                "reasoning_content": "I should call a tool.",
                "tool_calls": [{
                    "id": "call_1",
                    "type": "function",
                    "function": {
                        "name": "lookup",
                        "arguments": "{\"q\":\"napaxi\"}"
                    }
                }]
            }
        }]
    }))
    .unwrap();
    assert_eq!(turn.content, "");
    assert_eq!(
        turn.reasoning_content.as_deref(),
        Some("I should call a tool.")
    );
    assert_eq!(turn.tool_calls[0].id, "call_1");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    assert_eq!(turn.tool_calls[0].arguments, "{\"q\":\"napaxi\"}");
}

#[test]
fn parses_openai_streaming_tool_call_deltas() {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    let mut events = Vec::new();
    let done = handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{"content":"Let me check.","reasoning_content":"I should ","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\"q\""}}]}}]}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{"reasoning_content":"call a tool.","tool_calls":[{"index":0,"function":{"arguments":":\"napaxi\"}"}}]}}]}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_openai_stream_turn_line("data: [DONE]", &mut accumulator, &mut |event| {
        events.push(event)
    })
    .unwrap();
    assert!(done);

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Let me check.");
    assert_eq!(
        turn.reasoning_content.as_deref(),
        Some("I should call a tool.")
    );
    assert_eq!(turn.tool_calls[0].id, "call_1");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    assert_eq!(turn.tool_calls[0].arguments, "{\"q\":\"napaxi\"}");
    assert_eq!(
        events,
        vec![
            LlmStreamEvent::ResponseDelta("Let me check.".to_string()),
            LlmStreamEvent::ReasoningDelta("I should ".to_string()),
            LlmStreamEvent::ToolCallDelta {
                index: 0,
                id: Some("call_1".to_string()),
                name: Some("lookup".to_string()),
                arguments_delta: "{\"q\"".to_string(),
            },
            LlmStreamEvent::ReasoningDelta("call a tool.".to_string()),
            LlmStreamEvent::ToolCallDelta {
                index: 0,
                id: None,
                name: None,
                arguments_delta: ":\"napaxi\"}".to_string(),
            },
        ]
    );
}

#[test]
fn openai_streaming_tool_call_keeps_incomplete_arguments_for_tool_loop() {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"shell","arguments":"{\"command\":\"printf "}}]}}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.tool_calls[0].name, "shell");
    assert_eq!(turn.tool_calls[0].arguments, r#"{"command":"printf "#);
}

#[test]
fn openai_streaming_empty_length_finish_reason_is_error() {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let error = accumulator.finish().unwrap_err().to_string();
    assert!(error.contains("output token limit"));
}

#[test]
fn openai_streaming_length_finish_reason_preserves_partial_content() {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{"content":"Partial"},"finish_reason":"length"}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Partial");
}

#[test]
fn openai_streaming_length_finish_reason_preserves_tool_calls() {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"read","arguments":"{\"path\":\"a\"}"}}]},"finish_reason":"length"}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.tool_calls.len(), 1);
    assert_eq!(turn.tool_calls[0].name, "read");
}

#[test]
fn openai_streaming_stop_finish_reason_allows_eof_without_done() {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{"content":"Done"},"finish_reason":"stop"}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    assert!(accumulator.has_finish_reason());
    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Done");
}

#[test]
fn openai_streaming_tool_calls_finish_without_tool_call_is_error() {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    handle_openai_stream_turn_line(
        r#"data: {"choices":[{"delta":{"content":"Let me search"},"finish_reason":"tool_calls"}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let error = accumulator.finish().unwrap_err().to_string();
    assert!(error.contains("did not include a complete tool call"));
}

#[test]
fn parses_anthropic_streaming_tool_call_deltas() {
    let mut accumulator = AnthropicStreamTurnAccumulator::default();
    let mut events = Vec::new();
    let done = handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Checking."}}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"lookup","input":{}}}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"q\""}}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":":\"napaxi\"}"}}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_anthropic_stream_turn_line(
        r#"data: {"type":"message_stop"}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(done);

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Checking.");
    assert_eq!(turn.tool_calls[0].id, "toolu_1");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    assert_eq!(turn.tool_calls[0].arguments, "{\"q\":\"napaxi\"}");
    assert_eq!(
        events,
        vec![
            LlmStreamEvent::ResponseDelta("Checking.".to_string()),
            LlmStreamEvent::ToolCallDelta {
                index: 1,
                id: Some("toolu_1".to_string()),
                name: Some("lookup".to_string()),
                arguments_delta: String::new(),
            },
            LlmStreamEvent::ToolCallDelta {
                index: 1,
                id: None,
                name: None,
                arguments_delta: "{\"q\"".to_string(),
            },
            LlmStreamEvent::ToolCallDelta {
                index: 1,
                id: None,
                name: None,
                arguments_delta: ":\"napaxi\"}".to_string(),
            },
        ]
    );
}

#[test]
fn anthropic_streaming_tool_call_keeps_incomplete_arguments_for_tool_loop() {
    let mut accumulator = AnthropicStreamTurnAccumulator::default();
    handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"shell","input":{}}}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();
    handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"command\":\"printf "}}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.tool_calls[0].name, "shell");
    assert_eq!(turn.tool_calls[0].arguments, r#"{"command":"printf "#);
}

#[test]
fn anthropic_streaming_empty_max_tokens_stop_reason_is_error() {
    let mut accumulator = AnthropicStreamTurnAccumulator::default();
    handle_anthropic_stream_turn_line(
        r#"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let error = accumulator.finish().unwrap_err().to_string();
    assert!(error.contains("output token limit"));
}

#[test]
fn anthropic_streaming_max_tokens_stop_reason_preserves_partial_content() {
    let mut accumulator = AnthropicStreamTurnAccumulator::default();
    handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Partial"}}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();
    handle_anthropic_stream_turn_line(
        r#"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Partial");
}

#[test]
fn anthropic_streaming_end_turn_stop_reason_allows_eof_without_message_stop() {
    let mut accumulator = AnthropicStreamTurnAccumulator::default();
    handle_anthropic_stream_turn_line(
        r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done"}}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();
    handle_anthropic_stream_turn_line(
        r#"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    assert!(accumulator.has_stop_reason());
    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Done");
}

#[test]
fn parses_gemini_streaming_tool_calls() {
    let mut accumulator = GeminiStreamTurnAccumulator::default();
    let mut events = Vec::new();
    let done = handle_gemini_stream_turn_line(
        r#"data: {"candidates":[{"content":{"parts":[{"text":"Checking."},{"functionCall":{"name":"lookup","args":{"q":"napaxi"}}}]}}]}"#,
        &mut accumulator,
        &mut |event| events.push(event),
    )
    .unwrap();
    assert!(!done);
    let done = handle_gemini_stream_turn_line("data: [DONE]", &mut accumulator, &mut |event| {
        events.push(event)
    })
    .unwrap();
    assert!(done);

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Checking.");
    assert_eq!(turn.tool_calls[0].id, "lookup");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    assert_eq!(turn.tool_calls[0].arguments, "{\"q\":\"napaxi\"}");
    assert_eq!(
        events,
        vec![
            LlmStreamEvent::ResponseDelta("Checking.".to_string()),
            LlmStreamEvent::ToolCallDelta {
                index: 0,
                id: Some("lookup".to_string()),
                name: Some("lookup".to_string()),
                arguments_delta: "{\"q\":\"napaxi\"}".to_string(),
            },
        ]
    );
}

#[test]
fn gemini_streaming_empty_max_tokens_finish_reason_is_error() {
    let mut accumulator = GeminiStreamTurnAccumulator::default();
    handle_gemini_stream_turn_line(
        r#"data: {"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[]}}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let error = accumulator.finish().unwrap_err().to_string();
    assert!(error.contains("output token limit"));
}

#[test]
fn gemini_streaming_max_tokens_finish_reason_preserves_partial_content() {
    let mut accumulator = GeminiStreamTurnAccumulator::default();
    handle_gemini_stream_turn_line(
        r#"data: {"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"Partial"}]}}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Partial");
}

#[test]
fn gemini_streaming_stop_finish_reason_allows_eof_without_done() {
    let mut accumulator = GeminiStreamTurnAccumulator::default();
    handle_gemini_stream_turn_line(
        r#"data: {"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"Done"}]}}]}"#,
        &mut accumulator,
        &mut |_| {},
    )
    .unwrap();

    assert!(accumulator.has_finish_reason());
    let turn = accumulator.finish().unwrap();
    assert_eq!(turn.content, "Done");
}

#[test]
fn maps_raw_messages_for_anthropic_tool_loop() {
    let messages = tool_loop_messages();
    let mapped = anthropic_messages_from_raw(&messages);

    assert_eq!(mapped[0]["role"], "user");
    assert_eq!(mapped[1]["role"], "assistant");
    assert_eq!(mapped[1]["content"][0]["type"], "tool_use");
    assert_eq!(mapped[1]["content"][0]["id"], "call_1");
    assert_eq!(mapped[1]["content"][0]["input"]["q"], "napaxi");
    assert_eq!(mapped[2]["content"][0]["type"], "tool_result");
    assert_eq!(mapped[2]["content"][0]["tool_use_id"], "call_1");
}

#[test]
fn maps_raw_messages_for_gemini_tool_loop() {
    let messages = tool_loop_messages();
    let mapped = gemini_contents_from_raw(&messages);

    assert_eq!(mapped[0]["role"], "user");
    assert_eq!(mapped[1]["role"], "model");
    assert_eq!(mapped[1]["parts"][0]["functionCall"]["name"], "lookup");
    assert_eq!(mapped[1]["parts"][0]["functionCall"]["args"]["q"], "napaxi");
    assert_eq!(mapped[2]["parts"][0]["functionResponse"]["name"], "lookup");
    assert_eq!(
        mapped[2]["parts"][0]["functionResponse"]["response"]["content"],
        "result"
    );
}

#[test]
fn parses_anthropic_tool_calls() {
    let turn = parse_anthropic_turn(&serde_json::json!({
        "content": [{
            "type": "tool_use",
            "id": "toolu_1",
            "name": "lookup",
            "input": { "q": "napaxi" }
        }]
    }))
    .unwrap();

    assert_eq!(turn.content, "");
    assert_eq!(turn.tool_calls[0].id, "toolu_1");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    assert_eq!(turn.tool_calls[0].arguments, "{\"q\":\"napaxi\"}");
}

#[test]
fn parses_gemini_tool_calls() {
    let turn = parse_gemini_turn(&serde_json::json!({
        "candidates": [{
            "content": {
                "parts": [{
                    "functionCall": {
                        "name": "lookup",
                        "args": { "q": "napaxi" }
                    }
                }]
            }
        }]
    }))
    .unwrap();

    assert_eq!(turn.content, "");
    assert_eq!(turn.tool_calls[0].id, "lookup");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    assert_eq!(turn.tool_calls[0].arguments, "{\"q\":\"napaxi\"}");
}

fn tool_loop_messages() -> Vec<Value> {
    vec![
        serde_json::json!({
            "role": "user",
            "content": "search",
        }),
        serde_json::json!({
            "role": "assistant",
            "content": null,
            "tool_calls": [{
                "id": "call_1",
                "type": "function",
                "function": {
                    "name": "lookup",
                    "arguments": "{\"q\":\"napaxi\"}",
                }
            }]
        }),
        serde_json::json!({
            "role": "tool",
            "tool_call_id": "call_1",
            "content": "result",
        }),
    ]
}
