//! Mobile-facing skill management for the standalone SDK runtime.
//!
//! Public surface preserved through pub use below. Implementation split into:
//!
//! - [`limits`]: numeric limits, well-known names, and shared error helpers
//! - [`paths`]: filesystem paths, agent-id normalization, ZIP/skill safe paths
//! - [`afs`]: local filesystem `napaxi_skills::AfsAccessor` and registry factory
//! - [`types`]: public DTOs and internal payload/state types
//! - [`usage`]: usage record persistence and lifecycle JSON
//! - [`session`]: per-thread skill session state
//! - [`catalog`]: compact catalog construction + ClawHub catalog HTTP queries
//! - [`prompt`]: prompt assembly for active and explicit skills
//! - [`private_skill`]: private skill protocol gate (leak detection, gating)
//! - [`skill_load`]: hidden `skill_load` tool descriptor and runtime handler
//! - [`install`]: install paths (raw markdown, JSON bundle, ZIP, URL, ClawHub)
//! - [`lifecycle`]: list/get/pin/archive/restore + backup-with-rollback
//! - [`curator`]: stale → archive curator and evolution action dispatch

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod afs;
pub(crate) mod bundled;
mod catalog;
mod commands;
mod config;
mod curator;
mod install;
mod lifecycle;
mod limits;
mod paths;
mod private_skill;
mod prompt;
mod remediation;
mod secrets;
mod session;
mod skill_load;
mod snapshots;
mod source_registry;
mod status;
mod types;
mod usage;

#[cfg(test)]
mod tests;

// Tool name constant exposed at the module root for back-compat.
pub(crate) use limits::SKILL_LOAD_TOOL_NAME;

// Public DTOs.
pub use commands::{SkillCommand, SkillCommandReport, SkillCommandResolution, SkillCommandRun};
pub use remediation::{SkillRemediationRun, SkillRemediationRunList};
pub use secrets::{SkillSecretAvailability, SkillSecretRequirement, SkillSecretRequirementReport};
pub use snapshots::{SkillSnapshot, SkillSnapshotList};
pub use source_registry::{SkillRefreshResult, SkillSourceEntry, SkillSourceReport};
pub use status::{SkillRemediationAction, SkillStatusEntry, SkillStatusReport};
pub(crate) use types::{ActiveSkillPrompt, PrivateSkillContext};
pub use types::{ArchivedSkillRecord, CuratorRunSummary, SkillLifecycleState, SkillUsageRecord};

// Catalog (ClawHub) operations and prompt assembly.
pub use catalog::{get_catalog_skill, search_catalog};
pub use prompt::active_skill_prompt;
pub(crate) use prompt::{
    active_skill_prompt_with_metadata, active_skill_prompt_with_metadata_for_turn,
};

// Private skill protocol gate.
pub(crate) use private_skill::{
    private_skill_command_correction_message, private_skill_context_from_messages,
    private_skill_context_from_system_and_messages, private_skill_load_required_correction_message,
    should_correct_private_skill_command_leak, should_gate_visible_tools_for_skill_protocol,
    should_require_skill_load_for_matched_candidate,
};

// Hidden skill_load tool.
pub(crate) use skill_load::{is_hidden_skill_tool, skill_load_descriptor, skill_load_handler};

// Session continuation state cleanup.
pub(crate) use session::delete_skill_continuation_state;

// Install paths.
pub use install::{
    install_from_catalog, install_from_catalog_handle, install_from_url, install_from_zip_bytes,
    install_skill, install_skill_handle,
};

// Lifecycle operations.
pub use commands::{
    list_skill_commands, list_skill_commands_handle, resolve_skill_command,
    resolve_skill_command_handle, run_skill_command, run_skill_command_handle,
};
pub use config::{
    record_skill_requirement_resolution_handle, set_skill_enabled_handle,
    update_skill_config_handle,
};
pub use lifecycle::{
    archive_skill, archive_skill_handle, get_skill, get_skill_handle, list_skill_usage,
    list_skill_usage_handle, list_skills, list_skills_handle, pin_skill, pin_skill_handle,
    read_skill_support_file, read_skill_support_file_handle, reload_skills, reload_skills_handle,
    remove_skill, remove_skill_handle, restore_skill, restore_skill_handle,
};
pub use remediation::{
    list_skill_remediation_runs, list_skill_remediation_runs_handle, request_skill_remediation,
    request_skill_remediation_handle, update_skill_remediation_run,
    update_skill_remediation_run_handle,
};
pub use secrets::{
    list_skill_secret_requirements, list_skill_secret_requirements_handle,
    record_skill_secret_availability, record_skill_secret_availability_handle,
};
pub use snapshots::{
    get_skill_snapshot, get_skill_snapshot_handle, list_skill_snapshots,
    list_skill_snapshots_handle,
};
pub use source_registry::{
    list_skill_sources, list_skill_sources_handle, record_skill_source_changed,
    record_skill_source_changed_handle,
};
pub use status::{
    check_skills, check_skills_handle, get_skill_status, get_skill_status_handle,
    list_skill_remediation_actions, list_skill_remediation_actions_handle, list_skill_status,
    list_skill_status_handle,
};

// Curator and evolution dispatch.
pub use curator::{apply_evolution_action, run_skill_curator, run_skill_curator_handle};
