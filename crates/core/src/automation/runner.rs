//! Job execution + scheduling: trigger evaluation, agent turn / system event,
//! run finalization and retry policy.

use chrono::{Datelike, Duration, LocalResult, TimeZone, Utc};
use chrono_tz::Tz;
use uuid::Uuid;

use crate::runtime::{
    Engine, SessionTurnInput, prepare_session_tool_context_with_config_for_core, run_session_turn,
};
use crate::types::{ChatEvent, PlatformLlmConfig};

use super::store::{append_run_log, with_store_result};
use super::types::{
    AutomationDeliveryStatus, AutomationJob, AutomationPayload, AutomationPolicy, AutomationRun,
    AutomationRunStatus, AutomationSessionMode, AutomationTrigger, AutomationTriggerSource,
    DEFAULT_RETRY_BACKOFF_MS,
};
use super::{error_json, json_string, now_ms};

pub(super) enum PreparedAutomationRun {
    AlreadyFinished(AutomationRun),
    Runnable {
        job: AutomationJob,
        run: AutomationRun,
    },
}

pub async fn run_automation_job_handle(handle: i64, job_id: &str, mode: &str) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { crate::runtime::handle_to_arc(handle) }) else {
        return error_json("invalid engine handle");
    };
    if let Err(error) = crate::capabilities::admit_service_for_config(
        super::AUTOMATION_CAPABILITY_ID,
        "automation.run_job",
        engine.platform(),
        &engine.capability_profile(),
        &engine.capability_selection(),
    ) {
        return error_json(&error.to_string());
    }
    let source = trigger_source_for_mode(mode);
    let started_at = now_ms();
    let run_id = Uuid::new_v4().to_string();

    let prepare = with_store_result(engine.files_dir(), |store| {
        let Some(index) = store.jobs.iter().position(|job| job.id == job_id) else {
            return Err(format!("automation job {job_id} not found"));
        };
        let due_mode = matches!(
            source,
            AutomationTriggerSource::Due | AutomationTriggerSource::PlatformWake
        );
        let force_mode = mode.trim().eq_ignore_ascii_case("force");
        if !store.jobs[index].enabled && !force_mode {
            let run = new_terminal_run(
                &run_id,
                job_id,
                source,
                started_at,
                AutomationRunStatus::Skipped,
                None,
                Some("automation job is disabled".to_string()),
            );
            append_run_log(engine.files_dir(), &run);
            return Ok(PreparedAutomationRun::AlreadyFinished(run));
        }
        if due_mode && !is_due(&store.jobs[index], started_at) && !force_mode {
            let run = new_terminal_run(
                &run_id,
                job_id,
                source,
                started_at,
                AutomationRunStatus::Skipped,
                None,
                Some("automation job is not due".to_string()),
            );
            append_run_log(engine.files_dir(), &run);
            return Ok(PreparedAutomationRun::AlreadyFinished(run));
        }
        if store.jobs[index].state.running_run_id.is_some() && !force_mode {
            let run = new_terminal_run(
                &run_id,
                job_id,
                source,
                started_at,
                AutomationRunStatus::Skipped,
                None,
                Some("automation job is already running".to_string()),
            );
            append_run_log(engine.files_dir(), &run);
            return Ok(PreparedAutomationRun::AlreadyFinished(run));
        }

        store.jobs[index].state.running_run_id = Some(run_id.clone());
        store.jobs[index].state.running_at_ms = Some(started_at);
        store.jobs[index].state.last_error = None;
        store.jobs[index].updated_at = started_at;
        let job = store.jobs[index].clone();
        let run = AutomationRun {
            run_id: run_id.clone(),
            job_id: job_id.to_string(),
            status: AutomationRunStatus::Running,
            trigger_source: source,
            started_at,
            completed_at: None,
            duration_ms: None,
            session_key: None,
            summary: None,
            error: None,
            tool_call_count: 0,
            delivery_status: AutomationDeliveryStatus::NotRequested,
        };
        append_run_log(engine.files_dir(), &run);
        Ok(PreparedAutomationRun::Runnable { job, run })
    });

    let mut run = match prepare {
        Ok(PreparedAutomationRun::AlreadyFinished(run)) => return json_string(&run),
        Ok(PreparedAutomationRun::Runnable { job, run }) => execute_job(&engine, job, run).await,
        Err(error) => return error_json(&error),
    };

    finalize_run(engine.files_dir(), job_id, &mut run);
    json_string(&run)
}

async fn execute_job(engine: &Engine, job: AutomationJob, mut run: AutomationRun) -> AutomationRun {
    match job.payload.clone() {
        AutomationPayload::SystemEvent {
            text, session_key, ..
        } => execute_system_event(engine, &job, &mut run, &text, session_key),
        AutomationPayload::AgentTurn {
            message,
            session_key,
            session_mode,
            max_iterations,
            ..
        } => {
            execute_agent_turn(
                engine,
                &job,
                &mut run,
                &message,
                session_key,
                session_mode,
                max_iterations,
            )
            .await
        }
    }
    run
}

fn execute_system_event(
    engine: &Engine,
    job: &AutomationJob,
    run: &mut AutomationRun,
    text: &str,
    session_key: Option<String>,
) {
    let session_key = session_key.unwrap_or_else(|| {
        crate::session::create_session(
            engine.files_dir(),
            &job.agent_id,
            "app",
            &job.account_id,
            None,
        )
    });
    let ok = crate::session::inject_user_message(engine.files_dir(), &session_key, text, "[]");
    run.session_key = Some(session_key);
    if ok {
        finish_run(
            run,
            AutomationRunStatus::Succeeded,
            Some(text.to_string()),
            None,
            0,
        );
    } else {
        finish_run(
            run,
            AutomationRunStatus::Failed,
            None,
            Some("failed to inject automation system event".to_string()),
            0,
        );
    }
}

async fn execute_agent_turn(
    engine: &Engine,
    job: &AutomationJob,
    run: &mut AutomationRun,
    message: &str,
    session_key: Option<String>,
    session_mode: AutomationSessionMode,
    max_iterations: Option<i32>,
) {
    let session_key = session_key
        .map(|key| key.trim().to_string())
        .filter(|key| !key.is_empty())
        .unwrap_or_else(|| match session_mode {
            AutomationSessionMode::Main => crate::session::create_session(
                engine.files_dir(),
                &job.agent_id,
                "app",
                &job.account_id,
                None,
            ),
            AutomationSessionMode::Isolated => crate::session::create_session(
                engine.files_dir(),
                &job.agent_id,
                "automation",
                &job.account_id,
                Some(&run.run_id),
            ),
        });
    run.session_key = Some(session_key.clone());
    let mut config = engine.config_with_capabilities(engine.config());
    config = automation_scoped_config(config, job);
    let effective_config_json = json_string(&config);
    let tool_context = prepare_session_tool_context_with_config_for_core(
        engine,
        &job.account_id,
        &job.agent_id,
        config,
    );
    engine.clear_session_cancellation(&session_key);
    let cancellation_key = session_key.clone();
    let events = crate::capabilities::with_admission_sink(
        engine.admission_sink(),
        run_session_turn(
            SessionTurnInput {
                files_dir: engine.files_dir().to_string(),
                workspace_files_dir: tool_context.workspace_files_dir,
                config_json: effective_config_json,
                agent_id: job.agent_id.clone(),
                session_key_json: session_key,
                message: message.to_string(),
                display_message: None,
                attachments_json: "[]".to_string(),
                tools: Some(engine.tools()),
                max_iterations: max_iterations.unwrap_or(0),
                extra_tools: tool_context.extra_tools,
                internal_tool_handler: tool_context.internal_tool_handler,
                is_group_context: false,
                agent_engine: None,
            },
            || engine.is_session_cancelled(&cancellation_key),
        ),
    )
    .await;
    let summary = final_response(&events);
    let error = first_error(&events);
    let tool_call_count = events
        .iter()
        .filter(|event| {
            matches!(
                event,
                ChatEvent::ToolCall { .. } | ChatEvent::AgentToolCall { .. }
            )
        })
        .count();
    let summary = if error.is_none() && summary.is_none() && tool_call_count == 0 {
        Some("automation agent produced no response".to_string())
    } else {
        summary
    };
    if engine.is_session_cancelled(&cancellation_key) {
        finish_run(
            run,
            AutomationRunStatus::Cancelled,
            summary,
            Some(
                error.unwrap_or_else(|| {
                    "automation run was cancelled before completion".to_string()
                }),
            ),
            tool_call_count,
        );
    } else if let Some(error) = error {
        finish_run(
            run,
            AutomationRunStatus::Failed,
            summary,
            Some(error),
            tool_call_count,
        );
    } else {
        finish_run(
            run,
            AutomationRunStatus::Succeeded,
            summary,
            None,
            tool_call_count,
        );
    }
}

pub(super) fn automation_scoped_config(
    mut config: PlatformLlmConfig,
    job: &AutomationJob,
) -> PlatformLlmConfig {
    let policy = &job.policy;
    if config
        .user_timezone
        .as_deref()
        .map(str::trim)
        .unwrap_or_default()
        .is_empty()
        && let AutomationTrigger::OneShotAt {
            timezone: Some(timezone),
            ..
        }
        | AutomationTrigger::LocalTime { timezone, .. } = &job.trigger
    {
        config.user_timezone = Some(timezone.to_string());
    }
    if !policy.allow_high_risk_tools {
        config.capability_selection.disabled_capabilities.extend([
            "napaxi.tool.shell".to_string(),
            "napaxi.tool.http".to_string(),
            "napaxi.tool.agent_app_action".to_string(),
        ]);
        config.capability_selection.disabled_capabilities.sort();
        config.capability_selection.disabled_capabilities.dedup();
    }
    config
}

pub(super) fn finish_run(
    run: &mut AutomationRun,
    status: AutomationRunStatus,
    summary: Option<String>,
    error: Option<String>,
    tool_call_count: usize,
) {
    let completed_at = now_ms();
    run.status = status;
    run.completed_at = Some(completed_at);
    run.duration_ms = Some((completed_at - run.started_at).max(0));
    run.summary = summary;
    run.error = error;
    run.tool_call_count = tool_call_count;
    run.delivery_status = if matches!(status, AutomationRunStatus::Succeeded) {
        AutomationDeliveryStatus::NotRequested
    } else {
        AutomationDeliveryStatus::Unknown
    };
}

fn finalize_run(files_dir: &str, job_id: &str, run: &mut AutomationRun) {
    let _ = with_store_result(files_dir, |store| {
        let Some(index) = store.jobs.iter().position(|job| job.id == job_id) else {
            append_run_log(files_dir, run);
            return Ok(());
        };
        let now = run.completed_at.unwrap_or_else(now_ms);
        let status = run.status;
        let job = &mut store.jobs[index];
        job.state.running_run_id = None;
        job.state.running_at_ms = None;
        job.state.last_run_at_ms = Some(run.started_at);
        job.state.last_run_status = Some(status);
        job.state.last_error = run.error.clone();
        if matches!(status, AutomationRunStatus::Failed) {
            job.state.consecutive_errors = job.state.consecutive_errors.saturating_add(1);
            if job.state.consecutive_errors <= job.policy.max_retries {
                job.state.next_run_at_ms =
                    Some(now + retry_backoff_ms(&job.policy, job.state.consecutive_errors));
            }
        } else {
            job.state.consecutive_errors = 0;
            if should_delete_after_success(job, status) {
                store.jobs.remove(index);
                append_run_log(files_dir, run);
                return Ok(());
            }
            if matches!(job.trigger, AutomationTrigger::OneShotAt { .. })
                && matches!(
                    status,
                    AutomationRunStatus::Succeeded
                        | AutomationRunStatus::Skipped
                        | AutomationRunStatus::Cancelled
                )
            {
                job.enabled = false;
                job.state.next_run_at_ms = None;
            } else if job.enabled {
                job.state.next_run_at_ms = compute_next_run_at_ms(job, now);
            } else {
                job.state.next_run_at_ms = None;
            }
        }
        job.updated_at = now;
        append_run_log(files_dir, run);
        Ok(())
    });
}

fn should_delete_after_success(job: &AutomationJob, status: AutomationRunStatus) -> bool {
    if !matches!(status, AutomationRunStatus::Succeeded) {
        return false;
    }
    job.policy
        .delete_after_success
        .unwrap_or(matches!(job.trigger, AutomationTrigger::OneShotAt { .. }))
}

fn retry_backoff_ms(policy: &AutomationPolicy, consecutive_errors: i32) -> i64 {
    let index = usize::try_from(consecutive_errors.saturating_sub(1)).unwrap_or(0);
    policy
        .retry_backoff_ms
        .get(index)
        .or_else(|| policy.retry_backoff_ms.last())
        .copied()
        .unwrap_or(DEFAULT_RETRY_BACKOFF_MS[0])
        .max(1_000)
}

pub(super) fn is_due(job: &AutomationJob, now: i64) -> bool {
    job.state
        .next_run_at_ms
        .is_some_and(|next_run_at_ms| now >= next_run_at_ms)
}

pub(super) fn trigger_source_for_mode(mode: &str) -> AutomationTriggerSource {
    match mode.trim().to_ascii_lowercase().as_str() {
        "due" => AutomationTriggerSource::Due,
        "host_event" => AutomationTriggerSource::HostEvent,
        "platform_wake" => AutomationTriggerSource::PlatformWake,
        _ => AutomationTriggerSource::Manual,
    }
}

pub(super) fn compute_next_run_at_ms(job: &AutomationJob, now: i64) -> Option<i64> {
    if !job.enabled {
        return None;
    }
    match job.trigger {
        AutomationTrigger::OneShotAt { at_ms, .. } => Some(at_ms),
        AutomationTrigger::LocalTime {
            hour,
            minute,
            ref timezone,
            ref days_of_week,
        } => {
            compute_next_local_time_run_at_ms(hour, minute, timezone, days_of_week.as_deref(), now)
        }
        AutomationTrigger::Interval {
            every_ms,
            anchor_ms,
        } => {
            let every_ms = every_ms.max(1_000);
            let anchor = anchor_ms.unwrap_or(job.created_at).max(0);
            if anchor > now {
                return Some(anchor);
            }
            let elapsed = now.saturating_sub(anchor);
            let slots = elapsed / every_ms + 1;
            Some(anchor + slots * every_ms)
        }
        AutomationTrigger::Manual | AutomationTrigger::HostEvent { .. } => None,
    }
}

fn compute_next_local_time_run_at_ms(
    hour: u8,
    minute: u8,
    timezone: &str,
    days_of_week: Option<&[u8]>,
    now: i64,
) -> Option<i64> {
    if hour > 23 || minute > 59 {
        return None;
    }
    let tz = timezone.parse::<Tz>().ok()?;
    let now_local = Utc.timestamp_millis_opt(now).single()?.with_timezone(&tz);
    let active_days = days_of_week.unwrap_or(&[]);
    for day_offset in 0..=7 {
        let date = now_local.date_naive() + Duration::days(day_offset);
        let weekday = date.weekday().num_days_from_monday() as u8 + 1;
        if !active_days.is_empty() && !active_days.contains(&weekday) {
            continue;
        }
        let naive = date.and_hms_opt(hour as u32, minute as u32, 0)?;
        let candidate = match tz.from_local_datetime(&naive) {
            LocalResult::Single(dt) => Some(dt),
            LocalResult::Ambiguous(a, b) => Some(a.min(b)),
            LocalResult::None => None,
        }?;
        let candidate_ms = candidate.timestamp_millis();
        if candidate_ms > now {
            return Some(candidate_ms);
        }
    }
    None
}

fn final_response(events: &[ChatEvent]) -> Option<String> {
    events.iter().rev().find_map(|event| match event {
        ChatEvent::Response { content } if !content.trim().is_empty() => Some(content.clone()),
        _ => None,
    })
}

fn first_error(events: &[ChatEvent]) -> Option<String> {
    events.iter().find_map(|event| match event {
        ChatEvent::Error { message } => Some(message.clone()),
        _ => None,
    })
}

pub(super) fn new_terminal_run(
    run_id: &str,
    job_id: &str,
    source: AutomationTriggerSource,
    started_at: i64,
    status: AutomationRunStatus,
    summary: Option<String>,
    error: Option<String>,
) -> AutomationRun {
    let completed_at = now_ms();
    AutomationRun {
        run_id: run_id.to_string(),
        job_id: job_id.to_string(),
        status,
        trigger_source: source,
        started_at,
        completed_at: Some(completed_at),
        duration_ms: Some((completed_at - started_at).max(0)),
        session_key: None,
        summary,
        error,
        tool_call_count: 0,
        delivery_status: AutomationDeliveryStatus::NotRequested,
    }
}

#[allow(dead_code)]
fn _silence_chrono() {
    let _ = Utc::now();
}
