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

// ── Exec policy layering ─────────────────────────────────────────────────
//
// Re-implemented from OpenClaw (MIT) design notes (workitem #188833). The
// merge semantics mirror `applyExecPolicyLayer`: an agent-level partial
// override layered on top of a global exec/security/approval policy. No
// OpenClaw source code is ported. See `THIRD-PARTY-LICENSES.md` and
// [`super::definitions::ExecSecurityPolicy`].

use std::collections::HashSet;

use super::definitions::{ExecCeiling, ExecPolicyOverride, ExecSecurityPolicy};

impl ExecSecurityPolicy {
    /// True when no field is explicitly set. Useful for tests that want to
    /// express an agent override touching nothing, and for callers that
    /// want to short-circuit a no-op layering pass.
    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.allowed_tools.is_none()
            && self.denied_tools.is_none()
            && self.approval_mode.is_none()
            && self.security_level.is_none()
            && self.exec_ceiling.is_none()
            && self.provider.is_none()
            && self.model.is_none()
    }
}

/// Layer an agent-level partial override on top of a global
/// exec/security/approval policy.
///
/// Merge semantics (per workitem #188833):
/// - For each field, an explicit agent value wins; a missing (`None`) agent
///   field falls back to the global baseline.
/// - `bypass_strings` is stripped from **both** sources, so the merged
///   decision never carries an escape path regardless of where it was
///   injected.
/// - The new per-provider/model ceiling fields (`provider`, `model`,
///   `exec_ceiling`) are merged by [`apply_exec_ceiling`] at the admission
///   gate against the requested `(provider, model)`, not flattened here —
///   `apply_exec_policy_layer` keeps the legacy exact-match merge for the
///   rest.
///
/// The merged record is logged at `tracing::debug!` rather than routed
/// through [`record_admission_decision`]; the latter is the admission gate
/// trace channel and must not be polluted by policy-layer merging.
#[allow(dead_code)]
pub fn apply_exec_policy_layer(
    global: &ExecSecurityPolicy,
    agent: &ExecPolicyOverride,
) -> ExecSecurityPolicy {
    let merged = ExecSecurityPolicy {
        allowed_tools: agent
            .allowed_tools
            .clone()
            .or_else(|| global.allowed_tools.clone()),
        denied_tools: agent
            .denied_tools
            .clone()
            .or_else(|| global.denied_tools.clone()),
        approval_mode: agent.approval_mode.or(global.approval_mode),
        security_level: agent.security_level.or(global.security_level),
        provider: agent.provider.clone().or_else(|| global.provider.clone()),
        model: agent.model.clone().or_else(|| global.model.clone()),
        exec_ceiling: agent.exec_ceiling.or(global.exec_ceiling),
        // Bypass strings are never honored — strip them from both sources
        // so the merged record is provably escape-free at the call site.
        bypass_strings: None,
    };
    tracing::debug!(
        agent_id = %agent.agent_id,
        allowed_tools = ?merged.allowed_tools,
        denied_tools = ?merged.denied_tools,
        approval_mode = ?merged.approval_mode,
        security_level = ?merged.security_level,
        exec_ceiling = ?merged.exec_ceiling,
        "exec policy layered: agent override merged on top of global baseline"
    );
    merged
}

// ── Per-provider/model exec ceiling (AC-2, DIMA-2026110600120401874) ───────

/// Process-level registry of `(provider, model)` pairs that a reviewer
/// policy hook has explicitly denied (see [`deny_model`]). Mirrors the
/// monotonic-anchor / OnceLock<Mutex<HashSet<...>>> pattern used by
/// [`crate::evolution::store`] and is consumed by `admit_provider` at the
/// admission gate: when a deny record is present for the currently-admitted
/// `(provider, model)` pair, the gate short-circuits with
/// [`crate::error::CapabilityError::Denied`] — but other `(provider, model)`
/// pairs on the same provider are NOT blocked, matching the #193566
/// "reviewer denial only blocks the capped model" requirement.
#[allow(dead_code)] // first wiring; consulted by admit_provider_with_model + tests.
fn model_deny_set() -> &'static Mutex<HashSet<(String, String)>> {
    static DENY: OnceLock<Mutex<HashSet<(String, String)>>> = OnceLock::new();
    DENY.get_or_init(|| Mutex::new(HashSet::new()))
}

/// Record a reviewer denial for a specific `(provider, model)` pair —
/// used by `admit_provider` at the ceiling gate when
/// `ExecCeiling::Deny` resolves for that pair. Subsequent
/// `admit_provider` calls for a matching pair short-circuit; pairs that
/// differ on the model dimension are NOT affected, so a deny on
/// `("openai", "gpt-4.1")` keeps `"openai", "gpt-4o"` admitted.
#[allow(dead_code)] // first wiring; called by future host exec bridge + tests.
pub(crate) fn deny_model(provider: &str, model: &str, reason: &str) {
    if let Ok(mut set) = model_deny_set().lock() {
        set.insert((provider.to_string(), model.to_string()));
    }
    tracing::info!(
        provider = %provider,
        model = %model,
        reason = %reason,
        "exec ceiling: reviewer deny recorded for (provider, model); other models on this provider are unaffected"
    );
}

/// Returns true when a previous [`deny_model`] recorded a reviewer denial
/// for the `(provider, model)` pair.
#[allow(dead_code)] // first wiring; called by admit_provider_with_model + tests.
pub(crate) fn is_model_denied(provider: &str, model: &str) -> bool {
    model_deny_set()
        .lock()
        .map(|set| set.contains(&(provider.to_string(), model.to_string())))
        .unwrap_or(false)
}

/// Clear the in-process model deny set. Tests use this to isolate reviewer
/// denial behavior between cases; production code generally does not need
/// to call it (denials expire only with the engine process).
#[allow(dead_code)] // first wiring; used by tests.
pub(crate) fn clear_model_deny_set() {
    if let Ok(mut set) = model_deny_set().lock() {
        set.clear();
    }
}

/// Resolve the effective exec ceiling for the requested
/// `(provider, model)` by combining the global [`ExecSecurityPolicy`] and
/// the agent-level [`ExecPolicyOverride`] (AC-2, DIMA-2026110600120401874).
///
/// Each layer independently filters against the requested pair:
/// - A layer matches when its `provider` is `None` OR equals the requested
///   provider, AND its `model` is `None` OR equals the requested model
///   (`None` acts as a wildcard).
/// - For each matching layer, the layer's `exec_ceiling` (if `Some`) is
///   folded into the running ceiling via [`ExecCeiling::strictest`]; a
///   layer that matches but has `exec_ceiling = None` does not contribute.
/// - If a layer has `provider` / `model` set to specific values that do
///   NOT match the requested pair, the layer is bypassed (its ceiling
///   does not apply to this request).
///
/// `restrict_only` (miss = deny) semantic: when no layer contributes a
/// ceiling (no global match and no agent match) AND the caller opted into
/// the restrict-only read, the result is [`ExecCeiling::Deny`]; otherwise
/// the merged ceiling defaults to [`ExecCeiling::Full`] (loosest) for
/// the call site to allow the standard admit path.
///
/// The function does NOT mutate any state; reviewers record a denied
/// pair via [`deny_model`] / the admission gate records it themselves
/// once `ExecCeiling::Deny` is returned.
fn layer_matches(
    layer_provider: Option<&str>,
    layer_model: Option<&str>,
    provider: &str,
    model: &str,
) -> bool {
    let provider_match = layer_provider
        .map(|value| value == provider)
        .unwrap_or(true);
    let model_match = layer_model.map(|value| value == model).unwrap_or(true);
    provider_match && model_match
}

#[allow(dead_code)]
pub(crate) fn apply_exec_ceiling(
    global: &ExecSecurityPolicy,
    agent: &ExecPolicyOverride,
    provider: &str,
    model: &str,
    restrict_only: bool,
) -> ExecCeiling {
    let mut ceiling: Option<ExecCeiling> = None;
    if layer_matches(
        global.provider.as_deref(),
        global.model.as_deref(),
        provider,
        model,
    ) && let Some(value) = global.exec_ceiling
    {
        ceiling = Some(match ceiling {
            Some(acc) => acc.strictest(value),
            None => value,
        });
    }
    if layer_matches(
        agent.provider.as_deref(),
        agent.model.as_deref(),
        provider,
        model,
    ) && let Some(value) = agent.exec_ceiling
    {
        ceiling = Some(match ceiling {
            Some(acc) => acc.strictest(value),
            None => value,
        });
    }
    match ceiling {
        Some(value) => value,
        None if restrict_only => ExecCeiling::Deny,
        None => ExecCeiling::Full,
    }
}
