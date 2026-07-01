//! Streaming-mode turn execution: drive the tool loop (or external agent
//! engine) while emitting each event incrementally through the caller's sink.
//! See [`collected`](super::collected) for the collect-then-return counterpart.

use super::checkpoint_after_event;
use crate::turn::{
    PromptPlanSummary, TurnInput, TurnLifecycleContext, TurnLifecycleHooks, TurnMode,
    TurnOutcomeSummary, TurnStage, chat_error, finish_cancelled_turn, finish_successful_turn,
    persist_turn_history_segments, prepare_turn_with_hooks,
    reprepare_turn_after_context_overflow_with_hooks, tool_execution_context,
    turn_history_recorder_for,
};
use crate::types::ChatEvent;

pub(crate) async fn stream_turn_with_hooks<H, E, C>(
    input: TurnInput,
    hooks: &mut H,
    mut emit: E,
    is_cancelled: C,
) where
    H: TurnLifecycleHooks + ?Sized,
    E: FnMut(ChatEvent),
    C: Fn() -> bool,
{
    let TurnInput {
        files_dir,
        workspace_files_dir,
        config_json,
        agent_id,
        session_key_json,
        message,
        display_message,
        attachments_json,
        tools,
        max_iterations,
        extra_tools,
        internal_tool_handler,
        is_group_context,
        agent_engine,
    } = input;
    let mut context = TurnLifecycleContext::new(TurnMode::Streaming, &agent_id, is_group_context);

    let prepared = {
        let mut prepare_hooks = StreamingPrepareHooks {
            inner: hooks,
            emit: &mut emit,
            is_cancelled: &is_cancelled,
        };
        match prepare_turn_with_hooks(
            &files_dir,
            &workspace_files_dir,
            &config_json,
            &agent_id,
            &session_key_json,
            &message,
            display_message.as_deref(),
            &attachments_json,
            tools.as_ref(),
            &extra_tools,
            is_group_context,
            &mut context,
            &mut prepare_hooks,
        )
        .await
        {
            Ok(prepared) => prepared,
            Err(event) => {
                emit(event);
                return;
            }
        }
    };

    let _human_loop_guard =
        crate::human_loop::activate_session_scoped(&files_dir, &session_key_json);
    let turn_tool_execution_context = tool_execution_context(
        &files_dir,
        &workspace_files_dir,
        &agent_id,
        &session_key_json,
    );
    let mut history_recorder = turn_history_recorder_for(TurnMode::Streaming);
    for event in prepared.context_events.clone() {
        if !is_cancelled() {
            emit(event);
        }
    }

    let external_plan = match crate::agent_engine::external_host_turn_plan(
        agent_engine.as_ref(),
        &prepared,
        tools.as_ref(),
        &files_dir,
        &workspace_files_dir,
        &agent_id,
        &session_key_json,
        &message,
        &attachments_json,
        &config_json,
    ) {
        Ok(plan) => plan,
        Err(error) => {
            hooks.stage_failed(&context, TurnStage::ExecuteToolLoop, &error);
            emit(chat_error(error));
            return;
        }
    };
    if let Some(external_plan) = external_plan {
        hooks.stage_started(&context, TurnStage::ExecuteToolLoop);
        let external_events = crate::agent_engine::run_external_host_turn(
            external_plan.request,
            external_plan.bridge,
            |_| {},
            &is_cancelled,
        )
        .await;
        let has_error = external_events
            .iter()
            .any(|event| matches!(event, ChatEvent::Error { .. }));
        let content = crate::agent_engine::final_content_from_events(&external_events);
        for event in crate::agent_engine::visible_external_events(external_events) {
            history_recorder.record(&event);
            if !is_cancelled() || event_survives_cancel(&event) {
                emit(event);
            }
        }
        if has_error {
            hooks.stage_failed(
                &context,
                TurnStage::ExecuteToolLoop,
                "External agent engine failed",
            );
            persist_turn_history_segments(&files_dir, &session_key_json, &history_recorder, true);
            return;
        }
        hooks.stage_completed(&context, TurnStage::ExecuteToolLoop);
        let outcome = finish_successful_turn(
            &files_dir,
            &workspace_files_dir,
            &agent_id,
            &session_key_json,
            &message,
            prepared,
            content,
            0,
            &mut history_recorder,
            &context,
            hooks,
        );
        hooks.turn_completed(&context, &outcome.summary());
        for event in outcome.into_emitted_events() {
            if !is_cancelled() || event_survives_cancel(&event) {
                emit(event);
            }
        }
        return;
    }

    hooks.stage_started(&context, TurnStage::ExecuteToolLoop);
    let skill_load_tool_active = !prepared.prompt_plan.skill_catalog_names.is_empty();
    let mut loop_extra_tools = extra_tools.clone();
    let loop_internal_tool_handler = if skill_load_tool_active {
        loop_extra_tools.push(crate::skills::skill_load_descriptor());
        Some(crate::skills::skill_load_handler(
            files_dir.clone(),
            agent_id.clone(),
            prepared.thread_id.clone(),
            prepared.prompt_plan.skill_catalog_names.clone(),
            prepared.prompt_plan.skill_catalog_hashes.clone(),
            prepared.config.response_language.clone(),
            internal_tool_handler.clone(),
        ))
    } else {
        internal_tool_handler.clone()
    };
    match crate::tool_loop::run_tool_loop_streaming(
        &prepared.config,
        &prepared.history,
        Some(prepared.raw_history.clone()),
        tools.clone(),
        max_iterations,
        loop_extra_tools,
        loop_internal_tool_handler,
        Some(turn_tool_execution_context),
        |event| {
            history_recorder.record(&event);
            if checkpoint_after_event(&event) {
                history_recorder.checkpoint(&files_dir, &session_key_json, true);
            }
            if !is_cancelled() || event_survives_cancel(&event) {
                emit(event);
            }
        },
        &is_cancelled,
    )
    .await
    {
        Ok(turn_result) => {
            if is_cancelled() {
                hooks.stage_failed(&context, TurnStage::ExecuteToolLoop, "Chat cancelled");
                let response_event = ChatEvent::Response {
                    content: turn_result.content,
                };
                history_recorder.record(&response_event);
                finish_cancelled_turn(
                    &files_dir,
                    &session_key_json,
                    &mut history_recorder,
                    prepared.config.interrupt_marker_enabled,
                    &context,
                    hooks,
                );
                emit(ChatEvent::Interrupted);
                return;
            }
            hooks.stage_completed(&context, TurnStage::ExecuteToolLoop);
            crate::context::record_last_prompt_snapshot(
                &files_dir,
                &prepared.thread_id,
                &prepared.config,
                turn_result.usage.as_ref(),
            );
            let outcome = finish_successful_turn(
                &files_dir,
                &workspace_files_dir,
                &agent_id,
                &session_key_json,
                &message,
                prepared,
                turn_result.content,
                turn_result.tool_call_count,
                &mut history_recorder,
                &context,
                hooks,
            );
            debug_assert_eq!(outcome.tool_call_count, turn_result.tool_call_count);
            hooks.turn_completed(&context, &outcome.summary());
            for event in outcome.into_emitted_events() {
                emit(event);
            }
        }
        Err(e) if e == "Chat cancelled" || is_cancelled() => {
            hooks.stage_failed(&context, TurnStage::ExecuteToolLoop, "Chat cancelled");
            finish_cancelled_turn(
                &files_dir,
                &session_key_json,
                &mut history_recorder,
                prepared.config.interrupt_marker_enabled,
                &context,
                hooks,
            );
            emit(ChatEvent::Interrupted);
        }
        Err(e) => {
            if crate::llm::is_context_overflow_error(&e)
                && history_recorder.is_empty()
                && !is_cancelled()
            {
                hooks.stage_warning(
                    &context,
                    TurnStage::ExecuteToolLoop,
                    "Provider reported context overflow; compacting and retrying once",
                );
                emit(ChatEvent::Thinking {
                    content: "Compacting context and retrying the request...".to_string(),
                });
                crate::context::record_overflow_recovery_snapshot(
                    &files_dir,
                    &prepared.thread_id,
                    &prepared.config,
                    false,
                    0,
                    "overflow_retry_compacting",
                    None,
                );
                let retry_prepared = {
                    let mut prepare_hooks = StreamingPrepareHooks {
                        inner: hooks,
                        emit: &mut emit,
                        is_cancelled: &is_cancelled,
                    };
                    match reprepare_turn_after_context_overflow_with_hooks(
                        &files_dir,
                        &workspace_files_dir,
                        &config_json,
                        &agent_id,
                        &session_key_json,
                        &message,
                        &attachments_json,
                        tools.as_ref(),
                        &extra_tools,
                        is_group_context,
                        &mut context,
                        &mut prepare_hooks,
                    )
                    .await
                    {
                        Ok(prepared) => prepared,
                        Err(event) => {
                            crate::context::record_overflow_recovery_snapshot(
                                &files_dir,
                                &prepared.thread_id,
                                &prepared.config,
                                false,
                                1,
                                "overflow_retry_failed",
                                Some("Context compaction failed before retry"),
                            );
                            hooks.stage_failed(
                                &context,
                                TurnStage::ExecuteToolLoop,
                                "Context overflow recovery failed before retry",
                            );
                            emit(event);
                            return;
                        }
                    }
                };
                for event in retry_prepared.context_events.clone() {
                    if !is_cancelled() {
                        emit(event);
                    }
                }
                let retry_skill_load_tool_active =
                    !retry_prepared.prompt_plan.skill_catalog_names.is_empty();
                let mut retry_extra_tools = extra_tools.clone();
                let retry_internal_tool_handler = if retry_skill_load_tool_active {
                    retry_extra_tools.push(crate::skills::skill_load_descriptor());
                    Some(crate::skills::skill_load_handler(
                        files_dir.clone(),
                        agent_id.clone(),
                        retry_prepared.thread_id.clone(),
                        retry_prepared.prompt_plan.skill_catalog_names.clone(),
                        retry_prepared.prompt_plan.skill_catalog_hashes.clone(),
                        retry_prepared.config.response_language.clone(),
                        internal_tool_handler.clone(),
                    ))
                } else {
                    internal_tool_handler.clone()
                };
                let retry_tool_execution_context = tool_execution_context(
                    &files_dir,
                    &workspace_files_dir,
                    &agent_id,
                    &session_key_json,
                );
                match crate::tool_loop::run_tool_loop_streaming(
                    &retry_prepared.config,
                    &retry_prepared.history,
                    Some(retry_prepared.raw_history.clone()),
                    tools.clone(),
                    max_iterations,
                    retry_extra_tools,
                    retry_internal_tool_handler,
                    Some(retry_tool_execution_context),
                    |event| {
                        history_recorder.record(&event);
                        if checkpoint_after_event(&event) {
                            history_recorder.checkpoint(&files_dir, &session_key_json, true);
                        }
                        if !is_cancelled() || event_survives_cancel(&event) {
                            emit(event);
                        }
                    },
                    &is_cancelled,
                )
                .await
                {
                    Ok(turn_result) => {
                        if is_cancelled() {
                            hooks.stage_failed(
                                &context,
                                TurnStage::ExecuteToolLoop,
                                "Chat cancelled",
                            );
                            let response_event = ChatEvent::Response {
                                content: turn_result.content,
                            };
                            history_recorder.record(&response_event);
                            finish_cancelled_turn(
                                &files_dir,
                                &session_key_json,
                                &mut history_recorder,
                                retry_prepared.config.interrupt_marker_enabled,
                                &context,
                                hooks,
                            );
                            emit(ChatEvent::Interrupted);
                            return;
                        }
                        hooks.stage_completed(&context, TurnStage::ExecuteToolLoop);
                        crate::context::record_overflow_recovery_snapshot(
                            &files_dir,
                            &retry_prepared.thread_id,
                            &retry_prepared.config,
                            true,
                            1,
                            "overflow_retry_succeeded",
                            None,
                        );
                        crate::context::record_last_prompt_snapshot(
                            &files_dir,
                            &retry_prepared.thread_id,
                            &retry_prepared.config,
                            turn_result.usage.as_ref(),
                        );
                        let outcome = finish_successful_turn(
                            &files_dir,
                            &workspace_files_dir,
                            &agent_id,
                            &session_key_json,
                            &message,
                            retry_prepared,
                            turn_result.content,
                            turn_result.tool_call_count,
                            &mut history_recorder,
                            &context,
                            hooks,
                        );
                        debug_assert_eq!(outcome.tool_call_count, turn_result.tool_call_count);
                        hooks.turn_completed(&context, &outcome.summary());
                        for event in outcome.into_emitted_events() {
                            emit(event);
                        }
                    }
                    Err(retry_error) => {
                        crate::context::record_overflow_recovery_snapshot(
                            &files_dir,
                            &retry_prepared.thread_id,
                            &retry_prepared.config,
                            false,
                            1,
                            "overflow_retry_failed",
                            Some(&retry_error),
                        );
                        hooks.stage_failed(&context, TurnStage::ExecuteToolLoop, &retry_error);
                        emit(chat_error(format!(
                            "Chat error: context overflow recovery failed after retry: {retry_error}"
                        )));
                    }
                }
            } else {
                if crate::llm::is_context_overflow_error(&e) {
                    crate::context::record_overflow_recovery_snapshot(
                        &files_dir,
                        &prepared.thread_id,
                        &prepared.config,
                        false,
                        0,
                        "overflow_retry_skipped_after_partial_turn",
                        Some(&e),
                    );
                }
                hooks.stage_failed(&context, TurnStage::ExecuteToolLoop, &e);
                emit(chat_error(format!("Chat error: {e}")));
            }
        }
    }
}

struct StreamingPrepareHooks<'a, H: ?Sized, E, C> {
    inner: &'a mut H,
    emit: &'a mut E,
    is_cancelled: &'a C,
}

impl<H, E, C> TurnLifecycleHooks for StreamingPrepareHooks<'_, H, E, C>
where
    H: TurnLifecycleHooks + ?Sized,
    E: FnMut(ChatEvent),
    C: Fn() -> bool,
{
    fn stage_started(&mut self, context: &TurnLifecycleContext, stage: TurnStage) {
        self.inner.stage_started(context, stage);
    }

    fn stage_completed(&mut self, context: &TurnLifecycleContext, stage: TurnStage) {
        self.inner.stage_completed(context, stage);
    }

    fn stage_warning(&mut self, context: &TurnLifecycleContext, stage: TurnStage, message: &str) {
        self.inner.stage_warning(context, stage, message);
    }

    fn stage_failed(&mut self, context: &TurnLifecycleContext, stage: TurnStage, message: &str) {
        self.inner.stage_failed(context, stage, message);
    }

    fn prompt_prepared(&mut self, context: &TurnLifecycleContext, summary: &PromptPlanSummary) {
        self.inner.prompt_prepared(context, summary);
    }

    fn context_event(&mut self, context: &TurnLifecycleContext, event: &ChatEvent) -> bool {
        let already_delivered = self.inner.context_event(context, event);
        if already_delivered {
            return true;
        }
        if (self.is_cancelled)() {
            return false;
        }
        (self.emit)(event.clone());
        true
    }

    fn turn_completed(&mut self, context: &TurnLifecycleContext, summary: &TurnOutcomeSummary) {
        self.inner.turn_completed(context, summary);
    }
}

/// Decide whether `event` should still reach the UI after the user has
/// cancelled the turn. Terminal events for in-flight work (tool results,
/// errors, the interrupted marker) must always pass so the UI can flip a
/// running tool out of its spinner state. Progress events (deltas, thinking,
/// new tool calls, compaction notices) are suppressed because they only
/// represent work the user no longer wants.
fn event_survives_cancel(event: &ChatEvent) -> bool {
    matches!(
        event,
        ChatEvent::ToolResult { .. }
            | ChatEvent::AgentToolResult { .. }
            | ChatEvent::GroupDelegationResult { .. }
            | ChatEvent::AgentDelegationResult { .. }
            | ChatEvent::Error { .. }
            | ChatEvent::Interrupted
            | ChatEvent::HumanResponse { .. }
    )
}

#[cfg(test)]
mod cancel_gate_tests {
    use super::*;

    #[test]
    fn terminal_events_survive_cancel() {
        assert!(event_survives_cancel(&ChatEvent::ToolResult {
            call_id: "c".into(),
            name: "shell".into(),
            output: "killed".into(),
            is_error: true,
        }));
        assert!(event_survives_cancel(&ChatEvent::Interrupted));
        assert!(event_survives_cancel(&ChatEvent::Error {
            message: "boom".into(),
        }));
        assert!(event_survives_cancel(&ChatEvent::AgentToolResult {
            call_id: "c".into(),
            name: "shell".into(),
            output: "killed".into(),
            is_error: true,
            agent_id: "a".into(),
        }));
    }

    #[test]
    fn progress_events_are_dropped_on_cancel() {
        assert!(!event_survives_cancel(&ChatEvent::ResponseDelta {
            content: "still thinking".into(),
        }));
        assert!(!event_survives_cancel(&ChatEvent::ReasoningDelta {
            content: "ditto".into(),
        }));
        assert!(!event_survives_cancel(&ChatEvent::Thinking {
            content: "noise".into(),
        }));
        assert!(!event_survives_cancel(&ChatEvent::ToolCall {
            call_id: "c".into(),
            name: "shell".into(),
            arguments: "{}".into(),
        }));
        assert!(!event_survives_cancel(&ChatEvent::ToolOutputChunk {
            call_id: "c".into(),
            content: "x".into(),
            stream: "stdout".into(),
        }));
    }
}
