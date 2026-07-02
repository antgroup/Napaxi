//! Core skill types.
//!
//! Contains the data structures for skill manifests, activation criteria,
//! trust levels, and loaded skills.

use std::collections::HashMap;
use std::path::PathBuf;

use regex::Regex;
use serde::{Deserialize, Serialize};

/// Maximum number of keywords allowed per skill to prevent scoring manipulation.
const MAX_KEYWORDS_PER_SKILL: usize = 20;

/// Maximum number of regex patterns allowed per skill.
const MAX_PATTERNS_PER_SKILL: usize = 5;

/// Maximum number of tags allowed per skill to prevent scoring manipulation.
const MAX_TAGS_PER_SKILL: usize = 10;

/// Maximum number of companion skill declarations in `requires.skills`.
/// Mirrors `MAX_CHAIN_DEPS` in the host crate's skill_install tool to keep
/// the chain installer's queue size bounded from hostile manifests.
pub const MAX_REQUIRED_SKILLS_PER_MANIFEST: usize = 10;

/// Minimum length for keywords and tags. Short tokens like "a" or "is"
/// match too broadly and can be used to game the scoring system.
const MIN_KEYWORD_TAG_LENGTH: usize = 3;

/// Maximum file size for SKILL.md (64 KiB).
pub const MAX_PROMPT_FILE_SIZE: u64 = 64 * 1024;

/// Trust state for a skill, determining its authority ceiling.
///
/// SAFETY: Variant ordering matters. `Ord` is derived from discriminant values
/// and the security model relies on `Installed < Trusted`. Do NOT reorder
/// variants or change discriminant values without auditing all `min()` /
/// comparison call-sites in attenuation code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SkillTrust {
    /// Registry/external skill. Read-only tools only.
    Installed = 0,
    /// User-placed skill (local or workspace). Full trust, all tools available.
    Trusted = 1,
}

impl std::fmt::Display for SkillTrust {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Installed => write!(f, "installed"),
            Self::Trusted => write!(f, "trusted"),
        }
    }
}

/// Where a skill was loaded from.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SkillSource {
    /// Workspace skills directory (`<workspace>/skills/`).
    Workspace(PathBuf),
    /// User skills directory (~/.napaxi/skills/).
    User(PathBuf),
    /// Registry-installed skills directory (~/.napaxi/installed_skills/).
    Installed(PathBuf),
    /// Bundled with the application.
    Bundled(PathBuf),
}

/// Activation criteria parsed from SKILL.md frontmatter `activation` section.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ActivationCriteria {
    /// Keywords that trigger this skill (exact and substring match).
    /// Capped at `MAX_KEYWORDS_PER_SKILL` during loading.
    #[serde(default)]
    pub keywords: Vec<String>,
    /// Keywords that veto this skill — if any match, score is 0 regardless of
    /// keyword/pattern matches. Prevents cross-skill interference.
    #[serde(default)]
    pub exclude_keywords: Vec<String>,
    /// Regex patterns for more complex matching.
    /// Capped at `MAX_PATTERNS_PER_SKILL` during loading.
    #[serde(default)]
    pub patterns: Vec<String>,
    /// Tags for broad category matching.
    #[serde(default)]
    pub tags: Vec<String>,
    /// Maximum context tokens this skill's prompt should consume.
    #[serde(default = "default_max_context_tokens")]
    pub max_context_tokens: usize,
}

impl ActivationCriteria {
    /// Enforce limits on keywords, patterns, and tags to prevent scoring manipulation.
    ///
    /// Filters out short keywords/tags (< 3 chars) that match too broadly,
    /// then truncates to per-field caps.
    pub fn enforce_limits(&mut self) {
        self.keywords.retain(|k| k.len() >= MIN_KEYWORD_TAG_LENGTH);
        self.keywords.truncate(MAX_KEYWORDS_PER_SKILL);
        self.exclude_keywords
            .retain(|k| k.len() >= MIN_KEYWORD_TAG_LENGTH);
        self.exclude_keywords.truncate(MAX_KEYWORDS_PER_SKILL);
        self.patterns.truncate(MAX_PATTERNS_PER_SKILL);
        self.tags.retain(|t| t.len() >= MIN_KEYWORD_TAG_LENGTH);
        self.tags.truncate(MAX_TAGS_PER_SKILL);
    }
}

fn default_max_context_tokens() -> usize {
    2000
}

/// Parsed skill manifest from SKILL.md YAML frontmatter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillManifest {
    /// Skill name (validated against SKILL_NAME_PATTERN).
    pub name: String,
    /// Optional human-facing display name used by ClawHub/OpenClaw listings.
    #[serde(default)]
    pub display_name: Option<String>,
    /// Skill version.
    #[serde(default = "default_version")]
    pub version: String,
    /// Short description of the skill.
    #[serde(default)]
    pub description: String,
    /// Activation criteria.
    #[serde(default)]
    pub activation: ActivationCriteria,
    /// Credential requirements for API access.
    /// Parsed at load time; values are never in the LLM context.
    #[serde(default)]
    pub credentials: Vec<SkillCredentialSpec>,
    /// Gating requirements (binaries, env vars, config files, companion skills).
    #[serde(default)]
    pub requires: GatingRequirements,
    /// Raw extension metadata from ClawHub/OpenClaw and other AgentSkills publishers.
    #[serde(default)]
    pub metadata: serde_json::Value,
}

impl SkillManifest {
    /// OpenClaw-compatible metadata object, if present.
    pub fn openclaw_metadata(&self) -> Option<&serde_json::Value> {
        self.metadata.get("openclaw")
    }

    pub fn metadata_string(&self, key: &str) -> Option<String> {
        self.openclaw_metadata()
            .and_then(|metadata| metadata.get(key))
            .and_then(serde_json::Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    }

    pub fn metadata_bool(&self, key: &str, default: bool) -> bool {
        self.openclaw_metadata()
            .and_then(|metadata| metadata.get(key))
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(default)
    }

    pub fn disable_model_invocation(&self) -> bool {
        self.metadata_bool("disable-model-invocation", false)
    }

    pub fn user_invocable(&self) -> bool {
        self.metadata_bool("user-invocable", true)
    }
}

fn default_version() -> String {
    "0.0.0".to_string()
}

/// Requirements that must be satisfied for a skill to load.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GatingRequirements {
    /// Required binaries that must be on PATH.
    #[serde(default)]
    pub bins: Vec<String>,
    /// Alternative binaries where at least one must be present.
    #[serde(default, alias = "anyBins")]
    pub any_bins: Vec<String>,
    /// Required environment variables that must be set.
    #[serde(default)]
    pub env: Vec<String>,
    /// Required config file paths that must exist.
    #[serde(default)]
    pub config: Vec<String>,
    /// Platforms supported by the skill, using host platform names such as
    /// `android`, `ios`, `macos`, `linux`, `windows`, or `all`.
    #[serde(default)]
    pub os: Vec<String>,
    /// Core/host capabilities the skill expects to be enabled.
    #[serde(default)]
    pub capabilities: Vec<String>,
    /// Companion skills that should be installed alongside this one.
    ///
    /// Unlike bins/env/config, these entries are advisory metadata only and do
    /// not currently prevent the skill from loading when missing. This allows
    /// bundle/setup skills to declare which sub-skills they are intended to be
    /// used with (e.g., a `ceo-assistant` bundle references
    /// `commitment-triage`, `commitment-digest`, `decision-capture`, etc.).
    ///
    /// Capped at `MAX_REQUIRED_SKILLS_PER_MANIFEST` during parsing via
    /// [`GatingRequirements::enforce_limits`] to keep the chain installer's
    /// queue size bounded from hostile manifests.
    #[serde(default)]
    pub skills: Vec<String>,
}

impl GatingRequirements {
    /// Enforce per-manifest limits on `requires.skills`.
    ///
    /// Called from the parser so hostile or buggy manifests with hundreds of
    /// companion-skill declarations can't cause unbounded queue growth in
    /// the chain installer before the downstream `MAX_CHAIN_DEPS` cap kicks
    /// in.
    pub fn enforce_limits(&mut self) {
        self.skills.truncate(MAX_REQUIRED_SKILLS_PER_MANIFEST);
    }

    pub fn is_empty(&self) -> bool {
        self.bins.is_empty()
            && self.any_bins.is_empty()
            && self.env.is_empty()
            && self.config.is_empty()
            && self.os.is_empty()
            && self.capabilities.is_empty()
            && self.skills.is_empty()
    }

    pub fn merge_missing_from(&mut self, fallback: &GatingRequirements) {
        if self.bins.is_empty() {
            self.bins = fallback.bins.clone();
        }
        if self.any_bins.is_empty() {
            self.any_bins = fallback.any_bins.clone();
        }
        if self.env.is_empty() {
            self.env = fallback.env.clone();
        }
        if self.config.is_empty() {
            self.config = fallback.config.clone();
        }
        if self.os.is_empty() {
            self.os = fallback.os.clone();
        }
        if self.capabilities.is_empty() {
            self.capabilities = fallback.capabilities.clone();
        }
        if self.skills.is_empty() {
            self.skills = fallback.skills.clone();
        }
        self.enforce_limits();
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SkillReadinessContext {
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default, alias = "availableBins")]
    pub available_bins: Vec<String>,
    #[serde(default, alias = "envKeys")]
    pub env_keys: Vec<String>,
    #[serde(default, alias = "configFlags")]
    pub config_flags: Vec<String>,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub use_process_fallback: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MissingRequirements {
    #[serde(default)]
    pub bins: Vec<String>,
    #[serde(default, alias = "anyBins")]
    pub any_bins: Vec<String>,
    #[serde(default)]
    pub env: Vec<String>,
    #[serde(default)]
    pub config: Vec<String>,
    #[serde(default)]
    pub os: Vec<String>,
    #[serde(default)]
    pub capabilities: Vec<String>,
}

/// Where to inject a credential in HTTP requests.
///
/// Maps 1:1 to `CredentialLocation` in `src/secrets/types.rs` but is defined
/// here so that `napaxi_skills` remains independent of the main crate.
/// Conversion happens at registration time in `src/skills/mod.rs`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum SkillCredentialLocation {
    /// `Authorization: Bearer {secret}`
    Bearer,
    /// `Authorization: Basic base64(username:secret)`
    BasicAuth { username: String },
    /// Custom header, optionally prefixed (e.g. `X-API-Key: Token {secret}`)
    Header {
        name: String,
        #[serde(default)]
        prefix: Option<String>,
    },
    /// Query parameter (e.g. `?api_key={secret}`)
    QueryParam { name: String },
}

/// How the provider handles token refresh.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(tag = "strategy", rename_all = "snake_case")]
pub enum ProviderRefreshStrategy {
    /// Standard OAuth2 `refresh_token` grant.
    #[default]
    Standard,
    /// Provider does not support refresh — re-authorize when expired.
    ReauthorizeOnly,
    /// Provider-specific refresh endpoint or extra parameters.
    Custom {
        refresh_url: String,
        #[serde(default)]
        extra_params: HashMap<String, String>,
    },
}

/// OAuth configuration for a credential declared by a skill.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillOAuthConfig {
    pub authorization_url: String,
    pub token_url: String,
    #[serde(default)]
    pub client_id: Option<String>,
    #[serde(default)]
    pub client_id_env: Option<String>,
    #[serde(default)]
    pub client_secret: Option<String>,
    #[serde(default)]
    pub client_secret_env: Option<String>,
    #[serde(default)]
    pub scopes: Vec<String>,
    #[serde(default)]
    pub use_pkce: bool,
    #[serde(default)]
    pub extra_params: HashMap<String, String>,
    /// How this provider handles token refresh (default: standard OAuth2).
    #[serde(default)]
    pub refresh: ProviderRefreshStrategy,
    /// Optional endpoint to test the token after exchange (e.g. Google userinfo).
    #[serde(default)]
    pub test_url: Option<String>,
}

/// A credential requirement declared by a skill.
///
/// Skills declare credentials in YAML frontmatter so the system can register
/// host→credential mappings and manage OAuth flows without WASM modules.
/// Credential *values* are never in the LLM's context — only these metadata
/// specs are parsed at skill-load time.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillCredentialSpec {
    /// Secret name in the `SecretsStore` (e.g. `google_oauth_token`).
    pub name: String,
    /// Provider hint (e.g. `google`, `github`, `slack`).
    pub provider: String,
    /// Where to inject the credential in HTTP requests.
    pub location: SkillCredentialLocation,
    /// Host patterns this credential applies to (glob syntax, e.g. `*.googleapis.com`).
    pub hosts: Vec<String>,
    /// Optional OAuth configuration for automated token exchange and refresh.
    #[serde(default)]
    pub oauth: Option<SkillOAuthConfig>,
    /// Human-readable setup instructions shown when the credential is missing.
    #[serde(default)]
    pub setup_instructions: Option<String>,
}

/// A fully loaded skill ready for activation.
#[derive(Debug, Clone)]
pub struct LoadedSkill {
    /// Parsed manifest from YAML frontmatter.
    pub manifest: SkillManifest,
    /// Raw prompt content (markdown body after frontmatter).
    pub prompt_content: String,
    /// Trust state (determined by source location).
    pub trust: SkillTrust,
    /// Where this skill was loaded from.
    pub source: SkillSource,
    /// SHA-256 hash of the prompt content (computed at load time).
    pub content_hash: String,
    /// Pre-compiled regex patterns from activation criteria (compiled at load time).
    pub compiled_patterns: Vec<Regex>,
    /// Pre-computed lowercased keywords for scoring (avoids per-message allocation).
    /// Derived from `manifest.activation.keywords` at load time — do not mutate independently.
    pub lowercased_keywords: Vec<String>,
    /// Pre-computed lowercased exclude keywords for veto scoring.
    /// Derived from `manifest.activation.exclude_keywords` at load time.
    pub lowercased_exclude_keywords: Vec<String>,
    /// Pre-computed lowercased tags for scoring (avoids per-message allocation).
    /// Derived from `manifest.activation.tags` at load time — do not mutate independently.
    pub lowercased_tags: Vec<String>,
    /// Pre-compiled regex patterns from common ClawHub/OpenClaw metadata extensions.
    pub compiled_metadata_patterns: Vec<Regex>,
    /// Pre-computed searchable terms from AgentSkills metadata such as name,
    /// display_name, description, and metadata intents.
    pub lowercased_metadata_terms: Vec<String>,
    /// Owner user ID. Empty string means global (bundled) skill visible to all users.
    /// Non-empty means this skill belongs to a specific user and is only visible
    /// to that user.
    ///
    /// INVARIANT: owner_user_id == "" implies SkillSource::Bundled or
    /// SkillSource::Workspace. A skill with owner_user_id == "" MUST NOT be
    /// removable by any user.
    pub owner_user_id: String,
}

impl LoadedSkill {
    /// Get the skill name.
    pub fn name(&self) -> &str {
        &self.manifest.name
    }

    /// Get the skill version.
    pub fn version(&self) -> &str {
        &self.manifest.version
    }

    /// Read a string array from raw metadata by key.
    pub fn metadata_string_array(metadata: &serde_json::Value, key: &str) -> Vec<String> {
        metadata
            .get(key)
            .and_then(serde_json::Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| item.as_str().map(str::trim))
                    .filter(|item| !item.is_empty())
                    .take(20)
                    .map(ToOwned::to_owned)
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Compile regex patterns from activation criteria. Invalid or oversized patterns
    /// are logged and skipped. A size limit of 64 KiB is imposed on compiled regex
    /// state to prevent ReDoS via pathological patterns.
    pub fn compile_patterns(patterns: &[String]) -> Vec<Regex> {
        /// Maximum compiled regex size (64 KiB) to prevent ReDoS.
        const MAX_REGEX_SIZE: usize = 1 << 16;

        patterns
            .iter()
            .filter_map(|p| {
                match regex::RegexBuilder::new(p)
                    .size_limit(MAX_REGEX_SIZE)
                    .build()
                {
                    Ok(re) => Some(re),
                    Err(e) => {
                        tracing::warn!("Invalid activation regex pattern '{}': {}", p, e);
                        None
                    }
                }
            })
            .collect()
    }
}

#[cfg(test)]
mod tests;
