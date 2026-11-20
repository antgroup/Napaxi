//! Compaction assembly — payload-free planning over range-local facts.
//!
//! Internal sibling of [`super::compaction`]: holds the OpenClaw #201304
//! "compaction-assembly" counterpart in Napaxi. Pure transform from a
//! [`CompactionTranscript`] (range-local source) to:
//! 1. a single bounded pass of [`CompactionFact`] (no content clone);
//! 2. a payload-free [`CompactionPlan`] over those facts (chunk boundaries
//!    + oversized markers, no content instantiated);
//! 3. lazy per-chunk [`render_chunk_prompt`] — selected rows are rendered
//!    only when the LLM call is about to fire, and the rendered `String`
//!    is dropped as soon as the call returns.
//!
//! The default [`OwnedSliceTranscript`] wraps `&[SessionMessage]` so the
//! short/mid-session path stays byte-equal with the previous direct
//! materialize-all flow (`sanitize_oversized_messages` +
//! `chunk_messages_by_tokens` over owned `Vec<SessionMessage>`).
//!
//! A streaming / paginated impl (transcript that reads rows on demand
//! instead of holding the whole middle window) is the deliberate
//! follow-up for long-lived sessions — see `plan.md §6 CR2`. The trait,
//! `CompactionFact`, `CompactionPlan` and `render_chunk_prompt` form the
//! abstract point where that future impl plugs in without touching
//! `summarize_middle_with_llm` again.

use std::borrow::Cow;

use crate::session::SessionMessage;
use crate::types::{ContextEngineConfig, PlatformLlmConfig};

use super::compaction::{
    adaptive_chunk_token_budget, compact_text_preview, effective_oversized_threshold,
    redacted_preview, session_message_tokens, tool_summary_items,
};

/// Per-message bounded metadata collected in a single pass — no `content`
/// clone, no retained body bytes. Carries only what payload-free planning
/// and lazy oversize-replacement rendering need.
#[allow(dead_code)]
pub(super) struct CompactionFact {
    /// Index inside the middle slice.
    pub index: usize,
    /// `SessionMessage::id` (short fixed-cost string).
    pub id: String,
    /// `SessionMessage::role` (user/assistant/tool_calls/...).
    pub role: String,
    /// `session_message_tokens(message)` — token estimate based on
    /// `approx_tokens`, identical to `chunk_messages_by_tokens` /
    /// `sanitize_oversized_messages` so chunking boundaries stay aligned.
    pub token_estimate: usize,
    /// Token cost this row contributes to the *chunking* budget. For a
    /// non-oversized row this equals [`CompactionFact::token_estimate`]. For
    /// an oversized row it equals `session_message_tokens` of the sanitized
    /// placeholder message (the small `[oversized message omitted …]\nPreview:
    /// …` body), so chunk boundaries match the legacy path, which replaces
    /// oversized rows with that placeholder *before* chunking. The full
    /// `token_estimate` is still used for the `> threshold` oversize
    /// classification; only the chunk budget uses this reduced cost.
    pub chunk_budget_tokens: usize,
    /// `message.content.chars().count()` — kept for future audits of
    /// oversize classification; not consumed by planning directly.
    pub content_chars: usize,
    /// Pass-through timestamp; useful for ordering/audits.
    pub created_at: String,
}

impl CompactionFact {
    fn from_message(index: usize, message: &SessionMessage) -> Self {
        let token_estimate = session_message_tokens(message);
        Self {
            index,
            id: message.id.clone(),
            role: message.role.clone(),
            token_estimate,
            chunk_budget_tokens: token_estimate,
            content_chars: message.content.chars().count(),
            created_at: message.created_at.clone(),
        }
    }
}

/// Range-local compaction source. Decouples transcript reads from fact
/// collection and per-chunk lazy render, so the planning pass and the
/// render pass never materialize the whole middle window in a single
/// `Vec<SessionMessage>` on the calling thread.
///
/// Default impl: [`OwnedSliceTranscript`] (`&[SessionMessage]`).
/// Future long-lived-session impl: a streaming / paginated reader
/// that fetches rows on demand.
pub(super) trait CompactionTranscript {
    /// Number of rows in the middle slice.
    fn len(&self) -> usize;
    /// Lazy single-row fetch by middle index. Drives both fact collection
    /// and lazy per-chunk render; never clones the message body.
    fn message(&self, index: usize) -> &SessionMessage;
}

pub(super) struct OwnedSliceTranscript<'a> {
    slice: &'a [SessionMessage],
}

impl<'a> OwnedSliceTranscript<'a> {
    pub(super) fn new(slice: &'a [SessionMessage]) -> Self {
        Self { slice }
    }
}

impl<'a> CompactionTranscript for OwnedSliceTranscript<'a> {
    fn len(&self) -> usize {
        self.slice.len()
    }
    fn message(&self, index: usize) -> &SessionMessage {
        &self.slice[index]
    }
}

/// Single bounded pass: collect [`CompactionFact`] for every row in the
/// transcript. No content clone; only short per-row metadata strings are
/// retained. For long-lived sessions this is the same-domain "accumulate
/// facts during transcript reads" point that OpenClaw #201304 stages.
/// Collect per-row facts and precompute each row's `chunk_budget_tokens`:
/// for oversized rows (token_estimate > threshold) this is the token cost of
/// the legacy `sanitize_oversized_messages` placeholder message, so the
/// payload-free planner chunks on the same (small) cost the legacy path
/// chunks on after sanitizing — keeping chunk boundaries byte-equal to the
/// prior materialize-all flow. Takes the oversize `threshold`
/// (`effective_oversized_threshold`, identical to legacy's sanitize threshold)
/// so the placeholder budget is computed only for rows legacy would also
/// replace.
pub(super) fn collect_facts(
    transcript: &dyn CompactionTranscript,
    threshold: usize,
) -> Vec<CompactionFact> {
    let len = transcript.len();
    (0..len)
        .map(|index| {
            let message = transcript.message(index);
            let mut fact = CompactionFact::from_message(index, message);
            if fact.token_estimate > threshold {
                fact.chunk_budget_tokens = sanitized_placeholder_tokens(message, &fact);
            }
            fact
        })
        .collect()
}

/// Token cost a row would contribute to the chunking budget when oversized:
/// equal to `session_message_tokens` of the sanitized placeholder message,
/// i.e. the legacy `sanitize_oversized_messages` replacement body `[oversized
/// message omitted …]\nPreview: {compact_text_preview(content, 1200)}`. Used
/// so the payload-free planner's chunk boundaries match the legacy path,
/// which chunks on the sanitized (small-placeholder) token cost rather than
/// the row's original (large) token estimate.
fn sanitized_placeholder_tokens(message: &SessionMessage, fact: &CompactionFact) -> usize {
    let preview = compact_text_preview(&message.content, 1_200);
    let placeholder_content = format!(
        "[oversized message omitted during context compaction: role={}, original_chars={}, estimated_tokens={}]\nPreview: {}",
        message.role, fact.content_chars, fact.token_estimate, preview,
    );
    let placeholder = SessionMessage {
        id: message.id.clone(),
        role: message.role.clone(),
        content: placeholder_content,
        created_at: message.created_at.clone(),
        interrupted: message.interrupted,
        turn_id: message.turn_id.clone(),
    };
    session_message_tokens(&placeholder)
}

/// Payload-free planning output: chunk boundaries + oversized markers
/// only. Consumed by [`render_chunk_prompt`] to lazily render the prompt
/// for a selected chunk just before the LLM call.
pub(super) struct CompactionPlan {
    pub chunks: Vec<CompactionChunk>,
    pub oversized_count: usize,
    /// Effective oversize cutoff: `min(oversize_threshold, adaptive_chunk_token_budget).max(1)`.
    /// Stored so per-row lazy render matches the plan's oversized
    /// classification byte-for-byte.
    pub oversized_threshold: usize,
    /// `adaptive_chunk_token_budget(config, settings)`. Recorded for audit;
    /// parity tests assert it equals the legacy `chunk_messages_by_tokens`
    /// budget parameter.
    #[allow(dead_code)]
    pub adaptive_chunk_token_budget: usize,
}

/// Index range `[start, end)` inside the middle slice, plus an oversized
/// marker (precomputed during planning; render uses it only as a hint and
/// re-checks per row by `fact.token_estimate > plan.oversized_threshold`).
pub(super) struct CompactionChunk {
    pub start: usize,
    pub end: usize,
    /// Oversized marker for this chunk. The lazy renderer re-checks per row
    /// (via `fact.token_estimate > plan.oversized_threshold`) so this is an
    /// audit hint; `cfg_attr(not(test))` because parity tests are the only
    /// reader outside render.
    #[allow(dead_code)]
    pub has_oversized: bool,
}

/// Build a [`CompactionPlan`] from facts only. Chunking mirrors the
/// legacy `chunk_messages_by_tokens(sanitized, max_chunk_tokens)` token
/// sum walk. Crucially, the per-row token cost used for the chunk-budget
/// walk is [`CompactionFact::chunk_budget_tokens`], which for oversized
/// rows equals the legacy sanitized placeholder's token cost (not the
/// row's original large token estimate) — so chunk boundaries stay
/// byte-equal with the legacy path even when rows are oversized.
pub(super) fn plan_from_facts(
    facts: &[CompactionFact],
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> CompactionPlan {
    let max_chunk_tokens = adaptive_chunk_token_budget(config, settings);
    let threshold = effective_oversized_threshold(config, settings);

    // The legacy `chunk_messages_by_tokens` walks each message and pushes a
    // new chunk when the running sum would exceed the budget — identical
    // token-sum rule, applied to per-row `chunk_budget_tokens` here. Oversized
    // rows contribute their (small) placeholder cost, matching legacy's
    // sanitize-then-chunk order.
    let mut chunks: Vec<CompactionChunk> = Vec::new();
    let mut current_start = 0usize;
    let mut current_tokens = 0usize;
    let mut chunk_has_oversized = false;
    let mut count_in_current = 0usize;
    let mut oversized_count = 0usize;

    for (idx, fact) in facts.iter().enumerate() {
        let oversized = fact.token_estimate > threshold;
        if oversized {
            oversized_count = oversized_count.saturating_add(1);
        }
        if count_in_current > 0
            && current_tokens.saturating_add(fact.chunk_budget_tokens) > max_chunk_tokens
        {
            chunks.push(CompactionChunk {
                start: current_start,
                end: idx,
                has_oversized: chunk_has_oversized,
            });
            current_start = idx;
            current_tokens = 0;
            chunk_has_oversized = false;
            count_in_current = 0;
        }
        current_tokens = current_tokens.saturating_add(fact.chunk_budget_tokens);
        if oversized {
            chunk_has_oversized = true;
        }
        count_in_current = count_in_current.saturating_add(1);
    }
    if count_in_current > 0 {
        chunks.push(CompactionChunk {
            start: current_start,
            end: facts.len(),
            has_oversized: chunk_has_oversized,
        });
    }
    if chunks.is_empty() {
        chunks.push(CompactionChunk {
            start: 0,
            end: 0,
            has_oversized: false,
        });
    }

    CompactionPlan {
        chunks,
        oversized_count,
        oversized_threshold: threshold,
        adaptive_chunk_token_budget: max_chunk_tokens,
    }
}

/// Lazy render the prompt for the chunk's selected rows just before the
/// LLM call. Mirrors `compaction_user_prompt` byte-for-byte when the chunk
/// holds no oversized rows; for oversized rows it emits the legacy
/// `sanitize_oversized_messages` placeholder text in place of the row's
/// body, so the rendered prompt matches the prior `sanitize` + draw path.
///
/// The returned `String` is meant to be handed straight to the LLM call
/// and dropped afterwards — no row content survives past this render.
pub(super) fn render_chunk_prompt(
    plan: &CompactionPlan,
    chunk: &CompactionChunk,
    transcript: &dyn CompactionTranscript,
    facts: &[CompactionFact],
    previous_summary: Option<&str>,
    focus: Option<&str>,
) -> String {
    let mut sections: Vec<String> = Vec::new();
    if let Some(focus) = focus.filter(|value| !value.trim().is_empty()) {
        sections.push(format!("Focus:\n{}", redacted_preview(focus, 1_200)));
    }
    if let Some(summary) = previous_summary.filter(|value| !value.trim().is_empty()) {
        sections.push(format!(
            "Previous summary:\n{}",
            redacted_preview(summary, 6_000)
        ));
    }
    let mut message_lines: Vec<String> = Vec::new();
    // `idx` indexes both `facts` and `transcript.message(idx)`; an iterator
    // rewrite would obscure the dual indexing, so the range loop is clearer
    // here than clippy's suggested `enumerate().skip().take()`.
    #[allow(clippy::needless_range_loop)]
    for idx in chunk.start..chunk.end {
        let fact = &facts[idx];
        let message = transcript.message(idx);
        let content: Cow<'_, str> = if fact.token_estimate > plan.oversized_threshold {
            Cow::Owned(format_oversized_placeholder(message, fact))
        } else {
            Cow::Borrowed(&message.content)
        };
        match message.role.as_str() {
            "user" | "assistant" => message_lines.push(format!(
                "<message id=\"{}\" role=\"{}\">\n{}\n</message>",
                message.id,
                message.role,
                redacted_preview(&content, 1_000)
            )),
            "tool_calls" => {
                let items = tool_summary_items(&content, 12);
                if items.is_empty() && !content.trim().is_empty() {
                    message_lines.push(format!(
                        "<tool_observation source_message_id=\"{}\">\n{}\n</tool_observation>",
                        message.id,
                        redacted_preview(&content, 700)
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

fn format_oversized_placeholder(message: &SessionMessage, fact: &CompactionFact) -> String {
    let original_chars = message.content.chars().count();
    let preview = compact_text_preview(&message.content, 1_200);
    format!(
        "[oversized message omitted during context compaction: role={}, original_chars={}, estimated_tokens={}]\nPreview: {}",
        message.role, original_chars, fact.token_estimate, preview
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::SessionMessage;
    use crate::types::{ContextEngineConfig, PlatformLlmConfig};
    use chrono::Utc;

    fn msg(id: &str, role: &str, content: &str) -> SessionMessage {
        SessionMessage {
            id: id.to_string(),
            role: role.to_string(),
            content: content.to_string(),
            created_at: Utc::now().to_rfc3339(),
            interrupted: false,
            turn_id: None,
        }
    }

    fn cfg(window: usize) -> (PlatformLlmConfig, ContextEngineConfig) {
        let mut config = PlatformLlmConfig::default();
        config.context_engine.context_window_tokens = Some(window);
        let settings = config.context_engine.clone();
        (config, settings)
    }

    fn facts(messages: &[SessionMessage]) -> (Vec<CompactionFact>, OwnedSliceTranscript<'_>) {
        facts_with_threshold(messages, usize::MAX)
    }

    fn facts_with_threshold(
        messages: &[SessionMessage],
        threshold: usize,
    ) -> (Vec<CompactionFact>, OwnedSliceTranscript<'_>) {
        let transcript = OwnedSliceTranscript::new(messages);
        let facts = collect_facts(&transcript, threshold);
        (facts, transcript)
    }

    #[test]
    fn collect_facts_uses_index_and_metadata_without_content() {
        let messages = vec![
            msg("m1", "user", "hello world"),
            msg("m2", "assistant", "hi"),
        ];
        let (facts, _) = facts(&messages);
        assert_eq!(facts.len(), 2);
        assert_eq!(facts[0].index, 0);
        assert_eq!(facts[0].id, "m1");
        assert_eq!(facts[0].role, "user");
        assert_eq!(facts[0].content_chars, "hello world".chars().count());
        assert!(facts[0].token_estimate > 0);
        assert_eq!(facts[1].index, 1);
        assert_eq!(facts[1].id, "m2");
        assert_eq!(facts[1].role, "assistant");
    }

    #[test]
    fn plan_one_chunk_for_short_middle() {
        let messages = vec![
            msg("m1", "user", "short turn"),
            msg("m2", "assistant", "small reply"),
        ];
        let (facts, _) = facts(&messages);
        let (config, settings) = cfg(8_000);
        let plan = plan_from_facts(&facts, &config, &settings);
        assert_eq!(plan.chunks.len(), 1);
        assert_eq!(plan.oversized_count, 0);
        let chunk = &plan.chunks[0];
        assert_eq!(chunk.start, 0);
        assert_eq!(chunk.end, 2);
        assert!(!chunk.has_oversized);
    }

    #[test]
    fn plan_splits_when_token_budget_exceeded() {
        // ~512 bytes each, dtype tokens >> adaptive_chunk_token_budget for a
        // small window so multiple chunks must be produced.
        let messages: Vec<SessionMessage> = (0..6)
            .map(|i| msg(&format!("m{i}"), "user", &"x".repeat(2_000)))
            .collect();
        let (facts, _) = facts(&messages);
        let (config, settings) = cfg(4_000);
        let plan = plan_from_facts(&facts, &config, &settings);
        assert!(
            plan.chunks.len() >= 2,
            "expected multiple chunks, got {}: {:?}",
            plan.chunks.len(),
            plan.chunks
                .iter()
                .map(|c| (c.start, c.end))
                .collect::<Vec<_>>()
        );
        // Chunks cover [0, len) contiguously, with each chunk non-empty.
        let mut cursor = 0usize;
        for chunk in &plan.chunks {
            assert_eq!(chunk.start, cursor);
            assert!(chunk.end > chunk.start);
            cursor = chunk.end;
        }
        assert_eq!(cursor, messages.len());
    }

    #[test]
    fn plan_marks_oversized_rows_and_counts_them() {
        // context_window=8_000 → oversized_threshold = max(4000*0.5, min(...))
        // adaptive_chunk_token_budget ≈ ((8000 - reserve - overhead)/1.2)
        // which is well above a 1-char row but well below a giant row.
        let messages = vec![
            msg("m1", "user", &"o".repeat(2_000)),       // normal
            msg("m2", "assistant", &"O".repeat(80_000)), // oversized
            msg("m3", "user", "small again"),
        ];
        let (facts, _) = facts(&messages);
        let (config, settings) = cfg(8_000);
        let plan = plan_from_facts(&facts, &config, &settings);
        assert_eq!(plan.oversized_count, 1);
        let oversize_chunk = plan
            .chunks
            .iter()
            .find(|c| c.has_oversized)
            .expect("at least one chunk should carry the oversized row");
        // The oversized row's token estimate must exceed the threshold.
        let oversized_fact = &facts[1];
        assert!(oversized_fact.token_estimate > plan.oversized_threshold);
        let _ = oversize_chunk;
    }

    #[test]
    fn render_chunk_prompt_byte_equal_for_non_oversized_single_chunk() {
        // Mirror the legacy `compaction_user_prompt(None, messages, focus)`
        // output for a non-oversized single chunk — this locks the parity
        // invariant called out in plan §5.1 / test matrix.
        let messages = vec![
            msg("u1", "user", "Please summarize this turn"),
            msg("a1", "assistant", "Acknowledged; proceeding."),
        ];
        let (facts, transcript) = facts(&messages);
        let (config, settings) = cfg(8_000);
        let plan = plan_from_facts(&facts, &config, &settings);
        let rendered = render_chunk_prompt(
            &plan,
            &plan.chunks[0],
            &transcript,
            &facts,
            None,
            Some("focus hint"),
        );
        let expected =
            super::super::compaction::compaction_user_prompt(None, &messages, Some("focus hint"));
        assert_eq!(rendered, expected);
    }

    #[test]
    fn render_chunk_prompt_emits_oversized_placeholder_for_oversized_row() {
        let messages = vec![
            msg("u1", "user", "small"),
            msg("u2", "user", &"O".repeat(80_000)),
        ];
        let (config, settings) = cfg(8_000);
        // Threshold must match the planner's so `chunk_budget_tokens` for the
        // oversized u2 is the small placeholder cost; otherwise the 80k-tok row
        // splits into its own chunk and `plan.chunks[0]` no longer covers u2.
        let threshold = effective_oversized_threshold(&config, &settings);
        let (facts, transcript) = facts_with_threshold(&messages, threshold);
        let plan = plan_from_facts(&facts, &config, &settings);
        assert!(plan.oversized_count >= 1);
        let rendered = render_chunk_prompt(&plan, &plan.chunks[0], &transcript, &facts, None, None);
        assert!(rendered.contains("[oversized message omitted during context compaction:"));
        assert!(
            !rendered.contains(&"O".repeat(80_000)),
            "raw oversized body leaked into prompt"
        );
    }
}
