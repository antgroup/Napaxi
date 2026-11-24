//! Cold-path compaction runtime — the `compaction_model`-set branch of the
//! [`super::run_compaction_with_retry`] dispatcher.
//!
//! Kept byte-equal with the prior `run_compaction_with_retry` so
//! `compaction_assembly_parity_tests` and all cold-path behavior stay
//! unchanged when `ContextEngineConfig.compaction_model` is explicitly set.
//! When `compaction_model` is empty the warm path in [`super::compaction_warm`]
//! is taken instead.

use std::time::Duration;

use super::{
    ContextEngineConfig, PlatformLlmConfig, compaction_max_tokens, compaction_system_prompt,
    redact_credentials_in_text, summary_has_required_sections,
};

/// Cold-path retry driver: legacy independent-summarizer-request behavior
/// (swap system prompt to `compaction_system_prompt()`, optionally override
/// the model with `settings.compaction_model`, single user message via
/// [`crate::llm::complete`]). Byte-equal with the prior
/// `run_compaction_with_retry`.
pub(super) async fn run_cold_compaction_with_retry<P>(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    focus: Option<&str>,
    render_prompt: P,
) -> Result<String, String>
where
    P: Fn(Option<&str>) -> String,
{
    let mut summary_config = config.clone();
    summary_config.system_prompt = compaction_system_prompt();
    summary_config.max_tokens = compaction_max_tokens(config, settings);
    if let Some(model) = settings
        .compaction_model
        .as_deref()
        .map(str::trim)
        .filter(|model| !model.is_empty())
    {
        summary_config.model = model.to_string();
    }
    let prompt = render_prompt(focus);
    let summary = run_compaction_llm(&summary_config, settings, &prompt).await?;
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
    let retry_prompt = render_prompt(Some(&retry_focus));
    let retry_summary = run_compaction_llm(&summary_config, settings, &retry_prompt).await?;
    if !summary_has_required_sections(&retry_summary) {
        return Err(
            "Context compaction LLM did not return the required summary sections".to_string(),
        );
    }
    Ok(retry_summary)
}

/// Cold-path LLM call: send a single fresh user message via
/// [`crate::llm::complete`] (which dispatches through
/// [`crate::llm::complete_with_history`] with a one-message history). The
/// request uses the swapped `compaction_system_prompt()` system prompt so
/// it does NOT share the session's prompt-cache prefix (OpenClaw #204111
/// calls this the "cold summarizer").
pub(super) async fn run_compaction_llm(
    summary_config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    prompt: &str,
) -> Result<String, String> {
    let timeout = Duration::from_millis(settings.compaction_timeout_ms.max(1));
    let result = tokio::time::timeout(timeout, crate::llm::complete(summary_config, prompt))
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
    // Redact credentials before the summary leaves this layer so neither the
    // required-section check nor the returned content can persist raw secrets
    // (covers both the first attempt and the retry path).
    Ok(redact_credentials_in_text(summary))
}
