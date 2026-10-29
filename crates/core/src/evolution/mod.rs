//! Mobile memory evolution glue.
//!
//! This module adapts `napaxi-evolution` to the file-backed mobile runtime.

pub mod curator;
mod executor;
mod pending_api;
mod queue;
mod review;
mod skill_consolidation;
mod store;

#[cfg(test)]
use chrono::Duration;
use chrono::Utc;
use napaxi_evolution::{PendingActionType, ReviewType};
use serde::{Deserialize, Serialize};

use crate::session::SessionMessage;
use crate::types::PlatformLlmConfig;
pub use pending_api::{
    apply_pending_evolution_handle, list_evolution_diagnostics_handle, list_evolution_runs_handle,
    list_pending_evolution_handle, reject_pending_evolution_handle,
};
pub use queue::{queue_memory_review_after_turn, queue_skill_review_after_turn};
use review::{review_memory_now, review_skill_now};
pub use skill_consolidation::{
    SkillConsolidationReviewResult, run_skill_consolidation_review_handle,
};
use store::*;

#[cfg(test)]
use pending_api::{
    apply_pending_evolution, list_evolution_diagnostics, list_evolution_runs,
    list_pending_evolution, reject_pending_evolution,
};
#[cfg(test)]
use queue::{release_review_in_flight, try_mark_review_in_flight};

const EVOLUTION_DIR: &str = "napaxi/evolution";
const DEFAULT_MEMORY_REVIEW_INTERVAL: usize = 10;
const DEFAULT_SKILL_REVIEW_INTERVAL: usize = 15;

fn invalid_handle_json() -> String {
    r#"{"error":"invalid engine handle"}"#.to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct EvolutionState {
    turns_since_memory: usize,
    tool_calls_since_skill: usize,
    last_memory_review_at: Option<String>,
    last_skill_review_at: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct EvolutionRun {
    pub reviewed: bool,
    pub suggestions_count: usize,
    pub auto_applied_count: usize,
    pub pending_count: usize,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvolutionRunStatus {
    Queued,
    Running,
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionRunRecord {
    pub id: String,
    pub agent_id: String,
    pub thread_id: String,
    pub review_type: String,
    pub status: EvolutionRunStatus,
    pub queued_at: String,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub suggestions_count: usize,
    pub auto_applied_count: usize,
    pub pending_count: usize,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionDiagnosticRecord {
    pub id: String,
    pub created_at: String,
    pub agent_id: String,
    pub thread_id: String,
    pub review_type: String,
    pub trigger_reason: String,
    pub input_summary: serde_json::Value,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub tool_calls: Vec<String>,
    pub suggestions_count: usize,
    pub pending_count: usize,
    pub auto_applied_count: usize,
    pub apply_result: Option<String>,
    pub failure_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueuedEvolutionRun {
    pub id: String,
    pub review_type: String,
}

fn review_type_name(review_type: ReviewType) -> &'static str {
    match review_type {
        ReviewType::Memory => "memory",
        ReviewType::Skill => "skill",
        ReviewType::Combined => "combined",
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PendingStatus {
    Pending,
    Rejected,
    Expired,
    Executed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingEvolution {
    pub id: String,
    pub agent_id: String,
    pub thread_id: String,
    pub created_at: String,
    pub expires_at: String,
    pub review_type: ReviewType,
    pub action_type: String,
    pub action: PendingActionType,
    #[serde(default)]
    pub aggregated_actions: Vec<PendingActionType>,
    pub reasoning: String,
    pub status: PendingStatus,
}

#[allow(dead_code)]
pub async fn maybe_review_memory_after_turn(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> Option<EvolutionRun> {
    if history.len() < 2 || config.api_key.trim().is_empty() || config.model.trim().is_empty() {
        return None;
    }

    let mut state = load_state(files_dir, thread_id);
    state.turns_since_memory += 1;
    if state.turns_since_memory < DEFAULT_MEMORY_REVIEW_INTERVAL {
        let _ = save_state(files_dir, thread_id, &state);
        return None;
    }

    state.turns_since_memory = 0;
    state.last_memory_review_at = Some(Utc::now().to_rfc3339());
    let _ = save_state(files_dir, thread_id, &state);

    Some(review_memory_now(files_dir, agent_id, thread_id, config, history).await)
}

pub(crate) async fn review_memory_before_compaction(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> EvolutionRun {
    review_memory_now(files_dir, agent_id, thread_id, config, history).await
}

#[allow(dead_code)]
pub async fn maybe_review_skill_after_turn(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
    tool_call_count: usize,
) -> Option<EvolutionRun> {
    if tool_call_count == 0
        || history.len() < 2
        || config.api_key.trim().is_empty()
        || config.model.trim().is_empty()
    {
        return None;
    }

    let mut state = load_state(files_dir, thread_id);
    state.tool_calls_since_skill = state.tool_calls_since_skill.saturating_add(tool_call_count);
    if state.tool_calls_since_skill < DEFAULT_SKILL_REVIEW_INTERVAL {
        let _ = save_state(files_dir, thread_id, &state);
        return None;
    }

    state.tool_calls_since_skill = 0;
    state.last_skill_review_at = Some(Utc::now().to_rfc3339());
    let _ = save_state(files_dir, thread_id, &state);

    Some(
        review_skill_now(
            files_dir,
            agent_id,
            thread_id,
            config,
            history,
            tool_call_count,
        )
        .await,
    )
}

#[cfg(test)]
mod tests;
