use chrono::{DateTime, Utc};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

/// Learning loop trigger type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum NudgeType {
    /// Review memory (every _memory_nudge_interval conversation turns)
    MemoryReview,
    /// Review skills (every _skill_nudge_interval tool calls)
    SkillReview,
}

impl NudgeType {
    /// Get the corresponding Review type
    pub fn to_review_type(&self) -> ReviewType {
        match self {
            NudgeType::MemoryReview => ReviewType::Memory,
            NudgeType::SkillReview => ReviewType::Skill,
        }
    }

    /// Get the system prompt file path
    pub fn prompt_file(&self) -> &'static str {
        match self {
            NudgeType::MemoryReview => "memory_review.md",
            NudgeType::SkillReview => "skill_review.md",
        }
    }
}

/// Background review target type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ReviewType {
    Memory,
    Skill,
    Combined,
}

impl ReviewType {
    /// Get the system prompt file path
    pub fn prompt_file(&self) -> &'static str {
        match self {
            ReviewType::Memory => "memory_review.md",
            ReviewType::Skill => "skill_review.md",
            ReviewType::Combined => "combined_review.md",
        }
    }
}

/// Skill management action
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SkillAction {
    /// Create new Skill (SKILL.md + directory structure)
    Create,
    /// Replace SKILL.md content (full rewrite)
    Edit,
    /// Targeted find-and-replace (SKILL.md or support files)
    Patch,
    /// Delete entire Skill
    Delete,
    /// Add/overwrite support file (references/templates/scripts/assets)
    WriteFile,
    /// Delete support file
    RemoveFile,
}

impl SkillAction {
    /// Whether security scan is required
    pub fn requires_security_scan(&self) -> bool {
        matches!(
            self,
            SkillAction::Create | SkillAction::Edit | SkillAction::Patch
        )
    }

    /// Whether user confirmation is required
    pub fn requires_user_confirmation(&self) -> bool {
        // All modification actions require confirmation
        matches!(
            self,
            SkillAction::Create
                | SkillAction::Edit
                | SkillAction::Patch
                | SkillAction::Delete
                | SkillAction::WriteFile
                | SkillAction::RemoveFile
        )
    }
}

/// Memory entry type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum MemoryEntryType {
    /// Environment facts (MEMORY.md)
    Environment,
    /// User profile (USER.md)
    UserProfile,
    /// Project conventions
    Project,
}

/// Suggested confidence level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum ConfidenceLevel {
    /// High confidence: user explicitly stated, can be executed directly
    High,
    /// Medium confidence: fairly clear, suggest user confirmation
    #[default]
    Medium,
    /// Low confidence: possibly relevant, wait for more evidence to accumulate
    Low,
}

impl ConfidenceLevel {
    /// Whether it can be executed directly (requires auto_apply config enabled)
    pub fn can_auto_apply(&self) -> bool {
        matches!(self, ConfidenceLevel::High)
    }

    /// Whether user confirmation is required
    pub fn needs_confirmation(&self) -> bool {
        !matches!(self, ConfidenceLevel::High)
    }
}

/// Suggestion with confidence level
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestedAction {
    /// Suggested action
    pub action: PendingActionType,
    /// Confidence level
    pub confidence: ConfidenceLevel,
    /// Reasoning
    pub reasoning: String,
    /// Source message indices (for traceability)
    pub source_indices: Vec<usize>,
}

/// Aggregated suggestion group
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatedSuggestion {
    /// List of suggested actions
    pub actions: Vec<PendingActionType>,
    /// Aggregated confidence level (takes the highest)
    pub confidence: ConfidenceLevel,
    /// Aggregation reasoning
    pub reasoning: String,
    /// Source messages
    pub sources: Vec<MessageSnapshot>,
}

/// Pending action type awaiting user confirmation
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type", content = "params")]
pub enum PendingActionType {
    /// Create new Skill
    Create {
        skill_name: String,
        content: String,
        category: Option<String>,
    },
    /// Replace SKILL.md (full rewrite)
    Edit {
        skill_name: String,
        new_content: String,
    },
    /// Targeted patch
    Patch {
        skill_name: String,
        old_string: String,
        new_string: String,
        file_path: Option<String>,
        replace_all: bool,
    },
    /// Delete/archive Skill
    Delete {
        skill_name: String,
        #[serde(default)]
        absorbed_into: Option<String>,
    },
    /// Write support file
    WriteFile {
        skill_name: String,
        file_path: String,
        file_content: String,
    },
    /// Delete support file
    RemoveFile {
        skill_name: String,
        file_path: String,
    },
    /// Write memory
    MemoryWrite {
        entry_type: MemoryEntryType,
        content: String,
    },
}

impl PendingActionType {
    /// Get the associated skill name (if any)
    pub fn skill_name(&self) -> Option<&str> {
        match self {
            PendingActionType::Create { skill_name, .. } => Some(skill_name),
            PendingActionType::Edit { skill_name, .. } => Some(skill_name),
            PendingActionType::Patch { skill_name, .. } => Some(skill_name),
            PendingActionType::Delete { skill_name, .. } => Some(skill_name),
            PendingActionType::WriteFile { skill_name, .. } => Some(skill_name),
            PendingActionType::RemoveFile { skill_name, .. } => Some(skill_name),
            PendingActionType::MemoryWrite { .. } => None,
        }
    }

    /// Get action type name (for logging)
    pub fn action_type_name(&self) -> &'static str {
        match self {
            PendingActionType::Create { .. } => "SkillCreate",
            PendingActionType::Edit { .. } => "SkillEdit",
            PendingActionType::Patch { .. } => "SkillPatch",
            PendingActionType::Delete { .. } => "SkillDelete",
            PendingActionType::WriteFile { .. } => "SkillWriteFile",
            PendingActionType::RemoveFile { .. } => "SkillRemoveFile",
            PendingActionType::MemoryWrite { .. } => "MemoryWrite",
        }
    }

    /// Whether backup is required
    pub fn requires_backup(&self) -> bool {
        matches!(
            self,
            PendingActionType::Edit { .. }
                | PendingActionType::Patch { .. }
                | PendingActionType::Delete { .. }
        )
    }
}

/// Message snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageSnapshot {
    pub role: String,
    pub content: String,
    pub timestamp: Option<DateTime<Utc>>,
}

/// Backup version info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupVersion {
    /// Backup ID
    pub id: Uuid,
    /// Original Skill name
    pub skill_name: String,
    /// Backup time
    pub created_at: DateTime<Utc>,
    /// Operation type (reason for creating backup)
    pub operation: String,
    /// Backup path (absolute path)
    pub backup_path: PathBuf,
    /// Original path
    pub original_path: PathBuf,
    /// File hash (for integrity verification)
    pub content_hash: String,
}

/// Rollback result
#[derive(Debug, Clone)]
pub struct RollbackResult {
    pub success: bool,
    pub rolled_back_to: BackupVersion,
    pub message: String,
}

/// Action execution result
#[derive(Debug, Clone)]
pub struct ActionResult {
    pub success: bool,
    pub executed: bool,
    pub message: String,
}

/// Scan summary
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanSummary {
    pub risk_score: u8,
    pub risk_level: String,
    pub findings_count: usize,
    pub passed: bool,
    pub details: Option<String>,
}

/// Review source info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewSource {
    /// Job ID
    pub job_id: String,
    /// Trigger time
    pub triggered_at: DateTime<Utc>,
    /// Review type
    pub review_type: ReviewType,
}

/// Constants
pub const MAX_NAME_LENGTH: usize = 64;
pub const MAX_DESCRIPTION_LENGTH: usize = 1024;
pub const ALLOWED_SUBDIRS: &[&str] = &["references", "templates", "scripts", "assets"];
pub const SKILL_FILE_NAME: &str = "SKILL.md";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_nudge_type_to_review_type() {
        assert_eq!(NudgeType::MemoryReview.to_review_type(), ReviewType::Memory);
        assert_eq!(NudgeType::SkillReview.to_review_type(), ReviewType::Skill);
    }

    #[test]
    fn test_nudge_type_prompt_file() {
        assert_eq!(NudgeType::MemoryReview.prompt_file(), "memory_review.md");
        assert_eq!(NudgeType::SkillReview.prompt_file(), "skill_review.md");
    }

    #[test]
    fn test_review_type_prompt_file() {
        assert_eq!(ReviewType::Memory.prompt_file(), "memory_review.md");
        assert_eq!(ReviewType::Skill.prompt_file(), "skill_review.md");
        assert_eq!(ReviewType::Combined.prompt_file(), "combined_review.md");
    }

    #[test]
    fn test_skill_action_requires_security_scan() {
        assert!(SkillAction::Create.requires_security_scan());
        assert!(SkillAction::Edit.requires_security_scan());
        assert!(SkillAction::Patch.requires_security_scan());
        assert!(!SkillAction::Delete.requires_security_scan());
        assert!(!SkillAction::WriteFile.requires_security_scan());
        assert!(!SkillAction::RemoveFile.requires_security_scan());
    }

    #[test]
    fn test_skill_action_requires_user_confirmation() {
        // All modification actions require confirmation
        assert!(SkillAction::Create.requires_user_confirmation());
        assert!(SkillAction::Edit.requires_user_confirmation());
        assert!(SkillAction::Patch.requires_user_confirmation());
        assert!(SkillAction::Delete.requires_user_confirmation());
        assert!(SkillAction::WriteFile.requires_user_confirmation());
        assert!(SkillAction::RemoveFile.requires_user_confirmation());
    }

    #[test]
    fn test_pending_action_type_skill_name() {
        let create = PendingActionType::Create {
            skill_name: "test".to_string(),
            content: "content".to_string(),
            category: None,
        };
        assert_eq!(create.skill_name(), Some("test"));

        let memory = PendingActionType::MemoryWrite {
            entry_type: MemoryEntryType::Environment,
            content: "content".to_string(),
        };
        assert_eq!(memory.skill_name(), None);
    }

    #[test]
    fn test_pending_action_type_requires_backup() {
        assert!(PendingActionType::Edit {
            skill_name: "test".to_string(),
            new_content: "content".to_string(),
        }
        .requires_backup());

        assert!(PendingActionType::Patch {
            skill_name: "test".to_string(),
            old_string: "old".to_string(),
            new_string: "new".to_string(),
            file_path: None,
            replace_all: false,
        }
        .requires_backup());

        assert!(PendingActionType::Delete {
            skill_name: "test".to_string(),
            absorbed_into: None,
        }
        .requires_backup());

        assert!(!PendingActionType::Create {
            skill_name: "test".to_string(),
            content: "content".to_string(),
            category: None,
        }
        .requires_backup());
    }

    #[test]
    fn test_constants() {
        assert_eq!(MAX_NAME_LENGTH, 64);
        assert_eq!(MAX_DESCRIPTION_LENGTH, 1024);
        assert_eq!(
            ALLOWED_SUBDIRS,
            &["references", "templates", "scripts", "assets"]
        );
        assert_eq!(SKILL_FILE_NAME, "SKILL.md");
    }
}