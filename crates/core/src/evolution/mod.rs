//! Mobile memory evolution glue.
//!
//! This module adapts `napaxi-evolution` to the file-backed mobile runtime.
//!
//! # Monotonic clock domain audit (AC-3, DIMA-2026110600120401874)
//!
//! Audit conclusion from a full-repo `Utc::now()` sweep at sites where the
//! call lands in an elapsed / remaining / recovery decision (vs. a purely
//! display / persistence field). The lattice is:
//! - **In-process elapsed/remaining/recovery** — MUST use
//!   `std::time::Instant::now()` + `Instant::elapsed()`. Wall-clock can
//!   jump backwards under host NTP / user-set-time, leaking a stale
//!   recovery / no-retry window.
//! - **Cross-process persisted fields** — MUST stay on
//!   `chrono::Utc::now()` (RFC3339). `Instant` is process-local and
//!   cannot round-trip through disk.
//!
//! ## Already on monotonic (no change)
//! - `crates/core/src/evolution/store.rs::refresh_stale_runs` —
//!   `peek_monotonic_anchor(run_id)` + `Instant::elapsed()` (with a
//!   wall-clock fallback when the anchor is missing after a restart).
//!   `record_monotonic_anchor` / `take_monotonic_anchor` live in
//!   `store.rs:34 / 42`; `queue.rs::create_queued_run_record` /
//!   `mark_run_started` record anchors at the run lifecycle points.
//! - `crates/core/src/mcp/oauth.rs::oauth_token_needs_refresh` and
//!   surrounding helpers — kept on `chrono::Utc::now()` BY DESIGN (the
//!   OAuth tokens cross process boundaries via RFC3339). The module
//!   documents the policy at the top of `mcp/oauth.rs`.
//!
//! ## Fixed in this round (AC-3)
//! - `crates/core/src/mcp/tools.rs::should_retry_lazy_load` elapsed
//!   decision — switched from `Utc::now().signed_duration_since(parsed)`
//!   to a process-local `monotonic_lazy_attempt_anchors` map (keyed by
//!   `"<user_id>::<server_name>"`), with the persisted
//!   `last_tools_attempt_at` RFC3339 kept on disk for the cross-process
//!   fallback. Functionally identical to the evolution/queue precedent.
//!
//! ## Remaining wall-clock sites — RECORDED regression baseline (TODO
//! #193070)
//! The sites below stay on `chrono::Utc::now()` because their values
//! cross process boundaries (persisted as RFC3339). They are listed here
//! as the regression baseline so a future change can quickly tell
//! "wall-clock eligible" from "needs monotonic" sites.
//! - `crates/core/src/a2a/local.rs:804`, `a2a/mod.rs:342 / 696` — A2A
//!   `expires_at` RFC3339 windows, cross-process by design.
//! - `crates/core/src/agents/agent_app/mod.rs:906 / 912` — agent app
//!   action expiry persisted as RFC3339.
//! - `crates/core/src/channel/*` — channel routing emits / persists
//!   timestamps used by display + cross-process recovery; the in-process
//!   waiting paths there use `Instant::elapsed()` already (see
//!   `channel_agent/state.rs`).
//! - `crates/core/src/agent_runtime/runs.rs:432`,
//!   `automation/mod.rs:34`, `automation/runner.rs:545`,
//!   `context/compaction.rs:11 / 805`, `context/resolver.rs:126`,
//!   `evolution/executor.rs:222 / 265` — all timestamp record / display
//!   fields (RFC3339). No elapsed/remaining/recovery decision is taken
//!   from these clocks: they are persisted surface values.
//! - `crates/core/src/turn/orchestration/*.rs::record_last_prompt_snapshot`
//!   — persists `updated_at` RFC3339; the elapsed-policy reason for a
//!   snapshot lives in `display::provider_snapshot_is_current`, which
//!   already runs off `chrono::Duration` against persisted timestamps
//!   (cross-process by design).
//!
//! When a new elapsed/recovery timer is added to any of the above (or a
//! new module), it MUST join the monotonic anchor family — `Utc::now()`
//! is only valid for the persistence / display side of that field.
//!
//! ## Re-confirmation cycle (DIMA #2026111000120512225)
//! This audit cycle re-confirmed no new wall-clock process-local
//! elapsed/recovery sites have been introduced: the lattice above still
//! holds, OpenClaw #196093 same-class fix (memory-search failure pause
//! written/read on `performance.now()`) is already closed in Napaxi via
//! the `mcp/tools.rs` + `evolution/store.rs` monotonic anchor families.
//! Regression tests were added pinning the elapsed-based decision under
//! an in-process anchor against wall-clock jumps:
//! `crates/core/src/mcp/tools.rs::monotonic_anchor_tests` and
//! `crates/core/src/evolution/tests.rs::refresh_stale_runs_decision_is_elapsed_based_independent_of_wall_clock`.

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
