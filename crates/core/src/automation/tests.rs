//! Integration tests covering CRUD, scheduling, run lifecycle, and policy.

use std::fs;

use chrono::TimeZone;
use serde_json::json;

use crate::types::PlatformLlmConfig;

use super::handles::{
    create_automation_job_handle, delete_automation_job_handle, list_automation_jobs_handle,
    normalize_job, update_automation_job_handle,
};
use super::now_ms;
use super::runner::{automation_scoped_config, compute_next_run_at_ms, run_automation_job_handle};
use super::store::{load_store_expiring_runs, read_runs_for_job, save_store};
use super::types::{
    AutomationJob, AutomationPayload, AutomationRunStatus, AutomationStore,
    DEFAULT_MAX_RUN_DURATION_MS,
};

fn engine_handle(files_dir: &str) -> i64 {
    let config_json = json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context_json = json!({
        "platform": "test",
        "files_dir": files_dir,
        "capability_profile": {
            "platform": "test",
            "supported_capabilities": ["napaxi.service.automation"]
        },
        "capability_selection": {
            "enabled_capabilities": ["napaxi.service.automation"]
        }
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

fn one_shot_job(at_ms: i64) -> String {
    json!({
        "name": "One shot",
        "trigger": {"kind": "oneShotAt", "atMs": at_ms},
        "payload": {"kind": "systemEvent", "text": "Wake up"}
    })
    .to_string()
}

#[test]
fn creates_lists_updates_and_deletes_jobs() {
    let tmp = tempfile::tempdir().unwrap();
    let handle = engine_handle(&tmp.path().to_string_lossy());

    let created = create_automation_job_handle(handle, &one_shot_job(now_ms() + 60_000));
    let job: AutomationJob = serde_json::from_str(&created).unwrap();
    assert!(!job.id.is_empty());
    assert_eq!(job.account_id, crate::runtime::DEFAULT_ACCOUNT_ID);

    let listed = list_automation_jobs_handle(handle, "{}");
    assert!(listed.contains("One shot"));

    let updated =
        update_automation_job_handle(handle, &job.id, r#"{"name":"Renamed","enabled":false}"#);
    let updated_job: AutomationJob = serde_json::from_str(&updated).unwrap();
    assert_eq!(updated_job.name, "Renamed");
    assert!(!updated_job.enabled);

    assert!(delete_automation_job_handle(handle, &job.id));
    assert_eq!(list_automation_jobs_handle(handle, "{}"), "[]");
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn interval_next_run_uses_anchor() {
    let now = now_ms();
    let mut job: AutomationJob = serde_json::from_value(json!({
        "id": "interval",
        "name": "Interval",
        "trigger": {"kind": "interval", "everyMs": 1000, "anchorMs": now - 2500},
        "payload": {"kind": "systemEvent", "text": "tick"}
    }))
    .unwrap();
    normalize_job(&mut job, now).unwrap();
    assert_eq!(compute_next_run_at_ms(&job, now), Some(now + 500));
}

#[test]
fn local_time_trigger_uses_timezone_and_iso_weekdays() {
    let now = chrono_tz::Asia::Shanghai
        .with_ymd_and_hms(2026, 6, 8, 8, 30, 0)
        .single()
        .unwrap()
        .timestamp_millis();
    let mut job: AutomationJob = serde_json::from_value(json!({
        "id": "local-time",
        "name": "Local time",
        "trigger": {
            "kind": "localTime",
            "hour": 9,
            "minute": 0,
            "timezone": "Asia/Shanghai",
            "daysOfWeek": [1]
        },
        "payload": {"kind": "systemEvent", "text": "tick"}
    }))
    .unwrap();
    normalize_job(&mut job, now).unwrap();

    let next = compute_next_run_at_ms(&job, now).unwrap();
    let expected = chrono_tz::Asia::Shanghai
        .with_ymd_and_hms(2026, 6, 8, 9, 0, 0)
        .single()
        .unwrap()
        .timestamp_millis();

    assert_eq!(next, expected);
}

#[test]
fn local_time_trigger_skips_inactive_weekdays() {
    let now = chrono_tz::Asia::Shanghai
        .with_ymd_and_hms(2026, 6, 8, 10, 0, 0)
        .single()
        .unwrap()
        .timestamp_millis();
    let mut job: AutomationJob = serde_json::from_value(json!({
        "id": "weekly-local-time",
        "name": "Weekly local time",
        "trigger": {
            "kind": "localTime",
            "hour": 9,
            "minute": 0,
            "timezone": "Asia/Shanghai",
            "daysOfWeek": [3]
        },
        "payload": {"kind": "systemEvent", "text": "tick"}
    }))
    .unwrap();
    normalize_job(&mut job, now).unwrap();

    let next = compute_next_run_at_ms(&job, now).unwrap();
    let expected = chrono_tz::Asia::Shanghai
        .with_ymd_and_hms(2026, 6, 10, 9, 0, 0)
        .single()
        .unwrap()
        .timestamp_millis();

    assert_eq!(next, expected);
}

#[test]
fn rejects_invalid_local_time_timezone() {
    let now = now_ms();
    let mut job: AutomationJob = serde_json::from_value(json!({
        "id": "bad-timezone",
        "name": "Bad timezone",
        "trigger": {
            "kind": "localTime",
            "hour": 9,
            "minute": 0,
            "timezone": "Mars/Base"
        },
        "payload": {"kind": "systemEvent", "text": "tick"}
    }))
    .unwrap();

    let err = normalize_job(&mut job, now).unwrap_err();

    assert!(err.contains("IANA timezone"));
}

#[test]
fn manual_due_and_force_modes_are_distinct() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);
    let created = create_automation_job_handle(handle, &one_shot_job(now_ms() + 60_000));
    let job: AutomationJob = serde_json::from_str(&created).unwrap();

    let rt = tokio::runtime::Runtime::new().unwrap();
    let due = rt.block_on(run_automation_job_handle(handle, &job.id, "due"));
    assert!(due.contains("\"status\":\"skipped\""));
    let manual = rt.block_on(run_automation_job_handle(handle, &job.id, "manual"));
    assert!(manual.contains("\"status\":\"succeeded\""));

    let force = rt.block_on(run_automation_job_handle(handle, &job.id, "force"));
    assert!(force.contains("not found") || force.contains("\"status\""));
    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn running_run_expires_on_load() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let old = now_ms() - DEFAULT_MAX_RUN_DURATION_MS - 1_000;
    let mut job: AutomationJob = serde_json::from_value(json!({
        "id": "stuck",
        "name": "Stuck",
        "trigger": {"kind": "manual"},
        "payload": {"kind": "systemEvent", "text": "tick"},
        "state": {"runningRunId": "run-a", "runningAtMs": old}
    }))
    .unwrap();
    normalize_job(&mut job, old).unwrap();
    assert!(save_store(&files_dir, &AutomationStore { jobs: vec![job] }));

    let store = load_store_expiring_runs(&files_dir);
    assert_eq!(
        store.jobs[0].state.last_run_status,
        Some(AutomationRunStatus::Expired)
    );
    let runs = read_runs_for_job(&files_dir, "stuck");
    assert_eq!(runs[0].status, AutomationRunStatus::Expired);
}

#[test]
fn automation_store_writes_to_neutral_runtime_path() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let job: AutomationJob = serde_json::from_value(json!({
        "id": "neutral-path",
        "name": "Neutral path",
        "trigger": {"kind": "manual"},
        "payload": {"kind": "systemEvent", "text": "tick"}
    }))
    .unwrap();

    assert!(save_store(&files_dir, &AutomationStore { jobs: vec![job] }));

    assert!(
        crate::agent_runtime::domain_dir(&files_dir, "automation")
            .join("jobs.json")
            .exists()
    );
    assert!(
        !crate::agent_runtime::legacy_brand_domain_dir(&files_dir, "automation")
            .join("jobs.json")
            .exists()
    );
}

#[test]
fn automation_store_reads_legacy_branded_path() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let legacy_path =
        crate::agent_runtime::legacy_brand_domain_dir(&files_dir, "automation").join("jobs.json");
    fs::create_dir_all(legacy_path.parent().unwrap()).unwrap();
    fs::write(
        &legacy_path,
        json!({
            "jobs": [{
                "id": "legacy",
                "name": "Legacy",
                "enabled": true,
                "accountId": "user",
                "agentId": "default",
                "trigger": {"kind": "manual"},
                "payload": {"kind": "systemEvent", "text": "tick"},
                "policy": {},
                "state": {},
                "createdAt": 1,
                "updatedAt": 1
            }]
        })
        .to_string(),
    )
    .unwrap();

    let store = load_store_expiring_runs(&files_dir);

    assert_eq!(store.jobs.len(), 1);
    assert_eq!(store.jobs[0].id, "legacy");
}

#[test]
fn automation_config_disables_high_risk_tools_by_default() {
    let job: AutomationJob = serde_json::from_str(&one_shot_job(now_ms() + 60_000)).unwrap();
    let config = automation_scoped_config(PlatformLlmConfig::default(), &job);
    assert!(
        config
            .capability_selection
            .disabled_capabilities
            .contains(&"napaxi.tool.shell".to_string())
    );
    assert!(
        config
            .capability_selection
            .disabled_capabilities
            .contains(&"napaxi.tool.http".to_string())
    );
}

#[test]
fn agent_turn_payload_accepts_existing_session_key() {
    let job: AutomationJob = serde_json::from_value(json!({
        "name": "Daily report",
        "trigger": {"kind": "oneShotAt", "atMs": now_ms() + 60_000},
        "payload": {
            "kind": "agentTurn",
            "message": "Write the daily report.",
            "sessionKey": "{\"channel_type\":\"app\",\"account_id\":\"default\",\"thread_id\":\"t1\"}",
            "sessionMode": "main",
            "maxIterations": 6
        }
    }))
    .unwrap();

    match job.payload {
        AutomationPayload::AgentTurn {
            session_key,
            session_mode,
            max_iterations,
            ..
        } => {
            assert!(session_key.unwrap().contains("\"thread_id\":\"t1\""));
            assert!(matches!(
                session_mode,
                super::types::AutomationSessionMode::Main
            ));
            assert_eq!(max_iterations, Some(6));
        }
        AutomationPayload::SystemEvent { .. } => panic!("expected agent turn payload"),
    }
}

#[test]
fn automation_config_uses_trigger_timezone_when_config_has_none() {
    let job: AutomationJob = serde_json::from_value(json!({
        "name": "Shanghai wakeup",
        "trigger": {"kind": "oneShotAt", "atMs": now_ms() + 60_000, "timezone": "Asia/Shanghai"},
        "payload": {"kind": "agentTurn", "message": "remind me"},
        "policy": {"allowHighRiskTools": true}
    }))
    .unwrap();

    let config = automation_scoped_config(PlatformLlmConfig::default(), &job);
    assert_eq!(config.user_timezone.as_deref(), Some("Asia/Shanghai"));
}

#[test]
fn empty_agent_response_gets_informational_summary() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);

    let created = create_automation_job_handle(
        handle,
        &json!({
            "name": "Empty agent",
            "trigger": {"kind": "manual"},
            "payload": {
                "kind": "agentTurn",
                "message": "hello",
                "sessionMode": "isolated"
            }
        })
        .to_string(),
    );
    let job: AutomationJob = serde_json::from_str(&created).unwrap();

    let rt = tokio::runtime::Runtime::new().unwrap();
    let result = rt.block_on(run_automation_job_handle(handle, &job.id, "manual"));

    assert!(
        result.contains("\"status\":\"succeeded\""),
        "run should succeed"
    );
    assert!(
        result.contains("no response"),
        "summary should mention no response, got: {result}"
    );

    crate::runtime::dispose_engine_handle(handle);
}

#[test]
fn automation_config_keeps_explicit_user_timezone() {
    let job: AutomationJob = serde_json::from_value(json!({
        "name": "Shanghai wakeup",
        "trigger": {"kind": "oneShotAt", "atMs": now_ms() + 60_000, "timezone": "Asia/Shanghai"},
        "payload": {"kind": "agentTurn", "message": "remind me"},
        "policy": {"allowHighRiskTools": true}
    }))
    .unwrap();
    let config = PlatformLlmConfig {
        user_timezone: Some("Europe/Vienna".to_string()),
        ..PlatformLlmConfig::default()
    };

    let config = automation_scoped_config(config, &job);
    assert_eq!(config.user_timezone.as_deref(), Some("Europe/Vienna"));
}

#[test]
fn empty_model_profile_id_is_cleared() {
    let now = now_ms();
    let mut job: AutomationJob = serde_json::from_value(json!({
        "id": "profile-test",
        "name": "Profile test",
        "trigger": {"kind": "manual"},
        "payload": {
            "kind": "agentTurn",
            "message": "hello",
            "modelProfileId": ""
        }
    }))
    .unwrap();

    normalize_job(&mut job, now).unwrap();

    match &job.payload {
        AutomationPayload::AgentTurn {
            model_profile_id, ..
        } => {
            assert_eq!(*model_profile_id, None);
        }
        _ => panic!("expected AgentTurn payload"),
    }
}
