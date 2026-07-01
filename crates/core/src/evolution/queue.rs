use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

use chrono::Utc;
use napaxi_evolution::ReviewType;

use crate::session::SessionMessage;
use crate::types::PlatformLlmConfig;

use super::review::{log_background_review_result, review_memory_now, review_skill_now};
use super::store::{load_state, save_state, update_run_record, upsert_run_record};
use super::{
    DEFAULT_MEMORY_REVIEW_INTERVAL, DEFAULT_SKILL_REVIEW_INTERVAL, EvolutionRun,
    EvolutionRunRecord, EvolutionRunStatus, QueuedEvolutionRun, review_type_name,
};

fn in_flight_reviews() -> &'static Mutex<HashSet<String>> {
    static IN_FLIGHT: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    IN_FLIGHT.get_or_init(|| Mutex::new(HashSet::new()))
}

fn review_in_flight_key(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    review_type: ReviewType,
) -> String {
    format!(
        "{}\x1f{}\x1f{}\x1f{}",
        files_dir,
        agent_id,
        thread_id,
        review_type_name(review_type)
    )
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn try_mark_review_in_flight(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    review_type: ReviewType,
) -> Option<String> {
    let key = review_in_flight_key(files_dir, agent_id, thread_id, review_type);
    let mut reviews = in_flight_reviews().lock().ok()?;
    if reviews.insert(key.clone()) {
        Some(key)
    } else {
        None
    }
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn release_review_in_flight(key: &str) {
    if let Ok(mut reviews) = in_flight_reviews().lock() {
        reviews.remove(key);
    }
}

pub fn queue_memory_review_after_turn(
    run_files_dir: &str,
    review_files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> Option<QueuedEvolutionRun> {
    if history.len() < 2 || config.api_key.trim().is_empty() || config.model.trim().is_empty() {
        return None;
    }

    let mut state = load_state(review_files_dir, thread_id);
    state.turns_since_memory += 1;
    if state.turns_since_memory < DEFAULT_MEMORY_REVIEW_INTERVAL {
        let _ = save_state(review_files_dir, thread_id, &state);
        return None;
    }

    let Some(guard_key) =
        try_mark_review_in_flight(review_files_dir, agent_id, thread_id, ReviewType::Memory)
    else {
        let _ = save_state(review_files_dir, thread_id, &state);
        return None;
    };

    state.turns_since_memory = 0;
    state.last_memory_review_at = Some(Utc::now().to_rfc3339());
    let _ = save_state(review_files_dir, thread_id, &state);

    let queued = create_queued_run_record(run_files_dir, agent_id, thread_id, ReviewType::Memory);

    spawn_memory_review(
        run_files_dir.to_string(),
        review_files_dir.to_string(),
        agent_id.to_string(),
        thread_id.to_string(),
        config.clone(),
        history.to_vec(),
        guard_key,
        queued.id.clone(),
    );

    Some(queued)
}

pub fn queue_skill_review_after_turn(
    run_files_dir: &str,
    review_files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
    tool_call_count: usize,
) -> Option<QueuedEvolutionRun> {
    if tool_call_count == 0
        || history.len() < 2
        || config.api_key.trim().is_empty()
        || config.model.trim().is_empty()
    {
        return None;
    }

    let mut state = load_state(review_files_dir, thread_id);
    state.tool_calls_since_skill = state.tool_calls_since_skill.saturating_add(tool_call_count);
    if state.tool_calls_since_skill < DEFAULT_SKILL_REVIEW_INTERVAL {
        let _ = save_state(review_files_dir, thread_id, &state);
        return None;
    }

    let Some(guard_key) =
        try_mark_review_in_flight(review_files_dir, agent_id, thread_id, ReviewType::Skill)
    else {
        let _ = save_state(review_files_dir, thread_id, &state);
        return None;
    };

    state.tool_calls_since_skill = 0;
    state.last_skill_review_at = Some(Utc::now().to_rfc3339());
    let _ = save_state(review_files_dir, thread_id, &state);

    let queued = create_queued_run_record(run_files_dir, agent_id, thread_id, ReviewType::Skill);

    spawn_skill_review(
        run_files_dir.to_string(),
        review_files_dir.to_string(),
        agent_id.to_string(),
        thread_id.to_string(),
        config.clone(),
        history.to_vec(),
        tool_call_count,
        guard_key,
        queued.id.clone(),
    );

    Some(queued)
}

fn spawn_memory_review(
    run_files_dir: String,
    review_files_dir: String,
    agent_id: String,
    thread_id: String,
    config: PlatformLlmConfig,
    history: Vec<SessionMessage>,
    guard_key: String,
    run_id: String,
) {
    tokio::spawn(async move {
        mark_run_started(&run_files_dir, &run_id);

        #[cfg(test)]
        if config.provider == "__test_noop__" {
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            mark_run_completed(
                &run_files_dir,
                &run_id,
                &EvolutionRun {
                    reviewed: true,
                    suggestions_count: 0,
                    auto_applied_count: 0,
                    pending_count: 0,
                    error: None,
                },
            );
            release_review_in_flight(&guard_key);
            return;
        }

        // Profile extraction fallback: if profile hasn't been written yet,
        // attempt to extract it from conversation history before running
        // the normal memory review.
        if !crate::workspace::is_profile_populated(&review_files_dir) && history.len() >= 4 {
            let _ =
                super::review::extract_profile_from_history(&review_files_dir, &config, &history)
                    .await;
        }

        let result =
            review_memory_now(&review_files_dir, &agent_id, &thread_id, &config, &history).await;
        mark_run_completed(&run_files_dir, &run_id, &result);
        log_background_review_result(&thread_id, ReviewType::Memory, &result);
        release_review_in_flight(&guard_key);
    });
}

fn spawn_skill_review(
    run_files_dir: String,
    review_files_dir: String,
    agent_id: String,
    thread_id: String,
    config: PlatformLlmConfig,
    history: Vec<SessionMessage>,
    trigger_tool_calls: usize,
    guard_key: String,
    run_id: String,
) {
    tokio::spawn(async move {
        mark_run_started(&run_files_dir, &run_id);

        #[cfg(test)]
        if config.provider == "__test_noop__" {
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            mark_run_completed(
                &run_files_dir,
                &run_id,
                &EvolutionRun {
                    reviewed: true,
                    suggestions_count: 0,
                    auto_applied_count: 0,
                    pending_count: 0,
                    error: None,
                },
            );
            release_review_in_flight(&guard_key);
            return;
        }

        let result = review_skill_now(
            &review_files_dir,
            &agent_id,
            &thread_id,
            &config,
            &history,
            trigger_tool_calls,
        )
        .await;
        mark_run_completed(&run_files_dir, &run_id, &result);
        log_background_review_result(&thread_id, ReviewType::Skill, &result);
        release_review_in_flight(&guard_key);
    });
}

fn create_queued_run_record(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    review_type: ReviewType,
) -> QueuedEvolutionRun {
    let review_type_name = review_type_name(review_type).to_string();
    let record = EvolutionRunRecord {
        id: uuid::Uuid::new_v4().to_string(),
        agent_id: agent_id.to_string(),
        thread_id: thread_id.to_string(),
        review_type: review_type_name.clone(),
        status: EvolutionRunStatus::Queued,
        queued_at: Utc::now().to_rfc3339(),
        started_at: None,
        completed_at: None,
        suggestions_count: 0,
        auto_applied_count: 0,
        pending_count: 0,
        error: None,
    };
    if let Err(error) = upsert_run_record(files_dir, record.clone()) {
        tracing::warn!(
            run_id = record.id,
            error,
            "[Evolution] Failed to persist queued review run"
        );
    }
    QueuedEvolutionRun {
        id: record.id,
        review_type: review_type_name,
    }
}

fn mark_run_started(files_dir: &str, run_id: &str) {
    update_run_record(files_dir, run_id, |record| {
        record.status = EvolutionRunStatus::Running;
        record.started_at = Some(Utc::now().to_rfc3339());
        record.error = None;
    });
}

fn mark_run_completed(files_dir: &str, run_id: &str, result: &EvolutionRun) {
    update_run_record(files_dir, run_id, |record| {
        record.completed_at = Some(Utc::now().to_rfc3339());
        record.suggestions_count = result.suggestions_count;
        record.auto_applied_count = result.auto_applied_count;
        record.pending_count = result.pending_count;
        record.error = result.error.clone();
        record.status = if result.error.is_some() {
            EvolutionRunStatus::Failed
        } else {
            EvolutionRunStatus::Completed
        };
    });
}
