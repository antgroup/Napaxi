//! Skill registry for discovering, loading, and managing available skills.
//!
//! Skills are discovered from multiple sources:
//! 1. Workspace skills directory (`<workspace>/skills/`) -- Trusted
//! 2. User skills directory (`~/.napaxi/skills/`) -- Trusted
//! 3. Installed skills directory (`~/.napaxi/installed_skills/`) -- Installed
//! 4. Bundled skills compiled into the binary -- Trusted
//!
//! Both flat (`skills/SKILL.md`) and subdirectory (`skills/<name>/SKILL.md`)
//! layouts are supported. Subdirectories without `SKILL.md` are treated as
//! bundle directories and recursed into (up to `SKILLS_MAX_SCAN_DEPTH`,
//! default 3). Earlier sources win on name collision (workspace overrides
//! user overrides installed overrides bundled).
//! Uses async I/O throughout to avoid blocking the tokio runtime.

mod install;

use parking_lot::RwLock;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::afs_traits::{AfsError, get_afs};
use crate::gating;
use crate::parser::{
    SkillParseError, parse_skill_md, parse_skill_md_for_install_recovery,
    split_skill_md_frontmatter,
};
use crate::types::{
    GatingRequirements, LoadedSkill, MAX_PROMPT_FILE_SIZE, SkillManifest, SkillSource, SkillTrust,
};
use crate::validation::{normalize_line_endings, normalize_skill_identifier};
/// Maximum total number of skills that can be discovered across all sources.
/// Shared across workspace, user, and installed directories.
/// Prevents resource exhaustion from directories with thousands of entries.
const MAX_DISCOVERED_SKILLS: usize = 100;

/// Default recursion depth for bundle directory scanning.
const DEFAULT_MAX_SCAN_DEPTH: usize = 3;

fn to_lowercase_vec(items: &[String]) -> Vec<String> {
    items.iter().map(|s| s.to_lowercase()).collect()
}

/// Error type for skill registry operations.
#[derive(Debug, thiserror::Error)]
pub enum SkillRegistryError {
    #[error("Skill not found: {0}")]
    NotFound(String),

    #[error("Failed to read skill file {path}: {reason}")]
    ReadError { path: String, reason: String },

    #[error("Failed to parse SKILL.md for '{name}': {reason}")]
    ParseError { name: String, reason: String },

    #[error("Skill file too large for '{name}': {size} bytes (max {max} bytes)")]
    FileTooLarge { name: String, size: u64, max: u64 },

    #[error("Symlink detected in skills directory: {path}")]
    SymlinkDetected { path: String },

    #[error("Skill '{name}' failed gating: {reason}")]
    GatingFailed { name: String, reason: String },

    #[error(
        "Skill '{name}' prompt exceeds token budget: ~{approx_tokens} tokens but declares max_context_tokens={declared}"
    )]
    TokenBudgetExceeded {
        name: String,
        approx_tokens: usize,
        declared: usize,
    },

    #[error("Skill '{name}' already exists")]
    AlreadyExists { name: String },

    #[error("Skill '{name}' failed security scan: {reason}")]
    SecurityCheckFailed { name: String, reason: String },

    #[error("Cannot remove skill '{name}': {reason}")]
    CannotRemove { name: String, reason: String },

    #[error("Failed to write skill file {path}: {reason}")]
    WriteError { path: String, reason: String },

    #[error("Afs error: {0}")]
    Afs(#[from] AfsError),
}

/// Registry of available skills.
pub struct SkillRegistry {
    /// All loaded skills.
    skills: RwLock<Vec<Arc<LoadedSkill>>>,
    /// User skills directory (~/.napaxi/skills/). Skills here are Trusted.
    user_dir: PathBuf,
    /// Registry-installed skills directory (~/.napaxi/installed_skills/). Skills here are Installed.
    installed_dir: Option<PathBuf>,
    /// Optional workspace skills directory.
    workspace_dir: Option<PathBuf>,
    /// Bundled skill content compiled into the binary (name, raw SKILL.md content).
    /// Loaded as Trusted at lowest discovery priority.
    bundled_content: &'static [(String, String)],
    /// Maximum recursion depth for bundle directory scanning (default: 3).
    max_scan_depth: usize,
}

impl SkillRegistry {
    /// Create a new skill registry.
    pub fn new(user_dir: PathBuf) -> Self {
        Self {
            skills: RwLock::new(Vec::new()),
            user_dir,
            installed_dir: None,
            workspace_dir: None,
            bundled_content: &[],
            max_scan_depth: DEFAULT_MAX_SCAN_DEPTH,
        }
    }

    /// Set the registry-installed skills directory.
    ///
    /// Skills installed via ClawHub or the skill tools are written here and
    /// loaded with `SkillTrust::Installed` (read-only tool access). This
    /// directory is separate from the user dir so that trust levels survive
    /// restarts correctly.
    pub fn with_installed_dir(mut self, dir: PathBuf) -> Self {
        self.installed_dir = Some(dir);
        self
    }

    /// Set a workspace skills directory.
    pub fn with_workspace_dir(mut self, dir: PathBuf) -> Self {
        self.workspace_dir = Some(dir);
        self
    }

    /// Set bundled skill content compiled into the binary.
    ///
    /// Each entry is `(skill_name, raw_skill_md_content)`. These skills are
    /// discovered at the lowest priority (after workspace, user, and installed)
    /// with `SkillTrust::Trusted` since they ship with the application binary.
    pub fn with_bundled_content(mut self, content: &'static [(String, String)]) -> Self {
        self.bundled_content = content;
        self
    }

    /// Set the maximum recursion depth for bundle directory scanning.
    pub fn with_max_scan_depth(mut self, depth: usize) -> Self {
        self.max_scan_depth = depth;
        self
    }

    /// Get all loaded skills.
    pub fn skills(&self) -> Vec<Arc<LoadedSkill>> {
        self.skills.read().iter().cloned().collect()
    }

    /// Get the number of loaded skills.
    pub fn count(&self) -> usize {
        self.skills.read().len()
    }

    /// Get the base directory where skills are stored.
    pub fn base_dir(&self) -> &PathBuf {
        &self.user_dir
    }

    /// Retain only skills whose names are in the given allowlist.
    ///
    /// If `names` is empty, this is a no-op (all skills are kept).
    pub fn retain_only(&self, names: &[&str]) {
        if names.is_empty() {
            return;
        }
        let names_set: HashSet<&str> = names.iter().copied().collect();
        self.skills
            .write()
            .retain(|s| names_set.contains(s.manifest.name.as_str()));
    }

    /// Check if a skill with the given name is loaded.
    pub fn has(&self, name: &str) -> bool {
        self.skills.read().iter().any(|s| s.manifest.name == name)
    }

    /// Find a skill by name.
    pub fn find_by_name(&self, name: &str) -> Option<Arc<LoadedSkill>> {
        self.skills
            .read()
            .iter()
            .find(|s| s.manifest.name == name)
            .cloned()
    }

    /// Get skills visible to a specific user.
    /// Returns: user-owned skills + global skills (owner_user_id is empty)
    pub fn skills_for_user(&self, user_id: &str) -> Vec<Arc<LoadedSkill>> {
        self.skills
            .read()
            .iter()
            .filter(|s| s.owner_user_id.is_empty() || s.owner_user_id == user_id)
            .cloned()
            .collect()
    }

    /// Check if a skill with the given name exists for a specific user.
    /// A user can see their own skills + global skills.
    pub fn has_for_user(&self, name: &str, user_id: &str) -> bool {
        self.skills.read().iter().any(|s| {
            s.manifest.name == name && (s.owner_user_id.is_empty() || s.owner_user_id == user_id)
        })
    }

    /// Check if a skill with the given name is owned by a specific user
    /// (strict ownership check, excluding global skills).
    pub fn has_owned(&self, name: &str, user_id: &str) -> bool {
        self.skills
            .read()
            .iter()
            .any(|s| s.manifest.name == name && s.owner_user_id == user_id)
    }

    /// Find a skill by name for a specific user.
    /// Returns the user-owned version first, then global.
    pub fn find_by_name_for_user(&self, name: &str, user_id: &str) -> Option<Arc<LoadedSkill>> {
        self.skills
            .read()
            .iter()
            .find(|s| s.manifest.name == name && s.owner_user_id == user_id)
            .cloned()
            .or_else(|| {
                self.skills
                    .read()
                    .iter()
                    .find(|s| s.manifest.name == name && s.owner_user_id.is_empty())
                    .cloned()
            })
    }

    /// Find a skill strictly owned by a specific user (no global fallback).
    pub fn find_owned(&self, name: &str, user_id: &str) -> Option<Arc<LoadedSkill>> {
        self.skills
            .read()
            .iter()
            .find(|s| s.manifest.name == name && s.owner_user_id == user_id)
            .cloned()
    }

    /// Get the user skills directory path.
    pub fn user_dir(&self) -> &Path {
        &self.user_dir
    }

    /// Get the installed skills directory path, if configured.
    pub fn installed_dir(&self) -> Option<&Path> {
        self.installed_dir.as_deref()
    }

    /// Get the directory where new registry installs should be written.
    ///
    /// Returns the installed_dir if configured (preferred), otherwise falls
    /// back to user_dir. In practice, the installed_dir is always set when
    /// the app is running; the fallback exists for test registries.
    pub fn install_target_dir(&self) -> &Path {
        self.installed_dir.as_deref().unwrap_or(&self.user_dir)
    }
}

/// Load and validate a single SKILL.md file from disk.
///
/// Reads the file, checks for symlinks and size limits, then delegates to
/// `build_loaded_skill` for parsing, validation, and construction.
async fn load_and_validate_skill(
    path: &Path,
    trust: SkillTrust,
    source: SkillSource,
    user_id: &str,
) -> Result<(String, LoadedSkill), SkillRegistryError> {
    let afs = get_afs(user_id)?;
    // Check for symlink at the file level
    let file_meta =
        afs.symlink_metadata(path)
            .await
            .map_err(|e| SkillRegistryError::ReadError {
                path: path.display().to_string(),
                reason: e.to_string(),
            })?;

    if file_meta.is_symlink() {
        return Err(SkillRegistryError::SymlinkDetected {
            path: path.display().to_string(),
        });
    }

    // Read and check size
    let raw_bytes = afs
        .read(path)
        .await
        .map_err(|e| SkillRegistryError::ReadError {
            path: path.display().to_string(),
            reason: e.to_string(),
        })?;

    if raw_bytes.len() as u64 > MAX_PROMPT_FILE_SIZE {
        return Err(SkillRegistryError::FileTooLarge {
            name: path.display().to_string(),
            size: raw_bytes.len() as u64,
            max: MAX_PROMPT_FILE_SIZE,
        });
    }

    let raw_content = String::from_utf8(raw_bytes).map_err(|e| SkillRegistryError::ReadError {
        path: path.display().to_string(),
        reason: format!("Invalid UTF-8: {}", e),
    })?;

    let normalized_content = normalize_line_endings(&raw_content);
    let error_label = path.display().to_string();

    build_loaded_skill(&normalized_content, &error_label, trust, source).await
}

/// Load and validate a skill from in-memory content (no disk I/O).
///
/// Used for bundled skills compiled into the binary.
async fn load_from_content(
    raw_content: &str,
    trust: SkillTrust,
    source: SkillSource,
) -> Result<(String, LoadedSkill), SkillRegistryError> {
    if raw_content.len() as u64 > MAX_PROMPT_FILE_SIZE {
        return Err(SkillRegistryError::FileTooLarge {
            name: "(bundled)".to_string(),
            size: raw_content.len() as u64,
            max: MAX_PROMPT_FILE_SIZE,
        });
    }

    let normalized_content = normalize_line_endings(raw_content);

    build_loaded_skill(&normalized_content, "(bundled)", trust, source).await
}

/// Parse, validate, gate-check, and construct a `LoadedSkill` from normalized content.
///
/// Shared implementation used by both `load_and_validate_skill` (disk) and
/// `load_from_content` (in-memory). The `error_label` is used in error messages
/// to identify the source (file path or "(bundled)").
async fn build_loaded_skill(
    normalized_content: &str,
    error_label: &str,
    trust: SkillTrust,
    source: SkillSource,
) -> Result<(String, LoadedSkill), SkillRegistryError> {
    let parsed = parse_skill_md(normalized_content).map_err(|e: SkillParseError| match e {
        SkillParseError::InvalidName { ref name } => SkillRegistryError::ParseError {
            name: name.clone(),
            reason: e.to_string(),
        },
        _ => SkillRegistryError::ParseError {
            name: error_label.to_string(),
            reason: e.to_string(),
        },
    })?;

    let manifest = parsed.manifest;
    let prompt_content = parsed.prompt_content;

    // Check gating requirements
    {
        let result = gating::check_requirements(&manifest.requires).await;
        if !result.passed {
            return Err(SkillRegistryError::GatingFailed {
                name: manifest.name.clone(),
                reason: result.failures.join("; "),
            });
        }
    }

    // Check token budget (reject if prompt is > 2x declared budget)
    // ~4 bytes per token for English prose = ~0.25 tokens per byte
    let approx_tokens = (prompt_content.len() as f64 * 0.25) as usize;
    let declared = manifest.activation.max_context_tokens;
    if declared > 0 && approx_tokens > declared * 2 {
        return Err(SkillRegistryError::TokenBudgetExceeded {
            name: manifest.name.clone(),
            approx_tokens,
            declared,
        });
    }

    let content_hash = compute_hash(&prompt_content);
    let metadata_patterns = LoadedSkill::metadata_string_array(&manifest.metadata, "patterns");
    let compiled_patterns = LoadedSkill::compile_patterns(&manifest.activation.patterns);
    let compiled_metadata_patterns = LoadedSkill::compile_patterns(&metadata_patterns);
    let lowercased_keywords = to_lowercase_vec(&manifest.activation.keywords);
    let lowercased_exclude_keywords = to_lowercase_vec(&manifest.activation.exclude_keywords);
    let lowercased_tags = to_lowercase_vec(&manifest.activation.tags);
    let lowercased_metadata_terms = metadata_terms(&manifest);

    let name = manifest.name.clone();
    let skill = LoadedSkill {
        manifest,
        prompt_content,
        trust,
        source,
        content_hash,
        compiled_patterns,
        lowercased_keywords,
        lowercased_exclude_keywords,
        lowercased_tags,
        compiled_metadata_patterns,
        lowercased_metadata_terms,
        owner_user_id: String::new(),
    };

    Ok((name, skill))
}

/// Compute SHA-256 hash of content in the format "sha256:hex...".
pub fn compute_hash(content: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let result = hasher.finalize();
    format!("sha256:{:x}", result)
}

fn metadata_terms(manifest: &SkillManifest) -> Vec<String> {
    let mut terms = Vec::new();
    push_search_terms(&mut terms, &manifest.name);
    if let Some(display_name) = &manifest.display_name {
        push_search_terms(&mut terms, display_name);
    }
    push_search_terms(&mut terms, &manifest.description);
    for intent in LoadedSkill::metadata_string_array(&manifest.metadata, "intents") {
        push_search_terms(&mut terms, &intent.replace('_', " "));
        push_search_terms(&mut terms, &intent.replace('_', "-"));
    }
    terms.sort();
    terms.dedup();
    terms
}

fn push_search_terms(out: &mut Vec<String>, text: &str) {
    let mut current = String::new();
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            current.extend(ch.to_lowercase());
        } else {
            push_search_term(out, &current);
            current.clear();
        }
    }
    push_search_term(out, &current);
}

fn push_search_term(out: &mut Vec<String>, term: &str) {
    const STOPWORDS: &[&str] = &[
        "and", "are", "for", "from", "how", "the", "this", "use", "user", "using", "when", "with",
        "you", "your", "什么", "使用", "用户", "需要", "触发",
    ];
    let term = term.trim();
    if term.len() < 3 || STOPWORDS.contains(&term) {
        return;
    }
    out.push(term.to_string());
}

/// Helper to check gating for a `GatingRequirements`. Useful for callers that
/// don't have the full skill loaded yet.
pub async fn check_gating(requirements: &GatingRequirements) -> crate::gating::GatingResult {
    gating::check_requirements(requirements).await
}

mod discovery;

#[cfg(test)]
mod tests;
