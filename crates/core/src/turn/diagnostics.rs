use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{
    PromptPlanSummary, TurnLifecycleContext, TurnLifecycleHooks, TurnMode, TurnOutcomeSummary,
    TurnStage,
};

pub(super) const TURN_DIAGNOSTICS_LIMIT: usize = 200;

#[derive(Debug, Clone)]
struct ActiveTurnStage {
    stage: TurnStage,
    started_at: String,
    started_instant: Instant,
    warning: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum TurnDiagnosticStageStatus {
    Completed,
    Warning,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct TurnStageDiagnostic {
    pub(crate) stage: TurnStage,
    pub(crate) status: TurnDiagnosticStageStatus,
    pub(crate) started_at: String,
    pub(crate) completed_at: String,
    pub(crate) duration_ms: u128,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum TurnDiagnosticStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct TurnDiagnosticRecord {
    pub(crate) id: String,
    pub(crate) created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) completed_at: Option<String>,
    pub(crate) status: TurnDiagnosticStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) mode: Option<TurnMode>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) agent_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) thread_id: Option<String>,
    pub(crate) is_group_context: bool,
    pub(crate) stages: Vec<TurnStageDiagnostic>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) prompt: Option<PromptPlanSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) outcome: Option<TurnOutcomeSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) error: Option<String>,
}

#[derive(Debug)]
pub(crate) struct TurnDiagnosticsRecorder {
    files_dir: String,
    record: TurnDiagnosticRecord,
    active_stage: Option<ActiveTurnStage>,
}

impl TurnDiagnosticsRecorder {
    pub(super) fn new(files_dir: &str) -> Self {
        Self {
            files_dir: files_dir.to_string(),
            record: TurnDiagnosticRecord {
                id: Uuid::new_v4().to_string(),
                created_at: now_rfc3339(),
                completed_at: None,
                status: TurnDiagnosticStatus::Running,
                mode: None,
                agent_id: None,
                thread_id: None,
                is_group_context: false,
                stages: Vec::new(),
                prompt: None,
                outcome: None,
                error: None,
            },
            active_stage: None,
        }
    }

    fn sync_context(&mut self, context: &TurnLifecycleContext) {
        self.record.mode = Some(context.mode);
        self.record.agent_id = Some(context.agent_id.clone());
        self.record.thread_id = context.thread_id.clone();
        self.record.is_group_context = context.is_group_context;
    }

    fn finish_active_stage(
        &mut self,
        stage: TurnStage,
        status: TurnDiagnosticStageStatus,
        message: Option<String>,
    ) {
        let completed_at = now_rfc3339();
        let active = self.active_stage.take();
        let (started_at, duration_ms, warning) = match active {
            Some(active) if active.stage == stage => (
                active.started_at,
                active.started_instant.elapsed().as_millis(),
                active.warning,
            ),
            Some(active) => {
                self.record.stages.push(TurnStageDiagnostic {
                    stage: active.stage,
                    status: active
                        .warning
                        .as_ref()
                        .map(|_| TurnDiagnosticStageStatus::Warning)
                        .unwrap_or(TurnDiagnosticStageStatus::Completed),
                    started_at: active.started_at,
                    completed_at: completed_at.clone(),
                    duration_ms: active.started_instant.elapsed().as_millis(),
                    message: active.warning,
                });
                (completed_at.clone(), 0, None::<String>)
            }
            None => (completed_at.clone(), 0, None::<String>),
        };
        let status = if status == TurnDiagnosticStageStatus::Completed && warning.is_some() {
            TurnDiagnosticStageStatus::Warning
        } else {
            status
        };
        self.record.stages.push(TurnStageDiagnostic {
            stage,
            status,
            started_at,
            completed_at,
            duration_ms,
            message: message.or(warning),
        });
    }

    pub(super) fn persist(mut self) {
        if let Some(active) = self.active_stage.take() {
            let completed_at = now_rfc3339();
            self.record.stages.push(TurnStageDiagnostic {
                stage: active.stage,
                status: TurnDiagnosticStageStatus::Failed,
                started_at: active.started_at,
                completed_at,
                duration_ms: active.started_instant.elapsed().as_millis(),
                message: Some("Stage did not complete".to_string()),
            });
            if self.record.status == TurnDiagnosticStatus::Running {
                self.record.status = TurnDiagnosticStatus::Failed;
            }
        }
        if self.record.status == TurnDiagnosticStatus::Running {
            self.record.status = TurnDiagnosticStatus::Succeeded;
        }
        self.record.completed_at = Some(now_rfc3339());
        if let Err(error) = append_turn_diagnostic_record(&self.files_dir, self.record) {
            tracing::warn!(error, "[Turn] Failed to persist turn diagnostic record");
        }
    }
}

impl TurnLifecycleHooks for TurnDiagnosticsRecorder {
    fn stage_started(&mut self, context: &TurnLifecycleContext, stage: TurnStage) {
        self.sync_context(context);
        if let Some(active) = self.active_stage.as_ref() {
            let previous_stage = active.stage;
            self.finish_active_stage(
                previous_stage,
                TurnDiagnosticStageStatus::Failed,
                Some("Previous stage did not complete before next stage started".to_string()),
            );
        }
        self.active_stage = Some(ActiveTurnStage {
            stage,
            started_at: now_rfc3339(),
            started_instant: Instant::now(),
            warning: None,
        });
    }

    fn stage_completed(&mut self, context: &TurnLifecycleContext, stage: TurnStage) {
        self.sync_context(context);
        self.finish_active_stage(stage, TurnDiagnosticStageStatus::Completed, None);
    }

    fn stage_warning(&mut self, context: &TurnLifecycleContext, stage: TurnStage, message: &str) {
        self.sync_context(context);
        if let Some(active) = self.active_stage.as_mut()
            && active.stage == stage
        {
            active.warning = Some(message.to_string());
            return;
        }
        let now = now_rfc3339();
        self.record.stages.push(TurnStageDiagnostic {
            stage,
            status: TurnDiagnosticStageStatus::Warning,
            started_at: now.clone(),
            completed_at: now,
            duration_ms: 0,
            message: Some(message.to_string()),
        });
    }

    fn stage_failed(&mut self, context: &TurnLifecycleContext, stage: TurnStage, message: &str) {
        self.sync_context(context);
        self.finish_active_stage(
            stage,
            TurnDiagnosticStageStatus::Failed,
            Some(message.to_string()),
        );
        self.record.status = if message == "Chat cancelled" {
            TurnDiagnosticStatus::Cancelled
        } else {
            TurnDiagnosticStatus::Failed
        };
        self.record.error = Some(message.to_string());
    }

    fn prompt_prepared(&mut self, context: &TurnLifecycleContext, summary: &PromptPlanSummary) {
        self.sync_context(context);
        self.record.prompt = Some(summary.clone());
    }

    fn turn_completed(&mut self, context: &TurnLifecycleContext, summary: &TurnOutcomeSummary) {
        self.sync_context(context);
        if self.record.status == TurnDiagnosticStatus::Running {
            self.record.status = TurnDiagnosticStatus::Succeeded;
        }
        self.record.outcome = Some(summary.clone());
    }
}

#[allow(dead_code)]
pub(crate) fn list_turn_diagnostics(files_dir: &str, limit: usize) -> Vec<TurnDiagnosticRecord> {
    let mut records = load_turn_diagnostics_store(files_dir);
    if limit > 0 && records.len() > limit {
        records = records.split_off(records.len() - limit);
    }
    records
}

pub(super) fn append_turn_diagnostic_record(
    files_dir: &str,
    record: TurnDiagnosticRecord,
) -> std::result::Result<(), String> {
    let mut records = load_turn_diagnostics_store(files_dir);
    records.push(record);
    if records.len() > TURN_DIAGNOSTICS_LIMIT {
        records = records.split_off(records.len() - TURN_DIAGNOSTICS_LIMIT);
    }
    save_turn_diagnostics_store(files_dir, &records)
}

fn load_turn_diagnostics_store(files_dir: &str) -> Vec<TurnDiagnosticRecord> {
    fs::read_to_string(turn_diagnostics_path(files_dir))
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
        .unwrap_or_default()
}

fn save_turn_diagnostics_store(
    files_dir: &str,
    records: &[TurnDiagnosticRecord],
) -> std::result::Result<(), String> {
    let path = turn_diagnostics_path(files_dir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let content = serde_json::to_string_pretty(records).map_err(|error| error.to_string())?;
    fs::write(path, content).map_err(|error| error.to_string())
}

fn turn_diagnostics_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join("napaxi")
        .join("turn_diagnostics")
        .join("records.json")
}

pub(super) fn now_rfc3339() -> String {
    Utc::now().to_rfc3339()
}
