//! File-backed mobile automation jobs and run audit log.
//!
//! Submodules:
//! - [`types`] — public DTOs (jobs, triggers, payloads, runs, policies)
//! - [`store`] — persistence I/O (jobs.json, runs/*.jsonl)
//! - [`runner`] — execution + scheduling (turn dispatch, retry policy)
//! - [`handles`] — engine-handle wrappers used by the bridge layer

use chrono::Utc;
use serde::Serialize;
use serde_json::json;

mod handles;
mod runner;
mod store;
mod types;

#[cfg(test)]
mod tests;

pub use handles::{
    cancel_automation_job_handle, create_automation_job_handle, delete_automation_job_handle,
    get_automation_job_handle, get_next_automation_wake_handle, list_automation_jobs_handle,
    list_automation_runs_handle, record_automation_wake_handle, update_automation_job_handle,
};
pub use runner::run_automation_job_handle;

/// Capability id for the automation service surface. Mirrors the A2A pattern
/// of exposing the capability id as a const so the registry definition and the
/// admission gate share one source of truth.
pub const AUTOMATION_CAPABILITY_ID: &str = "napaxi.service.automation";

pub(super) fn now_ms() -> i64 {
    Utc::now().timestamp_millis()
}

pub(super) fn json_string<T: Serialize>(value: &T) -> String {
    serde_json::to_string(value)
        .unwrap_or_else(|_| error_json("failed to serialize automation json"))
}

pub(super) fn error_json(message: &str) -> String {
    json!({ "error": message }).to_string()
}

pub(super) fn files_dir(handle: i64) -> Option<String> {
    crate::runtime::files_dir_from_handle(handle)
}
