//! Public DTOs and internal payload/state types for skill management.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::types::ActivatedSkillInfo;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum SkillLifecycleState {
    #[default]
    Active,
    Stale,
    Archived,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillUsageRecord {
    pub skill_name: String,
    pub created_by: Option<String>,
    pub created_at: Option<String>,
    #[serde(default)]
    pub use_count: u64,
    #[serde(default)]
    pub view_count: u64,
    #[serde(default)]
    pub patch_count: u64,
    pub last_used_at: Option<String>,
    pub last_viewed_at: Option<String>,
    pub last_patched_at: Option<String>,
    #[serde(default)]
    pub state: SkillLifecycleState,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub protected: bool,
    pub archived_at: Option<String>,
    pub absorbed_into: Option<String>,
}

impl SkillUsageRecord {
    pub(super) fn new(skill_name: &str) -> Self {
        Self {
            skill_name: skill_name.to_string(),
            created_by: None,
            created_at: None,
            use_count: 0,
            view_count: 0,
            patch_count: 0,
            last_used_at: None,
            last_viewed_at: None,
            last_patched_at: None,
            state: SkillLifecycleState::Active,
            pinned: false,
            protected: false,
            archived_at: None,
            absorbed_into: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArchivedSkillRecord {
    pub skill_name: String,
    pub archived_at: String,
    pub archive_path: String,
    pub original_path: String,
    pub absorbed_into: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CuratorRunSummary {
    pub dry_run: bool,
    pub checked: usize,
    pub marked_stale: usize,
    pub archived: usize,
    pub restored_active: usize,
    #[serde(default)]
    pub protected_skipped: usize,
    pub actions: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct ActiveSkillPrompt {
    pub(crate) prompt: String,
    pub(crate) skills: Vec<ActivatedSkillInfo>,
    pub(crate) catalog_prompt: String,
    pub(crate) catalog_skill_names: Vec<String>,
    pub(crate) catalog_skill_hashes: HashMap<String, String>,
    pub(crate) snapshot_id: Option<String>,
}

#[derive(Debug)]
pub(super) struct SkillPackage {
    pub(super) skill_md: String,
    pub(super) extra_files: Vec<(String, Vec<u8>)>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub(super) enum SkillInstallPayload {
    Raw(String),
    Bundle(SkillInstallBundlePayload),
}

#[derive(Debug, Deserialize)]
pub(super) struct SkillInstallBundlePayload {
    pub(super) skill_md: String,
    #[serde(default)]
    pub(super) extra_files: Vec<SkillInstallExtraFilePayload>,
}

#[derive(Debug, Deserialize)]
pub(super) struct SkillInstallExtraFilePayload {
    pub(super) path: String,
    #[serde(default)]
    pub(super) content_base64: String,
}

#[derive(Debug, Clone)]
pub(super) struct SkillCatalogEntry {
    pub(super) name: String,
    pub(super) version: String,
    pub(super) description: String,
    pub(super) trust: String,
    pub(super) activation_hint: &'static str,
    pub(super) content_hash: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(super) struct SkillSessionState {
    #[serde(default)]
    pub(super) agents: HashMap<String, SkillSessionAgentState>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(super) struct SkillSessionAgentState {
    #[serde(default)]
    pub(super) active_skills: Vec<SkillSessionActiveSkill>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct SkillSessionActiveSkill {
    pub(super) name: String,
    pub(super) version: String,
    pub(super) description: String,
    pub(super) trust: String,
    pub(super) loaded_at: String,
    #[serde(default = "default_skill_session_remaining_turns")]
    pub(super) remaining_turns: u8,
}

fn default_skill_session_remaining_turns() -> u8 {
    super::limits::SKILL_SESSION_ACTIVE_TURNS
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct PrivateSkillContext {
    pub(crate) has_loaded_skill: bool,
    pub(super) has_available_skill_catalog: bool,
    pub(super) has_matched_skill_candidate: bool,
    pub(super) has_active_conversation_skill: bool,
    pub(super) matched_skill_names: Vec<String>,
    pub(super) last_user_requested_code_or_command: bool,
    pub(super) last_user_disabled_skill_protocol: bool,
    pub(super) command_signatures: Vec<String>,
}

impl PrivateSkillContext {
    pub(super) fn push_signature(&mut self, signature: String) {
        if signature.len() < 3
            || self.command_signatures.len() >= super::limits::MAX_PRIVATE_SKILL_COMMAND_SIGNATURES
        {
            return;
        }
        let normalized = signature.to_lowercase();
        if !self
            .command_signatures
            .iter()
            .any(|existing| existing == &normalized)
        {
            self.command_signatures.push(normalized);
        }
    }
}

pub(super) struct SkillBackup {
    pub(super) backup_path: std::path::PathBuf,
    pub(super) original_path: std::path::PathBuf,
    pub(super) shadow_path: Option<std::path::PathBuf>,
}
