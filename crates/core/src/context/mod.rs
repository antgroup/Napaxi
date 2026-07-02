//! Core-owned context engine and session compaction helpers.
//!
//! Splits across submodules:
//! - [`state`]: persisted per-thread state types + load/save.
//! - [`budget`]: token estimation, model window inference, route routing.
//! - [`compaction`]: history compaction + tool-output reduction.
//! - [`display`]: context status display + snapshot-freshness helpers.

use std::time::Duration;

/// Capability id for the context engine service surface.
pub const CONTEXT_ENGINE_CAPABILITY_ID: &str = "napaxi.service.context_engine";

mod budget;
mod compaction;
mod display;
mod resolver;
mod state;
#[cfg(test)]
mod tests;

use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::llm::LlmUsage;
use crate::session::SessionMessage;
use crate::tool_registry::ToolDescriptor;
use crate::types::{ChatEvent, PlatformLlmConfig};

use budget::{
    ContextBudgetPlanner, build_preflight_snapshot, context_config_fingerprint,
    context_window_details, context_window_tokens, legacy_context_breakdown,
    model_context_breakdown, normalized_config, response_reserve_info, response_reserve_tokens,
};
use compaction::{
    compact_history, has_compactable_middle, tail_messages, visible_history_from_state,
};
use display::{display_context_delta, display_context_usage, usage_percent};
use state::{
    ContextBudgetStatus, ContextState, ContextTokenBreakdown, LastPromptSnapshot,
    MemoryFlushSnapshot, OverflowRecoverySnapshot, PreflightSnapshot, ToolCompactionSnapshot,
    load_state, save_state,
};

pub(crate) use budget::estimate_json_tokens;
pub(crate) use compaction::{ToolMessageCompactionStats, compact_tool_messages};
pub(crate) use state::delete_context_state;

const LEGACY_TAIL_HISTORY_MESSAGES: usize = 40;

#[derive(Debug, Clone)]
pub(crate) struct ContextBuildOutput {
    pub(crate) history: Vec<SessionMessage>,
    pub(crate) summary: Option<String>,
    pub(crate) events: Vec<ChatEvent>,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct PreCompactionMemoryFlush<'a> {
    pub(crate) review_files_dir: &'a str,
    pub(crate) agent_id: &'a str,
}

#[derive(Debug, Clone, Serialize)]
struct ContextStatus<'a> {
    thread_id: &'a str,
    engine: &'a str,
    summary_present: bool,
    compaction_count: usize,
    tokens_before: usize,
    tokens_after: usize,
    estimated_tokens: usize,
    context_window_tokens: usize,
    trigger_tokens: usize,
    target_tokens: usize,
    response_reserve_tokens: usize,
    response_reserve_source: &'a str,
    usage_percent: f64,
    trigger_ratio: f32,
    target_ratio: f32,
    last_compacted_at: Option<&'a str>,
    display_used_tokens: usize,
    display_source: &'a str,
    last_prompt_tokens: Option<usize>,
    preflight_estimated_tokens: Option<usize>,
    cache_read_tokens: usize,
    cache_write_tokens: usize,
    context_window_source: &'a str,
    native_context_window_tokens: usize,
    native_context_window_source: &'a str,
    effective_context_window_tokens: usize,
    effective_context_window_source: &'a str,
    provider_metadata_fetched_at: Option<&'a str>,
    provider_metadata_stale: bool,
    provider_metadata_error: Option<&'a str>,
    context_guard_status: &'a str,
    context_guard_reason: &'a str,
    context_route: &'a str,
    overflow_tokens: usize,
    breakdown: Option<&'a ContextTokenBreakdown>,
    context_budget_status: Option<&'a ContextBudgetStatus>,
    updated_at: Option<&'a str>,
    fresh: bool,
    current_window_tokens: usize,
    transcript_estimated_tokens: usize,
    last_context_delta_tokens: isize,
    last_context_delta_reason: &'a str,
    tool_result_pruned_tokens: usize,
    tool_result_pruned_chars: usize,
    context_display_label: &'a str,
    compaction_strategy: &'a str,
    last_compaction_duration_ms: Option<u64>,
    adaptive_chunk_count: usize,
    oversized_message_count: usize,
    protected_tail_tokens: usize,
    overflow_retry_attempted_at: Option<&'a str>,
    overflow_retry_succeeded: Option<bool>,
    overflow_retry_reason: Option<&'a str>,
    overflow_retry_error: Option<&'a str>,
    pre_compaction_memory_flush_enabled: bool,
    pre_compaction_memory_flush_status: Option<&'a str>,
}

struct DisplayContextUsage<'a> {
    used_tokens: usize,
    source: &'a str,
    updated_at: Option<&'a str>,
    fresh: bool,
}

pub(crate) async fn build_context(
    files_dir: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    base_prompt: &str,
    history: &[SessionMessage],
    force: bool,
    focus: Option<&str>,
) -> Result<ContextBuildOutput, String> {
    build_context_with_event_sink(
        files_dir,
        thread_id,
        config,
        base_prompt,
        history,
        force,
        focus,
        |_| false,
    )
    .await
}

pub(crate) async fn build_context_with_event_sink<F>(
    files_dir: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    base_prompt: &str,
    history: &[SessionMessage],
    force: bool,
    focus: Option<&str>,
    event_sink: F,
) -> Result<ContextBuildOutput, String>
where
    F: FnMut(&ChatEvent) -> bool,
{
    build_context_internal(
        files_dir,
        thread_id,
        config,
        base_prompt,
        history,
        force,
        focus,
        None,
        event_sink,
    )
    .await
}

pub(crate) async fn build_context_for_turn_with_event_sink<F>(
    files_dir: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    base_prompt: &str,
    history: &[SessionMessage],
    force: bool,
    focus: Option<&str>,
    memory_flush: Option<PreCompactionMemoryFlush<'_>>,
    event_sink: F,
) -> Result<ContextBuildOutput, String>
where
    F: FnMut(&ChatEvent) -> bool,
{
    build_context_internal(
        files_dir,
        thread_id,
        config,
        base_prompt,
        history,
        force,
        focus,
        memory_flush,
        event_sink,
    )
    .await
}

async fn build_context_internal<F>(
    files_dir: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    base_prompt: &str,
    history: &[SessionMessage],
    force: bool,
    focus: Option<&str>,
    memory_flush: Option<PreCompactionMemoryFlush<'_>>,
    mut event_sink: F,
) -> Result<ContextBuildOutput, String>
where
    F: FnMut(&ChatEvent) -> bool,
{
    let mut settings = normalized_config(&config.context_engine);
    if !settings.enabled {
        return Ok(ContextBuildOutput {
            history: tail_messages(history, LEGACY_TAIL_HISTORY_MESSAGES),
            summary: None,
            events: Vec::new(),
        });
    }

    let mut state = load_state(files_dir, thread_id).unwrap_or_else(|| ContextState {
        thread_id: thread_id.to_string(),
        engine: settings.engine.clone(),
        ..ContextState::default()
    });
    state.thread_id = thread_id.to_string();
    state.engine = settings.engine.clone();
    resolver::maybe_refresh_provider_context_metadata(config, &settings, &mut state).await;
    let effective_config = resolver::config_with_provider_metadata(config, &state);
    settings = normalized_config(&effective_config.context_engine);
    state.engine = settings.engine.clone();
    let _ = save_state(files_dir, &state);

    let mut current_history = visible_history_from_state(history, &state, &settings);
    let current_summary = state
        .summary
        .as_ref()
        .map(|summary| summary.content.clone());
    let response_reserve = response_reserve_tokens(&effective_config, &settings);
    let (current_breakdown, _) = model_context_breakdown_for_history(
        &effective_config,
        base_prompt,
        current_summary.as_deref(),
        &current_history,
        response_reserve,
    );
    let tokens_before = current_breakdown.total_tokens;
    let context_window = context_window_tokens(&effective_config, &settings);
    let prompt_tokens_before = tokens_before.saturating_sub(response_reserve);
    let budget_plan = ContextBudgetPlanner::plan(
        thread_id,
        &effective_config,
        &settings,
        prompt_tokens_before,
        response_reserve,
        0,
        current_history.len(),
        &Utc::now().to_rfc3339(),
    );
    let trigger_tokens =
        ((context_window as f64) * settings.trigger_ratio.clamp(0.1, 0.99) as f64).round() as usize;

    if !force && tokens_before < trigger_tokens && !budget_plan.status.should_compact {
        return Ok(ContextBuildOutput {
            history: current_history,
            summary: current_summary,
            events: Vec::new(),
        });
    }
    if !has_compactable_middle(history, &settings) {
        if budget_plan.status.route == "reject_too_large" {
            return Err(format!(
                "Context budget is too low to send safely: remaining prompt budget is {} tokens, effective window is {} tokens, response reserve is {} tokens. Increase the context window or reduce the prompt/history size.",
                budget_plan.status.remaining_prompt_budget_tokens,
                budget_plan.window.effective_tokens,
                budget_plan.response_reserve.tokens
            ));
        }
        return Ok(ContextBuildOutput {
            history: current_history,
            summary: current_summary,
            events: Vec::new(),
        });
    }

    if settings.pre_compaction_memory_flush {
        state.last_memory_flush = Some(
            run_pre_compaction_memory_flush(
                thread_id,
                &effective_config,
                &settings,
                history,
                memory_flush,
            )
            .await,
        );
        let _ = save_state(files_dir, &state);
    }

    let compacting_event = ChatEvent::ContextCompacting {
        usage_percent: usage_percent(tokens_before, context_window),
        strategy: settings.compaction_strategy.clone(),
    };
    let mut events = Vec::new();
    if !event_sink(&compacting_event) {
        events.push(compacting_event);
    }

    let Some(mut compacted) = compact_history(
        history,
        &state,
        &effective_config,
        &settings,
        base_prompt,
        tokens_before,
        focus,
    )
    .await?
    else {
        return Ok(ContextBuildOutput {
            history: current_history,
            summary: current_summary,
            events: Vec::new(),
        });
    };

    state.summary = Some(compacted.summary.clone());
    state.compaction_count = state.compaction_count.saturating_add(1);
    state.last_compacted_at = Some(compacted.summary.created_at.clone());
    state.preflight_snapshot = None;
    state.last_tool_compaction = None;

    current_history = visible_history_from_state(history, &state, &settings);
    let summary = state
        .summary
        .as_ref()
        .map(|summary| summary.content.clone());
    let (compacted_breakdown, _) = model_context_breakdown_for_history(
        &effective_config,
        base_prompt,
        summary.as_deref(),
        &current_history,
        response_reserve,
    );
    if let Some(summary_record) = state.summary.as_mut() {
        summary_record.tokens_after = compacted_breakdown.total_tokens;
        compacted.summary.tokens_after = compacted_breakdown.total_tokens;
    }
    let _ = save_state(files_dir, &state);
    let compacted_event = ChatEvent::ContextCompacted {
        turns_removed: compacted.turns_removed,
        tokens_before,
        tokens_after: compacted.summary.tokens_after,
    };
    if !event_sink(&compacted_event) {
        events.push(compacted_event);
    }

    Ok(ContextBuildOutput {
        history: current_history,
        summary,
        events,
    })
}

async fn run_pre_compaction_memory_flush(
    thread_id: &str,
    config: &PlatformLlmConfig,
    settings: &crate::types::ContextEngineConfig,
    history: &[SessionMessage],
    request: Option<PreCompactionMemoryFlush<'_>>,
) -> MemoryFlushSnapshot {
    let attempted_at = Utc::now().to_rfc3339();
    let Some(request) = request else {
        return MemoryFlushSnapshot {
            attempted_at,
            enabled: true,
            succeeded: false,
            reason: "unavailable_without_turn_context".to_string(),
            error: None,
        };
    };
    if history.len() < 2 {
        return MemoryFlushSnapshot {
            attempted_at,
            enabled: true,
            succeeded: false,
            reason: "skipped_not_enough_history".to_string(),
            error: None,
        };
    }
    if config.api_key.trim().is_empty() || config.model.trim().is_empty() {
        return MemoryFlushSnapshot {
            attempted_at,
            enabled: true,
            succeeded: false,
            reason: "skipped_missing_llm_config".to_string(),
            error: None,
        };
    }

    let timeout_ms = settings.compaction_timeout_ms.clamp(1, 20_000);
    match tokio::time::timeout(
        Duration::from_millis(timeout_ms),
        crate::evolution::review_memory_before_compaction(
            request.review_files_dir,
            request.agent_id,
            thread_id,
            config,
            history,
        ),
    )
    .await
    {
        Ok(run) if run.error.is_none() => MemoryFlushSnapshot {
            attempted_at,
            enabled: true,
            succeeded: true,
            reason: format!(
                "reviewed suggestions={} auto_applied={} pending={}",
                run.suggestions_count, run.auto_applied_count, run.pending_count
            ),
            error: None,
        },
        Ok(run) => MemoryFlushSnapshot {
            attempted_at,
            enabled: true,
            succeeded: false,
            reason: "review_failed".to_string(),
            error: run.error,
        },
        Err(_) => MemoryFlushSnapshot {
            attempted_at,
            enabled: true,
            succeeded: false,
            reason: "timeout".to_string(),
            error: Some(format!("Memory flush timed out after {timeout_ms} ms")),
        },
    }
}

pub(crate) async fn compact_session(
    files_dir: &str,
    config: &PlatformLlmConfig,
    session_key_json: &str,
    focus: Option<&str>,
) -> String {
    let Some(thread_id) = session_thread_id(session_key_json) else {
        return error_json("Session key is missing thread_id");
    };
    let history = crate::session::llm_context_history_all(files_dir, &thread_id);
    let output = match build_context(
        files_dir,
        &thread_id,
        config,
        &config.system_prompt,
        &history,
        true,
        focus,
    )
    .await
    {
        Ok(output) => output,
        Err(error) => return error_json(&error),
    };
    if output.events.is_empty() {
        return context_status_for_config(files_dir, &thread_id, Some(config));
    }
    context_status_for_config(files_dir, &thread_id, Some(config))
}

pub(crate) async fn compact_session_handle_async(
    handle: i64,
    config_json: &str,
    session_key_json: &str,
    focus: Option<&str>,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return error_json("invalid engine handle");
    };
    if let Err(error) =
        crate::capabilities::admit_service(CONTEXT_ENGINE_CAPABILITY_ID, "context_engine.compact")
    {
        return error_json(&error.to_string());
    }
    let config = serde_json::from_str::<PlatformLlmConfig>(config_json).unwrap_or_default();
    compact_session(&files_dir, &config, session_key_json, focus).await
}

pub(crate) fn compact_session_handle(
    handle: i64,
    config_json: &str,
    session_key_json: &str,
    focus: Option<&str>,
) -> String {
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => return error_json(&error.to_string()),
    };
    runtime.block_on(compact_session_handle_async(
        handle,
        config_json,
        session_key_json,
        focus,
    ))
}

#[allow(dead_code)]
pub(crate) fn context_status(files_dir: &str, thread_id: &str) -> String {
    context_status_for_config(files_dir, thread_id, None)
}

pub(crate) fn context_status_for_config(
    files_dir: &str,
    thread_id: &str,
    config: Option<&PlatformLlmConfig>,
) -> String {
    let state = load_state(files_dir, thread_id).unwrap_or_else(|| ContextState {
        thread_id: thread_id.to_string(),
        engine: "compressor".to_string(),
        ..ContextState::default()
    });
    let fallback_config;
    let config = match config {
        Some(config) => config,
        None => {
            fallback_config = PlatformLlmConfig::default();
            &fallback_config
        }
    };
    let effective_config = resolver::config_with_provider_metadata(config, &state);
    let settings = normalized_config(&effective_config.context_engine);
    let history = crate::session::llm_context_history_all(files_dir, thread_id);
    let visible_history = visible_history_from_state(&history, &state, &settings);
    let summary = state
        .summary
        .as_ref()
        .map(|summary| summary.content.as_str());
    let response_reserve = response_reserve_info(&effective_config, &settings);
    let window = context_window_details(&effective_config, &settings);
    let context_window = window.effective_tokens;
    let context_window_source = window.effective_source;
    let trigger_tokens =
        ((context_window as f64) * settings.trigger_ratio.clamp(0.1, 0.99) as f64).round() as usize;
    let target_tokens =
        ((context_window as f64) * settings.target_ratio.clamp(0.1, 0.95) as f64).round() as usize;
    let legacy_breakdown = legacy_context_breakdown(
        &effective_config.system_prompt,
        summary,
        &visible_history,
        response_reserve.tokens,
    );
    let (model_breakdown, live_tool_compaction) = model_context_breakdown_for_history(
        &effective_config,
        &effective_config.system_prompt,
        summary,
        &visible_history,
        response_reserve.tokens,
    );
    let live_budget_plan = ContextBudgetPlanner::plan(
        thread_id,
        &effective_config,
        &settings,
        model_breakdown
            .total_tokens
            .saturating_sub(response_reserve.tokens),
        response_reserve.tokens,
        live_tool_compaction.pruned_chars,
        visible_history.len(),
        &Utc::now().to_rfc3339(),
    );
    let current_estimated_tokens = model_breakdown.total_tokens;
    let transcript_estimated_tokens = legacy_breakdown.total_tokens;
    let display = display_context_usage(
        &state,
        &effective_config,
        &settings,
        current_estimated_tokens,
    );
    let (last_context_delta_tokens, last_context_delta_reason) =
        display_context_delta(&state, &display);
    let tool_result_pruned_tokens = state
        .last_tool_compaction
        .as_ref()
        .map(|snapshot| snapshot.estimated_pruned_tokens)
        .unwrap_or(live_tool_compaction.estimated_pruned_tokens);
    let tool_result_pruned_chars = state
        .last_tool_compaction
        .as_ref()
        .map(|snapshot| snapshot.pruned_chars)
        .unwrap_or(live_tool_compaction.pruned_chars);
    let (tokens_before, tokens_after) = state
        .summary
        .as_ref()
        .map(|summary| (summary.tokens_before, summary.tokens_after))
        .unwrap_or((0, 0));
    let compaction_strategy = state
        .summary
        .as_ref()
        .map(|summary| summary.strategy.as_str())
        .unwrap_or(settings.compaction_strategy.as_str());
    let last_compaction_duration_ms = state
        .summary
        .as_ref()
        .and_then(|summary| summary.duration_ms);
    let provider_metadata = resolver::provider_metadata_for_config(&effective_config, &state);
    let adaptive_chunk_count = state
        .summary
        .as_ref()
        .and_then(|summary| summary.adaptive_chunk_count)
        .unwrap_or(0);
    let oversized_message_count = state
        .summary
        .as_ref()
        .and_then(|summary| summary.oversized_message_count)
        .unwrap_or(0);
    let protected_tail_tokens = state
        .summary
        .as_ref()
        .and_then(|summary| summary.protected_tail_tokens)
        .unwrap_or(0);
    let memory_flush_status = state
        .last_memory_flush
        .as_ref()
        .map(|snapshot| snapshot.reason.as_str());
    serde_json::to_string(&ContextStatus {
        thread_id,
        engine: &state.engine,
        summary_present: state.summary.is_some(),
        compaction_count: state.compaction_count,
        tokens_before,
        tokens_after,
        estimated_tokens: display.used_tokens,
        context_window_tokens: context_window,
        trigger_tokens,
        target_tokens,
        response_reserve_tokens: response_reserve.tokens,
        response_reserve_source: response_reserve.source,
        usage_percent: usage_percent(display.used_tokens, context_window),
        trigger_ratio: settings.trigger_ratio,
        target_ratio: settings.target_ratio,
        last_compacted_at: state.last_compacted_at.as_deref(),
        display_used_tokens: display.used_tokens,
        display_source: display.source,
        last_prompt_tokens: state
            .last_prompt_snapshot
            .as_ref()
            .map(|snapshot| snapshot.prompt_tokens),
        preflight_estimated_tokens: state
            .preflight_snapshot
            .as_ref()
            .map(|snapshot| snapshot.estimated_tokens),
        cache_read_tokens: state
            .last_prompt_snapshot
            .as_ref()
            .map(|snapshot| snapshot.cache_read_tokens)
            .unwrap_or(0),
        cache_write_tokens: state
            .last_prompt_snapshot
            .as_ref()
            .map(|snapshot| snapshot.cache_write_tokens)
            .unwrap_or(0),
        context_window_source,
        native_context_window_tokens: window.native_tokens,
        native_context_window_source: window.native_source,
        effective_context_window_tokens: window.effective_tokens,
        effective_context_window_source: window.effective_source,
        provider_metadata_fetched_at: provider_metadata
            .map(|metadata| metadata.fetched_at.as_str()),
        provider_metadata_stale: provider_metadata
            .map(|metadata| metadata.stale)
            .unwrap_or(false),
        provider_metadata_error: provider_metadata.and_then(|metadata| metadata.error.as_deref()),
        context_guard_status: state
            .preflight_snapshot
            .as_ref()
            .map(|snapshot| snapshot.context_budget_status.context_guard_status.as_str())
            .filter(|value| !value.is_empty())
            .unwrap_or(live_budget_plan.status.context_guard_status.as_str()),
        context_guard_reason: state
            .preflight_snapshot
            .as_ref()
            .map(|snapshot| snapshot.context_budget_status.context_guard_reason.as_str())
            .filter(|value| !value.is_empty())
            .unwrap_or(live_budget_plan.status.context_guard_reason.as_str()),
        context_route: state
            .preflight_snapshot
            .as_ref()
            .map(|snapshot| snapshot.context_budget_status.route.as_str())
            .unwrap_or(live_budget_plan.status.route.as_str()),
        overflow_tokens: state
            .preflight_snapshot
            .as_ref()
            .map(|snapshot| snapshot.context_budget_status.overflow_tokens)
            .unwrap_or(live_budget_plan.status.overflow_tokens),
        breakdown: state
            .preflight_snapshot
            .as_ref()
            .map(|snapshot| &snapshot.breakdown)
            .or(Some(&model_breakdown)),
        context_budget_status: state
            .preflight_snapshot
            .as_ref()
            .map(|snapshot| &snapshot.context_budget_status),
        updated_at: display.updated_at,
        fresh: display.fresh,
        current_window_tokens: display.used_tokens,
        transcript_estimated_tokens,
        last_context_delta_tokens,
        last_context_delta_reason,
        tool_result_pruned_tokens,
        tool_result_pruned_chars,
        context_display_label: "current_window",
        compaction_strategy,
        last_compaction_duration_ms,
        adaptive_chunk_count,
        oversized_message_count,
        protected_tail_tokens,
        overflow_retry_attempted_at: state
            .last_overflow_recovery
            .as_ref()
            .map(|snapshot| snapshot.attempted_at.as_str()),
        overflow_retry_succeeded: state
            .last_overflow_recovery
            .as_ref()
            .map(|snapshot| snapshot.succeeded),
        overflow_retry_reason: state
            .last_overflow_recovery
            .as_ref()
            .map(|snapshot| snapshot.reason.as_str()),
        overflow_retry_error: state
            .last_overflow_recovery
            .as_ref()
            .and_then(|snapshot| snapshot.error.as_deref()),
        pre_compaction_memory_flush_enabled: settings.pre_compaction_memory_flush,
        pre_compaction_memory_flush_status: memory_flush_status,
    })
    .unwrap_or_else(|error| error_json(&error.to_string()))
}

fn model_context_breakdown_for_history(
    config: &PlatformLlmConfig,
    base_prompt: &str,
    summary: Option<&str>,
    history: &[SessionMessage],
    response_reserve: usize,
) -> (ContextTokenBreakdown, ToolMessageCompactionStats) {
    let mut raw_history = crate::llm::openai_messages_from_mobile_history(history);
    let tool_stats = compact_tool_messages(&mut raw_history, config, 0);
    (
        model_context_breakdown(base_prompt, summary, &raw_history, response_reserve),
        tool_stats,
    )
}

pub(crate) fn context_status_handle(handle: i64, config_json: &str, thread_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return error_json("invalid engine handle");
    };
    if let Err(error) =
        crate::capabilities::admit_service(CONTEXT_ENGINE_CAPABILITY_ID, "context_engine.status")
    {
        return error_json(&error.to_string());
    }
    let config = serde_json::from_str::<PlatformLlmConfig>(config_json).unwrap_or_default();
    context_status_for_config(&files_dir, thread_id, Some(&config))
}

pub(crate) fn record_preflight_snapshot(
    files_dir: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    raw_history: &[serde_json::Value],
    tool_descriptors: &[ToolDescriptor],
) {
    let settings = normalized_config(&config.context_engine);
    if !settings.enabled {
        return;
    }
    let mut state = load_state(files_dir, thread_id).unwrap_or_else(|| ContextState {
        thread_id: thread_id.to_string(),
        engine: settings.engine.clone(),
        ..ContextState::default()
    });
    state.thread_id = thread_id.to_string();
    state.engine = settings.engine.clone();
    let effective_config = resolver::config_with_provider_metadata(config, &state);
    let effective_settings = normalized_config(&effective_config.context_engine);
    let mut snapshot = build_preflight_snapshot(
        thread_id,
        &effective_config,
        &effective_settings,
        raw_history,
        tool_descriptors,
    );
    if let Some(metadata) = resolver::provider_metadata_for_config(&effective_config, &state) {
        snapshot.provider_metadata_fetched_at = Some(metadata.fetched_at.clone());
        snapshot.provider_metadata_stale = metadata.stale;
        snapshot.provider_metadata_error = metadata.error.clone();
        snapshot.context_budget_status.provider_metadata_fetched_at =
            Some(metadata.fetched_at.clone());
        snapshot.context_budget_status.provider_metadata_stale = metadata.stale;
        snapshot.context_budget_status.provider_metadata_error = metadata.error.clone();
    }
    state.preflight_snapshot = Some(snapshot);
    state.last_tool_compaction = None;
    let _ = save_state(files_dir, &state);
}

pub(crate) fn record_last_prompt_snapshot(
    files_dir: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    usage: Option<&LlmUsage>,
) {
    let Some(usage) = usage else {
        return;
    };
    let Some(prompt_tokens) = usage.prompt_tokens() else {
        return;
    };
    let settings = normalized_config(&config.context_engine);
    if !settings.enabled {
        return;
    }
    let mut state = load_state(files_dir, thread_id).unwrap_or_else(|| ContextState {
        thread_id: thread_id.to_string(),
        engine: settings.engine.clone(),
        ..ContextState::default()
    });
    state.thread_id = thread_id.to_string();
    state.engine = settings.engine.clone();
    let effective_config = resolver::config_with_provider_metadata(config, &state);
    let effective_settings = normalized_config(&effective_config.context_engine);
    state.last_prompt_snapshot = Some(LastPromptSnapshot {
        provider: effective_config.provider.clone(),
        model: effective_config.model.clone(),
        config_fingerprint: context_config_fingerprint(&effective_config, &effective_settings),
        prompt_tokens,
        input_tokens: usage.input_tokens.unwrap_or(0),
        output_tokens: usage.output_tokens.unwrap_or(0),
        cache_read_tokens: usage.cache_read_tokens.unwrap_or(0),
        cache_write_tokens: usage.cache_write_tokens.unwrap_or(0),
        reasoning_tokens: usage.reasoning_tokens.unwrap_or(0),
        total_tokens: usage.total_tokens,
        updated_at: Utc::now().to_rfc3339(),
    });
    let _ = save_state(files_dir, &state);
}

pub(crate) fn record_tool_compaction_snapshot_for_session(
    files_dir: &str,
    session_key_json: &str,
    config: &PlatformLlmConfig,
    stats: ToolMessageCompactionStats,
) {
    if stats.is_empty() {
        return;
    }
    let Some(thread_id) = session_thread_id(session_key_json) else {
        return;
    };
    let settings = normalized_config(&config.context_engine);
    if !settings.enabled {
        return;
    }
    let mut state = load_state(files_dir, &thread_id).unwrap_or_else(|| ContextState {
        thread_id: thread_id.clone(),
        engine: settings.engine.clone(),
        ..ContextState::default()
    });
    state.thread_id = thread_id;
    state.engine = settings.engine.clone();
    state.last_tool_compaction = Some(ToolCompactionSnapshot {
        compacted_messages: stats.compacted_messages,
        original_chars: stats.original_chars,
        compacted_chars: stats.compacted_chars,
        pruned_chars: stats.pruned_chars,
        estimated_pruned_tokens: stats.estimated_pruned_tokens,
        updated_at: Utc::now().to_rfc3339(),
    });
    let _ = save_state(files_dir, &state);
}

pub(crate) fn record_overflow_recovery_snapshot(
    files_dir: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    succeeded: bool,
    retry_count: usize,
    reason: &str,
    error: Option<&str>,
) {
    let settings = normalized_config(&config.context_engine);
    if !settings.enabled {
        return;
    }
    let mut state = load_state(files_dir, thread_id).unwrap_or_else(|| ContextState {
        thread_id: thread_id.to_string(),
        engine: settings.engine.clone(),
        ..ContextState::default()
    });
    state.thread_id = thread_id.to_string();
    state.engine = settings.engine.clone();
    state.last_overflow_recovery = Some(OverflowRecoverySnapshot {
        provider: config.provider.clone(),
        model: config.model.clone(),
        attempted_at: Utc::now().to_rfc3339(),
        succeeded,
        retry_count,
        reason: reason.to_string(),
        error: error.map(str::to_string),
    });
    let _ = save_state(files_dir, &state);
}

fn session_thread_id(session_key_json: &str) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(session_key_json)
        .ok()
        .and_then(|key| {
            key.get("thread_id")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
}

fn error_json(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}
