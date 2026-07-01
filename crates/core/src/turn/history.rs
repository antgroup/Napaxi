use serde::Serialize;
use uuid::Uuid;

use super::TurnMode;
use crate::types::ChatEvent;

#[derive(Debug)]
pub(crate) struct TurnHistoryRecorder {
    segments: Vec<TurnHistorySegment>,
    saw_response_delta: bool,
    turn_id: String,
}

impl Default for TurnHistoryRecorder {
    fn default() -> Self {
        Self {
            segments: Vec::new(),
            saw_response_delta: false,
            turn_id: Uuid::new_v4().to_string(),
        }
    }
}

pub(super) fn turn_history_recorder_for(_mode: TurnMode) -> TurnHistoryRecorder {
    TurnHistoryRecorder::default()
}

#[derive(Debug, Default)]
struct TurnHistorySegment {
    reasoning: String,
    tool_calls: Vec<TurnHistoryToolCall>,
    content: String,
}

#[derive(Debug, Clone, Serialize)]
struct TurnHistoryToolCall {
    call_id: String,
    name: String,
    arguments: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl TurnHistoryRecorder {
    pub(crate) fn is_empty(&self) -> bool {
        self.snapshot_messages(false).is_empty()
    }

    /// Whether this turn produced output that survives into the model-facing
    /// history envelope, i.e. assistant content or tool calls. Reasoning /
    /// thinking segments are deliberately excluded: `llm_context_history_all`
    /// drops the `reasoning` role, so a turn interrupted after only thinking
    /// tokens contributes nothing to the next request and still needs a
    /// `turn_aborted` boundary marker to avoid two consecutive `user` messages.
    pub(crate) fn produced_model_visible_output(&self) -> bool {
        self.segments
            .iter()
            .any(|segment| !segment.content.trim().is_empty() || !segment.tool_calls.is_empty())
    }

    pub(crate) fn record(&mut self, event: &ChatEvent) {
        match event {
            ChatEvent::ReasoningDelta { content } | ChatEvent::Thinking { content } => {
                self.segment_for_trace().reasoning.push_str(content);
            }
            ChatEvent::ResponseDelta { content } => {
                self.saw_response_delta = true;
                self.current_segment().content.push_str(content);
            }
            ChatEvent::StreamReset { .. } => {
                // The current LLM attempt aborted before completing. Discard the
                // partial assistant content/reasoning accumulated in the active
                // segment; the reconnected stream will repopulate it. Completed
                // tool calls live in prior segments and are left intact.
                if let Some(segment) = self.segments.last_mut() {
                    segment.content.clear();
                    segment.reasoning.clear();
                }
                self.saw_response_delta = false;
            }
            ChatEvent::Response { content } => {
                if !self.saw_response_delta {
                    self.current_segment().content = content.clone();
                }
            }
            ChatEvent::ToolCall {
                call_id,
                name,
                arguments,
            }
            | ChatEvent::AgentToolCall {
                call_id,
                name,
                arguments,
                ..
            } => {
                self.current_segment().tool_calls.push(TurnHistoryToolCall {
                    call_id: call_id.clone(),
                    name: name.clone(),
                    arguments: arguments.clone(),
                    result: None,
                    error: None,
                });
            }
            ChatEvent::ToolResult {
                call_id,
                output,
                is_error,
                ..
            }
            | ChatEvent::AgentToolResult {
                call_id,
                output,
                is_error,
                ..
            } => {
                self.finish_tool_call(call_id, output.clone(), *is_error);
            }
            ChatEvent::AgentDelegation {
                to_agent, message, ..
            } => {
                self.current_segment().tool_calls.push(TurnHistoryToolCall {
                    call_id: format!("delegation:{to_agent}"),
                    name: format!("delegate · {to_agent}"),
                    arguments: message.clone(),
                    result: None,
                    error: None,
                });
            }
            ChatEvent::AgentDelegationResult {
                to_agent,
                content,
                is_error,
                ..
            } => {
                self.finish_tool_call(
                    &format!("delegation:{to_agent}"),
                    content.clone(),
                    *is_error,
                );
            }
            _ => {}
        }
    }

    fn current_segment(&mut self) -> &mut TurnHistorySegment {
        if self.segments.is_empty() {
            self.segments.push(TurnHistorySegment::default());
        }
        self.segments.last_mut().expect("segment exists")
    }

    fn segment_for_trace(&mut self) -> &mut TurnHistorySegment {
        if self
            .segments
            .last()
            .is_none_or(|segment| !segment.content.trim().is_empty())
        {
            self.segments.push(TurnHistorySegment::default());
        }
        self.segments.last_mut().expect("segment exists")
    }

    fn finish_tool_call(&mut self, call_id: &str, output: String, is_error: bool) {
        for segment in self.segments.iter_mut().rev() {
            if let Some(call) = segment
                .tool_calls
                .iter_mut()
                .rev()
                .find(|call| call.call_id == call_id)
            {
                if is_error {
                    call.error = Some(output);
                } else {
                    call.result = Some(output);
                }
                return;
            }
        }
    }

    fn snapshot_messages(&self, interrupted: bool) -> Vec<crate::session::SessionAppendMessage> {
        let mut messages = Vec::new();
        for segment in &self.segments {
            if !segment.reasoning.trim().is_empty() {
                messages.push(crate::session::SessionAppendMessage {
                    role: "reasoning".to_string(),
                    content: segment.reasoning.clone(),
                    interrupted,
                    turn_id: Some(self.turn_id.clone()),
                });
            }
            if !segment.tool_calls.is_empty() {
                messages.push(crate::session::SessionAppendMessage {
                    role: "tool_calls".to_string(),
                    content: serde_json::json!({ "calls": segment.tool_calls }).to_string(),
                    interrupted,
                    turn_id: Some(self.turn_id.clone()),
                });
            }
            if !segment.content.trim().is_empty() {
                messages.push(crate::session::SessionAppendMessage {
                    role: "assistant".to_string(),
                    content: segment.content.clone(),
                    interrupted,
                    turn_id: Some(self.turn_id.clone()),
                });
            }
        }
        messages
    }

    /// Re-write the current turn's tail in session history. Idempotent: any
    /// previously-written checkpoint for this turn is replaced by the latest
    /// snapshot. Called on each tool-call boundary so an abrupt process kill
    /// still leaves the turn-so-far in history (marked interrupted).
    pub(crate) fn checkpoint(&self, files_dir: &str, session_key_json: &str, interrupted: bool) {
        let messages = self.snapshot_messages(interrupted);
        if messages.is_empty() {
            return;
        }
        let _ = crate::session::replace_turn_segment(
            files_dir,
            session_key_json,
            &self.turn_id,
            &messages,
        );
    }
}

pub(crate) fn persist_turn_history_segments(
    files_dir: &str,
    session_key_json: &str,
    recorder: &TurnHistoryRecorder,
    interrupted: bool,
) {
    recorder.checkpoint(files_dir, session_key_json, interrupted);
}
