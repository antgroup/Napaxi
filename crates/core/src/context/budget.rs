//! Token estimation, model context window inference, and budget routing.
//!
//! All math used to decide whether a turn fits within the model's context
//! window — pre-call estimates, in-place safety margins, route decisions,
//! and per-model window defaults — lives here.
//!
//! # Prompt usage authoritative source (AC-1, DIMA-2026110600120401874)
//!
//! Audit conclusion (estimator vs. real usage across the gates):
//! - **Display layer** (`display.rs::display_context_usage`): already uses
//!   [`super::state::LastPromptSnapshot`] as the authoritative source when
//!   the provider snapshot is fresh (`provider_snapshot_is_current`); the
//!   "provider" source is preferred over the preflight estimate.
//! - **Turn-start admission / preflight snapshot**
//!   (`budget.rs::build_preflight_snapshot`): sticks to the ESTIMATE path —
//!   no real `prompt_tokens` are available yet at preflight time, by
//!   design.
//! - **Mid-turn hard precheck** (`mid_turn_hard_precheck`, called from
//!   `tools::loop.rs::enforce_mid_turn_hard_precheck`): PRE-FIX used the
//!   pure `estimate_messages_tokens` baseline. POST-FIX takes
//!   `max(estimate, last_real_prompt_usage)` when a fresh
//!   `LastPromptSnapshot` is available — the real per-provider prompt
//!   usage is the authoritative source; the estimator is the fallback.
//!   Freshness gates: `config_fingerprint` match (provider/model/window/
//!   reserve) and `messages.len() >= snapshot.message_count` (no shrink
//!   since the snapshot was taken). On any miss the precheck silently
//!   falls back to the pure estimate — the new path can only tighten the
//!   check, never loosen it. See `super::fresh_last_prompt_tokens` for
//!   the validation and `tools/loop.rs::enforce_mid_turn_hard_precheck`
//!   for the `max(estimate, real)` plumbing.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use serde::Serialize;

use crate::session::SessionMessage;
use crate::tool_registry::ToolDescriptor;
use crate::types::{ContextEngineConfig, PlatformLlmConfig};

use super::state::{ContextBudgetStatus, ContextTokenBreakdown, PreflightSnapshot};

pub(super) const DEFAULT_CONTEXT_WINDOW_TOKENS: usize = 128_000;
pub(super) const ESTIMATED_CHARS_PER_TOKEN: usize = 4;
pub(super) const JSON_CHARS_PER_TOKEN: usize = 3;
pub(super) const TOOL_RESULT_CHARS_PER_TOKEN: usize = 2;
pub(super) const MESSAGE_OVERHEAD_TOKENS: usize = 12;
pub(super) const CONTENT_BLOCK_OVERHEAD_TOKENS: usize = 6;
pub(super) const IMAGE_BLOCK_TOKENS: usize = 2_000;
pub(super) const PREFLIGHT_SAFETY_MARGIN: f64 = 1.15;
pub(super) const TRUNCATION_ROUTE_BUFFER_TOKENS: usize = 512;
pub(super) const CONTEXT_GUARD_HARD_MIN_TOKENS: usize = 4_000;
pub(super) const CONTEXT_GUARD_WARN_MIN_TOKENS: usize = 8_000;
pub(super) const CONTEXT_GUARD_HARD_MIN_RATIO: f64 = 0.10;
pub(super) const CONTEXT_GUARD_WARN_MIN_RATIO: f64 = 0.20;

/// Floor reserve applied during the mid-turn hard precheck so that overflow
/// can still be detected even when the soft compaction enable/threshold
/// switches are turned off. Independent of `ContextEngineConfig::enabled`
/// and `trigger_ratio` by design — mirrors the OpenClaw #189810 fix idea
/// (Napaxi-native implementation, no code ported).
pub(super) const DEFAULT_AGENT_COMPACTION_RESERVE_TOKENS_FLOOR: usize = 4_096;

/// Outcome of the mid-turn hard context precheck run before each LLM call in
/// `run_tool_loop` / `run_tool_loop_streaming`, after soft compaction has
/// already collapsed tool-result messages.
///
/// This check is INDEPENDENT of `ContextEngineConfig::enabled` and the soft
/// `trigger_ratio` threshold: even when soft compaction is disabled, the
/// floor reserve enforced here guarantees we never enter an LLM call that
/// cannot possibly fit the response reserve. On `Overflow` the loop returns
/// a `"mid-turn context overflow: ..."` marker error which the turn
/// orchestration routes to
/// [`reprepare_turn_after_context_overflow_with_hooks`](crate::turn::reprepare_turn_after_context_overflow_with_hooks)
/// — even mid-turn (when `history_recorder` is non-empty).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MidTurnPrecheckStatus {
    /// The prompt still fits within `window - reserve`. Carries the
    /// remaining prompt-budget token count for observability.
    Fits {
        remaining_prompt_budget_tokens: isize,
    },
    /// The prompt plus the floor reserve exceeds the effective window.
    /// Carries the number of tokens by which the prompt budget is over
    /// the floor reserve.
    Overflow { overflow_tokens: usize },
}

/// Mid-turn hard context precheck — see [`MidTurnPrecheckStatus`].
///
/// `effective_floor` reuses the same floor math as `context_guard` so the
/// mid-turn check never raises the bar above the turn-start admission line.
/// `reserve` is `max(effective_floor, configured_reserve)`, ensuring the
/// configured `response_reserve_tokens` (when larger than the floor) still
/// wins, while never dropping below the floor — independent of
/// `settings.enabled` / `trigger_ratio`.
pub(super) fn mid_turn_hard_precheck(
    window: ContextWindowInfo,
    prompt_tokens: usize,
    configured_reserve: usize,
    _descriptor_tokens: usize,
) -> MidTurnPrecheckStatus {
    if window.effective_tokens == 0 {
        return MidTurnPrecheckStatus::Overflow {
            overflow_tokens: prompt_tokens,
        };
    }
    let budget = window.effective_tokens;
    let hard_floor = CONTEXT_GUARD_HARD_MIN_TOKENS
        .max(((budget as f64) * CONTEXT_GUARD_HARD_MIN_RATIO).round() as usize);
    let floor_reserve = DEFAULT_AGENT_COMPACTION_RESERVE_TOKENS_FLOOR.max(hard_floor);
    let reserve = floor_reserve.max(configured_reserve);
    let prompt_budget = budget.saturating_sub(reserve);
    let remaining_prompt_budget_tokens = prompt_budget as isize - prompt_tokens as isize;
    if remaining_prompt_budget_tokens < 0 {
        MidTurnPrecheckStatus::Overflow {
            overflow_tokens: prompt_tokens.saturating_sub(prompt_budget),
        }
    } else {
        MidTurnPrecheckStatus::Fits {
            remaining_prompt_budget_tokens,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ContextWindowInfo {
    pub(super) native_tokens: usize,
    pub(super) native_source: &'static str,
    pub(super) effective_tokens: usize,
    pub(super) effective_source: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ResponseReserveInfo {
    pub(super) tokens: usize,
    pub(super) source: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct ModelContextProfile {
    pub(super) provider: String,
    pub(super) model: String,
    pub(super) window: ContextWindowInfo,
    pub(super) response_reserve: ResponseReserveInfo,
}

#[derive(Debug, Clone)]
pub(super) struct ContextBudgetPlan {
    pub(super) status: ContextBudgetStatus,
    pub(super) window: ContextWindowInfo,
    pub(super) response_reserve: ResponseReserveInfo,
}

pub(super) struct ContextBudgetPlanner;

impl ContextBudgetPlanner {
    pub(super) fn plan(
        thread_id: &str,
        config: &PlatformLlmConfig,
        settings: &ContextEngineConfig,
        prompt_tokens: usize,
        reserve_tokens: usize,
        tool_result_reducible_chars: usize,
        message_count: usize,
        updated_at: &str,
    ) -> ContextBudgetPlan {
        build_context_budget_plan(
            thread_id,
            config,
            settings,
            prompt_tokens,
            reserve_tokens,
            tool_result_reducible_chars,
            message_count,
            updated_at,
        )
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub(super) struct MessageTokenEstimate {
    pub(super) total_tokens: usize,
    pub(super) tool_result_tokens: usize,
    pub(super) tool_call_tokens: usize,
    pub(super) attachment_tokens: usize,
    pub(super) image_tokens: usize,
    pub(super) tool_result_reducible_chars: usize,
}

impl MessageTokenEstimate {
    pub(super) fn saturating_add(self, other: MessageTokenEstimate) -> MessageTokenEstimate {
        MessageTokenEstimate {
            total_tokens: self.total_tokens.saturating_add(other.total_tokens),
            tool_result_tokens: self
                .tool_result_tokens
                .saturating_add(other.tool_result_tokens),
            tool_call_tokens: self.tool_call_tokens.saturating_add(other.tool_call_tokens),
            attachment_tokens: self
                .attachment_tokens
                .saturating_add(other.attachment_tokens),
            image_tokens: self.image_tokens.saturating_add(other.image_tokens),
            tool_result_reducible_chars: self
                .tool_result_reducible_chars
                .saturating_add(other.tool_result_reducible_chars),
        }
    }
}

pub(super) fn normalized_config(config: &ContextEngineConfig) -> ContextEngineConfig {
    let mut config = config.clone();
    if config.engine.trim().is_empty() {
        config.engine = "compressor".to_string();
    }
    if config.trigger_ratio <= 0.0 {
        config.trigger_ratio = 0.85;
    }
    if config.target_ratio <= 0.0 {
        config.target_ratio = 0.45;
    }
    if config.protect_tail_messages == 0 {
        config.protect_tail_messages = 20;
    }
    config.compaction_strategy = match config.compaction_strategy.trim() {
        "" | "recursive_summary" => "llm_summary".to_string(),
        value => value.to_string(),
    };
    if config
        .compaction_model
        .as_deref()
        .is_some_and(|value| value.trim().is_empty())
    {
        config.compaction_model = None;
    }
    if config
        .native_context_window_tokens
        .is_some_and(|tokens| tokens == 0)
    {
        config.native_context_window_tokens = None;
    }
    if config
        .provider_context_window_tokens
        .is_some_and(|tokens| tokens == 0)
    {
        config.provider_context_window_tokens = None;
    }
    if config.compaction_timeout_ms == 0 {
        config.compaction_timeout_ms = 60_000;
    }
    config
}

pub(super) fn context_config_fingerprint(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> String {
    let mut hasher = DefaultHasher::new();
    config.provider.hash(&mut hasher);
    config.model.hash(&mut hasher);
    config.base_url.hash(&mut hasher);
    config.max_tokens.hash(&mut hasher);
    settings.context_window_tokens.hash(&mut hasher);
    settings.native_context_window_tokens.hash(&mut hasher);
    settings.provider_context_window_tokens.hash(&mut hasher);
    settings.response_reserve_tokens.hash(&mut hasher);
    settings.compaction_strategy.hash(&mut hasher);
    settings.compaction_model.hash(&mut hasher);
    settings.pre_compaction_memory_flush.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

pub(super) fn estimate_context_tokens(
    base_prompt: &str,
    summary: Option<&str>,
    history: &[SessionMessage],
) -> usize {
    legacy_context_breakdown(base_prompt, summary, history, 0).total_tokens
}

pub(super) fn approx_tokens(text: &str) -> usize {
    estimate_string_tokens(text, ESTIMATED_CHARS_PER_TOKEN)
}

pub(crate) fn estimate_messages_tokens(messages: &[serde_json::Value]) -> usize {
    messages
        .iter()
        .map(|message| estimate_message_token_pressure(message).total_tokens)
        .sum()
}

pub(crate) fn estimate_json_tokens<T: Serialize>(value: &T) -> usize {
    serde_json::to_string(value)
        .map(|content| estimate_string_tokens(&content, JSON_CHARS_PER_TOKEN))
        .unwrap_or(0)
}

pub(super) fn legacy_context_breakdown(
    base_prompt: &str,
    summary: Option<&str>,
    history: &[SessionMessage],
    response_reserve: usize,
) -> ContextTokenBreakdown {
    let system_prompt_tokens = if base_prompt.trim().is_empty() {
        0
    } else {
        MESSAGE_OVERHEAD_TOKENS + approx_tokens(base_prompt)
    };
    let summary_tokens = summary
        .filter(|summary| !summary.trim().is_empty())
        .map(|summary| CONTENT_BLOCK_OVERHEAD_TOKENS + approx_tokens(summary))
        .unwrap_or(0);
    let history_tokens = history
        .iter()
        .map(|message| MESSAGE_OVERHEAD_TOKENS + approx_tokens(&message.content))
        .sum::<usize>();
    let prompt_tokens = apply_safety_margin(
        system_prompt_tokens
            .saturating_add(summary_tokens)
            .saturating_add(history_tokens),
    );
    ContextTokenBreakdown {
        system_prompt_tokens,
        summary_tokens,
        history_tokens,
        response_reserve_tokens: response_reserve,
        total_tokens: prompt_tokens.saturating_add(response_reserve),
        ..ContextTokenBreakdown::default()
    }
}

pub(super) fn model_context_breakdown(
    base_prompt: &str,
    summary: Option<&str>,
    raw_history: &[serde_json::Value],
    response_reserve: usize,
) -> ContextTokenBreakdown {
    let system_prompt_tokens = if base_prompt.trim().is_empty() {
        0
    } else {
        MESSAGE_OVERHEAD_TOKENS + approx_tokens(base_prompt)
    };
    let summary_tokens = summary
        .filter(|summary| !summary.trim().is_empty())
        .map(|summary| CONTENT_BLOCK_OVERHEAD_TOKENS + approx_tokens(summary))
        .unwrap_or(0);
    let mut message_estimate = MessageTokenEstimate::default();
    for message in raw_history {
        message_estimate =
            message_estimate.saturating_add(estimate_message_token_pressure(message));
    }
    let prompt_tokens = apply_safety_margin(
        system_prompt_tokens
            .saturating_add(summary_tokens)
            .saturating_add(message_estimate.total_tokens),
    );
    ContextTokenBreakdown {
        system_prompt_tokens,
        summary_tokens,
        history_tokens: message_estimate.total_tokens,
        tool_result_tokens: message_estimate.tool_result_tokens,
        tool_call_tokens: message_estimate.tool_call_tokens,
        attachment_tokens: message_estimate.attachment_tokens,
        image_tokens: message_estimate.image_tokens,
        response_reserve_tokens: response_reserve,
        total_tokens: prompt_tokens.saturating_add(response_reserve),
        ..ContextTokenBreakdown::default()
    }
}

pub(super) fn build_preflight_snapshot(
    thread_id: &str,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    raw_history: &[serde_json::Value],
    tool_descriptors: &[ToolDescriptor],
) -> PreflightSnapshot {
    let updated_at = chrono::Utc::now().to_rfc3339();
    let response_reserve = response_reserve_tokens(config, settings);
    let system_prompt_tokens = if config.system_prompt.trim().is_empty() {
        0
    } else {
        MESSAGE_OVERHEAD_TOKENS + approx_tokens(&config.system_prompt)
    };
    let mut message_estimate = MessageTokenEstimate::default();
    for message in raw_history {
        message_estimate =
            message_estimate.saturating_add(estimate_message_token_pressure(message));
    }
    let tool_descriptor_tokens = estimate_json_tokens(&tool_descriptors);
    let prompt_tokens = apply_safety_margin(
        system_prompt_tokens
            .saturating_add(message_estimate.total_tokens)
            .saturating_add(tool_descriptor_tokens),
    );
    let plan = ContextBudgetPlanner::plan(
        thread_id,
        config,
        settings,
        prompt_tokens,
        response_reserve,
        message_estimate.tool_result_reducible_chars,
        raw_history.len(),
        &updated_at,
    );
    let total_tokens = prompt_tokens.saturating_add(plan.response_reserve.tokens);
    PreflightSnapshot {
        provider: config.provider.clone(),
        model: config.model.clone(),
        config_fingerprint: context_config_fingerprint(config, settings),
        estimated_tokens: total_tokens,
        context_window_tokens: plan.window.effective_tokens,
        response_reserve_tokens: plan.response_reserve.tokens,
        context_window_source: plan.window.effective_source.to_string(),
        native_context_window_tokens: plan.window.native_tokens,
        native_context_window_source: plan.window.native_source.to_string(),
        effective_context_window_tokens: plan.window.effective_tokens,
        effective_context_window_source: plan.window.effective_source.to_string(),
        response_reserve_source: plan.response_reserve.source.to_string(),
        provider_metadata_fetched_at: None,
        provider_metadata_stale: false,
        provider_metadata_error: None,
        breakdown: ContextTokenBreakdown {
            system_prompt_tokens,
            history_tokens: message_estimate.total_tokens,
            tool_descriptor_tokens,
            tool_result_tokens: message_estimate.tool_result_tokens,
            tool_call_tokens: message_estimate.tool_call_tokens,
            attachment_tokens: message_estimate.attachment_tokens,
            image_tokens: message_estimate.image_tokens,
            response_reserve_tokens: plan.response_reserve.tokens,
            total_tokens,
            ..ContextTokenBreakdown::default()
        },
        context_budget_status: plan.status,
        updated_at,
    }
}

pub(super) fn build_context_budget_plan(
    thread_id: &str,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    prompt_tokens: usize,
    reserve_tokens: usize,
    tool_result_reducible_chars: usize,
    message_count: usize,
    updated_at: &str,
) -> ContextBudgetPlan {
    let profile = model_context_profile(config, settings);
    let status = build_context_budget_status_for_window(
        thread_id,
        config,
        settings,
        prompt_tokens,
        reserve_tokens,
        profile.window,
        profile.response_reserve,
        tool_result_reducible_chars,
        message_count,
        updated_at,
    );
    ContextBudgetPlan {
        status,
        window: profile.window,
        response_reserve: profile.response_reserve,
    }
}

#[cfg(test)]
pub(super) fn build_context_budget_status(
    _thread_id: &str,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    prompt_tokens: usize,
    reserve_tokens: usize,
    context_window_tokens: usize,
    tool_result_reducible_chars: usize,
    message_count: usize,
    updated_at: &str,
) -> ContextBudgetStatus {
    let window = ContextWindowInfo {
        native_tokens: context_window_tokens,
        native_source: "config",
        effective_tokens: context_window_tokens,
        effective_source: "config",
    };
    let reserve = ResponseReserveInfo {
        tokens: reserve_tokens,
        source: "config",
    };
    build_context_budget_status_for_window(
        _thread_id,
        config,
        settings,
        prompt_tokens,
        reserve_tokens,
        window,
        reserve,
        tool_result_reducible_chars,
        message_count,
        updated_at,
    )
}

fn build_context_budget_status_for_window(
    _thread_id: &str,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    prompt_tokens: usize,
    reserve_tokens: usize,
    window: ContextWindowInfo,
    reserve: ResponseReserveInfo,
    tool_result_reducible_chars: usize,
    message_count: usize,
    updated_at: &str,
) -> ContextBudgetStatus {
    let context_window_tokens = window.effective_tokens;
    let effective_reserve_tokens = reserve_tokens.min(context_window_tokens);
    let prompt_budget_before_reserve =
        context_window_tokens.saturating_sub(effective_reserve_tokens);
    let remaining_prompt_budget_tokens =
        prompt_budget_before_reserve as isize - prompt_tokens as isize;
    let overflow_tokens = prompt_tokens.saturating_sub(prompt_budget_before_reserve);
    let trigger_tokens = ((context_window_tokens as f64)
        * settings.trigger_ratio.clamp(0.1, 0.99) as f64)
        .round() as usize;
    let total_tokens = prompt_tokens.saturating_add(effective_reserve_tokens);
    let over_trigger = total_tokens >= trigger_tokens;
    let has_compactable_messages = message_count
        > settings
            .protect_head_messages
            .saturating_add(settings.protect_tail_messages);
    let reducible_tokens = tool_result_reducible_chars
        .saturating_add(TOOL_RESULT_CHARS_PER_TOKEN.saturating_sub(1))
        / TOOL_RESULT_CHARS_PER_TOKEN;
    let (context_guard_status, context_guard_reason) =
        context_guard(window, remaining_prompt_budget_tokens);
    let route = if overflow_tokens == 0 && !over_trigger && context_guard_status != "blocked" {
        "fits"
    } else if overflow_tokens > 0
        && reducible_tokens >= overflow_tokens.saturating_add(TRUNCATION_ROUTE_BUFFER_TOKENS)
    {
        "prune_tools"
    } else if overflow_tokens > 0 && tool_result_reducible_chars > 0 {
        "compact_then_prune"
    } else if context_guard_status == "blocked" && overflow_tokens == 0 && !has_compactable_messages
    {
        "reject_too_large"
    } else {
        "compact"
    };
    ContextBudgetStatus {
        source: "pre-prompt-estimate".to_string(),
        provider: config.provider.clone(),
        model: config.model.clone(),
        route: route.to_string(),
        should_compact: matches!(route, "compact" | "compact_then_prune"),
        estimated_prompt_tokens: prompt_tokens,
        context_token_budget: context_window_tokens,
        native_context_window_tokens: window.native_tokens,
        native_context_window_source: window.native_source.to_string(),
        effective_context_window_tokens: window.effective_tokens,
        effective_context_window_source: window.effective_source.to_string(),
        response_reserve_source: reserve.source.to_string(),
        provider_metadata_fetched_at: None,
        provider_metadata_stale: false,
        provider_metadata_error: None,
        prompt_budget_before_reserve,
        reserve_tokens,
        effective_reserve_tokens,
        remaining_prompt_budget_tokens,
        overflow_tokens,
        tool_result_reducible_chars,
        tool_result_reducible_tokens: reducible_tokens,
        context_guard_status: context_guard_status.to_string(),
        context_guard_reason: context_guard_reason.to_string(),
        message_count,
        unwindowed_message_count: message_count,
        updated_at: updated_at.to_string(),
    }
}

pub(super) fn estimate_message_token_pressure(message: &serde_json::Value) -> MessageTokenEstimate {
    let role = message
        .get("role")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    let mut estimate = MessageTokenEstimate {
        total_tokens: MESSAGE_OVERHEAD_TOKENS,
        ..MessageTokenEstimate::default()
    };
    if let Some(content) = message.get("content") {
        let content_estimate = estimate_content_token_pressure(content, role == "tool");
        estimate = estimate.saturating_add(content_estimate);
    }
    if let Some(tool_calls) = message.get("tool_calls") {
        let tool_call_tokens = estimate_json_payload_tokens(tool_calls);
        estimate.total_tokens = estimate.total_tokens.saturating_add(tool_call_tokens);
        estimate.tool_call_tokens = estimate.tool_call_tokens.saturating_add(tool_call_tokens);
    }
    estimate
}

fn estimate_content_token_pressure(
    content: &serde_json::Value,
    is_tool_result: bool,
) -> MessageTokenEstimate {
    match content {
        serde_json::Value::String(text) => {
            let chars_per_token = if is_tool_result {
                TOOL_RESULT_CHARS_PER_TOKEN
            } else {
                ESTIMATED_CHARS_PER_TOKEN
            };
            let tokens = estimate_string_tokens(text, chars_per_token);
            MessageTokenEstimate {
                total_tokens: tokens,
                tool_result_tokens: if is_tool_result { tokens } else { 0 },
                tool_result_reducible_chars: if is_tool_result {
                    text.chars().count().saturating_sub(800)
                } else {
                    0
                },
                ..MessageTokenEstimate::default()
            }
        }
        serde_json::Value::Array(items) => {
            items
                .iter()
                .fold(MessageTokenEstimate::default(), |acc, item| {
                    acc.saturating_add(estimate_content_block_token_pressure(item, is_tool_result))
                })
        }
        other => {
            let tokens = estimate_json_payload_tokens(other);
            MessageTokenEstimate {
                total_tokens: tokens,
                ..MessageTokenEstimate::default()
            }
        }
    }
}

fn estimate_content_block_token_pressure(
    block: &serde_json::Value,
    is_tool_result: bool,
) -> MessageTokenEstimate {
    let chars_per_token = if is_tool_result {
        TOOL_RESULT_CHARS_PER_TOKEN
    } else {
        ESTIMATED_CHARS_PER_TOKEN
    };
    if let Some(text) = block.get("text").and_then(serde_json::Value::as_str) {
        let tokens = CONTENT_BLOCK_OVERHEAD_TOKENS + estimate_string_tokens(text, chars_per_token);
        return MessageTokenEstimate {
            total_tokens: tokens,
            tool_result_tokens: if is_tool_result { tokens } else { 0 },
            attachment_tokens: attachment_marker_tokens(text),
            tool_result_reducible_chars: if is_tool_result {
                text.chars().count().saturating_sub(800)
            } else {
                0
            },
            ..MessageTokenEstimate::default()
        };
    }
    if block.get("image_url").is_some()
        || block.get("inline_data").is_some()
        || block.get("fileData").is_some()
    {
        let tokens = CONTENT_BLOCK_OVERHEAD_TOKENS + IMAGE_BLOCK_TOKENS;
        return MessageTokenEstimate {
            total_tokens: tokens,
            attachment_tokens: tokens,
            image_tokens: IMAGE_BLOCK_TOKENS,
            ..MessageTokenEstimate::default()
        };
    }
    let tokens = CONTENT_BLOCK_OVERHEAD_TOKENS + estimate_json_payload_tokens(block);
    MessageTokenEstimate {
        total_tokens: tokens,
        ..MessageTokenEstimate::default()
    }
}

fn attachment_marker_tokens(text: &str) -> usize {
    if !text.contains("<attachments>") {
        return 0;
    }
    text.split_once("<attachments>")
        .and_then(|(_, rest)| rest.split_once("</attachments>").map(|(body, _)| body))
        .map(|body| estimate_string_tokens(body, ESTIMATED_CHARS_PER_TOKEN))
        .unwrap_or(0)
}

fn estimate_json_payload_tokens(value: &serde_json::Value) -> usize {
    estimate_string_tokens(&value.to_string(), JSON_CHARS_PER_TOKEN)
}

pub(super) fn estimate_string_tokens(text: &str, chars_per_token: usize) -> usize {
    text.chars()
        .count()
        .saturating_add(chars_per_token.saturating_sub(1))
        / chars_per_token.max(1)
}

pub(super) fn apply_safety_margin(tokens: usize) -> usize {
    ((tokens as f64) * PREFLIGHT_SAFETY_MARGIN).ceil() as usize
}

pub(super) fn context_window_tokens(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> usize {
    context_window_details(config, settings).effective_tokens
}

pub(super) fn context_window_details(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> ContextWindowInfo {
    let (native_tokens, native_source) = if let Some(tokens) = settings
        .native_context_window_tokens
        .filter(|tokens| *tokens > 0)
    {
        (tokens, "config")
    } else if let Some(tokens) = settings
        .provider_context_window_tokens
        .filter(|tokens| *tokens > 0)
    {
        (tokens, "provider")
    } else {
        model_context_window_info(&config.provider, &config.model)
    };
    if let Some(tokens) = settings.context_window_tokens.filter(|tokens| *tokens > 0) {
        return ContextWindowInfo {
            native_tokens,
            native_source,
            effective_tokens: tokens,
            effective_source: "config",
        };
    }
    ContextWindowInfo {
        native_tokens,
        native_source,
        effective_tokens: native_tokens,
        effective_source: native_source,
    }
}

pub(super) fn response_reserve_tokens(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> usize {
    response_reserve_info(config, settings).tokens
}

pub(super) fn response_reserve_info(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> ResponseReserveInfo {
    if let Some(tokens) = settings
        .response_reserve_tokens
        .filter(|tokens| *tokens > 0)
    {
        return ResponseReserveInfo {
            tokens,
            source: "config",
        };
    }
    if config.max_tokens > 0 {
        return ResponseReserveInfo {
            tokens: (config.max_tokens as usize).clamp(2_048, 8_192),
            source: "model_output_limit",
        };
    }
    ResponseReserveInfo {
        tokens: 4_096,
        source: "default",
    }
}

pub(super) fn model_context_profile(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> ModelContextProfile {
    ModelContextProfile {
        provider: config.provider.clone(),
        model: config.model.clone(),
        window: context_window_details(config, settings),
        response_reserve: response_reserve_info(config, settings),
    }
}

fn context_guard(
    window: ContextWindowInfo,
    remaining_prompt_budget_tokens: isize,
) -> (&'static str, &'static str) {
    if window.effective_tokens == 0 {
        return ("blocked", "context_window_missing");
    }
    let budget = window.effective_tokens;
    let hard_floor = CONTEXT_GUARD_HARD_MIN_TOKENS
        .max(((budget as f64) * CONTEXT_GUARD_HARD_MIN_RATIO).round() as usize);
    let warn_floor = CONTEXT_GUARD_WARN_MIN_TOKENS
        .max(((budget as f64) * CONTEXT_GUARD_WARN_MIN_RATIO).round() as usize);
    if remaining_prompt_budget_tokens < hard_floor as isize {
        ("blocked", "remaining_budget_below_hard_floor")
    } else if remaining_prompt_budget_tokens < warn_floor as isize {
        ("warning", "remaining_budget_below_warning_floor")
    } else {
        ("ok", "")
    }
}

fn model_context_window_info(provider: &str, model: &str) -> (usize, &'static str) {
    let provider_lower = provider.to_ascii_lowercase();
    let lower = model.to_ascii_lowercase();
    let (qualified_provider, qualified_model) = split_qualified_model(&lower);
    let explicit_provider = !provider_lower.trim().is_empty() || qualified_provider.is_some();
    let effective_provider = if provider_lower.trim().is_empty() {
        qualified_provider.unwrap_or_default()
    } else {
        provider_lower.as_str()
    };
    let lower = qualified_model.unwrap_or(lower.as_str());
    if !explicit_provider {
        // default-fallback: model window not in catalog; compaction will use the 128k default (DIMA #2026111000120512225 §2.A baseline)
        return (DEFAULT_CONTEXT_WINDOW_TOKENS, "default");
    }
    if effective_provider.contains("gemini")
        || lower.contains("gemini-1.5")
        || lower.contains("gemini-2")
        || lower.contains("gemini-pro")
        || lower.contains("gpt-4.1")
    {
        (1_000_000, "model_rule")
    } else if lower.contains("claude") || lower.contains("gpt-5") {
        (200_000, "model_rule")
    } else if lower.contains("kimi-k2") || lower.contains("kimi-k2.7") {
        (256_000, "model_rule")
    } else if lower.contains("gpt-4o")
        || lower.contains("deepseek")
        || lower.contains("qwen")
        || lower.contains("moonshot")
        || lower.contains("kimi")
    {
        (128_000, "model_rule")
    } else {
        // default-fallback: model window not in catalog; compaction will use the 128k default (DIMA #2026111000120512225 §2.A baseline)
        (DEFAULT_CONTEXT_WINDOW_TOKENS, "default")
    }
}

fn split_qualified_model(model: &str) -> (Option<&str>, Option<&str>) {
    let Some((provider, model)) = model.split_once('/') else {
        return (None, None);
    };
    if provider.trim().is_empty() || model.trim().is_empty() {
        (None, None)
    } else {
        (Some(provider.trim()), Some(model.trim()))
    }
}

#[cfg(test)]
mod property_tests {
    use super::{
        ESTIMATED_CHARS_PER_TOKEN, apply_safety_margin, approx_tokens, estimate_string_tokens,
    };
    use proptest::prelude::*;

    proptest! {
        // Token estimation is monotonic: appending characters never decreases
        // the estimate. Context-budget decisions rely on this — a longer prompt
        // must never look cheaper than a shorter prefix of it.
        #[test]
        fn approx_tokens_is_monotonic_in_length(a in ".*", b in ".*") {
            let whole = format!("{a}{b}");
            prop_assert!(approx_tokens(&whole) >= approx_tokens(&a));
        }

        // estimate_string_tokens is a ceiling division: the estimate is always
        // within [chars/cpt, chars/cpt + 1] and never zero for non-empty input.
        #[test]
        fn estimate_string_tokens_is_ceil_div(
            text in ".*",
            cpt in 1usize..16,
        ) {
            let chars = text.chars().count();
            let est = estimate_string_tokens(&text, cpt);
            prop_assert_eq!(est, chars.div_ceil(cpt));
            if chars > 0 {
                prop_assert!(est >= 1);
            }
        }

        // The default-CPT path agrees with the ceil-div formula too.
        #[test]
        fn approx_tokens_matches_ceil_div(text in ".*") {
            let chars = text.chars().count();
            prop_assert_eq!(approx_tokens(&text), chars.div_ceil(ESTIMATED_CHARS_PER_TOKEN));
        }

        // The safety margin only ever pads upward (margin >= 1.0), so the
        // reserved budget is never smaller than the raw estimate.
        #[test]
        fn safety_margin_never_shrinks(tokens in 0usize..10_000_000) {
            prop_assert!(apply_safety_margin(tokens) >= tokens);
        }
    }
}

#[cfg(test)]
#[path = "budget_mid_turn_precheck_tests.rs"]
mod mid_turn_precheck_tests;

#[cfg(test)]
mod model_window_fallback_tests {
    //! Regression baseline for the compaction default-window fallback audit
    //! (DIMA #2026111000120512225 §2.A, mapping OpenClaw #195307).
    //!
    //! Napaxi routes every context-window decision through a single helper
    //! (`context_window_details` -> `model_context_window_info`), so it does
    //! NOT hit the OpenClaw chat-path/command-path catalog split. The
    //! same-shaped risk, however, lives in `model_context_window_info`: when
    //! a model is unknown to the catalog (or no provider is explicit), it
    //! silently returns `DEFAULT_CONTEXT_WINDOW_TOKENS` (128k). A large
    //! window model that falls through this fallback would compact at the
    //! 128k budget instead of its real window. These tests pin the current
    //! behavior so a future regression is loud: whitelisted large-window
    //! models resolve to their real window, unknown models land on the
    //! 128k default.

    use super::{DEFAULT_CONTEXT_WINDOW_TOKENS, context_window_details, model_context_window_info};
    use crate::types::{ContextEngineConfig, PlatformLlmConfig};

    #[test]
    fn whitelisted_large_window_model_uses_real_catalog_window() {
        // Claude is in the whitelist with a 200k window. With an explicit
        // provider, `model_context_window_info` must return that real
        // window (source != "default") so compaction uses it rather than
        // the 128k default.
        let (window, source) = model_context_window_info("anthropic", "claude-3.5-sonnet");
        assert_eq!(window, 200_000);
        assert_ne!(source, "default");

        // Gemini is whitelisted at 1M.
        let (window, source) = model_context_window_info("google", "gemini-1.5-pro");
        assert_eq!(window, 1_000_000);
        assert_ne!(source, "default");
    }

    #[test]
    fn unknown_model_falls_back_to_default_window() {
        // An unknown model (no whitelist hit) must fall back to the 128k
        // default. Pinning this as the regression baseline for the same-
        // shaped OpenClaw #195307 silent-fallback risk.
        let (window, source) = model_context_window_info("openai", "some-unknown-model");
        assert_eq!(window, DEFAULT_CONTEXT_WINDOW_TOKENS);
        assert_eq!(source, "default");
    }

    #[test]
    fn no_explicit_provider_falls_back_to_default_window() {
        // Without an explicit provider (empty string AND no qualified
        // `provider/model` form), the function cannot resolve a catalog
        // entry and must return the 128k default. This is the silent-
        // fallback-shaped risk: a config that omits the provider while
        // naming an unknown model compacts at 128k.
        let (window, source) = model_context_window_info("", "some-unknown-model");
        assert_eq!(window, DEFAULT_CONTEXT_WINDOW_TOKENS);
        assert_eq!(source, "default");
    }

    fn llm_config(provider: &str, model: &str) -> PlatformLlmConfig {
        PlatformLlmConfig {
            provider: provider.to_string(),
            model: model.to_string(),
            ..PlatformLlmConfig::default()
        }
    }

    #[test]
    fn context_window_details_uses_real_catalog_window_for_whitelisted_model() {
        // No native/provider window override in settings -> the catalog
        // path (`model_context_window_info`) drives the effective window.
        // A whitelisted large-window model must surface its real window as
        // the effective_tokens with source != "default", so compaction
        // uses the real window instead of the 128k default. This is the
        // §2.A core assertion: the catalog propagates through the single
        // `context_window_details` helper.
        let config = llm_config("anthropic", "claude-3.5-sonnet");
        let settings = ContextEngineConfig::default();
        let details = context_window_details(&config, &settings);
        assert_eq!(
            details.effective_tokens, 200_000,
            "whitelisted claude model must resolve to its real 200k window"
        );
        assert_ne!(
            details.effective_source, "default",
            "whitelisted model source must not be the default fallback"
        );
    }

    #[test]
    fn context_window_details_falls_back_to_default_for_unknown_model() {
        // An unknown model with no native/provider override must fall back
        // to the 128k default. Pinning this as the regression baseline:
        // a session on an unknown model compacts at 128k (the §2.A audit
        // baseline).
        let config = llm_config("openai", "some-unknown-model");
        let settings = ContextEngineConfig::default();
        let details = context_window_details(&config, &settings);
        assert_eq!(details.effective_tokens, DEFAULT_CONTEXT_WINDOW_TOKENS);
        assert_eq!(details.effective_source, "default");
    }
}
