//! Collected-mode turn execution: run the tool loop (or external agent engine)
//! to completion and return the accumulated event list. See
//! [`streaming`](super::streaming) for the incremental-emit counterpart.

use super::checkpoint_after_event;
use crate::turn::{
    TurnInput, TurnLifecycleContext, TurnLifecycleHooks, TurnMode, TurnStage, chat_error,
    finish_cancelled_turn, finish_successful_turn, persist_turn_history_segments,
    prepare_turn_with_hooks, reprepare_turn_after_context_overflow_with_hooks,
    tool_execution_context, turn_history_recorder_for,
};
use crate::types::ChatEvent;

pub(crate) async fn run_turn_with_hooks<H, C>(
    input: TurnInput,
    hooks: &mut H,
    mut is_cancelled: C,
) -> Vec<ChatEvent>
where
    H: TurnLifecycleHooks + ?Sized,
    C: FnMut() -> bool,
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
    let mut context = TurnLifecycleContext::new(TurnMode::Collected, &agent_id, is_group_context);

    let prepared = match prepare_turn_with_hooks(
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
        agent_engine.as_ref(),
        &mut context,
        hooks,
    )
    .await
    {
        Ok(prepared) => prepared,
        Err(event) => return vec![event],
    };

    let mut events = prepared.context_events.clone();
    let _human_loop_guard =
        crate::human_loop::activate_session_scoped(&files_dir, &session_key_json);
    let mut history_recorder = turn_history_recorder_for(TurnMode::Collected);
    let codex_request = match crate::agent_engine::codex_turn_plan(
        agent_engine.as_ref(),
        &prepared,
        tools.as_ref(),
        internal_tool_handler.as_ref(),
        &files_dir,
        &workspace_files_dir,
        &agent_id,
        &session_key_json,
        &message,
        &config_json,
    ) {
        Ok(request) => request,
        Err(error) => {
            hooks.stage_failed(&context, TurnStage::ExecuteToolLoop, &error);
            events.push(chat_error(error));
            return events;
        }
    };
    if let Some(codex_request) = codex_request {
        hooks.stage_started(&context, TurnStage::ExecuteToolLoop);
        let codex_events =
            crate::agent_engine::codex::run_codex_turn(codex_request, |_| {}, &mut is_cancelled)
                .await;
        let has_failure = codex_events
            .iter()
            .any(|event| matches!(event, ChatEvent::Error { .. } | ChatEvent::Interrupted));
        let content = crate::agent_engine::final_content_from_events(&codex_events);
        for event in crate::agent_engine::visible_external_events(codex_events) {
            history_recorder.record(&event);
            events.push(event);
        }
        if has_failure {
            hooks.stage_failed(
                &context,
                TurnStage::ExecuteToolLoop,
                "Codex agent engine failed or was interrupted",
            );
            persist_turn_history_segments(&files_dir, &session_key_json, &history_recorder, true);
            return events;
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
        events.extend(outcome.into_emitted_events());
        return events;
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
            events.push(chat_error(error));
            return events;
        }
    };
    if let Some(external_plan) = external_plan {
        hooks.stage_started(&context, TurnStage::ExecuteToolLoop);
        let external_events = crate::agent_engine::run_external_host_turn(
            external_plan.request,
            external_plan.bridge,
            |_| {},
            &mut is_cancelled,
        )
        .await;
        let has_error = external_events
            .iter()
            .any(|event| matches!(event, ChatEvent::Error { .. }));
        let content = crate::agent_engine::final_content_from_events(&external_events);
        for event in crate::agent_engine::visible_external_events(external_events) {
            history_recorder.record(&event);
            events.push(event);
        }
        if has_error {
            hooks.stage_failed(
                &context,
                TurnStage::ExecuteToolLoop,
                "External agent engine failed",
            );
            persist_turn_history_segments(&files_dir, &session_key_json, &history_recorder, true);
            return events;
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
        events.extend(outcome.into_emitted_events());
        return events;
    }
    let turn_tool_execution_context = tool_execution_context(
        &files_dir,
        &workspace_files_dir,
        &agent_id,
        &session_key_json,
    );
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
    match crate::tool_loop::run_tool_loop(
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
            events.push(event);
        },
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
                return events;
            }
            hooks.stage_completed(&context, TurnStage::ExecuteToolLoop);
            crate::context::record_last_prompt_snapshot(
                &files_dir,
                &prepared.thread_id,
                &prepared.config,
                turn_result.usage.as_ref(),
                prepared.raw_history.len(),
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
            events.extend(outcome.into_emitted_events());
            events
        }
        Err(e) => {
            // Mid-turn overflow marker: the tool loop raised
            // `"mid-turn context overflow: ..."` AFTER soft compaction
            // already collapsed tool results. Route to the existing
            // `reprepare_turn_after_context_overflow_with_hooks`
            // recovery EVEN when `history_recorder` is non-empty (turn
            // has already started) — the recovery path does not
            // re-persist the user message, so we can safely re-prepare.
            let is_mid_turn_overflow = crate::llm::is_context_overflow_error(&e)
                && e.starts_with("mid-turn context overflow:");
            if is_mid_turn_overflow
                || (crate::llm::is_context_overflow_error(&e) && history_recorder.is_empty())
            {
                let overflow_log = if is_mid_turn_overflow {
                    "上下文窗口在 turn 中途被超出"
                } else {
                    "Provider reported context overflow; compacting and retrying once"
                };
                hooks.stage_warning(&context, TurnStage::ExecuteToolLoop, overflow_log);
                events.push(ChatEvent::Thinking {
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
                let retry_prepared = match reprepare_turn_after_context_overflow_with_hooks(
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
                    agent_engine.as_ref(),
                    &mut context,
                    hooks,
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
                        events.push(event);
                        return events;
                    }
                };
                events.extend(retry_prepared.context_events.clone());
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
                match crate::tool_loop::run_tool_loop(
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
                        events.push(event);
                    },
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
                            return events;
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
                            retry_prepared.raw_history.len(),
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
                        events.extend(outcome.into_emitted_events());
                        events
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
                        events.push(chat_error(format!(
                            "Chat error: context overflow recovery failed after retry: {retry_error}"
                        )));
                        events
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
                events.push(chat_error(format!("Chat error: {e}")));
                events
            }
        }
    }
}

#[cfg(test)]
mod mid_turn_recovery_tests {
    //! AC-2 spy test: when the mid-turn hard precheck fires (history_recorder
    //! non-empty), the recovery path routes to
    //! `reprepare_turn_after_context_overflow_with_hooks`, which must NOT
    //! re-run `TurnStage::PersistUserMessage` — i.e. the user message is
    //! never persisted twice when mid-turn overflow recovery re-prepares.

    use super::*;
    use crate::turn::{PromptPlanSummary, TurnOutcomeSummary};

    #[derive(Default)]
    struct StageSpy {
        started: Vec<TurnStage>,
        completed: Vec<TurnStage>,
    }

    impl TurnLifecycleHooks for StageSpy {
        fn stage_started(&mut self, _ctx: &TurnLifecycleContext, stage: TurnStage) {
            self.started.push(stage);
        }
        fn stage_completed(&mut self, _ctx: &TurnLifecycleContext, stage: TurnStage) {
            self.completed.push(stage);
        }
        fn prompt_prepared(&mut self, _ctx: &TurnLifecycleContext, _summary: &PromptPlanSummary) {}
        fn turn_completed(&mut self, _ctx: &TurnLifecycleContext, _summary: &TurnOutcomeSummary) {}
    }

    #[tokio::test]
    async fn reprepare_after_overflow_does_not_persist_user_message_again() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().to_string_lossy().to_string();
        let session_key_json =
            crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

        // Use a tiny context window so reprepare's internal
        // `build_context_for_turn_with_event_sink` runs a compaction pass
        // rather than skipping as a no-op. enabled=true keeps the context
        // engine active.
        use crate::types::{ContextEngineConfig, PlatformLlmConfig};
        let config = PlatformLlmConfig {
            provider: "openai".to_string(),
            api_key: "test".to_string(),
            model: "test-model".to_string(),
            max_tokens: 128,
            context_engine: ContextEngineConfig {
                enabled: true,
                context_window_tokens: Some(1024),
                protect_head_messages: 1,
                protect_tail_messages: 1,
                compaction_strategy: "local_summary".to_string(),
                ..ContextEngineConfig::default()
            },
            ..PlatformLlmConfig::default()
        };
        // Seed history long enough that the compaction pass actually fires.
        for index in 0..8 {
            assert!(crate::session::append_message(
                &files_dir,
                &session_key_json,
                if index % 2 == 0 { "user" } else { "assistant" },
                &"long context ".repeat(40),
            ));
        }
        let config_json = serde_json::to_string(&config).unwrap();

        let mut context = TurnLifecycleContext::new(TurnMode::Collected, "napaxi", false);
        let mut hooks = StageSpy::default();

        let outcome = reprepare_turn_after_context_overflow_with_hooks(
            &files_dir,
            &files_dir,
            &config_json,
            "napaxi",
            &session_key_json,
            "continue the conversation",
            "[]",
            None,
            &[],
            false,
            None,
            &mut context,
            &mut hooks,
        )
        .await;

        // The recovery path must succeed; if it fails, surface the event so
        // the test does not silently pass while skipping the assertion.
        let prepared = outcome.unwrap_or_else(|event| {
            panic!("reprepare_turn_after_context_overflow_with_hooks failed: {event:?}");
        });

        // The user message stage must NOT be revisited during recovery.
        assert!(
            !hooks.started.contains(&TurnStage::PersistUserMessage),
            "reprepare_after_context_overflow must not re-run PersistUserMessage; \
             started stages = {:?}",
            hooks.started
        );
        assert!(
            !hooks.completed.contains(&TurnStage::PersistUserMessage),
            "reprepare_after_context_overflow must not complete PersistUserMessage; \
             completed stages = {:?}",
            hooks.completed
        );
        // The recovery path should still have produced a usable prepared turn.
        assert!(!prepared.raw_history.is_empty());
    }
}
