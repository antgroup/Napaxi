//! Replay tests that feed pre-recorded SSE fixtures into the
//! `handle_*_stream_turn_line` parsers, then call `finish()` on the
//! accumulator to assert the final shape (content / reasoning / tool calls).
//! These guard against provider-format regressions without depending on
//! live network access.
//!
//! Fixtures live under `crates/core/src/tests/fixtures/llm/` and are
//! embedded with `include_str!` so they travel with the source tree.

use super::sse::{
    AnthropicStreamTurnAccumulator, GeminiStreamTurnAccumulator, OpenAiStreamTurnAccumulator,
    handle_anthropic_stream_turn_line, handle_gemini_stream_turn_line,
    handle_openai_stream_turn_line,
};
use super::{LlmStreamEvent, LlmTurn};

// ---------------------------------------------------------------------------
// Replay helpers
// ---------------------------------------------------------------------------

#[derive(Debug)]
struct Replay {
    /// `Some` when the parser reported the stream finished cleanly (saw the
    /// provider's terminator); `Err` when `finish()` rejected the partial
    /// state (e.g. tool call args could not be parsed); `Ok` when finish
    /// produced a complete turn.
    turn: Result<LlmTurn, anyhow::Error>,
    events: Vec<LlmStreamEvent>,
    saw_done: bool,
}

fn replay_openai(fixture: &str) -> Replay {
    let mut accumulator = OpenAiStreamTurnAccumulator::default();
    let mut events = Vec::new();
    let mut saw_done = false;
    for line in fixture.lines() {
        match handle_openai_stream_turn_line(line, &mut accumulator, &mut |event| {
            events.push(event);
        }) {
            Ok(true) => {
                saw_done = true;
                break;
            }
            Ok(false) => {}
            Err(e) => panic!("openai parser rejected line: {e}\nline={line}"),
        }
    }
    Replay {
        turn: accumulator.finish(),
        events,
        saw_done,
    }
}

fn replay_anthropic(fixture: &str) -> Replay {
    let mut accumulator = AnthropicStreamTurnAccumulator::default();
    let mut events = Vec::new();
    let mut saw_done = false;
    for line in fixture.lines() {
        match handle_anthropic_stream_turn_line(line, &mut accumulator, &mut |event| {
            events.push(event);
        }) {
            Ok(true) => {
                saw_done = true;
                break;
            }
            Ok(false) => {}
            Err(e) => panic!("anthropic parser rejected line: {e}\nline={line}"),
        }
    }
    Replay {
        turn: accumulator.finish(),
        events,
        saw_done,
    }
}

fn replay_gemini(fixture: &str) -> Replay {
    let mut accumulator = GeminiStreamTurnAccumulator::default();
    let mut events = Vec::new();
    let mut saw_done = false;
    for line in fixture.lines() {
        match handle_gemini_stream_turn_line(line, &mut accumulator, &mut |event| {
            events.push(event);
        }) {
            Ok(true) => {
                saw_done = true;
                break;
            }
            Ok(false) => {}
            Err(e) => panic!("gemini parser rejected line: {e}\nline={line}"),
        }
    }
    Replay {
        turn: accumulator.finish(),
        events,
        saw_done,
    }
}

fn collect_text(events: &[LlmStreamEvent]) -> String {
    events
        .iter()
        .filter_map(|e| match e {
            LlmStreamEvent::ResponseDelta(s) => Some(s.as_str()),
            _ => None,
        })
        .collect()
}

fn collect_reasoning(events: &[LlmStreamEvent]) -> String {
    events
        .iter()
        .filter_map(|e| match e {
            LlmStreamEvent::ReasoningDelta(s) => Some(s.as_str()),
            _ => None,
        })
        .collect()
}

// ---------------------------------------------------------------------------
// OpenAI
// ---------------------------------------------------------------------------

const OPENAI_TEXT_ONLY: &str = include_str!("../tests/fixtures/llm/openai/text_only.sse");
const OPENAI_TOOL_CALL_SINGLE: &str =
    include_str!("../tests/fixtures/llm/openai/tool_call_single.sse");
const OPENAI_TOOL_CALL_PARALLEL: &str =
    include_str!("../tests/fixtures/llm/openai/tool_call_parallel.sse");
const OPENAI_REASONING_THEN_TEXT: &str =
    include_str!("../tests/fixtures/llm/openai/reasoning_then_text.sse");
const OPENAI_TRUNCATED: &str = include_str!("../tests/fixtures/llm/openai/truncated.sse");

#[test]
fn openai_text_only_accumulates_full_response() {
    let replay = replay_openai(OPENAI_TEXT_ONLY);
    assert!(replay.saw_done, "stream should terminate on [DONE]");
    let turn = replay.turn.expect("finish must succeed for clean stream");
    assert_eq!(turn.content, "Hello, world!");
    assert!(turn.tool_calls.is_empty());
    assert_eq!(collect_text(&replay.events), "Hello, world!");
}

#[test]
fn openai_tool_call_single_reassembles_arguments() {
    let replay = replay_openai(OPENAI_TOOL_CALL_SINGLE);
    assert!(replay.saw_done);
    let turn = replay.turn.expect("finish must succeed");
    assert!(turn.content.is_empty());
    assert_eq!(turn.tool_calls.len(), 1);
    assert_eq!(turn.tool_calls[0].id, "call_lookup_1");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    let args: serde_json::Value =
        serde_json::from_str(&turn.tool_calls[0].arguments).expect("arguments must parse");
    assert_eq!(args["query"], "napaxi");
}

#[test]
fn openai_tool_call_parallel_preserves_index_ordering() {
    let replay = replay_openai(OPENAI_TOOL_CALL_PARALLEL);
    assert!(replay.saw_done);
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.tool_calls.len(), 2);
    assert_eq!(turn.tool_calls[0].name, "search");
    assert_eq!(turn.tool_calls[1].name, "fetch");
    let args0: serde_json::Value = serde_json::from_str(&turn.tool_calls[0].arguments).unwrap();
    let args1: serde_json::Value = serde_json::from_str(&turn.tool_calls[1].arguments).unwrap();
    assert_eq!(args0["q"], "a");
    assert_eq!(args1["u"], "b");
}

#[test]
fn openai_reasoning_then_text_separates_streams() {
    let replay = replay_openai(OPENAI_REASONING_THEN_TEXT);
    assert!(replay.saw_done);
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.content, "The answer is 42.");
    assert_eq!(
        turn.reasoning_content.as_deref(),
        Some("Let me think step by step.")
    );
    assert_eq!(collect_text(&replay.events), "The answer is 42.");
    assert_eq!(
        collect_reasoning(&replay.events),
        "Let me think step by step."
    );
}

#[test]
fn openai_truncated_stream_does_not_signal_done() {
    let replay = replay_openai(OPENAI_TRUNCATED);
    assert!(
        !replay.saw_done,
        "missing [DONE] should leave saw_done=false"
    );
    // finish() is lenient: it still produces a turn with whatever content
    // arrived. The signal to callers that the stream was truncated is
    // saw_done=false, not an Err from finish().
    let turn = replay
        .turn
        .expect("OpenAI finish() is lenient with partial content");
    assert_eq!(turn.content, "Partial response");
    assert!(turn.tool_calls.is_empty());
}

// ---------------------------------------------------------------------------
// Anthropic
// ---------------------------------------------------------------------------

const ANTHROPIC_TEXT_ONLY: &str = include_str!("../tests/fixtures/llm/anthropic/text_only.sse");
const ANTHROPIC_TOOL_CALL_SINGLE: &str =
    include_str!("../tests/fixtures/llm/anthropic/tool_call_single.sse");
const ANTHROPIC_THINKING_THEN_TEXT: &str =
    include_str!("../tests/fixtures/llm/anthropic/thinking_then_text.sse");
const ANTHROPIC_CONTENT_BLOCK_SPLIT: &str =
    include_str!("../tests/fixtures/llm/anthropic/content_block_split.sse");
const ANTHROPIC_TRUNCATED: &str = include_str!("../tests/fixtures/llm/anthropic/truncated.sse");

#[test]
fn anthropic_text_only_accumulates_full_response() {
    let replay = replay_anthropic(ANTHROPIC_TEXT_ONLY);
    assert!(replay.saw_done, "message_stop should terminate the stream");
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.content, "Hello, world!");
    assert!(turn.tool_calls.is_empty());
}

#[test]
fn anthropic_tool_call_single_reassembles_partial_json() {
    let replay = replay_anthropic(ANTHROPIC_TOOL_CALL_SINGLE);
    assert!(replay.saw_done);
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.tool_calls.len(), 1);
    assert_eq!(turn.tool_calls[0].id, "toolu_lookup_1");
    assert_eq!(turn.tool_calls[0].name, "lookup");
    let args: serde_json::Value =
        serde_json::from_str(&turn.tool_calls[0].arguments).expect("merged input_json must parse");
    assert_eq!(args["query"], "napaxi");
}

#[test]
fn anthropic_thinking_then_text_separates_streams() {
    let replay = replay_anthropic(ANTHROPIC_THINKING_THEN_TEXT);
    assert!(replay.saw_done);
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.content, "The answer is 42.");
    // Note: Anthropic's accumulator emits thinking as a ReasoningDelta event
    // but does not persist it on the resulting LlmTurn — the assembled
    // turn always has `reasoning_content: None`. Callers that need the
    // thinking must collect it from the event stream.
    assert!(turn.reasoning_content.is_none());
    assert_eq!(
        collect_reasoning(&replay.events),
        "Let me think step by step."
    );
}

#[test]
fn anthropic_content_block_split_concatenates_all_deltas() {
    let replay = replay_anthropic(ANTHROPIC_CONTENT_BLOCK_SPLIT);
    assert!(replay.saw_done);
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.content, "This is split across many deltas.");
    let response_count = replay
        .events
        .iter()
        .filter(|e| matches!(e, LlmStreamEvent::ResponseDelta(_)))
        .count();
    assert_eq!(
        response_count, 6,
        "each text_delta should produce one ResponseDelta event"
    );
}

#[test]
fn anthropic_truncated_stream_does_not_signal_done() {
    let replay = replay_anthropic(ANTHROPIC_TRUNCATED);
    assert!(!replay.saw_done);
    // Anthropic's finish() is also lenient — the signal is saw_done=false
    // (no message_stop arrived).
    let turn = replay
        .turn
        .expect("Anthropic finish() is lenient with partial content");
    assert_eq!(turn.content, "Partial response");
}

// ---------------------------------------------------------------------------
// Gemini
// ---------------------------------------------------------------------------

const GEMINI_TEXT_ONLY: &str = include_str!("../tests/fixtures/llm/gemini/text_only.sse");
const GEMINI_TOOL_CALL_SINGLE: &str =
    include_str!("../tests/fixtures/llm/gemini/tool_call_single.sse");
const GEMINI_CHUNKED_PARTS: &str = include_str!("../tests/fixtures/llm/gemini/chunked_parts.sse");
const GEMINI_TRUNCATED: &str = include_str!("../tests/fixtures/llm/gemini/truncated.sse");

#[test]
fn gemini_text_only_accumulates_full_response() {
    let replay = replay_gemini(GEMINI_TEXT_ONLY);
    // Gemini's stream ends via finishReason=STOP, not an explicit [DONE]
    // sentinel — saw_done stays false but finish() should still succeed.
    assert!(!replay.saw_done);
    let turn = replay
        .turn
        .expect("finish must succeed once finishReason=STOP arrives");
    assert_eq!(turn.content, "Hello, world!");
    assert!(turn.tool_calls.is_empty());
}

#[test]
fn gemini_tool_call_single_extracts_function_call() {
    let replay = replay_gemini(GEMINI_TOOL_CALL_SINGLE);
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.tool_calls.len(), 1);
    assert_eq!(turn.tool_calls[0].name, "lookup");
    let args: serde_json::Value = serde_json::from_str(&turn.tool_calls[0].arguments).unwrap();
    assert_eq!(args["query"], "napaxi");
}

#[test]
fn gemini_chunked_parts_concatenates_multiple_parts_per_candidate() {
    let replay = replay_gemini(GEMINI_CHUNKED_PARTS);
    let turn = replay.turn.expect("finish must succeed");
    assert_eq!(turn.content, "Part one and part two.");
}

#[test]
fn gemini_truncated_stream_keeps_partial_content() {
    let replay = replay_gemini(GEMINI_TRUNCATED);
    assert!(!replay.saw_done);
    // Gemini's finish() is lenient too — partial content survives.
    let turn = replay
        .turn
        .expect("Gemini finish() is lenient with partial content");
    assert_eq!(turn.content, "Partial");
}
