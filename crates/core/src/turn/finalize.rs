use serde::{Deserialize, Serialize};

use crate::types::{ChatEvent, EvolutionQueuedRun};

use super::{
    PreparedTurn, TurnHistoryRecorder, TurnLifecycleContext, TurnLifecycleHooks, TurnStage,
    persist_turn_history_segments,
};

/// Semantic boundary marker inserted into history when a running turn is
/// interrupted and the assistant produced no model-visible output (content or
/// tool calls). Without it, two consecutive `user` messages would otherwise
/// appear in the model-facing history. The `messages.rs` builders map the
/// `turn_aborted` role onto the provider's assistant role.
pub(crate) const TURN_ABORTED_MARKER: &str = "<turn_aborted>用户主动中断了上一轮,正在执行的工具和命令已被强制打断,可能只执行了一部分。</turn_aborted>";

#[derive(Debug)]
pub(crate) struct TurnOutcome {
    pub(crate) content: String,
    pub(crate) emitted_events: Vec<ChatEvent>,
    pub(crate) tool_call_count: usize,
    pub(crate) queued_runs: Vec<EvolutionQueuedRun>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct TurnOutcomeSummary {
    pub(crate) final_response_char_count: usize,
    pub(crate) tool_call_count: usize,
    pub(crate) queued_review_types: Vec<String>,
    pub(crate) emitted_event_count: usize,
}

impl TurnOutcome {
    pub(crate) fn summary(&self) -> TurnOutcomeSummary {
        TurnOutcomeSummary {
            final_response_char_count: self.content.chars().count(),
            tool_call_count: self.tool_call_count,
            queued_review_types: self
                .queued_runs
                .iter()
                .map(|run| run.review_type.clone())
                .collect(),
            emitted_event_count: self.emitted_events.len(),
        }
    }

    pub(crate) fn into_emitted_events(self) -> Vec<ChatEvent> {
        let Self {
            content,
            emitted_events,
            tool_call_count: _,
            queued_runs,
        } = self;
        debug_assert!(emitted_events.iter().any(
            |event| matches!(event, ChatEvent::Response { content: event_content } if event_content == &content)
        ));
        debug_assert_eq!(
            queued_runs.is_empty(),
            !emitted_events
                .iter()
                .any(|event| matches!(event, ChatEvent::EvolutionQueued { .. }))
        );
        emitted_events
    }
}

pub(crate) fn finish_successful_turn<H>(
    files_dir: &str,
    workspace_files_dir: &str,
    agent_id: &str,
    session_key_json: &str,
    message: &str,
    prepared: PreparedTurn,
    content: String,
    tool_call_count: usize,
    history_recorder: &mut TurnHistoryRecorder,
    context: &TurnLifecycleContext,
    hooks: &mut H,
) -> TurnOutcome
where
    H: TurnLifecycleHooks + ?Sized,
{
    hooks.stage_started(context, TurnStage::PersistAssistantTrace);
    let response_event = ChatEvent::Response {
        content: content.clone(),
    };
    history_recorder.record(&response_event);
    persist_turn_history_segments(files_dir, session_key_json, history_recorder, false);
    hooks.stage_completed(context, TurnStage::PersistAssistantTrace);

    hooks.stage_started(context, TurnStage::AppendJournal);
    if let Err(error) = crate::workspace::append_journal_turn(
        workspace_files_dir,
        agent_id,
        &prepared.thread_id,
        message,
        &content,
    ) {
        hooks.stage_warning(context, TurnStage::AppendJournal, &error);
    }
    hooks.stage_completed(context, TurnStage::AppendJournal);

    hooks.stage_started(context, TurnStage::QueueEvolution);
    debug_assert!(!prepared.prompt_plan.sections.is_empty());
    let updated_history = crate::session::llm_history(files_dir, &prepared.thread_id, 40);
    let mut queued_runs = Vec::new();
    if let Some(run) = crate::evolution::queue_memory_review_after_turn(
        files_dir,
        workspace_files_dir,
        agent_id,
        &prepared.thread_id,
        &prepared.config,
        &updated_history,
    ) {
        queued_runs.push(EvolutionQueuedRun {
            id: run.id,
            review_type: run.review_type,
        });
    }
    if let Some(run) = crate::evolution::queue_skill_review_after_turn(
        files_dir,
        workspace_files_dir,
        agent_id,
        &prepared.thread_id,
        &prepared.config,
        &updated_history,
        tool_call_count,
    ) {
        queued_runs.push(EvolutionQueuedRun {
            id: run.id,
            review_type: run.review_type,
        });
    }
    hooks.stage_completed(context, TurnStage::QueueEvolution);

    hooks.stage_started(context, TurnStage::EmitFinalEvents);
    let emitted_events = final_turn_events(content.clone(), queued_runs.clone());
    hooks.stage_completed(context, TurnStage::EmitFinalEvents);

    TurnOutcome {
        content,
        emitted_events,
        tool_call_count,
        queued_runs,
    }
}

pub(crate) fn finish_cancelled_turn<H>(
    files_dir: &str,
    session_key_json: &str,
    history_recorder: &mut TurnHistoryRecorder,
    interrupt_marker_enabled: bool,
    context: &TurnLifecycleContext,
    hooks: &mut H,
) where
    H: TurnLifecycleHooks + ?Sized,
{
    hooks.stage_started(context, TurnStage::PersistAssistantTrace);
    persist_turn_history_segments(files_dir, session_key_json, history_recorder, true);
    // Insert the boundary marker unless the turn produced model-visible output
    // (assistant content or tool calls) that already fills the user/assistant
    // alternation gap. Reasoning-only turns do NOT count: the `reasoning` role
    // is stripped from the model envelope by `llm_context_history_all`, so
    // without the marker the next request would show two consecutive `user`
    // messages. `persist_turn_history_segments` writes nothing when there is no
    // persistable segment, so the marker is never clobbered.
    if interrupt_marker_enabled && !history_recorder.produced_model_visible_output() {
        crate::session::append_message(
            files_dir,
            session_key_json,
            "turn_aborted",
            TURN_ABORTED_MARKER,
        );
    }
    hooks.stage_completed(context, TurnStage::PersistAssistantTrace);
}

fn final_turn_events(content: String, queued_runs: Vec<EvolutionQueuedRun>) -> Vec<ChatEvent> {
    let mut events = vec![ChatEvent::Response { content }];
    if let Some(event) = evolution_event(queued_runs) {
        events.push(event);
    }
    events
}

fn evolution_event(queued_runs: Vec<EvolutionQueuedRun>) -> Option<ChatEvent> {
    if queued_runs.is_empty() {
        return None;
    }
    let review_types = queued_runs
        .iter()
        .map(|run| run.review_type.clone())
        .collect();
    Some(ChatEvent::EvolutionQueued {
        review_types,
        runs: queued_runs,
    })
}
