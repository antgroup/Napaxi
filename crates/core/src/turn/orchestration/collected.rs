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
            if crate::llm::is_context_overflow_error(&e) && history_recorder.is_empty() {
                hooks.stage_warning(
                    &context,
                    TurnStage::ExecuteToolLoop,
                    "Provider reported context overflow; compacting and retrying once",
                );
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
