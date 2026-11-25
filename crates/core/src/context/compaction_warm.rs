//! Warm-prefix compaction path — the `compaction_model`-empty branch of the
//! [`super::run_compaction_with_retry`] dispatcher.
//!
//! OpenClaw #204111 mapping: when `ContextEngineConfig.compaction_model` is
//! left empty, autocompaction reuses the session's next normal request
//! (`system_prompt`, `max_tokens`, `provider`/`model`/`api_key`) and sends the
//! middle-history prefix verbatim as the warm cache prefix. The summary
//! instruction is appended as a trailing user message (plain prompt, no
//! `<previous-summary>` envelope) so the request can attach to the existing
//! prompt-cache prefix instead of issuing a cold summarizer request with a
//! different system prompt.
//!
//! Failure / retry semantics mirror the cold path exactly: a single
//! `compaction_timeout_ms` timeout per attempt, empty-summary guard,
//! credential redaction on the final text, the six-section heading
//! check via [`super::summary_has_required_sections`], and a single retry
//! with `retry_focus` injected into the directive. Anything failing the
//! required-section check at both attempts surfaces the cold-path error
//! string so [`super::summarize_middle`]'s `local_summary_fallback` chain is
//! unchanged.
//!
//! This module owns the warm path's runtime: the input-shape enum, the
//! driver, the LLM call wrapper, the directive builder, the
//! messages-array assembler, and a test-only probe. The dispatcher lives in
//! [`super`] so callers in `summarize_chunk_with_llm_once` /
//! `summarize_middle_with_llm_once` keep their existing single entry point.

use std::time::Duration;

use chrono::Utc;

use super::{
    ContextEngineConfig, PlatformLlmConfig, SessionMessage, compaction_max_tokens,
    compaction_system_prompt, redact_credentials_in_text, redacted_preview,
    summary_has_required_sections, tool_summary_items,
};

/// Which input shape the warm compaction path should consume when
/// `settings.compaction_model` is empty. Single source of truth for the
/// warm-vs-cold dispatch in [`super::run_compaction_with_retry`].
pub(crate) enum WarmCompactionKind<'a> {
    /// Real middle-history slice with proper user/assistant alternation, sent
    /// verbatim as the warm prefix so the request shares the session's
    /// prompt-cache prefix. The directive is appended at the end (merged
    /// into the last user message if the prefix already ends on a user
    /// message), so the model continues from the cached conversation
    /// prefix.
    ChunkPrefix {
        messages: &'a [SessionMessage],
        previous_summary: Option<&'a str>,
    },
    /// Merge path after a multi-chunk run: the chunk summaries are all
    /// `assistant` role, so sending them as a multi-message prefix would
    /// violate Anthropic's user-first / alternating-role rule. Fold them
    /// into the directive text instead and send a single user message
    /// carrying the directive (with the session system prompt unchanged).
    MergeDirect {
        chunk_summaries: &'a [SessionMessage],
        previous_summary: Option<&'a str>,
    },
}

/// Warm-prefix retry driver (OpenClaw #204111 mapping). Keeps the session's
/// original `system_prompt` so the request shares the next normal turn's
/// prompt-cache prefix, sends the warm prefix messages verbatim (chunk
/// middle slice, or empty for the merge path), and appends the directive as
/// a trailing user message. Mirrors the cold path's failure/retry
/// semantics exactly so [`super::summarize_middle`]'s
/// `local_summary_fallback` chain is unchanged.
pub(crate) async fn run_warm_compaction_with_retry(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    focus: Option<&str>,
    warm_kind: WarmCompactionKind<'_>,
) -> Result<String, String> {
    #[cfg(test)]
    warm_path_inc();

    let mut summary_config = config.clone();
    // IMPORTANT: do NOT swap the system prompt here — the warm path reuses
    // the session's next normal request's system prompt so the request can
    // share the prompt-cache prefix. The six-section heading instruction is
    // emitted via `compaction_warm_directive` instead (single source of
    // truth shared with `compaction_system_prompt()`).
    summary_config.max_tokens = compaction_max_tokens(config, settings);

    let prefix_messages = warm_prefix_messages(&warm_kind);
    let directive = render_warm_directive(focus, &warm_kind);
    let summary =
        run_warm_compaction_llm(&summary_config, settings, prefix_messages, &directive).await?;
    if summary_has_required_sections(&summary) {
        return Ok(summary);
    }
    let retry_focus = focus
        .map(|value| {
            format!(
                "{value}\nThe previous attempt missed required section headings. Retry with exactly these headings: Decisions, Open TODOs, Constraints/Rules, Pending user asks, Exact identifiers, Tool outcomes."
            )
        })
        .unwrap_or_else(|| {
            "Retry with exactly these headings: Decisions, Open TODOs, Constraints/Rules, Pending user asks, Exact identifiers, Tool outcomes.".to_string()
        });
    let retry_directive = render_warm_directive(Some(&retry_focus), &warm_kind);
    let retry_summary =
        run_warm_compaction_llm(&summary_config, settings, prefix_messages, &retry_directive)
            .await?;
    if !summary_has_required_sections(&retry_summary) {
        return Err(
            "Context compaction LLM did not return the required summary sections".to_string(),
        );
    }
    Ok(retry_summary)
}

/// Select the warm prefix messages slice based on the warm kind. For the
/// merge path this is empty (the chunk summaries are folded into the
/// directive text by [`render_warm_directive`]).
fn warm_prefix_messages<'a>(warm_kind: &'a WarmCompactionKind<'a>) -> &'a [SessionMessage] {
    match warm_kind {
        WarmCompactionKind::ChunkPrefix { messages, .. } => messages,
        WarmCompactionKind::MergeDirect { .. } => &[],
    }
}

/// Render the warm-path directive text for the given focus override. The
/// directive is appended at the end of the warm prefix (or sent alone in
/// the merge case with no prefix). It always embeds the six-section heading
/// instruction from `compaction_system_prompt()` so the heading
/// requirement has a single source of truth regardless of whether the LLM
/// sees `compaction_system_prompt()` via the swapped config system prompt
/// (cold) or via this trailing directive (warm).
fn render_warm_directive(focus: Option<&str>, warm_kind: &WarmCompactionKind<'_>) -> String {
    match warm_kind {
        WarmCompactionKind::ChunkPrefix {
            previous_summary, ..
        } => compaction_warm_directive(*previous_summary, None, focus),
        WarmCompactionKind::MergeDirect {
            chunk_summaries,
            previous_summary,
        } => compaction_warm_directive(*previous_summary, Some(chunk_summaries), focus),
    }
}

/// Build the warm-path directive text appended at the end of the warm
/// prefix. Single source of truth for the six-section heading instruction
/// (reuses [`compaction_system_prompt`]) so warm and cold paths emit the
/// same required-section strings.
///
/// `chunk_summaries` is `Some` only for the merge path; for the chunk path
/// the middle messages flow as the warm prefix and there is nothing to fold
/// into the directive.
#[cfg(test)]
pub(crate) fn compaction_warm_directive_test(
    previous_summary: Option<&str>,
    chunk_summaries: Option<&[SessionMessage]>,
    focus: Option<&str>,
) -> String {
    compaction_warm_directive(previous_summary, chunk_summaries, focus)
}

#[cfg(test)]
pub(crate) fn build_warm_compaction_messages_test(
    warm_prefix_messages: &[SessionMessage],
    directive: &str,
) -> Vec<SessionMessage> {
    build_warm_compaction_messages(warm_prefix_messages, directive)
}

fn compaction_warm_directive(
    previous_summary: Option<&str>,
    chunk_summaries: Option<&[SessionMessage]>,
    focus: Option<&str>,
) -> String {
    let mut sections = Vec::new();
    // Embed the six-section heading instruction so the model produces the
    // required sections even though the session system prompt is unchanged
    // (warm path deliberately keeps the session's prompt to share the cache
    // prefix — see `run_warm_compaction_with_retry`).
    sections.push(compaction_system_prompt());
    if let Some(focus) = focus.filter(|value| !value.trim().is_empty()) {
        sections.push(format!("Focus:\n{}", redacted_preview(focus, 1_200)));
    }
    if let Some(summary) = previous_summary.filter(|value| !value.trim().is_empty()) {
        sections.push(format!(
            "Previous summary:\n{}",
            redacted_preview(summary, 6_000)
        ));
    }
    if let Some(messages) = chunk_summaries {
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
    }
    sections.push("Write the durable summary now.".to_string());
    sections.join("\n\n---\n\n")
}

/// Warm-path LLM call: sends the warm prefix verbatim via
/// [`crate::llm::complete_with_history`] (same dispatcher the next normal
/// turn uses) so the request can share the session's prompt-cache prefix.
/// Mirrors [`super::run_compaction_llm`]'s timeout / empty-check / redaction
/// post-processing so failure semantics stay identical and
/// [`super::summarize_middle`]'s `local_summary_fallback` chain is
/// unchanged.
async fn run_warm_compaction_llm(
    summary_config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    warm_prefix_messages: &[SessionMessage],
    directive: &str,
) -> Result<String, String> {
    let timeout = Duration::from_millis(settings.compaction_timeout_ms.max(1));
    let messages = build_warm_compaction_messages(warm_prefix_messages, directive);
    let result = tokio::time::timeout(
        timeout,
        crate::llm::complete_with_history(summary_config, &messages),
    )
    .await
    .map_err(|_| {
        format!(
            "Context compaction timed out after {} ms",
            settings.compaction_timeout_ms
        )
    })?
    .map_err(|error| format!("Context compaction LLM call failed: {error}"))?;
    let summary = result.trim();
    if summary.is_empty() {
        return Err("Context compaction LLM returned an empty summary".to_string());
    }
    Ok(redact_credentials_in_text(summary))
}

/// Build the LLM `messages` array for the warm compaction request.
///
/// The middle-history prefix is sent verbatim so the request reuses the
/// session's prompt-cache prefix (OpenClaw #204111). The directive is
/// appended as the trailing instruction. Provider-specific
/// alternation/adjoining rules are handled here so the dispatched
/// [`crate::llm::complete_with_history`] call stays provider-agnostic:
/// - If `warm_prefix_messages` is empty, the directive is the only (user)
///   message.
/// - If the prefix's last message is `user`, merge the directive into that
///   message's content rather than appending a second consecutive user
///   message (Anthropic/OpenAI reject or only merge through client
///   libraries; we control the wire here).
/// - Otherwise append the directive as a fresh `user` message.
fn build_warm_compaction_messages(
    warm_prefix_messages: &[SessionMessage],
    directive: &str,
) -> Vec<SessionMessage> {
    if warm_prefix_messages.is_empty() {
        return vec![SessionMessage {
            id: format!(
                "compaction_warm_directive_{}",
                Utc::now().timestamp_millis()
            ),
            role: "user".to_string(),
            content: directive.to_string(),
            created_at: Utc::now().to_rfc3339(),
            interrupted: false,
            turn_id: None,
        }];
    }
    let mut messages: Vec<SessionMessage> = warm_prefix_messages.to_vec();
    if let Some(last) = messages.last_mut()
        && last.role == "user"
    {
        last.content.push_str("\n\n---\n\n");
        last.content.push_str(directive);
        return messages;
    }
    messages.push(SessionMessage {
        id: format!(
            "compaction_warm_directive_{}",
            Utc::now().timestamp_millis()
        ),
        role: "user".to_string(),
        content: directive.to_string(),
        created_at: Utc::now().to_rfc3339(),
        interrupted: false,
        turn_id: None,
    });
    messages
}

#[cfg(test)]
tokio::task_local! {
    /// Test-only counter for the number of times the warm compaction path is
    /// entered. Tests scope this via [`with_warm_path_probe`] to distinguish
    /// warm-vs-cold routing end-to-end without provisioning a real LLM
    /// provider (the `__test_noop__` provider returns empty content and
    /// cannot otherwise tell us which `run_*_compaction_with_retry` branch
    /// was taken).
    static WARM_PATH_INVOKED: std::sync::Arc<std::sync::Mutex<u32>>;
}

/// Run `fut` with the warm-path invocation counter armed; returns the
/// counter value (clamped to `u32::MAX`) along with `fut`'s result.
#[cfg(test)]
pub(crate) async fn with_warm_path_probe<F, T>(fut: F) -> (u32, T)
where
    F: std::future::Future<Output = T>,
{
    let counter: std::sync::Arc<std::sync::Mutex<u32>> =
        std::sync::Arc::new(std::sync::Mutex::new(0));
    let value = WARM_PATH_INVOKED.scope(counter.clone(), fut).await;
    let count = *counter.lock().unwrap();
    (count, value)
}

#[cfg(test)]
fn warm_path_inc() {
    let _ = WARM_PATH_INVOKED.try_with(|c| {
        *c.lock().unwrap() += 1;
    });
}
