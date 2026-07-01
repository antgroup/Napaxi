//! Napaxi evolution feature crate — agent self-improvement subsystem.
//!
//! Owns the review job, suggestion aggregation, pending-action queue, and the
//! agent-facing tools that let the runtime propose and confirm skill and memory
//! updates. Consumed by `napaxi-core` through its public API; it does not depend
//! on core.

// Non-test paths in this crate are `.unwrap()`-free. Lock that in at the crate
// level so a future regression surfaces as a clippy warning instead of a panic
// in a host app (mobile builds use `panic = "abort"`). Mirrors `napaxi-core`.
// Test code is exempt — fixtures and assertions read fine with `.unwrap()`.
#![cfg_attr(not(test), warn(clippy::unwrap_used))]

pub mod config;
pub mod counter;
pub mod error;
pub mod fuzzy;
pub mod hook;
pub mod io;
pub mod job;
pub mod queue;
pub mod rollback;
pub mod tools;
pub mod traits;
pub mod types;

pub use config::{EvolutionConfig, EvolutionStatus, SecurityPolicy};
pub use counter::{
    AtomicNudgeCounter, CounterStorage, InMemoryMetadata, InMemoryStorage, NudgeState,
    ThreadMetadataAccessor, ThreadMetadataStorage,
};
pub use error::{EvolutionError, EvolutionResult};
pub use fuzzy::{fuzzy_find_and_replace, FuzzyMatcher, MatchError};
pub use hook::{
    create_hook, create_hook_with_all, create_hook_with_storage, create_review_job, EvolutionHook,
};
pub use io::{atomic_copy_dir, atomic_write_text};
pub use job::llm_integration; // napaxi LlmProvider integration module
pub use job::{DefaultLlmHandler, LlmReviewHandler, ReviewResult}; // LLM integration interface
pub use job::{EvolutionReviewInput, EvolutionReviewJob, EvolutionReviewOutput};
pub use queue::{ConfirmationStatus, PendingConfirmation, PendingQueue, UserPendingQueue};
pub use rollback::RollbackManager;
#[cfg(feature = "registry")]
pub use tools::ActionExecutor;
pub use tools::{
    ReviewMemoryInput, ReviewMemoryTool, ReviewSkillInput, ReviewSkillTool, SkillListInput,
    SkillListTool,
};
pub use traits::{
    AnyJob, DefaultJobQueue, Hook, HookContext, HookRegistry, Job, JobContext, JobError, JobQueue,
    JobScheduleError, Message, Role, Tool, ToolCall, ToolError, ToolRegistry, ToolSchema,
};
pub use types::MessageSnapshot;
pub use types::{
    ActionResult, BackupVersion, MemoryEntryType, NudgeType, PendingActionType, ReviewSource,
    ReviewType, RollbackResult, ScanSummary, SkillAction,
};

/// Validate skill name: starts with alphanumeric, allows alphanumeric/dot/hyphen/underscore, 1-64 characters.
// NOTE: This function duplicates logic from napaxi_skills::validation::validate_skill_name.
// It can be extracted to a shared validation module later to avoid continued divergence.
static SKILL_NAME_PATTERN: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
    regex::Regex::new(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$").expect("hardcoded literal regex")
});

pub fn validate_skill_name(name: &str) -> bool {
    SKILL_NAME_PATTERN.is_match(name)
}

/// Constants
pub const DEFAULT_MEMORY_NUDGE_INTERVAL: usize = 10;
pub const DEFAULT_SKILL_NUDGE_INTERVAL: usize = 10;
pub const DEFAULT_REVIEW_TIMEOUT_SECS: u64 = 60;
pub const DEFAULT_MAX_BACKUP_VERSIONS: usize = 5;
pub const DEFAULT_MIN_COMPLEXITY: usize = 5;
pub const CONFIRMATION_TIMEOUT_MINUTES: i64 = 30;
pub const MAX_SKILL_SIZE_KB: usize = 100;

/// Get skills base directory (using multi-user structure)
/// default user: ~/.napaxi/users/default/skills/
/// other users: ~/.napaxi/users/{user_id}/skills/
pub fn get_skills_base_dir() -> std::path::PathBuf {
    dirs::home_dir()
        .expect("Failed to get home dir")
        .join(".napaxi")
        .join("users")
        .join("default")
        .join("skills")
}

/// Get skills directory for a specified user
/// Uses unified users/{user_id}/skills/ structure
pub fn get_user_skills_dir(user_id: &str) -> std::path::PathBuf {
    let user = if user_id.is_empty() {
        "default"
    } else {
        user_id
    };
    dirs::home_dir()
        .expect("Failed to get home dir")
        .join(".napaxi")
        .join("users")
        .join(user)
        .join("skills")
}

/// Get backup directory (using multi-user structure)
pub fn get_backup_dir() -> std::path::PathBuf {
    dirs::home_dir()
        .expect("Failed to get home dir")
        .join(".napaxi")
        .join("users")
        .join("default")
        .join("backups")
}

/// Get backup directory for a specified user
pub fn get_user_backup_dir(user_id: &str) -> std::path::PathBuf {
    let user = if user_id.is_empty() {
        "default"
    } else {
        user_id
    };
    dirs::home_dir()
        .expect("Failed to get home dir")
        .join(".napaxi")
        .join("users")
        .join(user)
        .join("backups")
}

/// Get memory directory for a specified user
/// Uses unified users/{user_id}/workspace/ structure (workspace-compatible)
pub fn get_user_memory_dir(user_id: &str) -> std::path::PathBuf {
    let user = if user_id.is_empty() {
        "default"
    } else {
        user_id
    };
    dirs::home_dir()
        .expect("Failed to get home dir")
        .join(".napaxi")
        .join("users")
        .join(user)
        .join("workspace")
}

// NOTE: The Hook trait is defined in the main flow's tecle crate
// EvolutionHook depends on that trait for its implementation

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_library_exports() {
        // Verify all major types are accessible
        let _ = EvolutionConfig::default();
        let _ = EvolutionStatus::Enabled;
        let _ = ConfirmationStatus::Pending;
        let _ = NudgeState::default();
    }
}