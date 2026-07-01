use std::collections::HashMap;

use crate::llm::LlmStreamEvent;
use crate::tool_registry::ToolEffect;
use crate::types::ChatEvent;

#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct ToolTrace {
    pub reasoning: String,
    pub tool_calls: Vec<ToolTraceCall>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ToolTraceCall {
    pub call_id: String,
    pub name: String,
    pub arguments: String,
    pub effect: ToolEffect,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Default)]
pub(super) struct StreamingToolCallState {
    calls: HashMap<usize, StreamingToolCallPreview>,
}

#[derive(Default)]
struct StreamingToolCallPreview {
    call_id: Option<String>,
    name: String,
    arguments: String,
}

impl ToolTrace {
    pub(crate) fn push_reasoning(&mut self, content: &str) {
        if !content.trim().is_empty() {
            self.reasoning.push_str(content);
        }
    }

    /// Drop reasoning text accumulated during a stream attempt that was aborted
    /// and is being retried, so the persisted trace reflects only the attempt
    /// that actually completed.
    pub(crate) fn reset_reasoning(&mut self) {
        self.reasoning.clear();
    }

    pub(crate) fn push_tool_call(
        &mut self,
        call_id: String,
        name: String,
        arguments: String,
        effect: ToolEffect,
    ) {
        self.tool_calls.push(ToolTraceCall {
            call_id,
            name,
            arguments,
            effect,
            result: None,
            error: None,
        });
    }

    pub(crate) fn finish_tool_call(&mut self, call_id: &str, output: String, is_error: bool) {
        if let Some(call) = self
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
        }
    }
}

pub(super) fn emit_stream_event<F>(
    emit: &mut F,
    event: LlmStreamEvent,
    tool_call_state: Option<&mut StreamingToolCallState>,
) where
    F: FnMut(ChatEvent),
{
    match event {
        LlmStreamEvent::ResponseDelta(content) => {
            emit(ChatEvent::ResponseDelta { content });
        }
        LlmStreamEvent::ReasoningDelta(content) => {
            emit(ChatEvent::ReasoningDelta { content });
        }
        LlmStreamEvent::StreamReset { reason } => {
            // The aborted attempt's partial tool-call previews are stale; drop
            // them so the reconnected stream rebuilds indices from scratch.
            if let Some(state) = tool_call_state {
                state.calls.clear();
            }
            emit(ChatEvent::StreamReset { reason });
        }
        LlmStreamEvent::ToolCallDelta {
            index,
            id,
            name,
            arguments_delta,
        } => {
            let Some(state) = tool_call_state else {
                return;
            };
            let preview = state.calls.entry(index).or_default();
            if let Some(id) = id
                && !id.is_empty()
            {
                preview.call_id = Some(id);
            }
            if let Some(name) = name
                && !name.is_empty()
            {
                preview.name.push_str(&name);
            }
            preview.arguments.push_str(&arguments_delta);
            if preview.name.is_empty() && preview.arguments.is_empty() {
                return;
            }
            if crate::skills::SKILL_LOAD_TOOL_NAME.starts_with(preview.name.as_str())
                || crate::skills::is_hidden_skill_tool(&preview.name)
            {
                return;
            }
            emit(ChatEvent::ToolCallDelta {
                call_id: preview
                    .call_id
                    .clone()
                    .unwrap_or_else(|| format!("pending-tool-call-{index}")),
                name: preview.name.clone(),
                arguments_delta,
                arguments_so_far: preview.arguments.clone(),
            });
        }
    }
}

pub(super) fn emit_stream_event_with_trace<F>(
    emit: &mut F,
    trace: &mut ToolTrace,
    event: LlmStreamEvent,
    tool_call_state: Option<&mut StreamingToolCallState>,
) where
    F: FnMut(ChatEvent),
{
    if let LlmStreamEvent::ReasoningDelta(content) = &event {
        trace.push_reasoning(content);
    }
    if matches!(event, LlmStreamEvent::StreamReset { .. }) {
        trace.reset_reasoning();
    }
    emit_stream_event(emit, event, tool_call_state);
}
