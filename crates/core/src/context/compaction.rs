//! History compaction and tool-output reduction.
//!
//! Pure transforms that turn an over-budget conversation into a
//! summary-plus-tail history, or compact individual tool result messages
//! when only their payload pushes the prompt over budget. Both flows are
//! invoked from [`super::build_context`] and
//! [`super::compact_tool_messages`].

use std::time::Instant;

use chrono::Utc;

use crate::session::SessionMessage;
use crate::types::{ContextEngineConfig, PlatformLlmConfig};

use super::budget::{
    ContextBudgetPlanner, TOOL_RESULT_CHARS_PER_TOKEN, context_window_tokens,
    estimate_context_tokens, estimate_message_token_pressure, estimate_messages_tokens,
    normalized_config, response_reserve_info, response_reserve_tokens,
};
use super::state::{ContextState, ContextSummaryRecord};

#[path = "compaction_cold.rs"]
mod compaction_cold;
#[path = "compaction_warm.rs"]
mod compaction_warm;
#[cfg(test)]
pub(crate) use compaction_warm::with_warm_path_probe;

const COMPACTION_SAFETY_MARGIN: f64 = 1.2;
const COMPACTION_OVERHEAD_TOKENS: usize = 4_096;
const MAX_PROTECTED_TAIL_TOKENS: usize = 20_000;
const PROTECTED_TAIL_RATIO: f64 = 0.15;
const OVERSIZED_MESSAGE_RATIO: f64 = 0.50;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct ToolMessageCompactionStats {
    pub(crate) compacted_messages: usize,
    pub(crate) original_chars: usize,
    pub(crate) compacted_chars: usize,
    pub(crate) pruned_chars: usize,
    pub(crate) estimated_pruned_tokens: usize,
}

impl ToolMessageCompactionStats {
    fn record_compaction(&mut self, original_chars: usize, compacted_chars: usize) {
        self.compacted_messages = self.compacted_messages.saturating_add(1);
        self.original_chars = self.original_chars.saturating_add(original_chars);
        self.compacted_chars = self.compacted_chars.saturating_add(compacted_chars);
        self.pruned_chars = self.original_chars.saturating_sub(self.compacted_chars);
        self.estimated_pruned_tokens = self
            .pruned_chars
            .saturating_add(TOOL_RESULT_CHARS_PER_TOKEN.saturating_sub(1))
            / TOOL_RESULT_CHARS_PER_TOKEN;
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.compacted_messages == 0
    }
}

pub(super) struct CompactedHistory {
    pub(super) summary: ContextSummaryRecord,
    pub(super) turns_removed: usize,
}

struct SummaryResult {
    content: String,
    strategy: String,
    adaptive_chunk_count: usize,
    oversized_message_count: usize,
}

pub(super) fn has_compactable_middle(
    history: &[SessionMessage],
    settings: &ContextEngineConfig,
) -> bool {
    let head_count = settings.protect_head_messages.min(history.len());
    let tail_count = settings
        .protect_tail_messages
        .min(history.len().saturating_sub(head_count));
    let Some(compact_end) = history.len().checked_sub(tail_count) else {
        return false;
    };
    compact_end > head_count
}

pub(super) async fn compact_history(
    history: &[SessionMessage],
    state: &ContextState,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    base_prompt: &str,
    tokens_before: usize,
    focus: Option<&str>,
) -> Result<Option<CompactedHistory>, String> {
    let head_count = settings.protect_head_messages.min(history.len());
    let tail_count = protected_tail_count(history, head_count, config, settings)
        .min(history.len().saturating_sub(head_count));
    let Some(compact_end) = history.len().checked_sub(tail_count) else {
        return Ok(None);
    };
    if compact_end <= head_count {
        return Ok(None);
    }
    let middle = &history[head_count..compact_end];
    if middle.is_empty() {
        return Ok(None);
    }

    let started = Instant::now();
    let requested_strategy = normalized_compaction_strategy(settings);
    let auto_focus = derive_auto_focus_topic(history);
    let effective_focus = focus
        .filter(|value| !value.trim().is_empty())
        .or(auto_focus.as_deref());
    let summary_result = summarize_middle(
        &requested_strategy,
        config,
        settings,
        state
            .summary
            .as_ref()
            .map(|summary| summary.content.as_str()),
        middle,
        effective_focus,
    )
    .await?;
    let Some(last_middle) = middle.last() else {
        return Ok(None);
    };
    let compacted_through_message_id = last_middle.id.clone();
    let after_history = [&history[..head_count], &history[compact_end..]].concat();
    let tokens_after =
        estimate_context_tokens(base_prompt, Some(&summary_result.content), &after_history)
            + response_reserve_tokens(config, settings);
    Ok(Some(CompactedHistory {
        summary: ContextSummaryRecord {
            content: summary_result.content,
            compacted_through_message_id,
            source_message_count: middle.len(),
            tokens_before,
            tokens_after,
            created_at: Utc::now().to_rfc3339(),
            strategy: summary_result.strategy,
            duration_ms: Some(started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64),
            focus: effective_focus.map(str::to_string),
            adaptive_chunk_count: Some(summary_result.adaptive_chunk_count),
            oversized_message_count: Some(summary_result.oversized_message_count),
            protected_tail_tokens: Some(protected_tail_tokens(&history[compact_end..])),
        },
        turns_removed: middle.len(),
    }))
}

async fn summarize_middle(
    strategy: &str,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    previous_summary: Option<&str>,
    messages: &[SessionMessage],
    focus: Option<&str>,
) -> Result<SummaryResult, String> {
    match strategy {
        "local_summary" => Ok(SummaryResult {
            content: summarize_middle_locally(previous_summary, messages, focus),
            strategy: "local_summary".to_string(),
            adaptive_chunk_count: 1,
            oversized_message_count: 0,
        }),
        "llm_summary" => {
            match summarize_middle_with_llm(config, settings, previous_summary, messages, focus)
                .await
            {
                Ok(mut result) => {
                    result.strategy = "llm_summary".to_string();
                    Ok(result)
                }
                Err(error) => {
                    tracing::warn!(
                        error,
                        "Context compaction LLM summary failed; falling back to local summary"
                    );
                    Ok(SummaryResult {
                        content: summarize_middle_locally(previous_summary, messages, focus),
                        strategy: "local_summary_fallback".to_string(),
                        adaptive_chunk_count: 1,
                        oversized_message_count: 0,
                    })
                }
            }
        }
        other => Err(format!(
            "Unsupported context compaction strategy `{other}`. Use `llm_summary` or `local_summary`."
        )),
    }
}

fn summarize_middle_locally(
    previous_summary: Option<&str>,
    messages: &[SessionMessage],
    focus: Option<&str>,
) -> String {
    let mut user_items = Vec::new();
    let mut assistant_items = Vec::new();
    let mut tool_items = Vec::new();
    for message in messages {
        let preview = redacted_preview(&message.content, 280);
        match message.role.as_str() {
            "user" => user_items.push(preview),
            "assistant" => assistant_items.push(preview),
            "tool_calls" => tool_items.extend(tool_summary_items(&message.content, 6)),
            _ => {}
        }
    }
    let mut sections = Vec::new();
    sections.push("## Conversation Context Summary".to_string());
    sections.push(
        "This summary compresses earlier conversation turns. Use it as durable context, but prefer the uncompressed recent messages when they conflict."
            .to_string(),
    );
    if let Some(focus) = focus.filter(|value| !value.trim().is_empty()) {
        sections.push(format!("### Focus\n{}", redacted_preview(focus, 500)));
    }
    if let Some(previous) = previous_summary.filter(|value| !value.trim().is_empty()) {
        sections.push(format!(
            "### Previous Summary\n{}",
            redacted_preview(previous, 1400)
        ));
    }
    sections.push(format!(
        "### User Goals And Constraints\n{}",
        bullet_list(&user_items, 8)
    ));
    sections.push(format!(
        "### Assistant Progress And Decisions\n{}",
        bullet_list(&assistant_items, 8)
    ));
    sections.push(format!(
        "### Tool Outcomes\n{}",
        bullet_list(&tool_items, 8)
    ));
    sections.push("### Next-Step Context\nContinue from the protected recent messages. Do not assume omitted tool output unless it appears in the recent trace or this summary.".to_string());
    sections.join("\n\n")
}

async fn summarize_middle_with_llm(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    previous_summary: Option<&str>,
    messages: &[SessionMessage],
    focus: Option<&str>,
) -> Result<SummaryResult, String> {
    // range-local 累积 + payload-free planning + lazy render selected rows
    // (see `compaction_assembly` mod doc + plan.md §3.3). Default
    // `OwnedSliceTranscript` keeps short/mid-session byte-equal with the
    // previous direct materialize-all flow.
    use super::compaction_assembly::{OwnedSliceTranscript, collect_facts, plan_from_facts};

    let transcript = OwnedSliceTranscript::new(messages);
    let threshold = effective_oversized_threshold(config, settings);
    let facts = collect_facts(&transcript, threshold);
    let plan = plan_from_facts(&facts, config, settings);

    if plan.chunks.len() > 1 {
        let chunk_count = plan.chunks.len();
        let mut chunk_summaries = Vec::new();
        for (index, chunk) in plan.chunks.iter().enumerate() {
            let chunk_focus = format!(
                "Chunk {} of {}. Preserve concrete decisions, identifiers, constraints, pending asks, and visible tool outcomes from this chunk.",
                index + 1,
                chunk_count
            );
            // Chunk slices index into the same `messages` slice the
            // `OwnedSliceTranscript` wraps (see `plan_from_facts`); safe to
            // borrow directly for the warm prefix.
            let chunk_messages = &messages[chunk.start..chunk.end];
            let summary = summarize_chunk_with_llm_once(
                config,
                settings,
                &plan,
                chunk,
                &transcript,
                &facts,
                None,
                Some(&chunk_focus),
                chunk_messages,
            )
            .await?;
            chunk_summaries.push(SessionMessage {
                id: format!("compaction_chunk_{}", index + 1),
                role: "assistant".to_string(),
                content: summary,
                created_at: Utc::now().to_rfc3339(),
                interrupted: false,
                turn_id: None,
            });
        }
        let final_focus = focus
            .map(|value| format!("{value}\nMerge the chunk summaries into one durable summary."))
            .unwrap_or_else(|| "Merge the chunk summaries into one durable summary.".to_string());
        return summarize_middle_with_llm_once(
            config,
            settings,
            previous_summary,
            &chunk_summaries,
            Some(&final_focus),
        )
        .await
        .map(|content| SummaryResult {
            content,
            strategy: "llm_summary".to_string(),
            adaptive_chunk_count: chunk_count,
            oversized_message_count: plan.oversized_count,
        });
    }

    let first_chunk = &plan.chunks[0];
    let first_chunk_messages = &messages[first_chunk.start..first_chunk.end];
    summarize_chunk_with_llm_once(
        config,
        settings,
        &plan,
        first_chunk,
        &transcript,
        &facts,
        previous_summary,
        focus,
        first_chunk_messages,
    )
    .await
    .map(|content| SummaryResult {
        content,
        strategy: "llm_summary".to_string(),
        adaptive_chunk_count: 1,
        oversized_message_count: plan.oversized_count,
    })
}

/// Lazy-per-chunk LLM caller: renders the chunk's selected rows just before
/// the LLM call and drops the rendered `String` right after. The retry path
/// re-renders the prompt with the `retry_focus` injected, so the existing
/// required-section retry logic stays byte-equal with the previous
/// `summarize_middle_with_llm_once` implementation.
///
/// `warm_prefix_messages` is the middle-history slice the chunk covers. When
/// `settings.compaction_model` is empty, this slice is sent verbatim as the
/// warm prefix and the directive is appended at the end so the request shares
/// the session's prompt-cache prefix (OpenClaw #204111). When
/// `compaction_model` is set the cold path is taken instead; the slice is
/// only used to render the cold prompt.
async fn summarize_chunk_with_llm_once(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    plan: &super::compaction_assembly::CompactionPlan,
    chunk: &super::compaction_assembly::CompactionChunk,
    transcript: &dyn super::compaction_assembly::CompactionTranscript,
    facts: &[super::compaction_assembly::CompactionFact],
    previous_summary: Option<&str>,
    focus: Option<&str>,
    warm_prefix_messages: &[SessionMessage],
) -> Result<String, String> {
    let warm_kind = compaction_warm::WarmCompactionKind::ChunkPrefix {
        messages: warm_prefix_messages,
        previous_summary,
    };
    run_compaction_with_retry(
        config,
        settings,
        focus,
        |focus_override| {
            super::compaction_assembly::render_chunk_prompt(
                plan,
                chunk,
                transcript,
                facts,
                previous_summary,
                focus_override,
            )
        },
        warm_kind,
    )
    .await
}

async fn summarize_middle_with_llm_once(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    previous_summary: Option<&str>,
    messages: &[SessionMessage],
    focus: Option<&str>,
) -> Result<String, String> {
    // Merge path for chunk summaries (small `Vec<SessionMessage>`): reuse
    // the existing `compaction_user_prompt` renderer directly so the
    // 6-section prompt structure stays byte-equal with the prior cold flow.
    // Warm merge path folds the chunk summaries into the directive text
    // (they're all `assistant` role and would break Anthropic's user-first /
    // alternating-role rule if sent as a multi-message prefix); see
    // `WarmCompactionKind::MergeDirect` for the rationale.
    let warm_kind = compaction_warm::WarmCompactionKind::MergeDirect {
        chunk_summaries: messages,
        previous_summary,
    };
    run_compaction_with_retry(
        config,
        settings,
        focus,
        |focus_override| compaction_user_prompt(previous_summary, messages, focus_override),
        warm_kind,
    )
    .await
}

/// Shared retry-with-required-sections driver for both the lazy-per-chunk
/// path (`render_chunk_prompt` closure) and the merge path
/// (`compaction_user_prompt` closure).
///
/// Routing:
/// - `compaction_model` non-empty → [`compaction_cold`]: swap system prompt
///   to `compaction_system_prompt()`, override model, single user message
///   via [`crate::llm::complete`] (legacy "cold summarizer", byte-equal with
///   the prior flow).
/// - `compaction_model` empty → [`compaction_warm`]: keep the session's
///   `system_prompt` so the request shares the next normal turn's
///   prompt-cache prefix, send warm prefix messages verbatim, append the
///   directive as a trailing user message. Failure / retry semantics mirror
///   the cold path exactly (timeout, empty summary, six-section check,
///   single retry with `retry_focus` injected), so [`summarize_middle`]'s
///   `local_summary_fallback` chain is unchanged.
async fn run_compaction_with_retry<P>(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    focus: Option<&str>,
    render_prompt: P,
    warm_kind: compaction_warm::WarmCompactionKind<'_>,
) -> Result<String, String>
where
    P: Fn(Option<&str>) -> String,
{
    let compaction_model_set = settings
        .compaction_model
        .as_deref()
        .map(str::trim)
        .map(|model| !model.is_empty())
        .unwrap_or(false);
    if compaction_model_set {
        compaction_cold::run_cold_compaction_with_retry(config, settings, focus, render_prompt)
            .await
    } else {
        compaction_warm::run_warm_compaction_with_retry(config, settings, focus, warm_kind).await
    }
}

/// Effective oversized threshold used by both the legacy sanitize path and
/// the new payload-free planning path. Exposed `pub(super)` so the assembly
/// module can mirror it in `CompactionPlan::from_facts` and lazy render.
pub(super) fn effective_oversized_threshold(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> usize {
    let context_window = context_window_tokens(config, settings);
    let oversized_threshold = ((context_window as f64) * OVERSIZED_MESSAGE_RATIO).round() as usize;
    let max_chunk_tokens = adaptive_chunk_token_budget(config, settings);
    oversized_threshold.min(max_chunk_tokens).max(1)
}

fn summary_has_required_sections(summary: &str) -> bool {
    const REQUIRED: &[&str] = &[
        "Decisions",
        "Open TODOs",
        "Constraints/Rules",
        "Pending user asks",
        "Exact identifiers",
        "Tool outcomes",
    ];
    REQUIRED
        .iter()
        .all(|heading| summary.lines().any(|line| line.trim().contains(heading)))
}

fn normalized_compaction_strategy(settings: &ContextEngineConfig) -> String {
    match settings.compaction_strategy.trim() {
        "" => "llm_summary".to_string(),
        "recursive_summary" => "llm_summary".to_string(),
        "llm_summary" => "llm_summary".to_string(),
        "local_summary" => "local_summary".to_string(),
        other => other.to_string(),
    }
}

fn compaction_max_tokens(config: &PlatformLlmConfig, settings: &ContextEngineConfig) -> i32 {
    let reserve = response_reserve_tokens(config, settings);
    let preferred = if reserve > 0 {
        reserve.clamp(1_024, 8_192)
    } else {
        4_096
    };
    let current = config.max_tokens;
    if current > 0 {
        current.min(preferred as i32).max(1_024)
    } else {
        preferred as i32
    }
}

fn protected_tail_count(
    history: &[SessionMessage],
    head_count: usize,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> usize {
    let available = history.len().saturating_sub(head_count);
    let minimum = settings.protect_tail_messages.min(available);
    if available == 0 {
        return 0;
    }
    let available_tokens = history[head_count..]
        .iter()
        .map(session_message_tokens)
        .fold(0usize, usize::saturating_add);
    let target_tokens =
        protected_tail_token_target(config, settings).min((available_tokens / 2).max(1));
    let mut count = 0usize;
    let mut tokens = 0usize;
    for message in history[head_count..].iter().rev() {
        count = count.saturating_add(1);
        tokens = tokens.saturating_add(session_message_tokens(message));
        if count >= minimum && tokens >= target_tokens {
            break;
        }
    }
    count.min(available)
}

fn protected_tail_token_target(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> usize {
    let context_window = context_window_tokens(config, settings);
    ((context_window as f64 * PROTECTED_TAIL_RATIO).round() as usize)
        .clamp(1, MAX_PROTECTED_TAIL_TOKENS)
}

fn protected_tail_tokens(history: &[SessionMessage]) -> usize {
    history
        .iter()
        .map(session_message_tokens)
        .fold(0usize, usize::saturating_add)
}

pub(super) fn session_message_tokens(message: &SessionMessage) -> usize {
    estimate_context_tokens("", None, std::slice::from_ref(message))
}

pub(super) fn adaptive_chunk_token_budget(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> usize {
    let context_window = context_window_tokens(config, settings);
    let reserve = response_reserve_tokens(config, settings);
    let prompt_budget = context_window
        .saturating_sub(reserve)
        .saturating_sub(COMPACTION_OVERHEAD_TOKENS);
    ((prompt_budget as f64) / COMPACTION_SAFETY_MARGIN)
        .round()
        .max(1_024.0) as usize
}

/// Kept `pub(super)` for byte-equal golden parity tests against the new
/// `compaction_assembly` path; no longer called on the
/// `summarize_middle_with_llm` hot path (oversize replacement now happens
/// lazily inside `render_chunk_prompt`, see `compaction_assembly`).
#[allow(dead_code)]
pub(super) fn sanitize_oversized_messages(
    messages: &[SessionMessage],
    max_chunk_tokens: usize,
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> (Vec<SessionMessage>, usize) {
    let context_window = context_window_tokens(config, settings);
    let oversized_threshold = ((context_window as f64) * OVERSIZED_MESSAGE_RATIO).round() as usize;
    let threshold = oversized_threshold.min(max_chunk_tokens).max(1);
    let mut oversized_count = 0usize;
    let sanitized = messages
        .iter()
        .map(|message| {
            let tokens = session_message_tokens(message);
            if tokens <= threshold {
                return message.clone();
            }
            oversized_count = oversized_count.saturating_add(1);
            let original_chars = message.content.chars().count();
            let preview = compact_text_preview(&message.content, 1_200);
            let mut message = message.clone();
            message.content = format!(
                "[oversized message omitted during context compaction: role={}, original_chars={}, estimated_tokens={}]\nPreview: {}",
                message.role, original_chars, tokens, preview
            );
            message
        })
        .collect();
    (sanitized, oversized_count)
}

/// Kept `pub(super)` for byte-equal golden parity tests against the new
/// `compaction_assembly` path; no longer called on the
/// `summarize_middle_with_llm` hot path (chunking now happens inside
/// `CompactionPlan::from_facts`, see `compaction_assembly`).
#[allow(dead_code)]
pub(super) fn chunk_messages_by_tokens(
    messages: &[SessionMessage],
    max_chunk_tokens: usize,
) -> Vec<Vec<SessionMessage>> {
    let mut chunks: Vec<Vec<SessionMessage>> = Vec::new();
    let mut current: Vec<SessionMessage> = Vec::new();
    let mut current_tokens = 0usize;
    for message in messages {
        let tokens = session_message_tokens(message);
        if !current.is_empty() && current_tokens.saturating_add(tokens) > max_chunk_tokens {
            chunks.push(std::mem::take(&mut current));
            current_tokens = 0;
        }
        current.push(message.clone());
        current_tokens = current_tokens.saturating_add(tokens);
    }
    if !current.is_empty() {
        chunks.push(current);
    }
    if chunks.is_empty() {
        chunks.push(Vec::new());
    }
    chunks
}

fn compaction_system_prompt() -> String {
    [
        "You are Napaxi's context compactor.",
        "Compress earlier conversation context for a mobile agent loop.",
        "Preserve exact identifiers, file paths, commands, decisions, constraints, pending asks, and tool outcomes.",
        "Do not invent facts. Prefer concrete bullets over prose.",
        "Output exactly these Markdown sections: Decisions, Open TODOs, Constraints/Rules, Pending user asks, Exact identifiers, Tool outcomes.",
    ]
    .join("\n")
}

pub(super) fn compaction_user_prompt(
    previous_summary: Option<&str>,
    messages: &[SessionMessage],
    focus: Option<&str>,
) -> String {
    let mut sections = Vec::new();
    if let Some(focus) = focus.filter(|value| !value.trim().is_empty()) {
        sections.push(format!("Focus:\n{}", redacted_preview(focus, 1_200)));
    }
    if let Some(summary) = previous_summary.filter(|value| !value.trim().is_empty()) {
        sections.push(format!(
            "Previous summary:\n{}",
            redacted_preview(summary, 6_000)
        ));
    }
    let mut message_lines = Vec::new();
    for message in messages {
        match message.role.as_str() {
            "user" | "assistant" => message_lines.push(format!(
                "<message id=\"{}\" role=\"{}\">\n{}\n</message>",
                message.id,
                message.role,
                redacted_preview(&message.content, 1_000)
            )),
            "tool_calls" => {
                let items = tool_summary_items(&message.content, 12);
                if items.is_empty() && !message.content.trim().is_empty() {
                    message_lines.push(format!(
                        "<tool_observation source_message_id=\"{}\">\n{}\n</tool_observation>",
                        message.id,
                        redacted_preview(&message.content, 700)
                    ));
                }
                for item in items {
                    message_lines.push(format!(
                        "<tool_observation source_message_id=\"{}\">\n{}\n</tool_observation>",
                        message.id, item
                    ));
                }
            }
            _ => {}
        }
    }
    sections.push(format!(
        "Messages to compact:\n{}",
        if message_lines.is_empty() {
            "No compactable messages.".to_string()
        } else {
            message_lines.join("\n\n")
        }
    ));
    sections.push("Write the durable summary now.".to_string());
    sections.join("\n\n---\n\n")
}

const AUTO_FOCUS_MAX_TURNS: usize = 3;
const AUTO_FOCUS_TURN_MAX_CHARS: usize = 260;
const AUTO_FOCUS_MAX_CHARS: usize = 700;

/// Infer a compact focus hint from the most recent real user turns.
///
/// When the caller does not pass an explicit focus topic, automatic
/// compaction would otherwise summarize with no steer, diluting whatever the
/// user is actively working on. Pulling the last few genuine user messages
/// biases the summary toward current intent. Persisted compaction handoff
/// messages are skipped so a stale prior summary never becomes the focus.
fn derive_auto_focus_topic(history: &[SessionMessage]) -> Option<String> {
    let mut candidates: Vec<String> = Vec::new();
    for message in history.iter().rev() {
        if message.role != "user" {
            continue;
        }
        if is_context_summary_content(&message.content) {
            continue;
        }
        let text = compact_text_preview(message.content.trim(), AUTO_FOCUS_TURN_MAX_CHARS);
        if text.is_empty() {
            continue;
        }
        candidates.push(text);
        if candidates.len() >= AUTO_FOCUS_MAX_TURNS {
            break;
        }
    }
    if candidates.is_empty() {
        return None;
    }
    candidates.reverse();
    let mut focus = String::from("Recent user focus:");
    for item in &candidates {
        focus.push_str("\n- ");
        focus.push_str(item);
    }
    Some(compact_text_preview(&focus, AUTO_FOCUS_MAX_CHARS))
}

fn is_context_summary_content(content: &str) -> bool {
    let trimmed = content.trim_start();
    trimmed.starts_with("## Conversation Context Summary")
        || trimmed.starts_with("[CONTEXT COMPACTION")
}

pub(super) fn tool_summary_items(content: &str, limit: usize) -> Vec<String> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(content) else {
        return Vec::new();
    };
    let Some(calls) = value.get("calls").and_then(serde_json::Value::as_array) else {
        return Vec::new();
    };
    calls
        .iter()
        .take(limit)
        .filter_map(|call| {
            let name = call.get("name").and_then(serde_json::Value::as_str)?;
            if crate::skills::is_hidden_skill_tool(name) {
                return None;
            }
            let result = call
                .get("result")
                .or_else(|| call.get("error"))
                .map(|value| {
                    value
                        .as_str()
                        .map(ToString::to_string)
                        .unwrap_or_else(|| value.to_string())
                })
                .unwrap_or_else(|| "No completed result captured.".to_string());
            Some(format!("{name}: {}", compact_text_preview(&result, 260)))
        })
        .collect()
}

fn bullet_list(items: &[String], limit: usize) -> String {
    let mut out = Vec::new();
    for item in items
        .iter()
        .filter(|item| !item.trim().is_empty())
        .take(limit)
    {
        out.push(format!("- {item}"));
    }
    if out.is_empty() {
        "- No durable details captured.".to_string()
    } else {
        out.join("\n")
    }
}

pub(super) fn visible_history_from_state(
    history: &[SessionMessage],
    state: &ContextState,
    settings: &ContextEngineConfig,
) -> Vec<SessionMessage> {
    let Some(summary) = state.summary.as_ref() else {
        return history.to_vec();
    };
    let head_count = settings.protect_head_messages.min(history.len());
    let mut out = history[..head_count].to_vec();
    let start = history
        .iter()
        .position(|message| message.id == summary.compacted_through_message_id)
        .map(|index| index.saturating_add(1))
        .unwrap_or(head_count)
        .max(head_count);
    out.extend_from_slice(&history[start.min(history.len())..]);
    out
}

pub(super) fn tail_messages(
    history: &[SessionMessage],
    max_messages: usize,
) -> Vec<SessionMessage> {
    let start = history.len().saturating_sub(max_messages);
    history[start..].to_vec()
}

pub(crate) fn compact_tool_messages(
    messages: &mut [serde_json::Value],
    config: &PlatformLlmConfig,
    descriptor_tokens: usize,
) -> ToolMessageCompactionStats {
    let mut stats = ToolMessageCompactionStats::default();
    let settings = normalized_config(&config.context_engine);
    if !settings.enabled {
        return stats;
    }
    let context_window = context_window_tokens(config, &settings);
    let reserve_info = response_reserve_info(config, &settings);
    let reserve = reserve_info.tokens.saturating_add(descriptor_tokens);
    let target_tokens =
        ((context_window as f64) * settings.target_ratio.clamp(0.1, 0.95) as f64).round() as usize;
    let message_estimate = messages.iter().fold(
        super::budget::MessageTokenEstimate::default(),
        |acc, message| acc.saturating_add(estimate_message_token_pressure(message)),
    );
    let plan = ContextBudgetPlanner::plan(
        "tool_loop",
        config,
        &settings,
        message_estimate
            .total_tokens
            .saturating_add(descriptor_tokens),
        reserve_info.tokens,
        message_estimate.tool_result_reducible_chars,
        messages.len(),
        &chrono::Utc::now().to_rfc3339(),
    );
    if !matches!(
        plan.status.route.as_str(),
        "prune_tools" | "compact_then_prune"
    ) && message_estimate.total_tokens.saturating_add(reserve) <= target_tokens
    {
        return stats;
    }

    while estimate_messages_tokens(messages).saturating_add(reserve) > target_tokens {
        let Some(index) = oldest_large_tool_message(messages) else {
            break;
        };
        let content = messages[index]
            .get("content")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default();
        if content.chars().count() <= 800 {
            break;
        }
        let original_chars = content.chars().count();
        let preview = compact_text_preview(content, 360);
        let compacted = format!(
            "[tool result compacted: original_chars={}]\n{}",
            original_chars, preview
        );
        let compacted_chars = compacted.chars().count();
        messages[index]["content"] = serde_json::Value::String(compacted);
        stats.record_compaction(original_chars, compacted_chars);
    }
    stats
}

fn oldest_large_tool_message(messages: &[serde_json::Value]) -> Option<usize> {
    messages
        .iter()
        .enumerate()
        .find(|(_, message)| {
            message.get("role").and_then(serde_json::Value::as_str) == Some("tool")
                && message
                    .get("content")
                    .and_then(serde_json::Value::as_str)
                    .is_some_and(|content| content.chars().count() > 800)
        })
        .map(|(index, _)| index)
}

/// Replace likely-credential substrings in compaction products with a fixed
/// placeholder so summary / floor text never persists raw secrets.
///
/// Applied before preview/anchor extraction (matching the upstream #4a47d02c6d
/// mapping) so credentials cannot be echoed into the durable summary and later
/// re-extracted by downstream summarizers. Conservative on purpose: only high
/// confidence credential shapes are redacted, leaving a readable prefix
/// (`Bearer [REDACTED]`, `ghp_[REDACTED]`) so the surrounding prose stays useful.
///
/// No lookarounds are used — the `regex` crate does not support them — so each
/// pattern is `(prefix)(body)` and we keep the prefix, redacting only the body.
pub(crate) fn redact_credentials_in_text(text: &str) -> String {
    use regex::Regex;
    use std::sync::OnceLock;
    static PATTERNS: OnceLock<Vec<Regex>> = OnceLock::new();
    let patterns = PATTERNS.get_or_init(|| {
        // These patterns are compile-time-constant literals; if any is invalid it is a
        // programmer error caught at first use (build/test), so `expect` (not `unwrap`,
        // which `clippy::unwrap_used` denies in non-test builds — `lib.rs`) is the
        // sanctioned initializer here.
        vec![
            // RFC 6750 bearer tokens: `Bearer <opaque>` / `bearer  <opaque>`.
            Regex::new(r"(?i)(Bearer\s+)([A-Za-z0-9._~+/=-]{8,})")
                .expect("static credential-redaction regex"),
            // `Authorization: <opaque>` (bare scheme-less token, ≥8 alnum, no space).
            Regex::new(r"(?i)(Authorization\s*[:=]\s*)([A-Za-z0-9._~+/=-]{8,})")
                .expect("static credential-redaction regex"),
            // Known provider prefixes — keep the prefix, redact the body.
            //   GitHub (ghp_/gho_/ghs_/ghr_/github_pat_), Anthropic (sk-ant-),
            //   OpenAI (sk- + ≥20 body to avoid short false positives),
            //   Slack (xox[bps]-), Google API key (AIza).
            Regex::new(r"(ghp_|gho_|ghs_|ghr_|github_pat_|sk-ant-)([A-Za-z0-9]{8,})")
                .expect("static credential-redaction regex"),
            Regex::new(r"(sk-)([A-Za-z0-9]{20,})").expect("static credential-redaction regex"),
            Regex::new(r"(xox[bps]-)([A-Za-z0-9-]{8,})").expect("static credential-redaction regex"),
            Regex::new(r"\b(AIza)([A-Za-z0-9_\-]{20,})").expect("static credential-redaction regex"),
            // `<key>=` / `<key>:` assignments: api_key / access_token / refresh_token /
            // client_secret / secret / token, optionally followed by a quote char.
            Regex::new(
                r#"(?i)\b((?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret|token)\s*[:=]\s*['"]?)([A-Za-z0-9._~+/=-]{8,})"#,
            )
            .expect("static credential-redaction regex"),
        ]
    });
    let mut out = text.to_string();
    for re in patterns {
        out = re
            .replace_all(&out, |caps: &regex::Captures| {
                format!("{}[REDACTED]", &caps[1])
            })
            .to_string();
    }
    out
}

/// Redact credentials, then produce the bounded preview. Used at every compaction
/// write-out / sampling point so secrets never survive preview/anchor extraction.
pub(super) fn redacted_preview(text: &str, max_chars: usize) -> String {
    compact_text_preview(&redact_credentials_in_text(text), max_chars)
}

pub(super) fn compact_text_preview(text: &str, max_chars: usize) -> String {
    let compact = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() <= max_chars {
        compact
    } else {
        let preview: String = compact.chars().take(max_chars).collect();
        format!("{preview}...")
    }
}

#[cfg(test)]
#[path = "compaction_auto_focus_tests.rs"]
mod auto_focus_tests;

#[cfg(test)]
#[path = "compaction_credential_redaction_tests.rs"]
mod credential_redaction_tests;

// Golden parity tests for the compaction_assembly path against the legacy
// sanitize+chunk_messages_by_tokens+compaction_user_prompt flow. Locks the
// plan §5.1 / §5.4 invariant: the new lazy-render path produces
// byte-equal prompts with the prior materialize-all path for the
// non-oversized single/multi-chunk cases (the dominant short/mid session
// shape), and the oversized placeholder text matches the legacy
// `sanitize_oversized_messages` output exactly.
#[cfg(test)]
#[path = "compaction_assembly_parity_tests.rs"]
mod compaction_assembly_parity_tests;

// Warm-prefix tests for the `compaction_model`-empty branch of
// `run_compaction_with_retry`. Verify the routing invariant (warm taken
// when `compaction_model` is empty, cold taken when set), the directive
// builder's required-section headings + previous-summary / focus / chunk
// folding, and the fallback chain when the warm LLM response misses the
// required sections at both attempts. Mirrors the cold-path
// `llm_summary_compaction_falls_back_to_local_summary` behavior by routing
// through the same `summarize_middle` -> `local_summary_fallback` chain.
#[cfg(test)]
#[path = "compaction_warm_tests.rs"]
mod compaction_warm_tests;
