//! File-backed session run ledger and evidence review.

use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::tool_loop::ToolTrace;
use crate::tool_registry::ToolEffect;

const RUNS_DIR: &str = "runs";
const SESSION_RUNS_FILE: &str = "session_runs.jsonl";
const DEFAULT_LOST_AFTER_MS: i64 = 5 * 60 * 1000;
const RETAIN_LIMIT: usize = 500;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionRunStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Stalled,
    Lost,
    Unverified,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum RunEvidenceKind {
    #[default]
    ReplyOnly,
    ToolObserved,
    SideEffectObserved,
    DetachedTaskObserved,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum RunVerification {
    #[default]
    NotRequired,
    Verified,
    Unverified,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RunEvidence {
    pub kind: RunEvidenceKind,
    pub source: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effect: Option<ToolEffect>,
    #[serde(default)]
    pub is_error: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub digest: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionRun {
    pub run_id: String,
    pub status: SessionRunStatus,
    pub agent_id: String,
    pub session_key: String,
    pub thread_id: String,
    pub started_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<i64>,
    #[serde(default)]
    pub evidence_kind: RunEvidenceKind,
    #[serde(default)]
    pub verification: RunVerification,
    #[serde(default)]
    pub tool_call_count: usize,
    #[serde(default)]
    pub evidence: Vec<RunEvidence>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_run_id: Option<String>,
    #[serde(default)]
    pub child_run_ids: Vec<String>,
}

// Session-run ledger API. Currently exercised by this module's tests and
// staged for wiring into the turn-orchestration completion path; not yet
// called from non-test code, so allow dead_code until that lands.
#[allow(dead_code)]
pub fn start_session_run(
    files_dir: &str,
    agent_id: &str,
    session_key: &str,
    thread_id: &str,
) -> SessionRun {
    let run = SessionRun {
        run_id: Uuid::new_v4().to_string(),
        status: SessionRunStatus::Running,
        agent_id: agent_id.to_string(),
        session_key: session_key.to_string(),
        thread_id: thread_id.to_string(),
        started_at: now_ms(),
        completed_at: None,
        duration_ms: None,
        evidence_kind: RunEvidenceKind::ReplyOnly,
        verification: RunVerification::NotRequired,
        tool_call_count: 0,
        evidence: Vec::new(),
        summary: None,
        error: None,
        parent_run_id: None,
        child_run_ids: Vec::new(),
    };
    append_run_snapshot(files_dir, &run);
    run
}

#[allow(dead_code)] // staged session-run ledger API; see `start_session_run`.
pub fn complete_successful_run(
    files_dir: &str,
    mut run: SessionRun,
    content: String,
    tool_call_count: usize,
    trace: &ToolTrace,
) -> SessionRun {
    let evidence = evidence_from_trace(trace);
    let evidence_kind = strongest_evidence_kind(&evidence);
    let side_effect_claim = has_side_effect_completion_claim(&content);
    let verification = if side_effect_claim
        && !matches!(
            evidence_kind,
            RunEvidenceKind::SideEffectObserved | RunEvidenceKind::DetachedTaskObserved
        ) {
        RunVerification::Unverified
    } else if matches!(evidence_kind, RunEvidenceKind::ReplyOnly) {
        RunVerification::NotRequired
    } else {
        RunVerification::Verified
    };
    let status = if matches!(verification, RunVerification::Unverified) {
        SessionRunStatus::Unverified
    } else {
        SessionRunStatus::Succeeded
    };
    finish_run(
        files_dir,
        &mut run,
        status,
        evidence_kind,
        verification,
        evidence,
        Some(content),
        None,
        tool_call_count,
    );
    run
}

pub fn list_session_runs_handle(
    files_dir: &str,
    filter_json: &str,
    limit: i64,
    offset: i64,
) -> String {
    let filter = serde_json::from_str::<serde_json::Value>(filter_json).unwrap_or_default();
    let mut runs = latest_runs(load_session_runs(files_dir));
    runs.retain(|run| run_matches_filter(run, &filter));
    runs.sort_by(|a, b| b.started_at.cmp(&a.started_at));
    let limit = if limit <= 0 {
        100
    } else {
        limit.min(500) as usize
    };
    let offset = offset.max(0) as usize;
    serde_json::to_string(
        &runs
            .into_iter()
            .skip(offset)
            .take(limit)
            .collect::<Vec<_>>(),
    )
    .unwrap_or_else(|_| "[]".to_string())
}

pub fn get_session_run_handle(files_dir: &str, run_id: &str) -> String {
    latest_runs(load_session_runs(files_dir))
        .into_iter()
        .find(|run| run.run_id == run_id)
        .and_then(|run| serde_json::to_string(&run).ok())
        .unwrap_or_else(|| "null".to_string())
}

pub fn active_session_runs_handle(files_dir: &str) -> String {
    serde_json::to_string(
        &latest_runs(load_session_runs(files_dir))
            .into_iter()
            .filter(|run| run.status == SessionRunStatus::Running)
            .collect::<Vec<_>>(),
    )
    .unwrap_or_else(|_| "[]".to_string())
}

pub fn mark_stale_running_runs_lost(files_dir: &str) {
    let now = now_ms();
    let runs = latest_runs(load_session_runs(files_dir));
    for mut run in runs
        .into_iter()
        .filter(|run| run.status == SessionRunStatus::Running)
        .filter(|run| now.saturating_sub(run.started_at) > DEFAULT_LOST_AFTER_MS)
    {
        let evidence_kind = run.evidence_kind;
        let evidence = run.evidence.clone();
        let summary = run.summary.clone();
        let tool_call_count = run.tool_call_count;
        finish_run(
            files_dir,
            &mut run,
            SessionRunStatus::Lost,
            evidence_kind,
            RunVerification::Failed,
            evidence,
            summary,
            Some("session run lost after process interruption".to_string()),
            tool_call_count,
        );
    }
}

fn finish_run(
    files_dir: &str,
    run: &mut SessionRun,
    status: SessionRunStatus,
    evidence_kind: RunEvidenceKind,
    verification: RunVerification,
    evidence: Vec<RunEvidence>,
    summary: Option<String>,
    error: Option<String>,
    tool_call_count: usize,
) {
    let completed_at = now_ms();
    run.status = status;
    run.completed_at = Some(completed_at);
    run.duration_ms = Some(completed_at.saturating_sub(run.started_at));
    run.evidence_kind = evidence_kind;
    run.verification = verification;
    run.evidence = evidence;
    run.summary = summary;
    run.error = error;
    run.tool_call_count = tool_call_count;
    append_run_snapshot(files_dir, run);
}

#[allow(dead_code)] // evidence-review helper for the staged session-run ledger.
fn evidence_from_trace(trace: &ToolTrace) -> Vec<RunEvidence> {
    trace
        .tool_calls
        .iter()
        .map(|call| {
            let is_error = call.error.is_some();
            let kind = evidence_kind_for_effect(call.effect, is_error);
            RunEvidence {
                kind,
                source: call.name.clone(),
                effect: Some(call.effect),
                is_error,
                digest: call
                    .result
                    .as_deref()
                    .or(call.error.as_deref())
                    .map(stable_digest),
            }
        })
        .collect()
}

#[allow(dead_code)] // evidence-review helper for the staged session-run ledger.
fn evidence_kind_for_effect(effect: ToolEffect, is_error: bool) -> RunEvidenceKind {
    match effect {
        ToolEffect::Write if !is_error => RunEvidenceKind::SideEffectObserved,
        ToolEffect::Execute | ToolEffect::Deliver | ToolEffect::External if !is_error => {
            RunEvidenceKind::SideEffectObserved
        }
        ToolEffect::Read | ToolEffect::Write | ToolEffect::Unknown => RunEvidenceKind::ToolObserved,
        ToolEffect::Execute | ToolEffect::Deliver | ToolEffect::External => {
            RunEvidenceKind::ToolObserved
        }
    }
}

#[allow(dead_code)] // evidence-review helper for the staged session-run ledger.
fn strongest_evidence_kind(evidence: &[RunEvidence]) -> RunEvidenceKind {
    if evidence
        .iter()
        .any(|item| item.kind == RunEvidenceKind::DetachedTaskObserved)
    {
        return RunEvidenceKind::DetachedTaskObserved;
    }
    if evidence
        .iter()
        .any(|item| item.kind == RunEvidenceKind::SideEffectObserved)
    {
        return RunEvidenceKind::SideEffectObserved;
    }
    if evidence
        .iter()
        .any(|item| item.kind == RunEvidenceKind::ToolObserved)
    {
        return RunEvidenceKind::ToolObserved;
    }
    RunEvidenceKind::ReplyOnly
}

fn run_matches_filter(run: &SessionRun, filter: &serde_json::Value) -> bool {
    let Some(map) = filter.as_object() else {
        return true;
    };
    if let Some(agent_id) = map
        .get("agentId")
        .or_else(|| map.get("agent_id"))
        .and_then(|value| value.as_str())
        && run.agent_id != agent_id
    {
        return false;
    }
    if let Some(thread_id) = map
        .get("threadId")
        .or_else(|| map.get("thread_id"))
        .and_then(|value| value.as_str())
        && run.thread_id != thread_id
    {
        return false;
    }
    if let Some(status) = map.get("status").and_then(|value| value.as_str())
        && serde_json::to_string(&run.status)
            .ok()
            .map(|encoded| encoded.trim_matches('"').to_string())
            .as_deref()
            != Some(status)
    {
        return false;
    }
    true
}

fn append_run_snapshot(files_dir: &str, run: &SessionRun) {
    let path = session_runs_path(files_dir);
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(
            file,
            "{}",
            serde_json::to_string(run).unwrap_or_else(|_| "{}".to_string())
        );
    }
    maybe_compact_runs_file(&path);
}

fn load_session_runs(files_dir: &str) -> Vec<SessionRun> {
    fs::read_to_string(session_runs_path(files_dir))
        .ok()
        .map(|content| {
            content
                .lines()
                .filter_map(|line| serde_json::from_str::<SessionRun>(line).ok())
                .collect()
        })
        .unwrap_or_default()
}

fn latest_runs(runs: Vec<SessionRun>) -> Vec<SessionRun> {
    let mut by_id: HashMap<String, SessionRun> = HashMap::new();
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

fn maybe_compact_runs_file(path: &Path) {
    let Ok(content) = fs::read_to_string(path) else {
        return;
    };
    let lines: Vec<_> = content.lines().collect();
    if lines.len() <= RETAIN_LIMIT * 2 {
        return;
    }
    let runs = latest_runs(
        lines
            .into_iter()
            .filter_map(|line| serde_json::from_str::<SessionRun>(line).ok())
            .collect(),
    );
    let mut runs = runs;
    runs.sort_by(|a, b| a.started_at.cmp(&b.started_at));
    if runs.len() > RETAIN_LIMIT {
        runs = runs.split_off(runs.len() - RETAIN_LIMIT);
    }
    let compacted = runs
        .into_iter()
        .filter_map(|run| serde_json::to_string(&run).ok())
        .collect::<Vec<_>>()
        .join("\n");
    let _ = fs::write(path, format!("{compacted}\n"));
}

fn session_runs_path(files_dir: &str) -> PathBuf {
    super::domain_dir(files_dir, RUNS_DIR).join(SESSION_RUNS_FILE)
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

#[allow(dead_code)] // evidence-review helper for the staged session-run ledger.
fn stable_digest(value: &str) -> String {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

#[allow(dead_code)] // evidence-review helper for the staged session-run ledger.
fn has_side_effect_completion_claim(content: &str) -> bool {
    let lower = content.to_ascii_lowercase();
    let english = [
        "i modified",
        "i updated",
        "i committed",
        "i pushed",
        "i sent",
        "i deleted",
        "i created",
        "i installed",
        "i ran",
        "i executed",
        "has been modified",
        "has been updated",
        "has been committed",
        "has been pushed",
        "has been sent",
        "has been deleted",
        "has been created",
        "has been installed",
    ];
    if english.iter().any(|needle| lower.contains(needle)) {
        return true;
    }
    let chinese = [
        "已修改",
        "已经修改",
        "改好了",
        "已更新",
        "已经更新",
        "已提交",
        "已经提交",
        "已推送",
        "已经推送",
        "已发送",
        "已经发送",
        "已删除",
        "已经删除",
        "已创建",
        "已经创建",
        "已安装",
        "已经安装",
        "已运行",
        "已经运行",
        "已执行",
        "已经执行",
    ];
    chinese.iter().any(|needle| content.contains(needle))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tool_loop::{ToolTrace, ToolTraceCall};

    #[test]
    fn reply_only_completion_is_not_unverified() {
        let dir = tempfile::tempdir().unwrap();
        let run = start_session_run(dir.path().to_str().unwrap(), "agent", "{}", "thread");
        let run = complete_successful_run(
            dir.path().to_str().unwrap(),
            run,
            "这是一个解释。".to_string(),
            0,
            &ToolTrace::default(),
        );
        assert_eq!(run.status, SessionRunStatus::Succeeded);
        assert_eq!(run.evidence_kind, RunEvidenceKind::ReplyOnly);
        assert_eq!(run.verification, RunVerification::NotRequired);
    }

    #[test]
    fn side_effect_claim_without_side_effect_is_unverified() {
        let dir = tempfile::tempdir().unwrap();
        let run = start_session_run(dir.path().to_str().unwrap(), "agent", "{}", "thread");
        let run = complete_successful_run(
            dir.path().to_str().unwrap(),
            run,
            "已经修改好了。".to_string(),
            0,
            &ToolTrace::default(),
        );
        assert_eq!(run.status, SessionRunStatus::Unverified);
        assert_eq!(run.verification, RunVerification::Unverified);
    }

    #[test]
    fn write_tool_verifies_side_effect_claim() {
        let dir = tempfile::tempdir().unwrap();
        let mut trace = ToolTrace::default();
        trace.tool_calls.push(ToolTraceCall {
            call_id: "call".to_string(),
            name: "write_file".to_string(),
            arguments: "{}".to_string(),
            effect: ToolEffect::Write,
            result: Some("ok".to_string()),
            error: None,
        });
        let run = start_session_run(dir.path().to_str().unwrap(), "agent", "{}", "thread");
        let run = complete_successful_run(
            dir.path().to_str().unwrap(),
            run,
            "已修改。".to_string(),
            1,
            &trace,
        );
        assert_eq!(run.status, SessionRunStatus::Succeeded);
        assert_eq!(run.evidence_kind, RunEvidenceKind::SideEffectObserved);
        assert_eq!(run.verification, RunVerification::Verified);
    }

    #[test]
    fn read_tool_does_not_verify_side_effect_claim() {
        let dir = tempfile::tempdir().unwrap();
        let mut trace = ToolTrace::default();
        trace.tool_calls.push(ToolTraceCall {
            call_id: "call".to_string(),
            name: "read_file".to_string(),
            arguments: "{}".to_string(),
            effect: ToolEffect::Read,
            result: Some("content".to_string()),
            error: None,
        });
        let run = start_session_run(dir.path().to_str().unwrap(), "agent", "{}", "thread");
        let run = complete_successful_run(
            dir.path().to_str().unwrap(),
            run,
            "已修改。".to_string(),
            1,
            &trace,
        );
        assert_eq!(run.status, SessionRunStatus::Unverified);
        assert_eq!(run.evidence_kind, RunEvidenceKind::ToolObserved);
        assert_eq!(run.verification, RunVerification::Unverified);
    }

    #[test]
    fn stale_running_runs_are_marked_lost() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().to_str().unwrap();
        append_run_snapshot(
            files_dir,
            &SessionRun {
                run_id: "run-lost".to_string(),
                status: SessionRunStatus::Running,
                agent_id: "agent".to_string(),
                session_key: "{}".to_string(),
                thread_id: "thread".to_string(),
                started_at: now_ms() - DEFAULT_LOST_AFTER_MS - 1,
                completed_at: None,
                duration_ms: None,
                evidence_kind: RunEvidenceKind::ReplyOnly,
                verification: RunVerification::NotRequired,
                tool_call_count: 0,
                evidence: Vec::new(),
                summary: None,
                error: None,
                parent_run_id: None,
                child_run_ids: Vec::new(),
            },
        );

        mark_stale_running_runs_lost(files_dir);
        let raw = get_session_run_handle(files_dir, "run-lost");
        let run: SessionRun = serde_json::from_str(&raw).unwrap();

        assert_eq!(run.status, SessionRunStatus::Lost);
        assert_eq!(
            run.error.as_deref(),
            Some("session run lost after process interruption")
        );
    }
}
