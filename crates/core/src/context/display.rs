//! Context status display + snapshot-freshness helpers.
//!
//! Pure presentation logic split out of `mod.rs`: turning persisted
//! `ContextState` snapshots into the adapter-facing usage view, and the
//! freshness checks that decide which snapshot to display.

use super::*;

pub(super) fn display_context_usage<'a>(
    state: &'a ContextState,
    config: &PlatformLlmConfig,
    settings: &crate::types::ContextEngineConfig,
    current_estimated: usize,
) -> DisplayContextUsage<'a> {
    if let Some(snapshot) = state.last_prompt_snapshot.as_ref()
        && snapshot.prompt_tokens > 0
        && provider_snapshot_is_current(state, snapshot, config, settings)
    {
        return DisplayContextUsage {
            used_tokens: snapshot.prompt_tokens,
            source: "provider",
            updated_at: Some(&snapshot.updated_at),
            fresh: true,
        };
    }
    if let Some(snapshot) = state.preflight_snapshot.as_ref()
        && snapshot.estimated_tokens > 0
        && preflight_snapshot_is_current(state, snapshot, config, settings)
    {
        return DisplayContextUsage {
            used_tokens: preflight_display_tokens(state, snapshot),
            source: "preflight",
            updated_at: Some(preflight_display_updated_at(state, snapshot)),
            fresh: true,
        };
    }
    if let Some(summary) = state.summary.as_ref()
        && current_estimated > 0
    {
        return DisplayContextUsage {
            used_tokens: current_estimated,
            source: "legacy",
            updated_at: Some(
                state
                    .last_compacted_at
                    .as_deref()
                    .unwrap_or(summary.created_at.as_str()),
            ),
            fresh: true,
        };
    }
    if let Some(snapshot) = state.last_prompt_snapshot.as_ref()
        && snapshot.prompt_tokens > 0
        && provider_snapshot_matches_config(snapshot, config, settings)
    {
        return DisplayContextUsage {
            used_tokens: snapshot.prompt_tokens,
            source: "provider",
            updated_at: Some(&snapshot.updated_at),
            fresh: false,
        };
    }
    if current_estimated > 0 {
        return DisplayContextUsage {
            used_tokens: current_estimated,
            source: "legacy",
            updated_at: None,
            fresh: false,
        };
    }
    DisplayContextUsage {
        used_tokens: 0,
        source: "unknown",
        updated_at: None,
        fresh: false,
    }
}

fn provider_snapshot_is_current(
    state: &ContextState,
    snapshot: &LastPromptSnapshot,
    config: &PlatformLlmConfig,
    settings: &crate::types::ContextEngineConfig,
) -> bool {
    if !provider_snapshot_matches_config(snapshot, config, settings) {
        return false;
    }
    if let Some(preflight) = state.preflight_snapshot.as_ref()
        && timestamp_after(&preflight.updated_at, &snapshot.updated_at)
    {
        return false;
    }
    if let Some(compaction) = state.last_tool_compaction.as_ref()
        && timestamp_after(&compaction.updated_at, &snapshot.updated_at)
    {
        return false;
    }
    if let Some(compacted_at) = state.last_compacted_at.as_deref()
        && timestamp_after(compacted_at, &snapshot.updated_at)
    {
        return false;
    }
    true
}

fn provider_snapshot_matches_config(
    snapshot: &LastPromptSnapshot,
    config: &PlatformLlmConfig,
    settings: &crate::types::ContextEngineConfig,
) -> bool {
    if !snapshot.provider.is_empty() && snapshot.provider != config.provider {
        return false;
    }
    if !snapshot.model.is_empty() && snapshot.model != config.model {
        return false;
    }
    let fingerprint = context_config_fingerprint(config, settings);
    if !snapshot.config_fingerprint.is_empty() && snapshot.config_fingerprint != fingerprint {
        return false;
    }
    true
}

fn preflight_snapshot_is_current(
    state: &ContextState,
    snapshot: &PreflightSnapshot,
    config: &PlatformLlmConfig,
    settings: &crate::types::ContextEngineConfig,
) -> bool {
    if !snapshot.provider.is_empty() && snapshot.provider != config.provider {
        return false;
    }
    if !snapshot.model.is_empty() && snapshot.model != config.model {
        return false;
    }
    let fingerprint = context_config_fingerprint(config, settings);
    if !snapshot.config_fingerprint.is_empty() && snapshot.config_fingerprint != fingerprint {
        return false;
    }
    if let Some(compacted_at) = state.last_compacted_at.as_deref()
        && timestamp_after(compacted_at, &snapshot.updated_at)
    {
        return false;
    }
    true
}

fn preflight_display_tokens(state: &ContextState, snapshot: &PreflightSnapshot) -> usize {
    let mut tokens = if snapshot.context_budget_status.estimated_prompt_tokens > 0 {
        snapshot.context_budget_status.estimated_prompt_tokens
    } else {
        snapshot
            .estimated_tokens
            .saturating_sub(snapshot.response_reserve_tokens)
    };
    if tokens == 0 {
        tokens = snapshot.estimated_tokens;
    }
    if let Some(compaction) = state.last_tool_compaction.as_ref()
        && timestamp_after(&compaction.updated_at, &snapshot.updated_at)
    {
        tokens = tokens.saturating_sub(compaction.estimated_pruned_tokens);
    }
    tokens
}

fn preflight_display_updated_at<'a>(
    state: &'a ContextState,
    snapshot: &'a PreflightSnapshot,
) -> &'a str {
    let mut updated_at = snapshot.updated_at.as_str();
    if let Some(compaction) = state.last_tool_compaction.as_ref()
        && timestamp_after(&compaction.updated_at, updated_at)
    {
        updated_at = &compaction.updated_at;
    }
    if let Some(compacted_at) = state.last_compacted_at.as_deref()
        && timestamp_after(compacted_at, updated_at)
    {
        updated_at = compacted_at;
    }
    updated_at
}

fn timestamp_after(candidate: &str, baseline: &str) -> bool {
    match (
        DateTime::parse_from_rfc3339(candidate),
        DateTime::parse_from_rfc3339(baseline),
    ) {
        (Ok(candidate), Ok(baseline)) => {
            candidate.with_timezone(&Utc) > baseline.with_timezone(&Utc)
        }
        _ => candidate > baseline,
    }
}

pub(super) fn display_context_delta<'a>(
    state: &'a ContextState,
    display: &DisplayContextUsage<'_>,
) -> (isize, &'a str) {
    if let Some(recovery) = state.last_overflow_recovery.as_ref()
        && recovery.reason == "overflow_retry_failed"
    {
        return (0, "overflow_retry_failed");
    }
    if let Some(recovery) = state.last_overflow_recovery.as_ref()
        && recovery.reason == "overflow_retry_succeeded"
    {
        return (0, "overflow_retry_succeeded");
    }
    if display.source == "provider"
        && let Some(preflight) = state.preflight_snapshot.as_ref()
        && preflight.estimated_tokens > 0
    {
        let preflight_tokens = preflight_display_tokens(state, preflight);
        return (
            display.used_tokens as isize - preflight_tokens as isize,
            "provider_replaced_preflight",
        );
    }
    if let Some(compaction) = state.last_tool_compaction.as_ref()
        && compaction.estimated_pruned_tokens > 0
    {
        return (
            -(compaction.estimated_pruned_tokens as isize),
            "tool_result_pruned",
        );
    }
    if let Some(summary) = state.summary.as_ref()
        && summary.tokens_before > summary.tokens_after
    {
        return (
            summary.tokens_after as isize - summary.tokens_before as isize,
            "compacted",
        );
    }
    (0, "stable")
}

pub(super) fn usage_percent(tokens: usize, context_window: usize) -> f64 {
    if context_window == 0 {
        0.0
    } else {
        ((tokens as f64 / context_window as f64) * 1000.0).round() / 10.0
    }
}
