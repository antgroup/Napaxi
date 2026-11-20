//! Context-engine snapshot persistence helpers, split out of `mod.rs` so the
//! parent module stays under the 1000-line production-source limit set by
//! `tools/scripts/build.sh::check_source_file_size`.
//!
//! Turn-entry preflight snapshots, last-prompt usage snapshots, in-turn
//! tool-compaction snapshots, and overflow-recovery snapshots. Each helper
//! loads/persists the per-thread [`ContextState`] and is gated on the
//! context engine being enabled.

use chrono::Utc;

use crate::llm::LlmUsage;
use crate::tool_registry::ToolDescriptor;
use crate::types::PlatformLlmConfig;

use super::budget::{build_preflight_snapshot, context_config_fingerprint, normalized_config};
use super::compaction::ToolMessageCompactionStats;
use super::resolver;
use super::session_thread_id;
use super::state::{
    ContextState, LastPromptSnapshot, OverflowRecoverySnapshot, ToolCompactionSnapshot, load_state,
    save_state,
};

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
    message_count: usize,
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
        message_count,
    });
    let _ = save_state(files_dir, &state);
}

/// Authoritative-source plumbing (AC-1, DIMA-2026110600120401874): resolve
/// the last real per-provider prompt usage for the session backing
/// `session_key_json`, validated against the current `config` so a stale
/// snapshot from a different model/window/reserve never feeds the live
/// mid-turn hard precheck.
///
/// Returns the snapshot's `prompt_tokens` only when ALL of:
/// - the session resolves to a thread with persisted [`ContextState`],
/// - that state carries a [`LastPromptSnapshot`],
/// - the snapshot's `config_fingerprint` matches the current effective
///   config (same provider/model/window/reserve — modulo provider
///   metadata, which `resolver::config_with_provider_metadata` normalizes
///   in), AND
/// - the current `messages` list has not shrunk below the snapshot's
///   `message_count` (a shrink means the snapshot is from a different /
///   reset history and is no longer representative). When the persisted
///   snapshot predates the `message_count` field (older code path), the
///   shrink check is skipped and only the fingerprint gates the snapshot.
///
/// On any miss the caller falls back to the pure estimate — never returns
/// a value looser than the estimate. The mid-turn hard precheck then takes
/// `max(estimate, real)` ([`crate::context::mid_turn_hard_precheck_for_config`])
/// so introducing the authoritative source can only tighten the check,
/// never loosen it.
pub(crate) fn fresh_last_prompt_tokens(
    files_dir: &str,
    session_key_json: Option<&str>,
    config: &PlatformLlmConfig,
    messages: &[serde_json::Value],
) -> Option<usize> {
    let session_key_json = session_key_json?;
    let thread_id = session_thread_id(session_key_json)?;
    let state = load_state(files_dir, &thread_id)?;
    let snapshot = state.last_prompt_snapshot.as_ref()?;
    let effective_config = resolver::config_with_provider_metadata(config, &state);
    let effective_settings = normalized_config(&effective_config.context_engine);
    let fingerprint = context_config_fingerprint(&effective_config, &effective_settings);
    if snapshot.config_fingerprint != fingerprint {
        return None;
    }
    // If the persisted snapshot records the producing message count, the
    // current message list must not have shrunk below it. A grow between
    // snapshot and now is the normal mid-turn direction (tool results are
    // appended), and `max(estimate, real)` keeps the result on the strict
    // side; a shrink would let a stale large `real` shadow a tighter
    // estimate, so we drop the snapshot in that case.
    if snapshot.message_count > 0 && messages.len() < snapshot.message_count {
        return None;
    }
    Some(snapshot.prompt_tokens)
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
