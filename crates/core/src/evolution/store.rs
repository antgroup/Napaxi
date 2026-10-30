use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration as StdDuration, Instant};

use chrono::{Duration, Utc};
use napaxi_evolution::PendingConfirmation;

use super::{
    EVOLUTION_DIR, EvolutionDiagnosticRecord, EvolutionRunRecord, EvolutionRunStatus,
    EvolutionState, PendingEvolution, PendingStatus,
};

/// Monotonic anchor registry for in-flight evolution runs.
///
/// Wall-clock `queued_at` / `started_at` / `completed_at` fields stay on
/// `chrono::Utc` because they are persisted as RFC3339 and need to survive
/// process restarts (see `EvolutionRunRecord`). The stale check, however, is a
/// single-process elapsed-time judgement: wall-clock jumps (NTP, manual time
/// changes) would otherwise mis-flag a run as stale. We therefore record a
/// process-local monotonic anchor per `run_id` and compare `anchor.elapsed()`
/// against `RUN_STALE_AFTER_MINUTES`. When no anchor is present (a run
/// persisted by an earlier process), we gracefully fall back to the
/// wall-clock comparison.
fn monotonic_anchors() -> &'static Mutex<HashMap<String, Instant>> {
    static ANCHORS: OnceLock<Mutex<HashMap<String, Instant>>> = OnceLock::new();
    ANCHORS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Record (or refresh) the monotonic anchor for a given run id. Called from
/// `queue::create_queued_run_record` (queue anchor) and `queue::mark_run_started`
/// (start anchor refresh).
pub(super) fn record_monotonic_anchor(run_id: &str, at: Instant) {
    if let Ok(mut anchors) = monotonic_anchors().lock() {
        anchors.insert(run_id.to_string(), at);
    }
}

/// Take (peek + remove) the monotonic anchor for a given run id. Used to clean
/// up the anchor slot once a run reaches a terminal state.
pub(super) fn take_monotonic_anchor(run_id: &str) -> Option<Instant> {
    match monotonic_anchors().lock() {
        Ok(mut anchors) => anchors.remove(run_id),
        Err(_) => None,
    }
}

fn peek_monotonic_anchor(run_id: &str) -> Option<Instant> {
    match monotonic_anchors().lock() {
        Ok(anchors) => anchors.get(run_id).copied(),
        Err(_) => None,
    }
}

const PENDING_FILE: &str = "pending.json";
const RUNS_FILE: &str = "runs.json";
pub(super) const RUN_STALE_AFTER_MINUTES: i64 = 30;
const MAX_DIAGNOSTIC_RECORDS: usize = 200;

fn pending_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join(EVOLUTION_DIR).join(PENDING_FILE)
}

fn diagnostics_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join(EVOLUTION_DIR)
        .join("diagnostics.json")
}

pub(super) fn load_pending_store(files_dir: &str) -> Vec<PendingEvolution> {
    fs::read_to_string(pending_path(files_dir))
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
        .unwrap_or_default()
}

pub(super) fn load_diagnostics_store(files_dir: &str) -> Vec<EvolutionDiagnosticRecord> {
    fs::read_to_string(diagnostics_path(files_dir))
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
        .unwrap_or_default()
}

fn atomic_write_text_sync(path: &Path, content: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let temp = path.with_file_name(format!(
        ".{}.{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("store"),
        uuid::Uuid::new_v4()
    ));
    if let Err(error) = fs::write(&temp, content) {
        let _ = fs::remove_file(&temp);
        return Err(error.to_string());
    }
    fs::rename(&temp, path).map_err(|error| {
        let _ = fs::remove_file(&temp);
        error.to_string()
    })
}

pub(super) fn save_pending_store(
    files_dir: &str,
    pending: &[PendingEvolution],
) -> Result<(), String> {
    let path = pending_path(files_dir);
    let content = serde_json::to_string_pretty(pending).map_err(|e| e.to_string())?;
    atomic_write_text_sync(&path, &content)
}

fn save_diagnostics_store(
    files_dir: &str,
    records: &[EvolutionDiagnosticRecord],
) -> Result<(), String> {
    let path = diagnostics_path(files_dir);
    let content = serde_json::to_string_pretty(records).map_err(|e| e.to_string())?;
    atomic_write_text_sync(&path, &content)
}

pub(super) fn append_diagnostic_record(files_dir: &str, record: EvolutionDiagnosticRecord) {
    let mut records = load_diagnostics_store(files_dir);
    records.push(record);
    if records.len() > MAX_DIAGNOSTIC_RECORDS {
        let overflow = records.len() - MAX_DIAGNOSTIC_RECORDS;
        records.drain(0..overflow);
    }
    if let Err(error) = save_diagnostics_store(files_dir, &records) {
        tracing::warn!(error, "[Evolution] Failed to persist diagnostic record");
    }
}

pub(super) fn load_run_store(files_dir: &str) -> Vec<EvolutionRunRecord> {
    fs::read_to_string(runs_path(files_dir))
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
        .unwrap_or_default()
}

pub(super) fn save_run_store(files_dir: &str, runs: &[EvolutionRunRecord]) -> Result<(), String> {
    let path = runs_path(files_dir);
    let content = serde_json::to_string_pretty(runs).map_err(|e| e.to_string())?;
    atomic_write_text_sync(&path, &content)
}

pub(super) fn refresh_stale_runs(runs: &mut [EvolutionRunRecord]) -> bool {
    let now = Utc::now();
    let stale_after = Duration::minutes(RUN_STALE_AFTER_MINUTES);
    let monotonic_threshold = StdDuration::from_secs((RUN_STALE_AFTER_MINUTES.max(0) as u64) * 60);
    let mut changed = false;
    for run in runs {
        if !matches!(
            run.status,
            EvolutionRunStatus::Queued | EvolutionRunStatus::Running
        ) {
            continue;
        }
        let stale = match peek_monotonic_anchor(&run.id) {
            Some(anchor) => anchor.elapsed() >= monotonic_threshold,
            None => {
                tracing::debug!(
                    run_id = %run.id,
                    "[Evolution] No monotonic anchor; falling back to wall-clock stale check"
                );
                let anchor = run
                    .started_at
                    .as_deref()
                    .or(Some(run.queued_at.as_str()))
                    .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
                    .map(|value| value.with_timezone(&Utc));
                match anchor {
                    Some(started) => now.signed_duration_since(started) >= stale_after,
                    None => {
                        // RFC3339 parse failed: do not prematurely fail the run.
                        // Keep it alive and let a future refresh (with an anchor
                        // or a parseable timestamp) decide.
                        tracing::warn!(
                            run_id = %run.id,
                            "[Evolution] Failed to parse run timestamps; keeping run alive"
                        );
                        false
                    }
                }
            }
        };
        if stale {
            // Drop the monotonic anchor slot alongside flipping the record to
            // a terminal state so the registry cannot leak past a stale run.
            let _ = take_monotonic_anchor(&run.id);
            run.status = EvolutionRunStatus::Failed;
            run.completed_at = Some(now.to_rfc3339());
            run.error = Some("evolution run expired before completion".to_string());
            changed = true;
        }
    }
    changed
}

pub(super) fn refresh_expired(pending: &mut [PendingEvolution]) {
    let now = Utc::now();
    for item in pending {
        if item.status != PendingStatus::Pending {
            continue;
        }
        let expired = chrono::DateTime::parse_from_rfc3339(&item.expires_at)
            .ok()
            .map(|dt| dt.with_timezone(&Utc) < now)
            .unwrap_or(false);
        if expired {
            item.status = PendingStatus::Expired;
        }
    }
}

pub(super) fn persist_pending_confirmations(
    files_dir: &str,
    agent_id: &str,
    confirmations: &[PendingConfirmation],
) -> Result<usize, String> {
    let mut pending = load_pending_store(files_dir);
    refresh_expired(&mut pending);
    for confirmation in confirmations {
        let item = PendingEvolution {
            id: confirmation.id.to_string(),
            agent_id: agent_id.to_string(),
            thread_id: confirmation.thread_id.clone(),
            created_at: confirmation.created_at.to_rfc3339(),
            expires_at: confirmation.expires_at.to_rfc3339(),
            review_type: confirmation.source.review_type,
            action_type: confirmation.action.action_type_name().to_string(),
            action: confirmation.action.clone(),
            aggregated_actions: confirmation.aggregated_actions.clone(),
            reasoning: confirmation.reasoning.clone(),
            status: PendingStatus::Pending,
        };
        if let Some(existing) = pending.iter_mut().find(|existing| existing.id == item.id) {
            *existing = item;
        } else {
            pending.push(item);
        }
    }
    let count = pending
        .iter()
        .filter(|item| item.status == PendingStatus::Pending)
        .count();
    save_pending_store(files_dir, &pending)?;
    Ok(count)
}

pub(in crate::evolution) fn update_run_record<F>(files_dir: &str, run_id: &str, update: F)
where
    F: FnOnce(&mut EvolutionRunRecord),
{
    let mut runs = load_run_store(files_dir);
    let runs_changed = refresh_stale_runs(&mut runs);
    let Some(record) = runs.iter_mut().find(|record| record.id == run_id) else {
        tracing::warn!(run_id, "[Evolution] Review run record not found");
        if runs_changed {
            let _ = save_run_store(files_dir, &runs);
        }
        return;
    };
    update(record);
    if let Err(error) = save_run_store(files_dir, &runs) {
        tracing::warn!(run_id, error, "[Evolution] Failed to persist review run");
    }
}

pub(in crate::evolution) fn upsert_run_record(
    files_dir: &str,
    record: EvolutionRunRecord,
) -> Result<(), String> {
    let mut runs = load_run_store(files_dir);
    refresh_stale_runs(&mut runs);
    if let Some(existing) = runs.iter_mut().find(|existing| existing.id == record.id) {
        *existing = record;
    } else {
        runs.push(record);
    }
    save_run_store(files_dir, &runs)
}

fn state_path(files_dir: &str, thread_id: &str) -> PathBuf {
    Path::new(files_dir)
        .join(EVOLUTION_DIR)
        .join(format!("{thread_id}.json"))
}

fn runs_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join(EVOLUTION_DIR).join(RUNS_FILE)
}

pub(in crate::evolution) fn load_state(files_dir: &str, thread_id: &str) -> EvolutionState {
    let path = state_path(files_dir, thread_id);
    fs::read_to_string(path)
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
        .unwrap_or_default()
}

pub(in crate::evolution) fn save_state(
    files_dir: &str,
    thread_id: &str,
    state: &EvolutionState,
) -> Result<(), String> {
    let path = state_path(files_dir, thread_id);
    let content = serde_json::to_string_pretty(state).map_err(|e| e.to_string())?;
    atomic_write_text_sync(&path, &content)
}
