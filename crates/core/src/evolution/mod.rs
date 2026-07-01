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
mod tests {
    use super::*;
    use napaxi_evolution::{MemoryEntryType, PendingConfirmation, ReviewSource};

    fn config() -> PlatformLlmConfig {
        PlatformLlmConfig {
            provider: "openai".to_string(),
            api_key: "key".to_string(),
            base_url: None,
            model: "model".to_string(),
            system_prompt: "host".to_string(),
            max_tokens: 1000,
            max_tool_iterations: 0,
            extra_headers: None,
            allowed_models: None,
            image_model: None,
            image_analysis_model: None,
            capability_configs: None,
            scene_prompt_config: None,
            ..PlatformLlmConfig::default()
        }
    }

    fn noop_review_config() -> PlatformLlmConfig {
        PlatformLlmConfig {
            provider: "__test_noop__".to_string(),
            ..config()
        }
    }

    fn short_history() -> Vec<SessionMessage> {
        vec![
            SessionMessage {
                id: "1".to_string(),
                role: "user".to_string(),
                content: "hi".to_string(),
                created_at: Utc::now().to_rfc3339(),
                interrupted: false,
                turn_id: None,
            },
            SessionMessage {
                id: "2".to_string(),
                role: "assistant".to_string(),
                content: "hello".to_string(),
                created_at: Utc::now().to_rfc3339(),
                interrupted: false,
                turn_id: None,
            },
        ]
    }

    fn engine_handle(files_dir: &str) -> i64 {
        let config_json = serde_json::to_string(&config()).unwrap();
        let context_json = serde_json::json!({
            "platform": "test",
            "files_dir": files_dir,
            "native_library_dir": null,
        })
        .to_string();
        crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
    }

    #[test]
    fn memory_evolution_state_counts_until_interval() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let mut state = load_state(files_dir, "thread");
        assert_eq!(state.turns_since_memory, 0);
        state.turns_since_memory = 9;
        save_state(files_dir, "thread", &state).unwrap();
        assert_eq!(load_state(files_dir, "thread").turns_since_memory, 9);
    }

    #[test]
    fn in_flight_reviews_are_scoped_by_files_dir() {
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let first_dir = first.path().to_str().unwrap();
        let second_dir = second.path().to_str().unwrap();

        let first_key = try_mark_review_in_flight(first_dir, "agent", "thread", ReviewType::Memory)
            .expect("first review should be marked");
        let second_key =
            try_mark_review_in_flight(second_dir, "agent", "thread", ReviewType::Memory)
                .expect("matching review in another files dir should be allowed");
        assert_ne!(first_key, second_key);
        assert!(
            try_mark_review_in_flight(first_dir, "agent", "thread", ReviewType::Memory).is_none()
        );

        release_review_in_flight(&first_key);
        release_review_in_flight(&second_key);
    }

    #[tokio::test]
    async fn queues_memory_review_without_running_inline_and_guards_duplicates() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let history = short_history();
        let mut state = load_state(files_dir, "thread");
        state.turns_since_memory = DEFAULT_MEMORY_REVIEW_INTERVAL - 1;
        save_state(files_dir, "thread", &state).unwrap();

        let queued = queue_memory_review_after_turn(
            files_dir,
            files_dir,
            "napaxi",
            "thread",
            &noop_review_config(),
            &history,
        );

        let queued = queued.expect("memory review queued");
        assert_eq!(queued.review_type, "memory");
        assert_eq!(load_run_store(files_dir).len(), 1);
        assert_eq!(
            load_run_store(files_dir)[0].status,
            EvolutionRunStatus::Queued
        );
        assert_eq!(load_state(files_dir, "thread").turns_since_memory, 0);

        let mut state = load_state(files_dir, "thread");
        state.turns_since_memory = DEFAULT_MEMORY_REVIEW_INTERVAL - 1;
        save_state(files_dir, "thread", &state).unwrap();

        let duplicate = queue_memory_review_after_turn(
            files_dir,
            files_dir,
            "napaxi",
            "thread",
            &noop_review_config(),
            &history,
        );

        assert!(duplicate.is_none());
        assert_eq!(
            load_state(files_dir, "thread").turns_since_memory,
            DEFAULT_MEMORY_REVIEW_INTERVAL
        );

        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        let runs = load_run_store(files_dir);
        assert_eq!(runs[0].status, EvolutionRunStatus::Completed);
        assert_eq!(runs[0].suggestions_count, 0);
    }

    #[tokio::test]
    async fn queues_skill_review_without_running_inline_and_guards_duplicates() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let history = short_history();
        let mut state = load_state(files_dir, "thread");
        state.tool_calls_since_skill = DEFAULT_SKILL_REVIEW_INTERVAL - 1;
        save_state(files_dir, "thread", &state).unwrap();

        let queued = queue_skill_review_after_turn(
            files_dir,
            files_dir,
            "napaxi",
            "thread",
            &noop_review_config(),
            &history,
            1,
        );

        let queued = queued.expect("skill review queued");
        assert_eq!(queued.review_type, "skill");
        assert_eq!(load_run_store(files_dir).len(), 1);
        assert_eq!(
            load_run_store(files_dir)[0].status,
            EvolutionRunStatus::Queued
        );
        assert_eq!(load_state(files_dir, "thread").tool_calls_since_skill, 0);

        let mut state = load_state(files_dir, "thread");
        state.tool_calls_since_skill = DEFAULT_SKILL_REVIEW_INTERVAL - 1;
        save_state(files_dir, "thread", &state).unwrap();

        let duplicate = queue_skill_review_after_turn(
            files_dir,
            files_dir,
            "napaxi",
            "thread",
            &noop_review_config(),
            &history,
            1,
        );

        assert!(duplicate.is_none());
        assert_eq!(
            load_state(files_dir, "thread").tool_calls_since_skill,
            DEFAULT_SKILL_REVIEW_INTERVAL
        );

        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        let runs = load_run_store(files_dir);
        assert_eq!(runs[0].status, EvolutionRunStatus::Completed);
        assert_eq!(runs[0].pending_count, 0);
    }

    #[test]
    fn list_evolution_runs_filters_by_ids_and_handles_invalid_engine() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        upsert_run_record(
            files_dir,
            EvolutionRunRecord {
                id: "run-a".to_string(),
                agent_id: "napaxi".to_string(),
                thread_id: "thread".to_string(),
                review_type: "memory".to_string(),
                status: EvolutionRunStatus::Completed,
                queued_at: "2026-01-01T00:00:00Z".to_string(),
                started_at: None,
                completed_at: None,
                suggestions_count: 1,
                auto_applied_count: 1,
                pending_count: 0,
                error: None,
            },
        )
        .unwrap();
        upsert_run_record(
            files_dir,
            EvolutionRunRecord {
                id: "run-b".to_string(),
                agent_id: "napaxi".to_string(),
                thread_id: "thread".to_string(),
                review_type: "skill".to_string(),
                status: EvolutionRunStatus::Failed,
                queued_at: "2026-01-02T00:00:00Z".to_string(),
                started_at: None,
                completed_at: None,
                suggestions_count: 0,
                auto_applied_count: 0,
                pending_count: 0,
                error: Some("failed".to_string()),
            },
        )
        .unwrap();

        let filtered = list_evolution_runs(files_dir, r#"["run-a"]"#);
        let parsed: serde_json::Value = serde_json::from_str(&filtered).unwrap();
        assert_eq!(parsed.as_array().unwrap().len(), 1);
        assert_eq!(parsed[0]["id"], "run-a");
        assert_eq!(list_evolution_runs_handle(0, "[]"), "[]");
    }

    #[test]
    fn list_evolution_runs_marks_stale_running_records_failed() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        upsert_run_record(
            files_dir,
            EvolutionRunRecord {
                id: "stale-run".to_string(),
                agent_id: "napaxi".to_string(),
                thread_id: "thread".to_string(),
                review_type: "skill".to_string(),
                status: EvolutionRunStatus::Running,
                queued_at: (Utc::now() - Duration::minutes(RUN_STALE_AFTER_MINUTES + 5))
                    .to_rfc3339(),
                started_at: Some(
                    (Utc::now() - Duration::minutes(RUN_STALE_AFTER_MINUTES + 1)).to_rfc3339(),
                ),
                completed_at: None,
                suggestions_count: 0,
                auto_applied_count: 0,
                pending_count: 0,
                error: None,
            },
        )
        .unwrap();

        let json = list_evolution_runs(files_dir, "[]");
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed[0]["status"], "failed");
        assert_eq!(
            parsed[0]["error"],
            "evolution run expired before completion"
        );
    }

    #[tokio::test]
    async fn skill_evolution_state_counts_tool_calls_until_interval() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let history = vec![
            SessionMessage {
                id: "1".to_string(),
                role: "user".to_string(),
                content: "hi".to_string(),
                created_at: Utc::now().to_rfc3339(),
                interrupted: false,
                turn_id: None,
            },
            SessionMessage {
                id: "2".to_string(),
                role: "assistant".to_string(),
                content: "hello".to_string(),
                created_at: Utc::now().to_rfc3339(),
                interrupted: false,
                turn_id: None,
            },
        ];

        let result =
            maybe_review_skill_after_turn(files_dir, "napaxi", "thread", &config(), &history, 3)
                .await;
        assert!(result.is_none());
        assert_eq!(load_state(files_dir, "thread").tool_calls_since_skill, 3);
    }

    #[tokio::test]
    async fn handle_wrappers_delegate_to_pending_evolution_store() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let scoped =
            crate::workspace::default_scoped_files_dir(files_dir, crate::runtime::DEFAULT_AGENT_ID);
        let handle = engine_handle(files_dir);
        let confirmation = PendingConfirmation::new(
            PendingActionType::MemoryWrite {
                entry_type: MemoryEntryType::Environment,
                content: "Handle wrappers write memory".to_string(),
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Memory,
            },
            "Remember wrapper behavior".to_string(),
            "thread".to_string(),
        );
        let id = confirmation.id.to_string();
        persist_pending_confirmations(&scoped, "napaxi", &[confirmation]).unwrap();

        assert_eq!(list_pending_evolution_handle(0), "[]");
        assert!(reject_pending_evolution_handle(0, &id).contains("invalid engine handle"));
        assert!(list_pending_evolution_handle(handle).contains(&id));
        assert!(
            apply_pending_evolution_handle(handle, &id)
                .await
                .contains(r#""success":true"#)
        );
        let memory = crate::workspace::read_workspace_file_content(&scoped, "MEMORY.md")
            .unwrap()
            .unwrap();
        assert!(memory.contains("Handle wrappers write memory"));
        assert_eq!(list_pending_evolution_handle(handle), "[]");

        // SAFETY: `handle` is an engine handle owned by this call site and consumed exactly once here, satisfying `handle_consume`'s contract.
        let _ = unsafe { crate::runtime::handle_consume(handle) };
    }

    #[test]
    fn persists_and_rejects_pending_evolution() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let confirmation = PendingConfirmation::new(
            PendingActionType::MemoryWrite {
                entry_type: MemoryEntryType::UserProfile,
                content: "User likes concise updates".to_string(),
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Memory,
            },
            "Useful stable preference".to_string(),
            "thread".to_string(),
        );
        let id = confirmation.id.to_string();

        assert_eq!(
            persist_pending_confirmations(files_dir, "napaxi", &[confirmation]).unwrap(),
            1
        );
        assert!(list_pending_evolution(files_dir).contains(&id));
        assert!(reject_pending_evolution(files_dir, &id).contains("rejected"));
        assert_eq!(list_pending_evolution(files_dir), "[]");
    }

    #[test]
    fn reject_pending_evolution_is_idempotent_for_handled_items() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let confirmation = PendingConfirmation::new(
            PendingActionType::MemoryWrite {
                entry_type: MemoryEntryType::UserProfile,
                content: "User prefers ignored suggestions to disappear".to_string(),
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Memory,
            },
            "Dismiss stale suggestion".to_string(),
            "thread".to_string(),
        );
        let id = confirmation.id.to_string();
        persist_pending_confirmations(files_dir, "napaxi", &[confirmation]).unwrap();

        let first = reject_pending_evolution(files_dir, &id);
        assert!(first.contains(r#""success":true"#), "{first}");
        let second = reject_pending_evolution(files_dir, &id);
        assert!(second.contains(r#""success":true"#), "{second}");
        assert!(second.contains(r#""already_handled":true"#), "{second}");
        let missing = reject_pending_evolution(files_dir, "missing-pending-id");
        assert!(missing.contains(r#""success":true"#), "{missing}");
        assert!(missing.contains(r#""not_found""#), "{missing}");

        let mut expired = PendingConfirmation::new(
            PendingActionType::MemoryWrite {
                entry_type: MemoryEntryType::Project,
                content: "Expired suggestions can be ignored safely".to_string(),
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Memory,
            },
            "Dismiss expired suggestion".to_string(),
            "thread".to_string(),
        );
        expired.expires_at = Utc::now() - chrono::Duration::minutes(1);
        let expired_id = expired.id.to_string();
        persist_pending_confirmations(files_dir, "napaxi", &[expired]).unwrap();

        let expired_result = reject_pending_evolution(files_dir, &expired_id);
        assert!(
            expired_result.contains(r#""success":true"#),
            "{expired_result}"
        );
        assert!(expired_result.contains(r#""expired""#), "{expired_result}");
    }

    #[tokio::test]
    async fn apply_pending_evolution_is_idempotent_for_handled_items() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let confirmation = PendingConfirmation::new(
            PendingActionType::MemoryWrite {
                entry_type: MemoryEntryType::UserProfile,
                content: "User expects already-handled suggestions to refresh quietly".to_string(),
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Memory,
            },
            "Apply stale suggestion".to_string(),
            "thread".to_string(),
        );
        let id = confirmation.id.to_string();
        persist_pending_confirmations(files_dir, "napaxi", &[confirmation]).unwrap();

        let rejected = reject_pending_evolution(files_dir, &id);
        assert!(rejected.contains(r#""success":true"#), "{rejected}");
        let second_apply = apply_pending_evolution(files_dir, &id).await;
        assert!(second_apply.contains(r#""success":true"#), "{second_apply}");
        assert!(
            second_apply.contains(r#""already_handled":true"#),
            "{second_apply}"
        );

        let missing = apply_pending_evolution(files_dir, "missing-pending-id").await;
        assert!(missing.contains(r#""success":true"#), "{missing}");
        assert!(missing.contains(r#""not_found""#), "{missing}");
    }

    #[tokio::test]
    async fn applies_pending_memory_evolution() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let confirmation = PendingConfirmation::new(
            PendingActionType::MemoryWrite {
                entry_type: MemoryEntryType::Environment,
                content: "Project uses mobile workspace memory".to_string(),
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Memory,
            },
            "Remember project convention".to_string(),
            "thread".to_string(),
        );
        let id = confirmation.id.to_string();
        persist_pending_confirmations(files_dir, "napaxi", &[confirmation]).unwrap();

        let result = apply_pending_evolution(files_dir, &id).await;
        assert!(result.contains(r#""success":true"#));
        let memory = crate::workspace::read_workspace_file_content(files_dir, "MEMORY.md")
            .unwrap()
            .unwrap();
        assert!(memory.contains("Project uses mobile workspace memory"));
        assert_eq!(list_pending_evolution(files_dir), "[]");
        let diagnostics: serde_json::Value =
            serde_json::from_str(&list_evolution_diagnostics(files_dir)).unwrap();
        assert_eq!(diagnostics[0]["trigger_reason"], "apply_pending");
        assert_eq!(diagnostics[0]["review_type"], "memory");
        assert!(
            diagnostics[0]["apply_result"]
                .as_str()
                .unwrap()
                .contains("executed")
        );
    }

    #[tokio::test]
    async fn applies_pending_skill_evolution_create_and_patch() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let skill_content = r#"---
name: evolved-skill
version: 1.0.0
description: Evolved skill
activation:
  keywords: [evolve]
---

Use the old phrase.
"#;
        let mut confirmation = PendingConfirmation::new(
            PendingActionType::Create {
                skill_name: "evolved-skill".to_string(),
                content: skill_content.to_string(),
                category: None,
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "Create and refine skill".to_string(),
            "thread".to_string(),
        );
        confirmation.aggregated_actions = vec![
            confirmation.action.clone(),
            PendingActionType::Patch {
                skill_name: "evolved-skill".to_string(),
                old_string: "old phrase".to_string(),
                new_string: "new phrase".to_string(),
                file_path: None,
                replace_all: false,
            },
        ];
        let id = confirmation.id.to_string();
        persist_pending_confirmations(files_dir, "napaxi", &[confirmation]).unwrap();

        let result = apply_pending_evolution(files_dir, &id).await;
        assert!(result.contains(r#""success":true"#), "{result}");
        let skill = crate::skills::get_skill(files_dir, "napaxi", "evolved-skill").await;
        assert!(skill.contains("new phrase"));
        let diagnostics: serde_json::Value =
            serde_json::from_str(&list_evolution_diagnostics(files_dir)).unwrap();
        assert_eq!(diagnostics[0]["input_summary"]["action_count"], 2);
        assert_eq!(diagnostics[0]["review_type"], "skill");
    }

    #[tokio::test]
    async fn treats_pending_skill_partial_apply_as_handled() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let skill_content = r#"---
name: partially-evolved-skill
version: 1.0.0
description: Partially evolved skill
activation:
  keywords: [partial]
---

Use this skill.
"#;
        let mut confirmation = PendingConfirmation::new(
            PendingActionType::Create {
                skill_name: "partially-evolved-skill".to_string(),
                content: skill_content.to_string(),
                category: None,
            },
            ReviewSource {
                job_id: "job".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "Create skill and apply a follow-up edit".to_string(),
            "thread".to_string(),
        );
        confirmation.aggregated_actions = vec![
            confirmation.action.clone(),
            PendingActionType::Patch {
                skill_name: "partially-evolved-skill".to_string(),
                old_string: "text that does not exist".to_string(),
                new_string: "new text".to_string(),
                file_path: None,
                replace_all: false,
            },
        ];
        let id = confirmation.id.to_string();
        persist_pending_confirmations(files_dir, "napaxi", &[confirmation]).unwrap();

        let result = apply_pending_evolution(files_dir, &id).await;
        assert!(result.contains(r#""success":true"#), "{result}");
        assert!(result.contains(r#""partial":true"#), "{result}");
        assert_eq!(list_pending_evolution(files_dir), "[]");
        let skill = crate::skills::get_skill(files_dir, "napaxi", "partially-evolved-skill").await;
        assert!(skill.contains("partially-evolved-skill"));
        let diagnostics: serde_json::Value =
            serde_json::from_str(&list_evolution_diagnostics(files_dir)).unwrap();
        assert_eq!(diagnostics[0]["pending_count"], 0);
        assert_eq!(diagnostics[0]["auto_applied_count"], 1);
        assert!(
            diagnostics[0]["failure_reason"]
                .as_str()
                .is_some_and(|reason| !reason.trim().is_empty())
        );
    }

    #[test]
    fn evolution_config_can_be_cloned_for_review_handler() {
        assert_eq!(config().provider, "openai");
    }
}
