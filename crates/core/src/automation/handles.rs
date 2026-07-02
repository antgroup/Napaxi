//! Engine-handle wrappers for automation CRUD + scheduling queries.

use serde_json::Value;
use uuid::Uuid;

use super::runner::{compute_next_run_at_ms, run_automation_job_handle};
use super::store::{
    load_store_expiring_runs, read_all_runs, read_runs_for_job, with_store, with_store_result,
};
use super::types::{AutomationJob, AutomationPayload, AutomationTrigger, RUN_LOG_PAGE_LIMIT};
use super::{error_json, files_dir, json_string, now_ms};

pub fn create_automation_job_handle(handle: i64, job_json: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    with_store(&files_dir, |store| {
        let mut job: AutomationJob =
            serde_json::from_str(job_json).map_err(|e| format!("invalid automation job: {e}"))?;
        let now = now_ms();
        normalize_job(&mut job, now)?;
        if store.jobs.iter().any(|existing| existing.id == job.id) {
            return Err(format!("automation job {} already exists", job.id));
        }
        job.state.next_run_at_ms = compute_next_run_at_ms(&job, now);
        store.jobs.push(job.clone());
        Ok(job)
    })
}

pub fn update_automation_job_handle(handle: i64, job_id: &str, patch_json: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    with_store(&files_dir, |store| {
        let Some(index) = store.jobs.iter().position(|job| job.id == job_id) else {
            return Err(format!("automation job {job_id} not found"));
        };
        let patch: Value = serde_json::from_str(patch_json)
            .map_err(|e| format!("invalid automation patch: {e}"))?;
        apply_patch(&mut store.jobs[index], patch)?;
        let now = now_ms();
        store.jobs[index].updated_at = now;
        if store.jobs[index].enabled {
            store.jobs[index].state.next_run_at_ms =
                compute_next_run_at_ms(&store.jobs[index], now);
        } else {
            store.jobs[index].state.next_run_at_ms = None;
        }
        Ok(store.jobs[index].clone())
    })
}

pub fn delete_automation_job_handle(handle: i64, job_id: &str) -> bool {
    let Some(files_dir) = files_dir(handle) else {
        return false;
    };
    let mut store = load_store_expiring_runs(&files_dir);
    let old_len = store.jobs.len();
    store.jobs.retain(|job| job.id != job_id);
    old_len != store.jobs.len() && super::store::save_store(&files_dir, &store)
}

pub fn list_automation_jobs_handle(handle: i64, filter_json: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "[]".to_string();
    };
    let filter = serde_json::from_str::<Value>(filter_json).unwrap_or(Value::Null);
    let mut jobs = load_store_expiring_runs(&files_dir).jobs;
    jobs.retain(|job| job_matches_filter(job, &filter));
    jobs.sort_by(|a, b| {
        a.state
            .next_run_at_ms
            .unwrap_or(i64::MAX)
            .cmp(&b.state.next_run_at_ms.unwrap_or(i64::MAX))
            .then_with(|| a.name.cmp(&b.name))
    });
    json_string(&jobs)
}

pub fn get_automation_job_handle(handle: i64, job_id: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "null".to_string();
    };
    load_store_expiring_runs(&files_dir)
        .jobs
        .into_iter()
        .find(|job| job.id == job_id)
        .map(|job| json_string(&job))
        .unwrap_or_else(|| "null".to_string())
}

pub fn list_automation_runs_handle(
    handle: i64,
    job_id: Option<&str>,
    limit: i64,
    offset: i64,
) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "[]".to_string();
    };
    let limit = if limit <= 0 {
        RUN_LOG_PAGE_LIMIT
    } else {
        usize::try_from(limit)
            .unwrap_or(RUN_LOG_PAGE_LIMIT)
            .min(500)
    };
    let offset = usize::try_from(offset.max(0)).unwrap_or(0);
    let mut runs = if let Some(job_id) = job_id.filter(|id| !id.trim().is_empty()) {
        read_runs_for_job(&files_dir, job_id)
    } else {
        read_all_runs(&files_dir)
    };
    runs.sort_by(|a, b| b.started_at.cmp(&a.started_at));
    json_string(
        &runs
            .into_iter()
            .skip(offset)
            .take(limit)
            .collect::<Vec<_>>(),
    )
}

pub fn get_next_automation_wake_handle(handle: i64) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return "null".to_string();
    };
    let next = load_store_expiring_runs(&files_dir)
        .jobs
        .into_iter()
        .filter(|job| job.enabled)
        .filter_map(|job| {
            job.state.next_run_at_ms.map(|at_ms| {
                serde_json::json!({
                    "jobId": job.id,
                    "atMs": at_ms,
                    "trigger": job.trigger,
                })
            })
        })
        .min_by_key(|value| {
            value
                .get("atMs")
                .and_then(Value::as_i64)
                .unwrap_or(i64::MAX)
        });
    next.map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string())
}

pub async fn record_automation_wake_handle(handle: i64, job_id: &str, source: &str) -> String {
    let Some(files_dir) = files_dir(handle) else {
        return error_json("invalid engine handle");
    };
    let now = now_ms();
    let _ = with_store_result(&files_dir, |store| {
        if let Some(job) = store.jobs.iter_mut().find(|job| job.id == job_id) {
            job.state.last_wake_source = Some(source.trim().to_string());
            job.state.last_wake_at_ms = Some(now);
            job.updated_at = now;
        }
        Ok(())
    });
    run_automation_job_handle(handle, job_id, "platform_wake").await
}

pub fn cancel_automation_job_handle(handle: i64, job_id: &str) -> String {
    // SAFETY: The handle comes from the public engine API. Invalid or disposed
    // handles are represented as `None` and returned as a JSON error.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return error_json("invalid engine handle");
    };
    let files_dir = engine.files_dir();

    // Find the running run_id from the job state.
    let running_run_id = {
        let store = super::store::load_store_expiring_runs(files_dir);
        let Some(job) = store.jobs.iter().find(|j| j.id == job_id) else {
            return error_json(&format!("automation job {job_id} not found"));
        };
        let Some(run_id) = job.state.running_run_id.clone() else {
            return error_json(&format!("automation job {job_id} is not currently running"));
        };
        run_id
    };

    // Read the run log to find the session key for the running run.
    let runs = super::store::read_runs_for_job(files_dir, job_id);
    let session_key = runs
        .iter()
        .find(|r| r.run_id == running_run_id)
        .and_then(|r| r.session_key.clone());

    // Signal session cancellation if we have a session key.
    if let Some(ref key) = session_key {
        engine.cancel_session_key(key);
    }

    // Update the run log with Cancelled status.
    let now = now_ms();
    let run_entry = runs.into_iter().find(|r| r.run_id == running_run_id);
    let run = if let Some(mut r) = run_entry {
        let tool_calls = r.tool_call_count;
        super::runner::finish_run(
            &mut r,
            super::types::AutomationRunStatus::Cancelled,
            None,
            Some("cancelled by user".to_string()),
            tool_calls,
        );
        r
    } else {
        super::runner::new_terminal_run(
            &running_run_id,
            job_id,
            super::types::AutomationTriggerSource::Manual,
            now,
            super::types::AutomationRunStatus::Cancelled,
            None,
            Some("cancelled by user".to_string()),
        )
    };
    super::store::append_run_log(files_dir, &run);

    // Clear the running state from the job.
    let _ = super::store::with_store_result(files_dir, |store| {
        if let Some(job) = store.jobs.iter_mut().find(|j| j.id == job_id) {
            job.state.running_run_id = None;
            job.state.running_at_ms = None;
            job.state.last_run_at_ms = Some(run.started_at);
            job.state.last_run_status = Some(super::types::AutomationRunStatus::Cancelled);
            job.state.last_error = Some("cancelled by user".to_string());
            job.updated_at = now;
            if job.enabled {
                job.state.next_run_at_ms = super::runner::compute_next_run_at_ms(job, now);
            }
        }
        Ok(())
    });

    json_string(&run)
}

pub(super) fn normalize_job(job: &mut AutomationJob, now: i64) -> Result<(), String> {
    if job.id.trim().is_empty() {
        job.id = Uuid::new_v4().to_string();
    }
    assert_safe_job_id(&job.id)?;
    if job.name.trim().is_empty() {
        return Err("automation job name is required".to_string());
    }
    job.account_id = defaulted(&job.account_id, crate::runtime::DEFAULT_ACCOUNT_ID);
    job.agent_id = crate::runtime::normalize_agent_id(&job.agent_id);
    if job.created_at <= 0 {
        job.created_at = now;
    }
    if job.updated_at <= 0 {
        job.updated_at = now;
    }
    validate_trigger(&job.trigger)?;
    normalize_payload(&mut job.payload);
    Ok(())
}

fn normalize_payload(payload: &mut AutomationPayload) {
    if let AutomationPayload::AgentTurn {
        model_profile_id, ..
    } = payload
        && model_profile_id
            .as_deref()
            .is_some_and(|s| s.trim().is_empty())
    {
        *model_profile_id = None;
    }
}

fn apply_patch(job: &mut AutomationJob, patch: Value) -> Result<(), String> {
    let Some(map) = patch.as_object() else {
        return Err("automation patch must be an object".to_string());
    };
    if let Some(name) = get_string(map, "name") {
        if name.trim().is_empty() {
            return Err("automation job name cannot be empty".to_string());
        }
        job.name = name;
    }
    if let Some(enabled) = get_bool(map, "enabled") {
        job.enabled = enabled;
    }
    if let Some(account_id) = get_string_alias(map, "accountId", "account_id") {
        job.account_id = defaulted(&account_id, crate::runtime::DEFAULT_ACCOUNT_ID);
    }
    if let Some(agent_id) = get_string_alias(map, "agentId", "agent_id") {
        job.agent_id = crate::runtime::normalize_agent_id(&agent_id);
    }
    if let Some(trigger) = map.get("trigger") {
        job.trigger = serde_json::from_value(trigger.clone())
            .map_err(|e| format!("invalid automation trigger: {e}"))?;
    }
    if let Some(payload) = map.get("payload") {
        job.payload = serde_json::from_value(payload.clone())
            .map_err(|e| format!("invalid automation payload: {e}"))?;
        normalize_payload(&mut job.payload);
    }
    if let Some(policy) = map.get("policy") {
        job.policy = serde_json::from_value(policy.clone())
            .map_err(|e| format!("invalid automation policy: {e}"))?;
    }
    assert_safe_job_id(&job.id)?;
    validate_trigger(&job.trigger)?;
    Ok(())
}

fn validate_trigger(trigger: &AutomationTrigger) -> Result<(), String> {
    match trigger {
        AutomationTrigger::LocalTime {
            hour,
            minute,
            timezone,
            days_of_week,
        } => {
            if *hour > 23 {
                return Err("automation localTime hour must be 0..23".to_string());
            }
            if *minute > 59 {
                return Err("automation localTime minute must be 0..59".to_string());
            }
            timezone.parse::<chrono_tz::Tz>().map_err(|_| {
                "automation localTime timezone must be an IANA timezone".to_string()
            })?;
            if let Some(days) = days_of_week
                && days.iter().any(|day| !(1..=7).contains(day))
            {
                return Err(
                    "automation localTime daysOfWeek values must use ISO weekday numbers 1..7"
                        .to_string(),
                );
            }
        }
        AutomationTrigger::Interval { every_ms, .. } if *every_ms <= 0 => {
            return Err("automation interval everyMs must be positive".to_string());
        }
        AutomationTrigger::OneShotAt { at_ms, .. } if *at_ms <= 0 => {
            return Err("automation oneShotAt atMs must be positive".to_string());
        }
        _ => {}
    }
    Ok(())
}

fn get_string(map: &serde_json::Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn get_string_alias(
    map: &serde_json::Map<String, Value>,
    camel: &str,
    snake: &str,
) -> Option<String> {
    get_string(map, camel).or_else(|| get_string(map, snake))
}

fn get_bool(map: &serde_json::Map<String, Value>, key: &str) -> Option<bool> {
    map.get(key).and_then(Value::as_bool)
}

fn job_matches_filter(job: &AutomationJob, filter: &Value) -> bool {
    if !filter.is_object() {
        return true;
    }
    if let Some(account_id) = filter
        .get("accountId")
        .or_else(|| filter.get("account_id"))
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        && job.account_id != account_id
    {
        return false;
    }
    if let Some(agent_id) = filter
        .get("agentId")
        .or_else(|| filter.get("agent_id"))
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        && job.agent_id != agent_id
    {
        return false;
    }
    if let Some(enabled) = filter.get("enabled").and_then(Value::as_bool)
        && job.enabled != enabled
    {
        return false;
    }
    true
}

fn assert_safe_job_id(job_id: &str) -> Result<(), String> {
    let trimmed = job_id.trim();
    if trimmed.is_empty()
        || trimmed.contains('/')
        || trimmed.contains('\\')
        || trimmed.contains('\0')
    {
        return Err("invalid automation job id".to_string());
    }
    Ok(())
}

fn defaulted(value: &str, fallback: &str) -> String {
    let value = value.trim();
    if value.is_empty() {
        fallback.to_string()
    } else {
        value.to_string()
    }
}
