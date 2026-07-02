//! Minimal HTTP LLM adapter for the standalone mobile SDK runtime.

mod anthropic;
mod cache_policy;
mod dispatch;
mod gemini;
mod http;
mod messages;
mod openai_compatible;
mod output_cap;
mod provider;
mod sse;
mod tool_schema;
mod usage;

#[cfg(test)]
mod replay_tests;
#[cfg(test)]
mod tests;

use anyhow::Result;

#[cfg(test)]
pub(crate) use dispatch::with_scripted_turns;
pub use dispatch::{
    complete_turn_with_raw_messages, complete_with_history, stream_turn_with_raw_messages,
    stream_with_history_cancelable,
};
pub use messages::openai_messages_from_mobile_history;
pub use usage::LlmUsage;

use crate::session::SessionMessage;
use crate::types::PlatformLlmConfig;

pub(crate) fn is_context_overflow_error(error: &str) -> bool {
    let lower = error.to_ascii_lowercase();

    const EXCLUDED: &[&str] = &[
        "unsupported",
        "unknown parameter",
        "unrecognized parameter",
        "invalid parameter",
        "not supported",
        "is not allowed",
    ];
    if EXCLUDED.iter().any(|ex| lower.contains(ex)) {
        return false;
    }

    const NEEDLES: &[&str] = &[
        "context overflow",
        "context_length_exceeded",
        "maximum context",
        "maximum number of tokens",
        "max context",
        "prompt too long",
        "too many tokens",
        "input is too long",
        "input tokens",
        "exceeds the context",
        "exceeded token limit",
        "reduce the length",
        "request too large",
        "413",
    ];
    NEEDLES.iter().any(|needle| lower.contains(needle))
        || (lower.contains("context") && lower.contains("too long"))
        || (lower.contains("tokens") && lower.contains("exceed"))
        || (lower.contains("token") && lower.contains("limit") && lower.contains("input"))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LlmStreamEvent {
    ResponseDelta(String),
    ReasoningDelta(String),
    ToolCallDelta {
        index: usize,
        id: Option<String>,
        name: Option<String>,
        arguments_delta: String,
    },
    /// The provider connection dropped (or stalled) mid-stream and the request
    /// is being retried from scratch. Any partial content/reasoning/tool-call
    /// deltas emitted before this point belong to an aborted attempt and must be
    /// discarded by downstream consumers before the retried stream resumes.
    StreamReset {
        reason: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LlmToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LlmTurn {
    pub content: String,
    pub reasoning_content: Option<String>,
    pub tool_calls: Vec<LlmToolCall>,
    pub usage: Option<LlmUsage>,
}

#[allow(dead_code)] // Convenience wrapper kept on the public LLM surface.
pub async fn complete(config: &PlatformLlmConfig, user_message: &str) -> Result<String> {
    complete_with_history(
        config,
        &[SessionMessage {
            id: String::new(),
            role: "user".to_string(),
            content: user_message.to_string(),
            created_at: String::new(),
            interrupted: false,
            turn_id: None,
        }],
    )
    .await
}

// ============================================================================
// Typed boundary
// ============================================================================
//
// The LLM internals use `anyhow::Result`; `LlmError::from_anyhow` (error.rs)
// classifies those into a stable `code()` when an adapter needs typed errors.
