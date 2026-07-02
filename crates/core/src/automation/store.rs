//! Persistence: AutomationStore I/O, run logs, and on-disk paths.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::Serialize;
use uuid::Uuid;

use super::types::{
    AutomationDeliveryStatus, AutomationRun, AutomationRunStatus, AutomationStore,
    AutomationTriggerSource,
};
use super::{error_json, json_string, now_ms};

pub(super) fn with_store<T, F>(files_dir: &str, f: F) -> String
where
    T: Serialize,
    F: FnOnce(&mut AutomationStore) -> Result<T, String>,
{
    match with_store_result(files_dir, f) {
        Ok(value) => json_string(&value),
        Err(error) => error_json(&error),
    }
}

pub(super) fn with_store_result<T, F>(files_dir: &str, f: F) -> Result<T, String>
where
    F: FnOnce(&mut AutomationStore) -> Result<T, String>,
{
    let mut store = load_store_expiring_runs(files_dir);
    let result = f(&mut store)?;
    if !save_store(files_dir, &store) {
        return Err("failed to persist automation store".to_string());
    }
    Ok(result)
}

pub(super) fn load_store_expiring_runs(files_dir: &str) -> AutomationStore {
    let mut store = load_store(files_dir);
    let now = now_ms();
    let mut changed = false;
    for job in &mut store.jobs {
        let Some(running_at) = job.state.running_at_ms else {
            continue;
        };
        if now - running_at <= job.policy.max_run_duration_ms.max(1_000) {
            continue;
        }
        let run_id = job
            .state
            .running_run_id
            .clone()
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let mut run = AutomationRun {
            run_id,
            job_id: job.id.clone(),
            status: AutomationRunStatus::Running,
            trigger_source: AutomationTriggerSource::PlatformWake,
            started_at: running_at,
            completed_at: None,
            duration_ms: None,
            session_key: None,
            summary: None,
            error: None,
            tool_call_count: 0,
            delivery_status: AutomationDeliveryStatus::Unknown,
        };
        super::runner::finish_run(
            &mut run,
            AutomationRunStatus::Expired,
            None,
            Some("automation run expired after process interruption".to_string()),
            0,
        );
        append_run_log(files_dir, &run);
        job.state.running_at_ms = None;
        job.state.running_run_id = None;
        job.state.last_run_at_ms = Some(running_at);
        job.state.last_run_status = Some(AutomationRunStatus::Expired);
        job.state.last_error = run.error.clone();
        job.updated_at = now;
        changed = true;
    }
    if changed {
        let _ = save_store(files_dir, &store);
    }
    store
}

pub(super) fn load_store(files_dir: &str) -> AutomationStore {
    load_store_from_path(&store_path(files_dir))
        .or_else(|| load_store_from_path(&legacy_store_path(files_dir)))
        .unwrap_or(AutomationStore { jobs: Vec::new() })
}

pub(super) fn save_store(files_dir: &str, store: &AutomationStore) -> bool {
    let path = store_path(files_dir);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    serde_json::to_string_pretty(store)
        .ok()
        .and_then(|content| fs::write(path, content).ok())
        .is_some()
}

pub(super) fn append_run_log(files_dir: &str, run: &AutomationRun) {
    let path = run_log_path(files_dir, &run.job_id);
    let Some(parent) = path.parent() else {
        return;
    };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) else {
        return;
    };
    let _ = writeln!(file, "{}", json_string(run));
}

pub(super) fn read_all_runs(files_dir: &str) -> Vec<AutomationRun> {
    let mut runs = Vec::new();
    read_runs_from_dir(&run_logs_dir(files_dir), &mut runs);
    read_runs_from_dir(&legacy_run_logs_dir(files_dir), &mut runs);
    latest_runs(runs)
}

pub(super) fn read_runs_for_job(files_dir: &str, job_id: &str) -> Vec<AutomationRun> {
    let mut runs = read_runs_from_path(&run_log_path(files_dir, job_id));
    runs.extend(read_runs_from_path(&legacy_run_log_path(files_dir, job_id)));
    latest_runs(runs)
}

fn load_store_from_path(path: &Path) -> Option<AutomationStore> {
    fs::read_to_string(path)
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
}

fn read_runs_from_dir(dir: &Path, runs: &mut Vec<AutomationRun>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        if entry.path().extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
            continue;
        }
        runs.extend(read_runs_from_path(&entry.path()));
    }
}

fn read_runs_from_path(path: &Path) -> Vec<AutomationRun> {
    let Ok(content) = fs::read_to_string(path) else {
        return Vec::new();
    };
    content
        .lines()
        .filter_map(|line| serde_json::from_str::<AutomationRun>(line).ok())
        .collect()
}

fn latest_runs(runs: Vec<AutomationRun>) -> Vec<AutomationRun> {
    use std::collections::HashMap;
    let mut by_id: HashMap<String, AutomationRun> = HashMap::new();
    for run in runs {
        by_id
            .entry(run.run_id.clone())
            .and_modify(|existing| {
                if run.completed_at.or(Some(run.started_at))
                    >= existing.completed_at.or(Some(existing.started_at))
                {
                    *existing = run.clone();
                }
            })
            .or_insert(run);
    }
    by_id.into_values().collect()
}

fn store_path(files_dir: &str) -> PathBuf {
    crate::agent_runtime::domain_dir(files_dir, "automation").join("jobs.json")
}

fn legacy_store_path(files_dir: &str) -> PathBuf {
    crate::agent_runtime::legacy_brand_domain_dir(files_dir, "automation").join("jobs.json")
}

fn run_logs_dir(files_dir: &str) -> PathBuf {
    crate::agent_runtime::domain_dir(files_dir, "automation").join("runs")
}

fn legacy_run_logs_dir(files_dir: &str) -> PathBuf {
    crate::agent_runtime::legacy_brand_domain_dir(files_dir, "automation").join("runs")
}

fn run_log_path(files_dir: &str, job_id: &str) -> PathBuf {
    run_logs_dir(files_dir).join(format!("{job_id}.jsonl"))
}

fn legacy_run_log_path(files_dir: &str, job_id: &str) -> PathBuf {
    legacy_run_logs_dir(files_dir).join(format!("{job_id}.jsonl"))
}
