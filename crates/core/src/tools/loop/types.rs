use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use crate::types::ChatEvent;
use tokio::sync::mpsc;

use super::ToolTrace;

tokio::task_local! {
    /// Per–tool-call cancellation flag visible inside handler futures.
    ///
    /// `execute_tool_call` scopes each handler future with a flag that flips
    /// to `true` when the surrounding turn observes a cancellation. Handlers
    /// that drive long-running synchronous work (shell, FFI) read this flag
    /// to abort early and kill child processes.
    pub static TOOL_CALL_CANCEL: Arc<AtomicBool>;
}

/// Snapshot the currently active per–tool-call cancel flag from inside a
/// handler future. Returns `None` when called outside a scoped tool call
/// (e.g. unit tests that invoke handlers directly).
pub fn current_tool_call_cancel() -> Option<Arc<AtomicBool>> {
    TOOL_CALL_CANCEL.try_with(|flag| flag.clone()).ok()
}

#[derive(Debug, Clone)]
pub struct InternalToolResult {
    pub output: String,
    pub events: Vec<ChatEvent>,
}

#[derive(Debug, Clone)]
pub struct InternalToolProgressEvent {
    pub stream: String,
    pub content: String,
}

pub type InternalToolProgressSender = mpsc::UnboundedSender<InternalToolProgressEvent>;

pub type InternalToolFuture = Pin<Box<dyn Future<Output = Result<InternalToolResult, String>>>>;

pub type InternalToolHandler = Arc<
    dyn Fn(
            &str,
            serde_json::Value,
            Option<InternalToolProgressSender>,
        ) -> Option<InternalToolFuture>
        + Send
        + Sync,
>;

#[derive(Debug, Clone)]
pub struct ToolLoopResult {
    pub content: String,
    pub tool_call_count: usize,
    pub usage: Option<crate::llm::LlmUsage>,
    #[allow(dead_code)] // Captured for adapter diagnostics; not read by tool-loop core.
    pub trace: ToolTrace,
}
