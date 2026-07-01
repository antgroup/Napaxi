//! Mobile-facing message and attachment types shared by the SDK runtime.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Platform-agnostic LLM configuration.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PlatformLlmConfig {
    pub provider: String,
    /// LLM API key. Stored as a plain `String` for FFI compatibility.
    /// For enhanced security, consider wrapping in `secrecy::Secret<String>`
    /// or zeroizing on drop once the FFI boundary supports opaque types.
    pub api_key: String,
    pub base_url: Option<String>,
    pub model: String,
    pub system_prompt: String,
    /// Preferred response language. Supported SDK values are "en" and "zh".
    /// Unknown values keep the latest-user-message behavior.
    #[serde(default = "default_response_language")]
    pub response_language: String,
    pub max_tokens: i32,
    /// Default model/tool loop budget.
    /// 0 uses the runtime default; negative means practically unlimited.
    #[serde(default)]
    pub max_tool_iterations: i32,
    /// Extra HTTP headers in format "Key1:Value1,Key2:Value2"
    #[serde(default)]
    pub extra_headers: Option<String>,
    /// IANA timezone for the user whose local-time intent should guide turns.
    ///
    /// Runtime timestamps remain UTC/epoch based; this is used to explain
    /// user-local phrases such as "tomorrow morning" in prompts and automation.
    #[serde(default, alias = "userTimeZone", alias = "timeZoneId")]
    pub user_timezone: Option<String>,
    /// Allowed models for switch_model validation.
    #[serde(default)]
    pub allowed_models: Option<Vec<AllowedModel>>,
    /// Image generation model ID.
    #[serde(default)]
    pub image_model: Option<String>,
    /// Image analysis model ID used for chat turns that include image attachments.
    #[serde(default)]
    pub image_analysis_model: Option<String>,
    /// Provider-specific image_url base64 format for vision chat completions.
    /// Supported values: "data_url" and "raw".
    #[serde(default)]
    pub image_base64_url_format: Option<String>,
    /// Capability-specific provider configs keyed by capability name, such as
    /// "imageAnalysis" or "imageGeneration".
    #[serde(default)]
    pub capability_configs: Option<HashMap<String, PlatformLlmCapabilityConfig>>,
    /// Per-turn scene prompt injection configuration.
    #[serde(default)]
    pub scene_prompt_config: Option<crate::scene_prompt::ScenePromptConfig>,
    /// Context compaction and context-engine selection.
    #[serde(default)]
    pub context_engine: ContextEngineConfig,
    /// Shell command security posture (approval mode + hard gate).
    #[serde(default)]
    pub shell_security: ShellSecurityConfig,
    /// Git configuration for the mobile development scenario: execution mode
    /// (dedicated structured tools vs. native sandbox `git`) and commit
    /// identity written into the rootfs `~/.gitconfig`.
    #[serde(default)]
    pub git: Option<GitConfig>,
    /// Host-declared capability support carried by the active runtime.
    #[serde(default)]
    pub capability_profile: crate::capabilities::CapabilityProfile,
    /// Runtime capability selection carried by the active runtime.
    #[serde(default)]
    pub capability_selection: crate::capabilities::CapabilitySelection,
    /// Whether to insert a `<turn_aborted>` boundary marker into history when a
    /// running turn is interrupted with no assistant output. Defaults to true.
    ///
    /// NOTE on `Default`: this struct keeps `#[derive(Default)]`, whose derived
    /// impl ignores serde attributes and yields `bool::default() == false` for
    /// this field. That is intentional and harmless: every runtime config that
    /// drives `finish_cancelled_turn` originates from
    /// `serde_json::from_str::<PlatformLlmConfig>` (see `turn::prepare`), where
    /// this `#[serde(default = ...)]` correctly applies `true`. The `false`
    /// produced by `PlatformLlmConfig::default()` only appears in tests and
    /// placeholder/sub-request configs (e.g. image generation) that never reach
    /// the interrupt path, so deriving Default is preferred over a manual impl.
    #[serde(default = "default_interrupt_marker_enabled")]
    pub interrupt_marker_enabled: bool,
}

fn default_response_language() -> String {
    "en".to_string()
}

fn default_interrupt_marker_enabled() -> bool {
    true
}

/// Context engine configuration for long-running sessions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextEngineConfig {
    #[serde(default = "default_context_engine_enabled")]
    pub enabled: bool,
    #[serde(default = "default_context_engine_name")]
    pub engine: String,
    #[serde(default = "default_context_trigger_ratio")]
    pub trigger_ratio: f32,
    #[serde(default = "default_context_target_ratio")]
    pub target_ratio: f32,
    #[serde(default = "default_context_protect_head_messages")]
    pub protect_head_messages: usize,
    #[serde(default = "default_context_protect_tail_messages")]
    pub protect_tail_messages: usize,
    #[serde(default)]
    pub context_window_tokens: Option<usize>,
    #[serde(default)]
    pub native_context_window_tokens: Option<usize>,
    #[serde(default)]
    pub provider_context_window_tokens: Option<usize>,
    #[serde(default)]
    pub response_reserve_tokens: Option<usize>,
    #[serde(default = "default_context_compaction_strategy")]
    pub compaction_strategy: String,
    #[serde(default)]
    pub compaction_model: Option<String>,
    #[serde(default = "default_context_compaction_timeout_ms")]
    pub compaction_timeout_ms: u64,
    #[serde(default)]
    pub pre_compaction_memory_flush: bool,
}

impl Default for ContextEngineConfig {
    fn default() -> Self {
        Self {
            enabled: default_context_engine_enabled(),
            engine: default_context_engine_name(),
            trigger_ratio: default_context_trigger_ratio(),
            target_ratio: default_context_target_ratio(),
            protect_head_messages: default_context_protect_head_messages(),
            protect_tail_messages: default_context_protect_tail_messages(),
            context_window_tokens: None,
            native_context_window_tokens: None,
            provider_context_window_tokens: None,
            response_reserve_tokens: None,
            compaction_strategy: default_context_compaction_strategy(),
            compaction_model: None,
            compaction_timeout_ms: default_context_compaction_timeout_ms(),
            pre_compaction_memory_flush: false,
        }
    }
}

fn default_context_engine_enabled() -> bool {
    true
}

fn default_context_engine_name() -> String {
    "compressor".to_string()
}

fn default_context_trigger_ratio() -> f32 {
    0.85
}

fn default_context_target_ratio() -> f32 {
    0.45
}

fn default_context_protect_head_messages() -> usize {
    2
}

fn default_context_protect_tail_messages() -> usize {
    20
}

fn default_context_compaction_strategy() -> String {
    "llm_summary".to_string()
}

fn default_context_compaction_timeout_ms() -> u64 {
    60_000
}

/// Shell command approval posture.
///
/// The SDK provides the mechanism; the host selects the policy. Every mode
/// shares the same hard gate (destructive / data-exfiltration commands are
/// always rejected, see [`ShellDecision::Reject`]); the mode only decides what
/// happens to commands that are *not* in the known-safe allow-list.
///
/// Mirrors codex's `AskForApproval` (without the sandbox-dependent `OnFailure`,
/// which has no analogue in the mobile emulated environment).
///
/// Deserialization is fail-safe: unknown wire strings (typos, future variants,
/// or hostile payloads) silently fall back to [`ShellApprovalMode::OnRequest`]
/// instead of erroring, so an unrecognized value never poisons the whole
/// [`PlatformLlmConfig`] parse. This mirrors the three host adapters
/// (Kotlin/Swift/Dart `fromWire`), keeping the SDK self-contained. The
/// `Serialize` half keeps `#[serde(rename_all = "snake_case")]` so the wire
/// values stay `read_only_only` / `on_request` / `trusted_allow` / `custom`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ShellApprovalMode {
    /// Only known-safe read-only commands run automatically; everything else is
    /// sent to the host approval bridge (rejected when no bridge is wired).
    /// Strictest posture.
    ReadOnlyOnly,
    /// Known-safe commands run automatically; everything else requests host
    /// approval (rejected when no bridge is wired). SDK default — closest to the
    /// historical behavior and aligned with codex's `OnRequest`.
    #[default]
    OnRequest,
    /// Known-safe commands run automatically; everything else runs directly once
    /// it clears the hard gate, without prompting the host. The napaxi demo uses
    /// this: only the hard gate is effectively in play. Use when the host already
    /// controls the blast radius (e.g. a sandboxed workspace directory).
    TrustedAllow,
    /// No built-in posture: after the hard gate, classification is delegated to a
    /// host-registered capability policy hook.
    Custom,
}

impl<'de> Deserialize<'de> for ShellApprovalMode {
    /// Fail-safe deserialize: read the wire value as a string and map known
    /// snake_case tags to their variants. Any other value (unknown string,
    /// typo, future tag) falls back to [`ShellApprovalMode::OnRequest`] rather
    /// than failing the parse, so a single bad value cannot reject the entire
    /// surrounding config.
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        Ok(match raw.as_str() {
            "read_only_only" => ShellApprovalMode::ReadOnlyOnly,
            "on_request" => ShellApprovalMode::OnRequest,
            "trusted_allow" => ShellApprovalMode::TrustedAllow,
            "custom" => ShellApprovalMode::Custom,
            _ => ShellApprovalMode::OnRequest,
        })
    }
}

/// Shell command security configuration carried on [`PlatformLlmConfig`].
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ShellSecurityConfig {
    /// Approval posture for shell commands that are not known-safe.
    #[serde(default)]
    pub approval_mode: ShellApprovalMode,
}

/// Git execution mode for the mobile development scenario.
///
/// - `Structured` (default, historical): the agent's shell `git ...` commands
///   are redirected to dedicated structured tools (`git_clone`, `git_status`,
///   ...) provided by the host, and `git install` through the shell is blocked.
/// - `Native` (paseo-style): shell `git` runs directly against the real `git`
///   binary baked into the sandbox rootfs, exactly like any other shell
///   command. The read-only allow-list (`shell_safe`) and the shell approval
///   posture still gate it, so the safety net is preserved.
///
/// Deserialization is fail-safe (mirrors [`ShellApprovalMode`]): unknown wire
/// strings fall back to [`GitMode::Structured`] instead of erroring, so a bad
/// value cannot poison the whole [`PlatformLlmConfig`] parse.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum GitMode {
    #[default]
    Structured,
    Native,
}

impl<'de> Deserialize<'de> for GitMode {
    /// Fail-safe deserialize: map known snake_case tags to variants; any other
    /// value (unknown string, typo, future tag) falls back to
    /// [`GitMode::Structured`] rather than failing the parse.
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        Ok(match raw.as_str() {
            "structured" => GitMode::Structured,
            "native" => GitMode::Native,
            _ => GitMode::Structured,
        })
    }
}

/// Git identity written into the sandbox rootfs `~/.gitconfig` `[user]` section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitIdentity {
    pub name: String,
    pub email: String,
}

/// Git configuration carried on [`PlatformLlmConfig`] for the mobile
/// development scenario.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GitConfig {
    /// Execution mode. Defaults to [`GitMode::Structured`] (historical).
    #[serde(default)]
    pub mode: GitMode,
    /// Commit identity written to the sandbox rootfs `~/.gitconfig`.
    #[serde(default)]
    pub identity: Option<GitIdentity>,
}

/// Final verdict for a single shell command.
///
/// `Prompt` carries a user/model-facing reason and is resolved by the shell
/// tool layer via the existing approval bridge; it never reaches the capability
/// admission enum (which stays binary `Allow`/`Deny`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShellDecision {
    /// Auto-approve and run.
    Allow,
    /// Requires host approval, with a reason surfaced to the user/model.
    Prompt(String),
    /// Reject execution, with a reason that can be returned to the model.
    Reject(String),
}

/// Provider config for one model capability slot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlatformLlmCapabilityConfig {
    pub provider: String,
    /// LLM API key. Stored as a plain `String` for FFI compatibility.
    /// Consider `secrecy::Secret<String>` or zeroize-on-drop for enhanced security.
    pub api_key: String,
    pub base_url: Option<String>,
    pub model: String,
    #[serde(default)]
    pub max_tokens: Option<i32>,
    #[serde(default)]
    pub extra_headers: Option<String>,
    /// Provider-specific image_url base64 format for vision chat completions.
    /// Supported values: "data_url" and "raw".
    #[serde(default)]
    pub image_base64_url_format: Option<String>,
}

/// A model entry in the allowed_models whitelist.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllowedModel {
    pub name: String,
    pub id: String,
}

/// Event sent back to the platform UI during chat processing.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ChatEvent {
    RunStarted {
        run_id: String,
        session_key: String,
        agent_id: String,
    },
    RunProgress {
        run_id: String,
        kind: String,
        message: String,
    },
    RunCompleted {
        run_id: String,
        status: String,
        evidence_kind: String,
        verification: String,
        tool_call_count: usize,
    },
    ToolCall {
        call_id: String,
        name: String,
        arguments: String,
    },
    ToolCallDelta {
        call_id: String,
        name: String,
        arguments_delta: String,
        arguments_so_far: String,
    },
    ToolResult {
        call_id: String,
        name: String,
        output: String,
        is_error: bool,
    },
    Response {
        content: String,
    },
    ResponseDelta {
        content: String,
    },
    ReasoningDelta {
        content: String,
    },
    Error {
        message: String,
    },
    AgentDelegation {
        from_agent: String,
        to_agent: String,
        message: String,
    },
    AgentDelegationResult {
        from_agent: String,
        to_agent: String,
        content: String,
        is_error: bool,
    },
    AgentToolCall {
        call_id: String,
        name: String,
        arguments: String,
        agent_id: String,
    },
    AgentToolCallDelta {
        call_id: String,
        name: String,
        arguments_delta: String,
        arguments_so_far: String,
        agent_id: String,
    },
    AgentToolResult {
        call_id: String,
        name: String,
        output: String,
        is_error: bool,
        agent_id: String,
    },
    Thinking {
        content: String,
    },
    ImageGenerated {
        data_url: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        path: Option<String>,
    },
    ToolOutputChunk {
        call_id: String,
        content: String,
        stream: String,
    },
    GroupDelegation {
        group_id: String,
        from_agent: String,
        to_agent: String,
        task: String,
    },
    GroupDelegationResult {
        group_id: String,
        from_agent: String,
        to_agent: String,
        result: String,
        is_error: bool,
    },
    MessageInjected {
        content: String,
    },
    AskingHuman {
        question: String,
        request_id: String,
        options: Vec<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        context: Option<String>,
    },
    HumanResponse {
        request_id: String,
        response: String,
    },
    /// The in-flight LLM stream dropped or stalled and is being retried. The UI
    /// should discard any partial assistant content/reasoning streamed so far
    /// for the current turn and wait for the reconnected stream to repopulate
    /// it. No history side effects have occurred yet.
    StreamReset {
        reason: String,
    },
    ContextCompacting {
        usage_percent: f64,
        strategy: String,
    },
    ContextCompacted {
        turns_removed: usize,
        tokens_before: usize,
        tokens_after: usize,
    },
    MemoryEvolved {
        target: String,
        content: String,
    },
    SkillEvolved {
        skill_name: String,
        action: String,
        summary: String,
    },
    EvolutionQueued {
        review_types: Vec<String>,
        runs: Vec<EvolutionQueuedRun>,
    },
    SkillActivated {
        agent_id: String,
        skills: Vec<ActivatedSkillInfo>,
    },
    ActionProposalCreated {
        request_id: String,
        provider_id: String,
        agent_id: String,
        action_id: String,
        tool_name: String,
        risk: String,
        expires_at: String,
    },
    ActionHandoffStarted {
        request_id: String,
        mode: String,
    },
    ActionWaitingForProvider {
        request_id: String,
        provider_id: String,
    },
    ActionResultReceived {
        request_id: String,
        status: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        provider_trace_id: Option<String>,
    },
    ActionExpired {
        request_id: String,
    },
    ActionFailed {
        request_id: String,
        message: String,
    },
    Interrupted,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActivatedSkillInfo {
    pub name: String,
    pub version: String,
    pub description: String,
    pub trust: String,
    #[serde(default)]
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EvolutionQueuedRun {
    pub id: String,
    pub review_type: String,
}

/// Kind of attachment carried on an incoming message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AttachmentKind {
    /// Audio content (voice notes, audio files).
    Audio,
    /// Image content (photos, screenshots).
    Image,
    /// Document content (PDFs, files).
    Document,
}

impl AttachmentKind {
    /// Infer attachment kind from MIME type.
    pub fn from_mime_type(mime: &str) -> Self {
        let base = mime.split(';').next().unwrap_or(mime).trim();
        if base.starts_with("audio/") {
            Self::Audio
        } else if base.starts_with("image/") {
            Self::Image
        } else {
            Self::Document
        }
    }
}

/// A file or media attachment on an incoming message.
#[derive(Debug, Clone)]
pub struct IncomingAttachment {
    /// Unique identifier within the channel (e.g., Telegram file_id).
    pub id: String,
    /// What kind of content this is.
    pub kind: AttachmentKind,
    /// MIME type (e.g., "image/jpeg", "audio/ogg", "application/pdf").
    pub mime_type: String,
    /// Original filename, if known.
    pub filename: Option<String>,
    /// File size in bytes, if known.
    pub size_bytes: Option<u64>,
    /// URL to download the file from the channel's API.
    pub source_url: Option<String>,
    /// Opaque key for host-side storage (e.g., after download/caching).
    pub storage_key: Option<String>,
    /// Original host/local file path, if the attachment came from local picker.
    pub local_path: Option<String>,
    /// Extracted text content (e.g., OCR result, PDF text, audio transcript).
    pub extracted_text: Option<String>,
    /// Raw file bytes (for small files downloaded by the channel).
    pub data: Vec<u8>,
    /// Duration in seconds (for audio/video).
    pub duration_secs: Option<u32>,
}

/// A message received from an external channel.
#[derive(Debug, Clone)]
pub struct IncomingMessage {
    /// Unique message ID.
    pub id: Uuid,
    /// Channel this message came from.
    pub channel: String,
    /// Storage/persistence scope for this interaction.
    ///
    /// For owner-capable channels this is the stable instance owner ID when the
    /// configured owner is speaking; otherwise it can be a guest/sender-scoped
    /// identifier to preserve isolation.
    pub user_id: String,
    /// Stable instance owner scope for this Napaxi deployment.
    pub owner_id: String,
    /// Channel-specific sender/actor identifier.
    pub sender_id: String,
    /// Optional display name.
    pub user_name: Option<String>,
    /// Message content.
    pub content: String,
    /// Thread/conversation ID for threaded conversations.
    pub thread_id: Option<String>,
    /// Stable channel/chat/thread scope for this conversation.
    pub conversation_scope_id: Option<String>,
    /// When the message was received.
    pub received_at: DateTime<Utc>,
    /// Channel-specific metadata.
    pub metadata: serde_json::Value,
    /// IANA timezone string from the client (e.g. "America/New_York").
    pub timezone: Option<String>,
    /// File or media attachments on this message.
    pub attachments: Vec<IncomingAttachment>,
}

impl IncomingMessage {
    /// Create a new incoming message.
    pub fn new(
        channel: impl Into<String>,
        user_id: impl Into<String>,
        content: impl Into<String>,
    ) -> Self {
        let user_id = user_id.into();
        Self {
            id: Uuid::new_v4(),
            channel: channel.into(),
            owner_id: user_id.clone(),
            sender_id: user_id.clone(),
            user_id,
            user_name: None,
            content: content.into(),
            thread_id: None,
            conversation_scope_id: None,
            received_at: Utc::now(),
            metadata: serde_json::Value::Null,
            timezone: None,
            attachments: Vec::new(),
        }
    }

    /// Set the thread ID.
    pub fn with_thread(mut self, thread_id: impl Into<String>) -> Self {
        let thread_id = thread_id.into();
        self.conversation_scope_id = Some(thread_id.clone());
        self.thread_id = Some(thread_id);
        self
    }

    /// Set the stable owner scope for this message.
    pub fn with_owner_id(mut self, owner_id: impl Into<String>) -> Self {
        self.owner_id = owner_id.into();
        self
    }

    /// Set the channel-specific sender/actor identifier.
    pub fn with_sender_id(mut self, sender_id: impl Into<String>) -> Self {
        self.sender_id = sender_id.into();
        self
    }

    /// Set the conversation scope for this message.
    pub fn with_conversation_scope(mut self, scope_id: impl Into<String>) -> Self {
        self.conversation_scope_id = Some(scope_id.into());
        self
    }

    /// Set metadata.
    pub fn with_metadata(mut self, metadata: serde_json::Value) -> Self {
        self.metadata = metadata;
        self
    }

    /// Set user name.
    pub fn with_user_name(mut self, name: impl Into<String>) -> Self {
        self.user_name = Some(name.into());
        self
    }

    /// Set the client timezone.
    pub fn with_timezone(mut self, tz: impl Into<String>) -> Self {
        self.timezone = Some(tz.into());
        self
    }

    /// Set attachments.
    pub fn with_attachments(mut self, attachments: Vec<IncomingAttachment>) -> Self {
        self.attachments = attachments;
        self
    }

    /// Effective conversation scope, falling back to thread_id for older callers.
    pub fn conversation_scope(&self) -> Option<&str> {
        self.conversation_scope_id
            .as_deref()
            .or(self.thread_id.as_deref())
    }

    /// Best-effort routing target for proactive replies on the current channel.
    pub fn routing_target(&self) -> Option<String> {
        routing_target_from_metadata(&self.metadata).or_else(|| {
            if self.sender_id.is_empty() {
                None
            } else {
                Some(self.sender_id.clone())
            }
        })
    }
}

/// Extract a channel-specific proactive routing target from message metadata.
pub fn routing_target_from_metadata(metadata: &serde_json::Value) -> Option<String> {
    let extract = |key: &str| -> Option<String> {
        metadata.get(key).and_then(|value| match value {
            serde_json::Value::String(s) => Some(s.clone()),
            serde_json::Value::Number(n) => Some(n.to_string()),
            _ => None,
        })
    };

    extract("signal_target")
        .or_else(|| extract("chat_id"))
        .or_else(|| extract("channel_id"))
        .or_else(|| extract("target"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_evolved_serializes_with_expected_shape() {
        let event = ChatEvent::MemoryEvolved {
            target: "MEMORY.md".to_string(),
            content: "## test\n\ntest content\n".to_string(),
        };

        let json = serde_json::to_string(&event).expect("serialization failed");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("invalid JSON");

        assert_eq!(parsed["type"], "memory_evolved");
        assert_eq!(parsed["target"], "MEMORY.md");
        assert_eq!(parsed["content"], "## test\n\ntest content\n");
    }

    #[test]
    fn skill_evolved_serializes_with_expected_shape() {
        let event = ChatEvent::SkillEvolved {
            skill_name: "my-skill".to_string(),
            action: "create".to_string(),
            summary: "# My Skill\n\nDoes things.".to_string(),
        };

        let json = serde_json::to_string(&event).expect("serialization failed");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("invalid JSON");

        assert_eq!(parsed["type"], "skill_evolved");
        assert_eq!(parsed["skill_name"], "my-skill");
        assert_eq!(parsed["action"], "create");
        assert_eq!(parsed["summary"], "# My Skill\n\nDoes things.");
    }

    #[test]
    fn evolution_queued_serializes_with_expected_shape() {
        let event = ChatEvent::EvolutionQueued {
            review_types: vec!["memory".to_string(), "skill".to_string()],
            runs: vec![EvolutionQueuedRun {
                id: "run-1".to_string(),
                review_type: "memory".to_string(),
            }],
        };

        let json = serde_json::to_string(&event).expect("serialization failed");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("invalid JSON");

        assert_eq!(parsed["type"], "evolution_queued");
        assert_eq!(parsed["review_types"][0], "memory");
        assert_eq!(parsed["review_types"][1], "skill");
        assert_eq!(parsed["runs"][0]["id"], "run-1");
        assert_eq!(parsed["runs"][0]["review_type"], "memory");
    }

    #[test]
    fn shell_approval_mode_deserializes_known_wire_values() {
        assert_eq!(
            serde_json::from_str::<ShellApprovalMode>("\"read_only_only\"").unwrap(),
            ShellApprovalMode::ReadOnlyOnly
        );
        assert_eq!(
            serde_json::from_str::<ShellApprovalMode>("\"on_request\"").unwrap(),
            ShellApprovalMode::OnRequest
        );
        assert_eq!(
            serde_json::from_str::<ShellApprovalMode>("\"trusted_allow\"").unwrap(),
            ShellApprovalMode::TrustedAllow
        );
        assert_eq!(
            serde_json::from_str::<ShellApprovalMode>("\"custom\"").unwrap(),
            ShellApprovalMode::Custom
        );
    }

    #[test]
    fn shell_approval_mode_unknown_value_falls_back_to_on_request() {
        // Typo, future tag, or hostile payload must degrade safely instead of
        // erroring — otherwise the whole PlatformLlmConfig parse would fail.
        assert_eq!(
            serde_json::from_str::<ShellApprovalMode>("\"bogus\"").unwrap(),
            ShellApprovalMode::OnRequest
        );
        assert_eq!(
            serde_json::from_str::<ShellApprovalMode>("\"\"").unwrap(),
            ShellApprovalMode::OnRequest
        );
    }

    #[test]
    fn shell_security_config_unknown_mode_parses_and_falls_back() {
        let config: ShellSecurityConfig =
            serde_json::from_str(r#"{"approval_mode": "definitely_not_a_mode"}"#)
                .expect("config with unknown approval_mode must still parse");
        assert_eq!(config.approval_mode, ShellApprovalMode::OnRequest);
    }

    #[test]
    fn shell_approval_mode_serializes_unchanged_snake_case() {
        // Serialize half must keep emitting the snake_case wire values; the
        // fail-safe only applies to the deserialize direction.
        assert_eq!(
            serde_json::to_string(&ShellApprovalMode::TrustedAllow).unwrap(),
            "\"trusted_allow\""
        );
        assert_eq!(
            serde_json::to_string(&ShellApprovalMode::ReadOnlyOnly).unwrap(),
            "\"read_only_only\""
        );
        assert_eq!(
            serde_json::to_string(&ShellApprovalMode::OnRequest).unwrap(),
            "\"on_request\""
        );
        assert_eq!(
            serde_json::to_string(&ShellApprovalMode::Custom).unwrap(),
            "\"custom\""
        );
    }

    #[test]
    fn git_mode_default_is_structured() {
        assert_eq!(GitMode::default(), GitMode::Structured);
        assert!(matches!(
            GitConfig::default().mode,
            GitMode::Structured
        ));
    }

    #[test]
    fn git_mode_deserializes_known_wire_values() {
        assert_eq!(
            serde_json::from_str::<GitMode>("\"structured\"").unwrap(),
            GitMode::Structured
        );
        assert_eq!(
            serde_json::from_str::<GitMode>("\"native\"").unwrap(),
            GitMode::Native
        );
    }

    #[test]
    fn git_mode_unknown_value_falls_back_to_structured() {
        // Typos / future tags / hostile payloads must degrade safely instead
        // of failing the whole PlatformLlmConfig parse.
        assert_eq!(
            serde_json::from_str::<GitMode>("\"bogus\"").unwrap(),
            GitMode::Structured
        );
        assert_eq!(
            serde_json::from_str::<GitMode>("\"\"").unwrap(),
            GitMode::Structured
        );
    }

    #[test]
    fn platform_llm_config_defaults_to_structured_git_and_absent_is_structured() {
        // Absent `git` field (legacy configs) must parse without error and leave
        // no git config, which the runtime treats as Structured.
        let cfg: PlatformLlmConfig = serde_json::from_str(
            r#"{"provider":"x","api_key":"","model":"m","system_prompt":"","max_tokens":128}"#,
        )
        .expect("minimal config must parse");
        assert!(cfg.git.is_none());

        let native: PlatformLlmConfig = serde_json::from_str(
            r#"{"provider":"x","api_key":"","model":"m","system_prompt":"","max_tokens":128,"git":{"mode":"native","identity":{"name":"Ada","email":"a@b.c"}}}"#,
        )
        .expect("native git config must parse");
        let git = native.git.expect("git config present");
        assert_eq!(git.mode, GitMode::Native);
        let id = git.identity.expect("identity present");
        assert_eq!(id.name, "Ada");
        assert_eq!(id.email, "a@b.c");
    }
}
