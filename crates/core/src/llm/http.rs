//! HTTP plumbing shared by provider modules: header builders, URL templates,
//! JSON response decoding, and standardised provider error messages.

use std::time::Duration;

use anyhow::{Result, anyhow};
use std::sync::LazyLock;
use reqwest::Response;
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE, HeaderMap, HeaderName, HeaderValue};
use serde_json::Value;

use super::sse::response_body_preview;
use crate::types::PlatformLlmConfig;

/// Time allowed to establish a TCP+TLS connection before the attempt is
/// treated as a (retryable) failure. Kept generous for weak mobile networks.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
/// Idle pool timeout. Connections are reused across LLM calls within this
/// window, avoiding a fresh TLS handshake on every turn.
const POOL_IDLE_TIMEOUT: Duration = Duration::from_secs(90);
/// Overall request timeout for non-streaming JSON calls (complete/complete_raw,
/// context compaction). Streaming calls deliberately omit an overall timeout —
/// a long generation is normal — and rely on the per-chunk stall timeout in the
/// stream read loops instead.
const NON_STREAM_TIMEOUT: Duration = Duration::from_secs(180);

/// Process-wide client for streaming (SSE) requests. No overall timeout: a long
/// generation must not be aborted mid-stream. Stall detection lives in the
/// per-provider stream read loops.
static STREAM_CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .pool_idle_timeout(POOL_IDLE_TIMEOUT)
        .build()
        .expect("failed to build streaming LLM HTTP client")
});

/// Process-wide client for non-streaming JSON requests. Bounded by an overall
/// timeout so a stuck request cannot hang a turn forever.
static JSON_CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .pool_idle_timeout(POOL_IDLE_TIMEOUT)
        .timeout(NON_STREAM_TIMEOUT)
        .build()
        .expect("failed to build non-streaming LLM HTTP client")
});

/// Shared client for SSE/streaming LLM requests.
pub(super) fn stream_client() -> reqwest::Client {
    STREAM_CLIENT.clone()
}

/// Shared client for non-streaming JSON LLM requests.
pub(super) fn json_client() -> reqwest::Client {
    JSON_CLIENT.clone()
}

pub(super) fn openai_headers(config: &PlatformLlmConfig) -> Result<HeaderMap> {
    let mut headers = extra_headers(config)?;
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&format!("Bearer {}", config.api_key.trim()))?,
    );
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    Ok(headers)
}

pub(super) async fn response_json(response: Response, provider: &str) -> Result<Value> {
    let status = response.status();
    let text = response.text().await.map_err(|error| {
        anyhow!(
            "{provider} response body could not be read ({}): {error}",
            status.as_u16()
        )
    })?;
    serde_json::from_str::<Value>(&text).map_err(|error| {
        anyhow!(
            "{provider} returned a non-JSON response ({}): {}. Body: {}",
            status.as_u16(),
            error,
            response_body_preview(&text)
        )
    })
}

pub(super) fn extra_headers(config: &PlatformLlmConfig) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();
    let Some(raw) = config.extra_headers.as_deref() else {
        return Ok(headers);
    };
    for part in raw
        .split(',')
        .map(str::trim)
        .filter(|part| !part.is_empty())
    {
        let Some((name, value)) = part.split_once(':') else {
            continue;
        };
        let name = HeaderName::from_bytes(name.trim().as_bytes())?;
        let value = HeaderValue::from_str(value.trim())?;
        headers.insert(name, value);
    }
    Ok(headers)
}

pub(super) fn chat_completions_url(config: &PlatformLlmConfig) -> String {
    let base = config
        .base_url
        .as_deref()
        .filter(|url| !url.trim().is_empty())
        .unwrap_or_else(|| {
            if config.provider.eq_ignore_ascii_case("glm")
                || config.provider.eq_ignore_ascii_case("zai")
                || config.provider.eq_ignore_ascii_case("zhipu")
                || config.provider.eq_ignore_ascii_case("bigmodel")
            {
                "https://open.bigmodel.cn/api/paas/v4"
            } else if config.provider.eq_ignore_ascii_case("nearai") {
                "https://cloud-api.near.ai"
            } else {
                "https://api.openai.com/v1"
            }
        })
        .trim_end_matches('/');
    if base.ends_with("/chat/completions") {
        base.to_string()
    } else {
        format!("{base}/chat/completions")
    }
}

pub(super) fn positive_max_tokens(max_tokens: i32) -> i32 {
    if max_tokens > 0 { max_tokens } else { 40960 }
}

pub(super) fn uses_max_completion_tokens(model: &str) -> bool {
    let m = model.to_ascii_lowercase();
    m.starts_with("o1")
        || m.starts_with("o3")
        || m.starts_with("o4")
        || m.starts_with("gpt-4o")
        || m.starts_with("gpt-4.1")
        || m.contains("o1-")
        || m.contains("o3-")
        || m.contains("o4-")
}

pub(super) fn provider_error_message(value: &Value, status: u16) -> String {
    value
        .pointer("/error/message")
        .or_else(|| value.pointer("/error"))
        .and_then(Value::as_str)
        .map(|message| format!("LLM provider error ({status}): {message}"))
        .unwrap_or_else(|| format!("LLM provider error ({status}): {value}"))
}
