//! Napaxi-owned mobile LLM tool loop orchestration.

use std::sync::Arc;

use crate::llm;
use crate::session::SessionMessage;
use crate::tool_registry::{ToolDescriptor, ToolExecutionContext, ToolRegistry};
use crate::types::{ChatEvent, PlatformLlmConfig};

#[path = "loop/descriptors.rs"]
mod descriptors;
#[path = "loop/execution.rs"]
mod execution;
#[path = "loop/limits.rs"]
mod limits;
#[path = "loop/runtime.rs"]
mod runtime;
#[path = "loop/trace.rs"]
mod trace;
#[path = "loop/types.rs"]
mod types;

#[allow(unused_imports)]
pub use descriptors::gather_tool_descriptors;
use descriptors::tool_descriptors;
pub use descriptors::{gather_tool_descriptors_for_config, has_tool_named};
pub(crate) use execution::execute_single_tool_call_for_broker;
use execution::{
    append_tool_limit_final_message, drain_interjections_into_messages, execute_turn_tool_calls,
    tool_limit_extra_tool_error, tool_limit_synthesis_error,
};
use limits::resolved_tool_turn_limit;
#[allow(unused_imports)]
pub use limits::tool_turn_limit;
pub use trace::ToolTrace;
#[allow(unused_imports)]
pub use trace::ToolTraceCall;
use trace::{StreamingToolCallState, emit_stream_event, emit_stream_event_with_trace};
#[allow(unused_imports)]
pub use types::InternalToolFuture;
pub use types::{
    InternalToolHandler, InternalToolProgressEvent, InternalToolProgressSender, InternalToolResult,
    ToolLoopResult, current_tool_call_cancel,
};

const INTERNAL_HIDDEN_TOOL_TURN_LIMIT: usize = 8;
const PRIVATE_SKILL_LEAK_ERROR: &str = "The model exposed private skill implementation commands instead of executing through tools; the turn was stopped to avoid leaking skill internals.";

#[derive(Debug, Clone, PartialEq, Eq)]
enum SkillProtocolToolGate {
    UseTurn(llm::LlmTurn),
    Retry,
}

fn turn_has_visible_tool_calls(turn: &llm::LlmTurn) -> bool {
    turn.tool_calls
        .iter()
        .any(|call| !crate::skills::is_hidden_skill_tool(&call.name))
}

fn descriptors_for_skill_protocol(
    system_prompt: &str,
    messages: &[serde_json::Value],
    descriptors: &[ToolDescriptor],
) -> Vec<ToolDescriptor> {
    let context =
        crate::skills::private_skill_context_from_system_and_messages(system_prompt, messages);
    if !crate::skills::should_gate_visible_tools_for_skill_protocol(&context)
        || !descriptors
            .iter()
            .any(|descriptor| crate::skills::is_hidden_skill_tool(&descriptor.name))
    {
        return descriptors.to_vec();
    }
    descriptors
        .iter()
        .filter(|descriptor| crate::skills::is_hidden_skill_tool(&descriptor.name))
        .cloned()
        .collect()
}

fn maybe_gate_visible_tools_for_skill_protocol<F>(
    system_prompt: &str,
    messages: &mut Vec<serde_json::Value>,
    trace: &mut ToolTrace,
    turn: llm::LlmTurn,
    skill_load_correction_attempted: &mut bool,
    emit: &mut F,
) -> Result<SkillProtocolToolGate, String>
where
    F: FnMut(ChatEvent),
{
    let private_skill_context =
        crate::skills::private_skill_context_from_system_and_messages(system_prompt, messages);
    if !crate::skills::should_gate_visible_tools_for_skill_protocol(&private_skill_context)
        || !turn_has_visible_tool_calls(&turn)
    {
        return Ok(SkillProtocolToolGate::UseTurn(turn));
    }

    let hidden_tool_calls = turn
        .tool_calls
        .iter()
        .filter(|call| crate::skills::is_hidden_skill_tool(&call.name))
        .cloned()
        .collect::<Vec<_>>();
    if !hidden_tool_calls.is_empty() {
        let notice = "The model requested skill_load together with visible tools. Loading the skill first, then asking the model to choose tools again from the full skill context.";
        trace.push_reasoning(notice);
        emit(ChatEvent::Thinking {
            content: notice.to_string(),
        });
        return Ok(SkillProtocolToolGate::UseTurn(llm::LlmTurn {
            content: String::new(),
            reasoning_content: turn.reasoning_content,
            tool_calls: hidden_tool_calls,
            usage: turn.usage,
        }));
    }

    if *skill_load_correction_attempted {
        let notice = "The model still chose visible tools after the skill-load correction. Treating the matched skill as not applicable and continuing with the requested tools.";
        trace.push_reasoning(notice);
        emit(ChatEvent::Thinking {
            content: notice.to_string(),
        });
        return Ok(SkillProtocolToolGate::UseTurn(turn));
    }
    *skill_load_correction_attempted = true;
    let notice = "The current task matches an available skill, but the model requested visible tools before loading the skill. Correcting the turn to follow the skill lazy-load protocol.";
    trace.push_reasoning(notice);
    emit(ChatEvent::Thinking {
        content: notice.to_string(),
    });
    messages.push(
        crate::skills::private_skill_load_required_correction_message(&private_skill_context),
    );
    Ok(SkillProtocolToolGate::Retry)
}

fn maybe_correct_private_skill_command_leak<F>(
    system_prompt: &str,
    messages: &mut Vec<serde_json::Value>,
    trace: &mut ToolTrace,
    content: &str,
    leak_correction_attempted: &mut bool,
    skill_load_correction_attempted: &mut bool,
    emit: &mut F,
) -> Result<bool, String>
where
    F: FnMut(ChatEvent),
{
    let private_skill_context =
        crate::skills::private_skill_context_from_system_and_messages(system_prompt, messages);
    if crate::skills::should_require_skill_load_for_matched_candidate(&private_skill_context)
        && !*skill_load_correction_attempted
    {
        *skill_load_correction_attempted = true;
        let notice = "The current task matches an available skill, but the model drafted an answer before loading the skill. Correcting the turn to follow the skill lazy-load protocol.";
        trace.push_reasoning(notice);
        emit(ChatEvent::Thinking {
            content: notice.to_string(),
        });
        messages.push(
            crate::skills::private_skill_load_required_correction_message(&private_skill_context),
        );
        return Ok(true);
    }
    if !crate::skills::should_correct_private_skill_command_leak(&private_skill_context, content) {
        return Ok(false);
    }
    if *leak_correction_attempted {
        return Err(PRIVATE_SKILL_LEAK_ERROR.to_string());
    }
    *leak_correction_attempted = true;
    let notice = "A loaded skill produced a draft that exposed private implementation commands. Correcting the turn before sending a final answer.";
    trace.push_reasoning(notice);
    emit(ChatEvent::Thinking {
        content: notice.to_string(),
    });
    messages.push(crate::skills::private_skill_command_correction_message());
    Ok(true)
}

fn compact_messages_for_context(
    messages: &mut [serde_json::Value],
    config: &PlatformLlmConfig,
    descriptor_tokens: usize,
    tool_execution_context: Option<&ToolExecutionContext>,
) {
    let stats = crate::context::compact_tool_messages(messages, config, descriptor_tokens);
    if stats.is_empty() {
        return;
    }
    let Some(context) = tool_execution_context else {
        return;
    };
    let Some(session_key_json) = context.session_key_json.as_deref() else {
        return;
    };
    crate::context::record_tool_compaction_snapshot_for_session(
        &context.files_dir,
        session_key_json,
        config,
        stats,
    );
}

pub async fn run_tool_loop<F>(
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
    raw_history: Option<Vec<serde_json::Value>>,
    tools: Option<Arc<ToolRegistry>>,
    max_iterations: i32,
    extra_tools: Vec<ToolDescriptor>,
    internal_tool_handler: Option<InternalToolHandler>,
    tool_execution_context: Option<ToolExecutionContext>,
    mut emit: F,
) -> Result<ToolLoopResult, String>
where
    F: FnMut(ChatEvent),
{
    let mut descriptors = tool_descriptors(config, tools.as_ref(), extra_tools.clone()).await;
    if descriptors.is_empty() {
        let mut usage = None;
        let content = if let Some(mut messages) = raw_history {
            compact_messages_for_context(&mut messages, config, 0, tool_execution_context.as_ref());
            let turn = llm::complete_turn_with_raw_messages(config, &messages, &[])
                .await
                .map_err(|e| e.to_string())?;
            usage = turn.usage.clone();
            if let Some(reasoning) = turn.reasoning_content.as_deref() {
                emit(ChatEvent::ReasoningDelta {
                    content: reasoning.to_string(),
                });
            }
            turn.content
        } else {
            llm::complete_with_history(config, history)
                .await
                .map_err(|e| e.to_string())?
        };
        emit(ChatEvent::ResponseDelta {
            content: content.clone(),
        });
        return Ok(ToolLoopResult {
            content,
            tool_call_count: 0,
            usage,
            trace: ToolTrace::default(),
        });
    }

    let mut messages =
        raw_history.unwrap_or_else(|| llm::openai_messages_from_mobile_history(history));
    let limit = resolved_tool_turn_limit(max_iterations, config.max_tool_iterations);
    let mut tool_call_count = 0usize;
    let mut budgeted_tool_turns = 0usize;
    let mut hidden_only_tool_turns = 0usize;
    let mut leak_correction_attempted = false;
    let mut skill_load_correction_attempted = false;
    let mut trace = ToolTrace::default();
    let mut last_usage: Option<llm::LlmUsage>;
    while budgeted_tool_turns < limit {
        descriptors = tool_descriptors(config, tools.as_ref(), extra_tools.clone()).await;
        drain_interjections_into_messages(
            tool_execution_context.as_ref(),
            &mut messages,
            &mut emit,
        );
        let descriptor_tokens = crate::context::estimate_json_tokens(&descriptors);
        compact_messages_for_context(
            &mut messages,
            config,
            descriptor_tokens,
            tool_execution_context.as_ref(),
        );
        let active_descriptors =
            descriptors_for_skill_protocol(&config.system_prompt, &messages, &descriptors);
        let turn = llm::complete_turn_with_raw_messages(config, &messages, &active_descriptors)
            .await
            .map_err(|e| e.to_string())?;
        last_usage = turn.usage.clone();
        if let Some(reasoning) = turn.reasoning_content.as_deref() {
            trace.push_reasoning(reasoning);
            emit(ChatEvent::ReasoningDelta {
                content: reasoning.to_string(),
            });
        }
        if turn.tool_calls.is_empty() {
            if maybe_correct_private_skill_command_leak(
                &config.system_prompt,
                &mut messages,
                &mut trace,
                &turn.content,
                &mut leak_correction_attempted,
                &mut skill_load_correction_attempted,
                &mut emit,
            )? {
                continue;
            }
            if !turn.content.is_empty() {
                emit(ChatEvent::ResponseDelta {
                    content: turn.content.clone(),
                });
            }
            return Ok(ToolLoopResult {
                content: turn.content,
                tool_call_count,
                usage: last_usage,
                trace,
            });
        }
        let turn = match maybe_gate_visible_tools_for_skill_protocol(
            &config.system_prompt,
            &mut messages,
            &mut trace,
            turn,
            &mut skill_load_correction_attempted,
            &mut emit,
        )? {
            SkillProtocolToolGate::UseTurn(turn) => turn,
            SkillProtocolToolGate::Retry => continue,
        };
        let has_visible_tool_calls = turn_has_visible_tool_calls(&turn);
        if has_visible_tool_calls {
            budgeted_tool_turns = budgeted_tool_turns.saturating_add(1);
            hidden_only_tool_turns = 0;
        } else {
            hidden_only_tool_turns = hidden_only_tool_turns.saturating_add(1);
            if hidden_only_tool_turns > INTERNAL_HIDDEN_TOOL_TURN_LIMIT {
                return Err(format!(
                    "Internal skill loading exceeded {INTERNAL_HIDDEN_TOOL_TURN_LIMIT} consecutive model turns"
                ));
            }
        }
        let executed_tool_count = execute_turn_tool_calls(
            turn,
            config,
            tools.as_ref(),
            internal_tool_handler.as_ref(),
            &active_descriptors,
            tool_execution_context.as_ref(),
            &mut messages,
            &mut trace,
            false,
            || false,
            &mut emit,
        )
        .await?;
        tool_call_count = tool_call_count.saturating_add(executed_tool_count);
        drain_interjections_into_messages(
            tool_execution_context.as_ref(),
            &mut messages,
            &mut emit,
        );
    }

    emit(ChatEvent::Thinking {
        content: format!(
            "Tool execution reached the configured limit after {limit} visible tool turns; composing a final response from the gathered results."
        ),
    });
    append_tool_limit_final_message(&mut messages, limit);
    compact_messages_for_context(&mut messages, config, 0, tool_execution_context.as_ref());
    let turn = llm::complete_turn_with_raw_messages(config, &messages, &[])
        .await
        .map_err(|e| tool_limit_synthesis_error(limit, e))?;
    last_usage = turn.usage.clone();
    if let Some(reasoning) = turn.reasoning_content.as_deref() {
        trace.push_reasoning(reasoning);
        emit(ChatEvent::ReasoningDelta {
            content: reasoning.to_string(),
        });
    }
    if !turn.tool_calls.is_empty() {
        return Err(tool_limit_extra_tool_error(limit));
    }
    let mut final_leak_correction_attempted = true;
    let mut final_skill_load_correction_attempted = true;
    maybe_correct_private_skill_command_leak(
        &config.system_prompt,
        &mut messages,
        &mut trace,
        &turn.content,
        &mut final_leak_correction_attempted,
        &mut final_skill_load_correction_attempted,
        &mut emit,
    )?;
    if !turn.content.is_empty() {
        emit(ChatEvent::ResponseDelta {
            content: turn.content.clone(),
        });
    }
    Ok(ToolLoopResult {
        content: turn.content,
        tool_call_count,
        usage: last_usage,
        trace,
    })
}

pub async fn run_tool_loop_streaming<F, C>(
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
    raw_history: Option<Vec<serde_json::Value>>,
    tools: Option<Arc<ToolRegistry>>,
    max_iterations: i32,
    extra_tools: Vec<ToolDescriptor>,
    internal_tool_handler: Option<InternalToolHandler>,
    tool_execution_context: Option<ToolExecutionContext>,
    mut emit: F,
    mut should_cancel: C,
) -> Result<ToolLoopResult, String>
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool,
{
    let mut descriptors = tool_descriptors(config, tools.as_ref(), extra_tools.clone()).await;
    if descriptors.is_empty() {
        let mut usage = None;
        let content = if let Some(mut messages) = raw_history {
            compact_messages_for_context(&mut messages, config, 0, tool_execution_context.as_ref());
            let turn = llm::stream_turn_with_raw_messages(
                config,
                &messages,
                &[],
                |event| emit_stream_event(&mut emit, event, None),
                &mut should_cancel,
            )
            .await
            .map_err(|e| e.to_string())?;
            usage = turn.usage.clone();
            turn.content
        } else {
            llm::stream_with_history_cancelable(
                config,
                history,
                |event| emit_stream_event(&mut emit, event, None),
                &mut should_cancel,
            )
            .await
            .map_err(|e| e.to_string())?
        };
        return Ok(ToolLoopResult {
            content,
            tool_call_count: 0,
            usage,
            trace: ToolTrace::default(),
        });
    }

    let mut messages =
        raw_history.unwrap_or_else(|| llm::openai_messages_from_mobile_history(history));
    let limit = resolved_tool_turn_limit(max_iterations, config.max_tool_iterations);
    let mut tool_call_count = 0usize;
    let mut budgeted_tool_turns = 0usize;
    let mut hidden_only_tool_turns = 0usize;
    let mut leak_correction_attempted = false;
    let mut skill_load_correction_attempted = false;
    let mut trace = ToolTrace::default();
    let mut last_usage: Option<llm::LlmUsage>;
    while budgeted_tool_turns < limit {
        descriptors = tool_descriptors(config, tools.as_ref(), extra_tools.clone()).await;
        if should_cancel() {
            return Err("Chat cancelled".to_string());
        }
        drain_interjections_into_messages(
            tool_execution_context.as_ref(),
            &mut messages,
            &mut emit,
        );
        let descriptor_tokens = crate::context::estimate_json_tokens(&descriptors);
        compact_messages_for_context(
            &mut messages,
            config,
            descriptor_tokens,
            tool_execution_context.as_ref(),
        );
        let active_descriptors =
            descriptors_for_skill_protocol(&config.system_prompt, &messages, &descriptors);
        let mut tool_call_stream_state = StreamingToolCallState::default();
        let turn = llm::stream_turn_with_raw_messages(
            config,
            &messages,
            &active_descriptors,
            |event| {
                emit_stream_event_with_trace(
                    &mut emit,
                    &mut trace,
                    event,
                    Some(&mut tool_call_stream_state),
                )
            },
            &mut should_cancel,
        )
        .await
        .map_err(|e| e.to_string())?;
        last_usage = turn.usage.clone();
        if turn.tool_calls.is_empty() {
            if maybe_correct_private_skill_command_leak(
                &config.system_prompt,
                &mut messages,
                &mut trace,
                &turn.content,
                &mut leak_correction_attempted,
                &mut skill_load_correction_attempted,
                &mut emit,
            )? {
                continue;
            }
            return Ok(ToolLoopResult {
                content: turn.content,
                tool_call_count,
                usage: last_usage,
                trace,
            });
        }
        let turn = match maybe_gate_visible_tools_for_skill_protocol(
            &config.system_prompt,
            &mut messages,
            &mut trace,
            turn,
            &mut skill_load_correction_attempted,
            &mut emit,
        )? {
            SkillProtocolToolGate::UseTurn(turn) => turn,
            SkillProtocolToolGate::Retry => continue,
        };
        let has_visible_tool_calls = turn_has_visible_tool_calls(&turn);
        if has_visible_tool_calls {
            budgeted_tool_turns = budgeted_tool_turns.saturating_add(1);
            hidden_only_tool_turns = 0;
        } else {
            hidden_only_tool_turns = hidden_only_tool_turns.saturating_add(1);
            if hidden_only_tool_turns > INTERNAL_HIDDEN_TOOL_TURN_LIMIT {
                return Err(format!(
                    "Internal skill loading exceeded {INTERNAL_HIDDEN_TOOL_TURN_LIMIT} consecutive model turns"
                ));
            }
        }
        let executed_tool_count = execute_turn_tool_calls(
            turn,
            config,
            tools.as_ref(),
            internal_tool_handler.as_ref(),
            &active_descriptors,
            tool_execution_context.as_ref(),
            &mut messages,
            &mut trace,
            true,
            &mut should_cancel,
            &mut emit,
        )
        .await?;
        tool_call_count = tool_call_count.saturating_add(executed_tool_count);
        drain_interjections_into_messages(
            tool_execution_context.as_ref(),
            &mut messages,
            &mut emit,
        );
    }

    if should_cancel() {
        return Err("Chat cancelled".to_string());
    }
    emit(ChatEvent::Thinking {
        content: format!(
            "Tool execution reached the configured limit after {limit} visible tool turns; composing a final response from the gathered results."
        ),
    });
    append_tool_limit_final_message(&mut messages, limit);
    compact_messages_for_context(&mut messages, config, 0, tool_execution_context.as_ref());
    let turn = llm::stream_turn_with_raw_messages(
        config,
        &messages,
        &[],
        |event| emit_stream_event_with_trace(&mut emit, &mut trace, event, None),
        &mut should_cancel,
    )
    .await
    .map_err(|e| tool_limit_synthesis_error(limit, e))?;
    last_usage = turn.usage.clone();
    if !turn.tool_calls.is_empty() {
        return Err(tool_limit_extra_tool_error(limit));
    }
    let mut final_leak_correction_attempted = true;
    let mut final_skill_load_correction_attempted = true;
    maybe_correct_private_skill_command_leak(
        &config.system_prompt,
        &mut messages,
        &mut trace,
        &turn.content,
        &mut final_leak_correction_attempted,
        &mut final_skill_load_correction_attempted,
        &mut emit,
    )?;
    Ok(ToolLoopResult {
        content: turn.content,
        tool_call_count,
        usage: last_usage,
        trace,
    })
}

#[cfg(test)]
#[path = "loop/tests.rs"]
mod tests;
