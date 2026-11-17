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
