//! Centralized prompt-cache breakpoint policy.
//!
//! Whether to inject Anthropic-style `cache_control` markers — and which
//! layout to use — is decided in ONE place, keyed off the request's wire
//! protocol (route), target model, provider id, and base URL. The three
//! transports (`anthropic`, `openai_compatible`, `gemini`) read this instead
//! of each making their own ad-hoc decision.
//!
//! This mirrors hermes-agent's `anthropic_prompt_cache_policy`: caching is
//! opt-in per known `(wire, model, provider)` combination. An unrecognized
//! combination returns "don't cache" rather than guessing, so we never send a
//! marker a relay's upstream might reject (400) or silently ignore (0 hits,
//! full re-bill every turn).

use crate::capabilities::LlmProviderRoute;
use crate::types::PlatformLlmConfig;

/// Where `cache_control` markers are placed when caching is enabled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CacheLayout {
    /// Markers on the inner content blocks of the system/tool messages.
    /// Required by the native Anthropic Messages API and gateways that speak
    /// the native Anthropic protocol.
    NativeBlock,
    /// Markers on the message envelope (system content parts) for OpenAI-wire
    /// proxies that nonetheless honor Anthropic-style markers.
    Envelope,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct CachePolicy {
    pub(crate) should_cache: bool,
    pub(crate) layout: CacheLayout,
}

impl CachePolicy {
    const fn off() -> Self {
        // Layout is irrelevant when caching is off; pick a stable default so
        // the value is still Copy/Eq-comparable in tests.
        Self {
            should_cache: false,
            layout: CacheLayout::Envelope,
        }
    }

    const fn native() -> Self {
        Self {
            should_cache: true,
            layout: CacheLayout::NativeBlock,
        }
    }
}

fn host_of(base_url: Option<&str>) -> String {
    let Some(raw) = base_url else {
        return String::new();
    };
    // Cheap host extraction without pulling in a URL crate: strip scheme, then
    // cut at the first '/'. Good enough for host_matches checks below.
    let after_scheme = raw.split_once("://").map(|(_, rest)| rest).unwrap_or(raw);
    let host = after_scheme.split('/').next().unwrap_or("");
    host.to_ascii_lowercase()
}

/// Decide the prompt-cache policy for an outgoing request.
pub(crate) fn prompt_cache_policy(
    route: LlmProviderRoute,
    config: &PlatformLlmConfig,
) -> CachePolicy {
    let provider = config.provider.trim().to_ascii_lowercase();
    let model = config.model.to_ascii_lowercase();
    let host = host_of(config.base_url.as_deref());
    let is_claude = model.contains("claude");

    match route {
        // Native Anthropic Messages API, or any gateway speaking that wire.
        // The cache_control contract is
        // explicit and well-defined here: always cache, native-block layout.
        LlmProviderRoute::Anthropic => CachePolicy::native(),

        // Gemini uses implicit context caching (cachedContentTokenCount);
        // there is no client-side marker to place.
        LlmProviderRoute::Gemini => CachePolicy::off(),

        // OpenAI-wire transport. Caching depends on whether the upstream
        // honors Anthropic-style markers on OpenAI-format messages.
        LlmProviderRoute::OpenAiCompatible => {
            // Third-party gateway fronting a Claude model over OpenAI wire
            // (OpenRouter-style) — markers go on the envelope.
            if is_claude {
                return CachePolicy {
                    should_cache: true,
                    layout: CacheLayout::Envelope,
                };
            }

            // GLM / Zhipu family over an OpenAI-compatible relay: do NOT
            // inject markers. Measured 2026-06-15 against a relay /v1: a second
            // identical turn reports cached_tokens=6931/7008 (98.9%) with NO
            // cache_control sent: the relay does transparent OpenAI-style
            // prefix caching on the OpenAI wire, like the OpenAI API itself.
            // Adding an Anthropic-style cache_control array here would gain
            // nothing and risk a 400 or disrupting that automatic caching.
            // The stable-prefix prompt layout (turn/prompt.rs) is what makes
            // this hit; keeping caching OFF here lets the automatic path work.
            let _ = (&provider, &host); // kept for future provider-specific tuning
            CachePolicy::off()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(provider: &str, model: &str, base_url: Option<&str>) -> PlatformLlmConfig {
        let mut config = PlatformLlmConfig::default();
        config.provider = provider.to_string();
        config.model = model.to_string();
        config.base_url = base_url.map(str::to_string);
        config
    }

    #[test]
    fn anthropic_wire_always_caches_native() {
        let policy = prompt_cache_policy(
            LlmProviderRoute::Anthropic,
            &config(
                "anthropic",
                "claude-opus-4-6",
                Some("https://api.anthropic.com"),
            ),
        );
        assert!(policy.should_cache);
        assert_eq!(policy.layout, CacheLayout::NativeBlock);
    }

    #[test]
    fn anthropic_wire_caches_even_for_relay_gateway() {
        // A relay /api/anthropic endpoint fronting GLM still speaks the native wire.
        let policy = prompt_cache_policy(
            LlmProviderRoute::Anthropic,
            &config(
                "glm",
                "GLM-4.7",
                Some("https://relay.example.com/api/anthropic"),
            ),
        );
        assert!(policy.should_cache);
        assert_eq!(policy.layout, CacheLayout::NativeBlock);
    }

    #[test]
    fn gemini_never_marks() {
        let policy = prompt_cache_policy(
            LlmProviderRoute::Gemini,
            &config("gemini", "gemini-2.0", None),
        );
        assert!(!policy.should_cache);
    }

    #[test]
    fn claude_over_openai_wire_uses_envelope() {
        let policy = prompt_cache_policy(
            LlmProviderRoute::OpenAiCompatible,
            &config(
                "openrouter",
                "claude-3-5-sonnet",
                Some("https://openrouter.ai/api/v1"),
            ),
        );
        assert!(policy.should_cache);
        assert_eq!(policy.layout, CacheLayout::Envelope);
    }

    #[test]
    fn glm_over_openai_wire_relies_on_relay_automatic_caching() {
        // Verified 2026-06-15: a relay /v1 auto-caches the prefix (98.9% hit
        // on a repeat turn) without any cache_control, so we send none.
        let policy = prompt_cache_policy(
            LlmProviderRoute::OpenAiCompatible,
            &config("glm", "GLM-4.7", Some("https://relay.example.com/v1")),
        );
        assert!(!policy.should_cache);
    }

    #[test]
    fn host_extraction_handles_scheme_and_path() {
        assert_eq!(
            host_of(Some("https://relay.example.com/v1")),
            "relay.example.com"
        );
        assert_eq!(host_of(Some("HTTP://API.OpenAI.com/")), "api.openai.com");
        assert_eq!(host_of(None), "");
    }
}
