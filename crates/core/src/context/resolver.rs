//! Lightweight model context-window discovery.
//!
//! Napaxi keeps the mobile SDK boundary small, so this resolver only performs
//! provider metadata discovery where the provider exposes stable token limits
//! today. Gemini supports this through its Models API; OpenAI-compatible and
//! Anthropic continue to rely on config/profile/model-rule fallbacks.

use std::time::Duration;

use chrono::{DateTime, Utc};

use crate::types::{ContextEngineConfig, PlatformLlmConfig};

use super::state::{ContextState, ProviderContextMetadataSnapshot};

const PROVIDER_METADATA_TTL_HOURS: i64 = 24;
const PROVIDER_METADATA_TIMEOUT_SECS: u64 = 3;

pub(super) async fn maybe_refresh_provider_context_metadata(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    state: &mut ContextState,
) {
    if !should_fetch_gemini_metadata(config, settings) {
        return;
    }
    if provider_metadata_is_fresh(config, state.provider_context_metadata.as_ref()) {
        return;
    }
    match fetch_gemini_model_metadata(config).await {
        Ok(metadata) => {
            state.provider_context_metadata = Some(metadata);
        }
        Err(error) => {
            let now = Utc::now().to_rfc3339();
            state.provider_context_metadata = Some(ProviderContextMetadataSnapshot {
                provider: config.provider.clone(),
                model: config.model.clone(),
                native_context_window_tokens: 0,
                output_token_limit: None,
                fetched_at: now,
                stale: true,
                error: Some(error),
            });
        }
    }
}

pub(super) fn config_with_provider_metadata(
    config: &PlatformLlmConfig,
    state: &ContextState,
) -> PlatformLlmConfig {
    let mut config = config.clone();
    let settings = &mut config.context_engine;
    if settings.native_context_window_tokens.is_some()
        || settings.provider_context_window_tokens.is_some()
    {
        return config;
    }
    let Some(metadata) = state.provider_context_metadata.as_ref() else {
        return config;
    };
    if !metadata_matches_config(config.provider.as_str(), config.model.as_str(), metadata)
        || metadata.stale
        || metadata.native_context_window_tokens == 0
    {
        return config;
    }
    settings.provider_context_window_tokens = Some(metadata.native_context_window_tokens);
    config
}

pub(super) fn provider_metadata_for_config<'a>(
    config: &PlatformLlmConfig,
    state: &'a ContextState,
) -> Option<&'a ProviderContextMetadataSnapshot> {
    state
        .provider_context_metadata
        .as_ref()
        .filter(|metadata| metadata_matches_config(&config.provider, &config.model, metadata))
}

fn should_fetch_gemini_metadata(
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
) -> bool {
    if settings.native_context_window_tokens.is_some()
        || settings.provider_context_window_tokens.is_some()
        || config.api_key.trim().is_empty()
    {
        return false;
    }
    is_gemini_config(config)
}

fn is_gemini_config(config: &PlatformLlmConfig) -> bool {
    let provider = config.provider.to_ascii_lowercase();
    let (qualified_provider, model) = split_qualified_model(&config.model);
    provider.contains("gemini")
        || qualified_provider
            .as_deref()
            .is_some_and(|provider| provider.contains("gemini") || provider.contains("google"))
        || model
            .as_deref()
            .unwrap_or(config.model.as_str())
            .to_ascii_lowercase()
            .starts_with("gemini-")
}

fn provider_metadata_is_fresh(
    config: &PlatformLlmConfig,
    metadata: Option<&ProviderContextMetadataSnapshot>,
) -> bool {
    let Some(metadata) = metadata else {
        return false;
    };
    if !metadata_matches_config(&config.provider, &config.model, metadata)
        || metadata.stale
        || metadata.native_context_window_tokens == 0
    {
        return false;
    }
    DateTime::parse_from_rfc3339(&metadata.fetched_at)
        .ok()
        .map(|fetched| {
            Utc::now()
                .signed_duration_since(fetched.with_timezone(&Utc))
                .num_hours()
                < PROVIDER_METADATA_TTL_HOURS
        })
        .unwrap_or(false)
}

fn metadata_matches_config(
    provider: &str,
    model: &str,
    metadata: &ProviderContextMetadataSnapshot,
) -> bool {
    metadata.provider == provider && metadata.model == model
}

async fn fetch_gemini_model_metadata(
    config: &PlatformLlmConfig,
) -> Result<ProviderContextMetadataSnapshot, String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(PROVIDER_METADATA_TIMEOUT_SECS))
        .build()
        .map_err(|error| error.to_string())?;
    let base_url = config
        .base_url
        .as_deref()
        .filter(|url| !url.trim().is_empty())
        .unwrap_or("https://generativelanguage.googleapis.com/v1beta")
        .trim_end_matches('/')
        .to_string();
    let model_path = gemini_model_path(&config.model);
    let url = format!("{base_url}/{model_path}");
    let response = client
        .get(url)
        .query(&[("key", config.api_key.trim())])
        .send()
        .await
        .map_err(|error| format!("Gemini model metadata request failed: {error}"))?;
    let status = response.status();
    let value = response
        .json::<serde_json::Value>()
        .await
        .map_err(|error| format!("Gemini model metadata decode failed ({status}): {error}"))?;
    if !status.is_success() {
        return Err(format!(
            "Gemini model metadata error ({}): {}",
            status.as_u16(),
            compact_json_error(&value)
        ));
    }
    let input_limit = value
        .get("inputTokenLimit")
        .and_then(serde_json::Value::as_u64)
        .or_else(|| {
            value
                .get("input_token_limit")
                .and_then(serde_json::Value::as_u64)
        })
        .map(|tokens| tokens as usize)
        .ok_or_else(|| "Gemini model metadata did not include inputTokenLimit".to_string())?;
    let output_limit = value
        .get("outputTokenLimit")
        .and_then(serde_json::Value::as_u64)
        .or_else(|| {
            value
                .get("output_token_limit")
                .and_then(serde_json::Value::as_u64)
        })
        .map(|tokens| tokens as usize);
    Ok(ProviderContextMetadataSnapshot {
        provider: config.provider.clone(),
        model: config.model.clone(),
        native_context_window_tokens: input_limit,
        output_token_limit: output_limit,
        fetched_at: Utc::now().to_rfc3339(),
        stale: false,
        error: None,
    })
}

fn gemini_model_path(model: &str) -> String {
    let (_, qualified_model) = split_qualified_model(model);
    let model_id = qualified_model.as_deref().unwrap_or(model).trim();
    if model_id.starts_with("models/") {
        model_id.to_string()
    } else {
        format!("models/{model_id}")
    }
}

fn split_qualified_model(model: &str) -> (Option<String>, Option<String>) {
    let lower = model.to_ascii_lowercase();
    let Some((provider, model)) = lower.split_once('/') else {
        return (None, None);
    };
    if provider.trim().is_empty() || model.trim().is_empty() {
        (None, None)
    } else {
        (
            Some(provider.trim().to_string()),
            Some(model.trim().to_string()),
        )
    }
}

fn compact_json_error(value: &serde_json::Value) -> String {
    value
        .pointer("/error/message")
        .or_else(|| value.pointer("/error"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| value.to_string())
}
