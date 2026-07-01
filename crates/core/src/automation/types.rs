//! Public DTOs for automation jobs and runs.

use serde::{Deserialize, Serialize};

pub(super) const DEFAULT_MAX_RUN_DURATION_MS: i64 = 10 * 60 * 1000;
pub(super) const DEFAULT_RETRY_BACKOFF_MS: &[i64] = &[30_000, 300_000];
pub(super) const RUN_LOG_PAGE_LIMIT: usize = 200;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationStore {
    #[serde(default)]
    pub(super) jobs: Vec<AutomationJob>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutomationJob {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default, alias = "account_id")]
    pub account_id: String,
    #[serde(default, alias = "agent_id")]
    pub agent_id: String,
    pub trigger: AutomationTrigger,
    pub payload: AutomationPayload,
    #[serde(default)]
    pub policy: AutomationPolicy,
    #[serde(default)]
    pub state: AutomationJobState,
    #[serde(default, alias = "created_at")]
    pub created_at: i64,
    #[serde(default, alias = "updated_at")]
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AutomationTrigger {
    OneShotAt {
        #[serde(rename = "atMs", alias = "at_ms")]
        at_ms: i64,
        #[serde(default)]
        timezone: Option<String>,
    },
    LocalTime {
        hour: u8,
        minute: u8,
        timezone: String,
        #[serde(default, rename = "daysOfWeek", alias = "days_of_week")]
        days_of_week: Option<Vec<u8>>,
    },
    Interval {
        #[serde(rename = "everyMs", alias = "every_ms")]
        every_ms: i64,
        #[serde(default, rename = "anchorMs", alias = "anchor_ms")]
        anchor_ms: Option<i64>,
    },
    Manual,
    HostEvent {
        #[serde(alias = "event_type")]
        event_type: String,
        #[serde(default)]
        source: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AutomationPayload {
    SystemEvent {
        text: String,
        #[serde(default, rename = "sessionKey", alias = "session_key")]
        session_key: Option<String>,
        #[serde(default, alias = "wake_mode")]
        wake_mode: AutomationWakeMode,
    },
    AgentTurn {
        message: String,
        #[serde(default, rename = "sessionKey", alias = "session_key")]
        session_key: Option<String>,
        #[serde(default, rename = "sessionMode", alias = "session_mode")]
        session_mode: AutomationSessionMode,
        #[serde(default, rename = "modelProfileId", alias = "model_profile_id")]
        model_profile_id: Option<String>,
        #[serde(default, rename = "maxIterations", alias = "max_iterations")]
        max_iterations: Option<i32>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum AutomationWakeMode {
    #[default]
    NextForegroundOrHostWake,
    Now,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum AutomationSessionMode {
    #[default]
    Isolated,
    Main,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutomationPolicy {
    #[serde(default = "default_true", alias = "requires_user_visible_notification")]
    pub requires_user_visible_notification: bool,
    #[serde(default, alias = "allow_high_risk_tools")]
    pub allow_high_risk_tools: bool,
    #[serde(default = "default_max_run_duration_ms", alias = "max_run_duration_ms")]
    pub max_run_duration_ms: i64,
    #[serde(default = "default_max_retries", alias = "max_retries")]
    pub max_retries: i32,
    #[serde(default = "default_retry_backoff_ms", alias = "retry_backoff_ms")]
    pub retry_backoff_ms: Vec<i64>,
    #[serde(default, alias = "delete_after_success")]
    pub delete_after_success: Option<bool>,
}

impl Default for AutomationPolicy {
    fn default() -> Self {
        Self {
            requires_user_visible_notification: true,
            allow_high_risk_tools: false,
            max_run_duration_ms: DEFAULT_MAX_RUN_DURATION_MS,
            max_retries: 2,
            retry_backoff_ms: DEFAULT_RETRY_BACKOFF_MS.to_vec(),
            delete_after_success: None,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutomationJobState {
    #[serde(default, alias = "next_run_at_ms")]
    pub next_run_at_ms: Option<i64>,
    #[serde(default, alias = "last_run_at_ms")]
    pub last_run_at_ms: Option<i64>,
    #[serde(default, alias = "last_run_status")]
    pub last_run_status: Option<AutomationRunStatus>,
    #[serde(default, alias = "last_error")]
    pub last_error: Option<String>,
    #[serde(default, alias = "consecutive_errors")]
    pub consecutive_errors: i32,
    #[serde(default, alias = "running_run_id")]
    pub running_run_id: Option<String>,
    #[serde(default, alias = "running_at_ms")]
    pub running_at_ms: Option<i64>,
    #[serde(default, alias = "last_wake_source")]
    pub last_wake_source: Option<String>,
    #[serde(default, alias = "last_wake_at_ms")]
    pub last_wake_at_ms: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AutomationRunStatus {
    Queued,
    Running,
    Succeeded,
    Failed,
    Skipped,
    Cancelled,
    Expired,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AutomationTriggerSource {
    Manual,
    Due,
    HostEvent,
    PlatformWake,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AutomationDeliveryStatus {
    NotRequested,
    Notified,
    Failed,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutomationRun {
    pub run_id: String,
    pub job_id: String,
    pub status: AutomationRunStatus,
    pub trigger_source: AutomationTriggerSource,
    pub started_at: i64,
    #[serde(default)]
    pub completed_at: Option<i64>,
    #[serde(default)]
    pub duration_ms: Option<i64>,
    #[serde(default)]
    pub session_key: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub tool_call_count: usize,
    pub delivery_status: AutomationDeliveryStatus,
}

pub(super) fn default_true() -> bool {
    true
}

pub(super) fn default_max_run_duration_ms() -> i64 {
    DEFAULT_MAX_RUN_DURATION_MS
}

pub(super) fn default_max_retries() -> i32 {
    2
}

pub(super) fn default_retry_backoff_ms() -> Vec<i64> {
    DEFAULT_RETRY_BACKOFF_MS.to_vec()
}
