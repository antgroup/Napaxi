//! Admission decision recording.
//!
//! Every [`super::admission::admit_typed`] call records one
//! [`AdmissionDecisionRecord`]. Recording is routed to the **current engine's
//! sink** when one is active (set via [`with_admission_sink`] at the engine's
//! operation boundary), and otherwise falls back to a process-global ring
//! buffer. This gives each engine its own admission trace
//! (`EngineHandle::admission_trace`) while keeping a safe global fallback for
//! admissions that happen outside any engine scope (e.g. spawned sub-tasks).
//! Both buffers are capped at [`ADMISSION_DECISION_BUFFER_CAP`].

use std::collections::VecDeque;
use std::future::Future;
use std::sync::{Arc, Mutex, OnceLock};

use serde::{Deserialize, Serialize};

use super::types::CapabilityAdmissionKind;

pub(crate) const ADMISSION_DECISION_BUFFER_CAP: usize = 100;

/// A bounded ring buffer of admission outcomes. Each engine owns one (its
/// per-engine trace); a process-global one is the fallback sink.
pub(crate) type AdmissionSink = Arc<Mutex<VecDeque<AdmissionDecisionRecord>>>;

/// Create a fresh, empty admission sink for an engine to own.
pub(crate) fn new_admission_sink() -> AdmissionSink {
    Arc::new(Mutex::new(VecDeque::with_capacity(
        ADMISSION_DECISION_BUFFER_CAP,
    )))
}

tokio::task_local! {
    /// The admission sink for the engine operation currently executing on this
    /// task. Set by [`with_admission_sink`]; read by [`record_admission_decision`].
    static CURRENT_ADMISSION_SINK: AdmissionSink;
}

/// Run `fut` with `sink` as the active admission sink: every admission decision
/// recorded while the future is polled lands in `sink` instead of the global
/// buffer. Used at engine operation boundaries so each engine's
/// `admission_trace()` reflects only its own decisions.
pub(crate) fn with_admission_sink<F>(
    sink: AdmissionSink,
    fut: F,
) -> tokio::task::futures::TaskLocalFuture<AdmissionSink, F>
where
    F: Future,
{
    CURRENT_ADMISSION_SINK.scope(sink, fut)
}

/// Snapshot of a specific engine's sink (most recent last).
pub(crate) fn sink_snapshot(sink: &AdmissionSink) -> Vec<AdmissionDecisionRecord> {
    sink.lock()
        .map(|buf| buf.iter().cloned().collect())
        .unwrap_or_default()
}

fn push_bounded(buf: &mut VecDeque<AdmissionDecisionRecord>, decision: AdmissionDecisionRecord) {
    if buf.len() >= ADMISSION_DECISION_BUFFER_CAP {
        buf.pop_front();
    }
    buf.push_back(decision);
}

/// One admission outcome captured by `admit_typed`. Adapter-visible through
/// `api::capability::recent_admission_decisions`. Fields are intentionally
/// flat so the type can serialize over the FRB bridge.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AdmissionDecisionRecord {
    /// Capability id the decision applied to. Falls back to the subject name
    /// when the gate could not resolve a capability id.
    pub capability_id: String,
    /// Which admission gate produced the decision.
    pub kind: CapabilityAdmissionKind,
    /// Tool name / provider name the gate was asked about.
    pub subject: String,
    /// True for Allow, false for Deny.
    pub allowed: bool,
    /// Short reason. `"admitted"` for Allow, hook-supplied string for Deny.
    pub reason: String,
    /// RFC3339 timestamp.
    pub recorded_at: String,
}

impl AdmissionDecisionRecord {
    pub(super) fn allow(capability_id: &str, kind: CapabilityAdmissionKind, subject: &str) -> Self {
        Self {
            capability_id: capability_id.to_string(),
            kind,
            subject: subject.to_string(),
            allowed: true,
            reason: "admitted".to_string(),
            recorded_at: chrono::Utc::now().to_rfc3339(),
        }
    }

    pub(super) fn deny(
        capability_id: &str,
        kind: CapabilityAdmissionKind,
        subject: &str,
        reason: &str,
    ) -> Self {
        Self {
            capability_id: capability_id.to_string(),
            kind,
            subject: subject.to_string(),
            allowed: false,
            reason: reason.to_string(),
            recorded_at: chrono::Utc::now().to_rfc3339(),
        }
    }
}

fn global_admission_decisions() -> &'static Mutex<VecDeque<AdmissionDecisionRecord>> {
    static BUF: OnceLock<Mutex<VecDeque<AdmissionDecisionRecord>>> = OnceLock::new();
    BUF.get_or_init(|| Mutex::new(VecDeque::with_capacity(ADMISSION_DECISION_BUFFER_CAP)))
}

pub(super) fn record_admission_decision(decision: AdmissionDecisionRecord) {
    // Route to the current engine's sink if one is active for this task;
    // otherwise fall back to the process-global buffer.
    let recorded = CURRENT_ADMISSION_SINK
        .try_with(|sink| {
            if let Ok(mut buf) = sink.lock() {
                push_bounded(&mut buf, decision.clone());
            }
        })
        .is_ok();
    if recorded {
        return;
    }
    if let Ok(mut buf) = global_admission_decisions().lock() {
        push_bounded(&mut buf, decision);
    }
}

/// Snapshot of recent **global-fallback** admission decisions (most recent
/// last). Per-engine decisions live in that engine's sink and are read via
/// `EngineHandle::admission_trace`. Bounded at `ADMISSION_DECISION_BUFFER_CAP`.
pub fn recent_admission_decisions() -> Vec<AdmissionDecisionRecord> {
    global_admission_decisions()
        .lock()
        .map(|buf| buf.iter().cloned().collect())
        .unwrap_or_default()
}

/// Clear the global-fallback admission decision buffer. Tests use this to
/// isolate observations; adapter code generally should not need to call it.
pub fn clear_admission_decisions() {
    if let Ok(mut buf) = global_admission_decisions().lock() {
        buf.clear();
    }
}
