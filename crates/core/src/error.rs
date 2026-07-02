//! Core error model.
//!
//! Two-layer design:
//! 1. Domain enums (`StorageError`, `LlmError`, `ToolError`, `McpError`,
//!    `CapabilityError`) — used inside one domain module so that domain code
//!    does not need to import the umbrella enum.
//! 2. Umbrella [`CoreError`](crate::error::CoreError) — what crosses module
//!    boundaries and reaches the `api` layer. Domain errors lift into
//!    `CoreError` via `#[from]`.
//!
//! Adapter bridges that need to surface errors over FFI/FRB should use
//! [`CoreError::to_wire_json`](crate::error::CoreError::to_wire_json) to produce
//! the stable wire shape: `{"error": {"code": "...", "message": "..."}}`.
//!
//! During migration, [`CoreError::Other`](crate::error::CoreError::Other)
//! accepts `anyhow::Error` so existing `anyhow::Result` call sites can lift into
//! [`CoreResult`](crate::error::CoreResult) with `?`.

use std::fmt;

use serde::Serialize;
use thiserror::Error;

/// Result alias used by code that has been migrated to the core error model.
pub type CoreResult<T> = Result<T, CoreError>;

/// Umbrella error type carried across module boundaries.
#[derive(Debug, Error)]
pub enum CoreError {
    #[error("invalid engine handle: {0}")]
    InvalidHandle(i64),

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("config error: {0}")]
    Config(String),

    #[error(transparent)]
    Storage(#[from] StorageError),

    #[error(transparent)]
    Llm(#[from] LlmError),

    #[error(transparent)]
    Tool(#[from] ToolError),

    #[error(transparent)]
    Mcp(#[from] McpError),

    #[error(transparent)]
    Capability(#[from] CapabilityError),

    #[error("session cancelled")]
    Cancelled,

    #[error("lock poisoned: {0}")]
    LockPoisoned(&'static str),

    #[error("serialization failed: {0}")]
    Serialization(String),

    /// Transitional bucket for code paths that still surface `anyhow::Error`.
    /// New code should not introduce this variant; replace with a domain
    /// error or a more specific variant as the migration progresses.
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

impl CoreError {
    /// Stable short code used in the wire envelope, suitable for adapter
    /// branching (`error.code == "invalid_handle"`).
    pub fn code(&self) -> &'static str {
        match self {
            CoreError::InvalidHandle(_) => "invalid_handle",
            CoreError::InvalidInput(_) => "invalid_input",
            CoreError::Config(_) => "config",
            CoreError::Storage(e) => e.code(),
            CoreError::Llm(e) => e.code(),
            CoreError::Tool(e) => e.code(),
            CoreError::Mcp(e) => e.code(),
            CoreError::Capability(e) => e.code(),
            CoreError::Cancelled => "cancelled",
            CoreError::LockPoisoned(_) => "lock_poisoned",
            CoreError::Serialization(_) => "serialization",
            CoreError::Other(_) => "other",
        }
    }

    /// Serialize as the stable wire envelope used by adapter bridges.
    pub fn to_wire_json(&self) -> String {
        let envelope = WireErrorEnvelope {
            error: WireErrorBody {
                code: self.code(),
                message: self.to_string(),
            },
        };
        serde_json::to_string(&envelope).unwrap_or_else(|_| {
            r#"{"error":{"code":"serialization","message":"failed to encode error"}}"#.to_string()
        })
    }
}

#[derive(Serialize)]
struct WireErrorEnvelope {
    error: WireErrorBody,
}

#[derive(Serialize)]
struct WireErrorBody {
    code: &'static str,
    message: String,
}

// ---------------------------------------------------------------------------
// Domain enums
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("storage io: {0}")]
    Io(#[from] std::io::Error),

    #[error("storage path not found: {0}")]
    NotFound(String),

    #[error("storage path outside sandbox: {0}")]
    OutsideSandbox(String),

    #[error("storage attachment error: {0}")]
    Attachment(String),

    #[error("storage decode: {0}")]
    Decode(String),
}

impl StorageError {
    pub fn code(&self) -> &'static str {
        match self {
            StorageError::Io(_) => "storage_io",
            StorageError::NotFound(_) => "storage_not_found",
            StorageError::OutsideSandbox(_) => "storage_outside_sandbox",
            StorageError::Attachment(_) => "storage_attachment",
            StorageError::Decode(_) => "storage_decode",
        }
    }
}

#[derive(Debug, Error)]
pub enum LlmError {
    #[error("llm http: {0}")]
    Http(String),

    #[error("llm provider error ({status}): {message}")]
    Provider { status: u16, message: String },

    #[error("llm rate limit ({status}): {message}")]
    RateLimit { status: u16, message: String },

    #[error("llm quota exceeded ({status}): {message}")]
    QuotaExhausted { status: u16, message: String },

    #[error("llm decode: {0}")]
    Decode(String),

    #[error("llm stream ended unexpectedly: {0}")]
    StreamTruncated(String),

    #[error("llm cancelled")]
    Cancelled,

    #[error("llm config: {0}")]
    Config(String),
}

impl LlmError {
    pub fn code(&self) -> &'static str {
        match self {
            LlmError::Http(_) => "llm_http",
            LlmError::Provider { .. } => "llm_provider",
            LlmError::RateLimit { .. } => "llm_rate_limit",
            LlmError::QuotaExhausted { .. } => "llm_quota_exhausted",
            LlmError::Decode(_) => "llm_decode",
            LlmError::StreamTruncated(_) => "llm_stream_truncated",
            LlmError::Cancelled => "llm_cancelled",
            LlmError::Config(_) => "llm_config",
        }
    }

    /// Classify an opaque `anyhow::Error` raised by the existing LLM internals
    /// into a structured `LlmError`. Used at the llm crate boundary so callers
    /// receive `code()` instead of a free-form string.
    pub fn from_anyhow(error: anyhow::Error) -> Self {
        let msg = error.to_string();
        if msg == "Chat cancelled" {
            return LlmError::Cancelled;
        }
        if msg.contains("stream ended") || msg.contains("stream failed before") {
            return LlmError::StreamTruncated(msg);
        }
        if msg.contains("did not contain") {
            return LlmError::Decode(msg);
        }
        let status = extract_http_status(&msg).unwrap_or(0);
        if status == 429 || has_rate_limit_signal(&msg) {
            if has_quota_signal(&msg) {
                return LlmError::QuotaExhausted {
                    status,
                    message: msg,
                };
            }
            return LlmError::RateLimit {
                status,
                message: msg,
            };
        }
        LlmError::Provider {
            status,
            message: msg,
        }
    }
}

/// Extract the HTTP status from error messages like "LLM provider error (429): ...".
fn extract_http_status(msg: &str) -> Option<u16> {
    let rest = msg.split("error (").nth(1)?;
    let code = rest.split(')').next()?;
    code.trim().parse().ok()
}

/// Detect rate-limit signals in the error message beyond just HTTP 429.
fn has_rate_limit_signal(msg: &str) -> bool {
    let lower = msg.to_lowercase();
    lower.contains("rate limit")
        || lower.contains("rate_limit")
        || lower.contains("too many requests")
}

/// Detect quota/billing exhaustion signals that distinguish quota from transient rate limits.
fn has_quota_signal(msg: &str) -> bool {
    let lower = msg.to_lowercase();
    lower.contains("quota")
        || lower.contains("billing")
        || lower.contains("insufficient_quota")
        || lower.contains("exceeded your current quota")
        || lower.contains("account balance")
        || lower.contains("invalid subscription")
        || lower.contains("invalidsubscription")
}

#[derive(Debug, Error)]
pub enum ToolError {
    #[error("tool not found: {0}")]
    NotFound(String),

    #[error("tool invalid params: {0}")]
    InvalidParams(String),

    #[error("tool execution failed: {0}")]
    Execution(String),

    #[error("tool not admitted: {0}")]
    NotAdmitted(String),
}

impl ToolError {
    pub fn code(&self) -> &'static str {
        match self {
            ToolError::NotFound(_) => "tool_not_found",
            ToolError::InvalidParams(_) => "tool_invalid_params",
            ToolError::Execution(_) => "tool_execution",
            ToolError::NotAdmitted(_) => "tool_not_admitted",
        }
    }
}

#[derive(Debug, Error)]
pub enum McpError {
    #[error("mcp transport: {0}")]
    Transport(String),

    #[error("mcp oauth: {0}")]
    OAuth(String),

    #[error("mcp server not found: {0}")]
    ServerNotFound(String),

    #[error("mcp protocol: {0}")]
    Protocol(String),
}

impl McpError {
    pub fn code(&self) -> &'static str {
        match self {
            McpError::Transport(_) => "mcp_transport",
            McpError::OAuth(_) => "mcp_oauth",
            McpError::ServerNotFound(_) => "mcp_server_not_found",
            McpError::Protocol(_) => "mcp_protocol",
        }
    }
}

#[derive(Debug, Error)]
pub enum CapabilityError {
    #[error("capability not registered: {0}")]
    NotRegistered(String),

    #[error("capability not available on this platform: {0}")]
    NotAvailable(String),

    #[error("capability not enabled: {0}")]
    NotEnabled(String),

    #[error("capability denied by policy: {capability} ({reason})")]
    Denied { capability: String, reason: String },
}

impl CapabilityError {
    pub fn code(&self) -> &'static str {
        match self {
            CapabilityError::NotRegistered(_) => "capability_not_registered",
            CapabilityError::NotAvailable(_) => "capability_not_available",
            CapabilityError::NotEnabled(_) => "capability_not_enabled",
            CapabilityError::Denied { .. } => "capability_denied",
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

impl From<serde_json::Error> for CoreError {
    fn from(e: serde_json::Error) -> Self {
        CoreError::Serialization(e.to_string())
    }
}

/// Convenience for `Mutex::lock().map_err(...)`. Use when poisoning is treated
/// as a recoverable runtime error rather than a panic.
pub fn lock_poisoned(name: &'static str) -> CoreError {
    CoreError::LockPoisoned(name)
}

/// Convenience accessor: render any displayable value as `InvalidInput`.
pub fn invalid_input(msg: impl fmt::Display) -> CoreError {
    CoreError::InvalidInput(msg.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_envelope_includes_code_and_message() {
        let err = CoreError::InvalidHandle(42);
        let wire = err.to_wire_json();
        assert!(wire.contains(r#""code":"invalid_handle""#));
        assert!(wire.contains("42"));
    }

    #[test]
    fn domain_error_lifts_into_core_error() {
        fn produce() -> CoreResult<()> {
            Err(StorageError::NotFound("/x".into()).into())
        }
        let err = produce().unwrap_err();
        assert_eq!(err.code(), "storage_not_found");
    }

    #[test]
    fn capability_denied_has_structured_fields() {
        let err: CoreError = CapabilityError::Denied {
            capability: "napaxi.tool.shell".into(),
            reason: "policy".into(),
        }
        .into();
        assert_eq!(err.code(), "capability_denied");
        assert!(err.to_string().contains("napaxi.tool.shell"));
    }

    #[test]
    fn serde_json_error_lifts_as_serialization() {
        let bad: Result<serde_json::Value, _> = serde_json::from_str("not json");
        let core: CoreResult<serde_json::Value> = bad.map_err(Into::into);
        let err = core.unwrap_err();
        assert_eq!(err.code(), "serialization");
    }

    #[test]
    fn anyhow_error_lifts_via_other() {
        fn produce() -> CoreResult<()> {
            Err(anyhow::anyhow!("legacy").into())
        }
        let err = produce().unwrap_err();
        assert_eq!(err.code(), "other");
    }

    #[test]
    fn from_anyhow_classifies_429_as_rate_limit() {
        let err = LlmError::from_anyhow(anyhow::anyhow!(
            "LLM provider error (429): too many requests"
        ));
        assert_eq!(err.code(), "llm_rate_limit");
    }

    #[test]
    fn from_anyhow_classifies_429_quota_as_quota_exhausted() {
        let err = LlmError::from_anyhow(anyhow::anyhow!(
            "LLM provider error (429): You exceeded your current quota"
        ));
        assert_eq!(err.code(), "llm_quota_exhausted");
    }

    #[test]
    fn from_anyhow_classifies_billing_error_with_429() {
        let err = LlmError::from_anyhow(anyhow::anyhow!(
            "LLM provider error (429): billing account inactive"
        ));
        assert_eq!(err.code(), "llm_quota_exhausted");
    }

    #[test]
    fn from_anyhow_classifies_invalid_subscription() {
        let err = LlmError::from_anyhow(anyhow::anyhow!(
            "LLM provider error (429): InvalidSubscription - account suspended"
        ));
        assert_eq!(err.code(), "llm_quota_exhausted");
    }

    #[test]
    fn from_anyhow_classifies_rate_limit_in_message() {
        let err = LlmError::from_anyhow(anyhow::anyhow!("Rate limit exceeded, please retry"));
        assert_eq!(err.code(), "llm_rate_limit");
    }

    #[test]
    fn from_anyhow_generic_provider_stays_provider() {
        let err = LlmError::from_anyhow(anyhow::anyhow!("LLM provider error (400): invalid model"));
        assert_eq!(err.code(), "llm_provider");
    }

    #[test]
    fn rate_limit_wire_envelope_has_correct_code() {
        let err: CoreError = LlmError::RateLimit {
            status: 429,
            message: "slow down".into(),
        }
        .into();
        let wire = err.to_wire_json();
        assert!(wire.contains(r#""code":"llm_rate_limit""#));
    }
}
