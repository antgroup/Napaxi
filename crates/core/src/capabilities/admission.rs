//! Capability admission gates.
//!
//! Entry points:
//! - [`admit_tool_descriptor`] / [`admit_tool_invocation`] / [`admit_provider`]
//!   / [`admit_agent_engine`] — string-error gates used by the runtime.
//! - [`admit_tool_invocation_typed`] — typed-error sibling (test-exercised).
//! - [`admit_service`] — Service-kind capability entry surfaces (A2A,
//!   automation, context engine) gated by capability id.
//! - [`admit_tool_descriptor_for_config`] /
//!   [`admit_tool_invocation_for_config`] — combine an admission gate with
//!   enablement check against a profile/selection.
//!
//! Each gate calls into the shared [`admit_typed`] helper, which runs
//! [`super::hooks`] in order and records the outcome to
//! [`super::decisions`].

use super::decisions::{AdmissionDecisionRecord, record_admission_decision};
use super::definitions::definitions;
use super::hooks::{CapabilityPolicyHook, policy_hooks};
use super::resolve::agent_engine_capability_id;
use super::resolve::{provider_capability_id, status_for_definition, tool_capability_id};
use super::types::{
    CapabilityAdmission, CapabilityAdmissionDecision, CapabilityAdmissionKind, CapabilityProfile,
    CapabilitySelection,
};

pub(crate) fn admit_tool_descriptor(tool_name: &str) -> Result<(), String> {
    admit_typed(CapabilityAdmission {
        kind: CapabilityAdmissionKind::Descriptor,
        subject: tool_name.to_string(),
        capability_id: tool_capability_id(tool_name),
    })
    .map_err(|e| e.to_string())
}

pub(crate) fn admit_tool_invocation(tool_name: &str) -> Result<(), String> {
    admit_typed(CapabilityAdmission {
        kind: CapabilityAdmissionKind::Invocation,
        subject: tool_name.to_string(),
        capability_id: tool_capability_id(tool_name),
    })
    .map_err(|e| e.to_string())
}

pub(crate) fn admit_provider(provider: &str) -> Result<(), String> {
    admit_typed(CapabilityAdmission {
        kind: CapabilityAdmissionKind::Provider,
        subject: provider.to_string(),
        capability_id: provider_capability_id(provider).map(str::to_string),
    })
    .map_err(|e| e.to_string())
}

pub(crate) fn admit_agent_engine(engine_id: &str) -> Result<(), String> {
    admit_typed(CapabilityAdmission {
        kind: CapabilityAdmissionKind::AgentEngine,
        subject: engine_id.to_string(),
        capability_id: agent_engine_capability_id(engine_id).map(str::to_string),
    })
    .map_err(|e| e.to_string())
}

/// Admit a Service-kind capability at its entry surface (A2A peer/deep-link
/// intake, peer-session open, automation job run, ...). Unlike the tool gates,
/// the caller passes the capability id directly because a service is its own
/// subject — there is no tool/provider name to resolve. Runs the same policy
/// hook chain and records the same decision trace as every other gate, so a
/// host policy can deny a whole service surface, not just the tools a task
/// later spins up.
pub(crate) fn admit_service(capability_id: &str, subject: &str) -> crate::error::CoreResult<()> {
    admit_typed(CapabilityAdmission {
        kind: CapabilityAdmissionKind::Service,
        subject: subject.to_string(),
        capability_id: Some(capability_id.to_string()),
    })
}

/// Admit a Service-kind capability AND verify it is enabled for the given
/// profile/selection. `admit_service` alone only runs the policy-hook chain, so
/// on a host that registers no deny hook a Service surface would fail open — but
/// A2A/automation are `default_enabled: false` + Host-activation, so they must
/// stay closed until the host both declares support and enables them. This gate
/// composes the policy chain with `require_enabled`, matching the
/// `admit_*_for_config` pattern used by tool/provider/engine gates.
pub(crate) fn admit_service_for_config(
    capability_id: &str,
    subject: &str,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> crate::error::CoreResult<()> {
    use crate::error::CapabilityError;
    admit_service(capability_id, subject)?;
    require_enabled(capability_id, platform, profile, selection)
        .map_err(|reason| CapabilityError::NotEnabled(reason).into())
}

/// Typed variant of `admit_tool_descriptor`. Returns
/// `CapabilityError::Denied { capability, reason }` on policy deny — adapter
/// code can branch on `code() == "capability_denied"`.
// Staged typed-error API sibling of the string-returning admit_* gates; kept
// ahead of its adapter call sites per the typed-first migration.
#[allow(dead_code)] // staged typed-error admit_* sibling; see admit_tool_descriptor_typed.
pub(crate) fn admit_tool_invocation_typed(tool_name: &str) -> crate::error::CoreResult<()> {
    admit_typed(CapabilityAdmission {
        kind: CapabilityAdmissionKind::Invocation,
        subject: tool_name.to_string(),
        capability_id: tool_capability_id(tool_name),
    })
}

pub(crate) fn admit_tool_descriptor_for_config(
    tool_name: &str,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> Result<(), String> {
    admit_tool_descriptor(tool_name)?;
    require_tool_enabled(tool_name, platform, profile, selection)
}

pub(crate) fn admit_tool_invocation_for_config(
    tool_name: &str,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> Result<(), String> {
    admit_tool_invocation(tool_name)?;
    require_tool_enabled(tool_name, platform, profile, selection)
}

pub(super) fn admit_typed(admission: CapabilityAdmission) -> crate::error::CoreResult<()> {
    use crate::error::{CapabilityError, CoreError};
    let hooks: Vec<CapabilityPolicyHook> = policy_hooks()
        .lock()
        .map_err(|_| CoreError::LockPoisoned("capability.policy_hooks"))?
        .iter()
        .map(|h| h.hook.clone())
        .collect();
    for hook in hooks {
        match hook(&admission) {
            CapabilityAdmissionDecision::Allow => {}
            CapabilityAdmissionDecision::Deny(reason) => {
                let capability_id = admission
                    .capability_id
                    .clone()
                    .unwrap_or_else(|| admission.subject.clone());
                record_admission_decision(AdmissionDecisionRecord::deny(
                    &capability_id,
                    admission.kind,
                    &admission.subject,
                    &reason,
                ));
                return Err(CapabilityError::Denied {
                    capability: capability_id,
                    reason,
                }
                .into());
            }
        }
    }
    let capability_id = admission
        .capability_id
        .clone()
        .unwrap_or_else(|| admission.subject.clone());
    record_admission_decision(AdmissionDecisionRecord::allow(
        &capability_id,
        admission.kind,
        &admission.subject,
    ));
    Ok(())
}

fn require_tool_enabled(
    tool_name: &str,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> Result<(), String> {
    let capability_id =
        tool_capability_id(tool_name).unwrap_or_else(|| "napaxi.tool.custom_host".to_string());
    require_enabled(&capability_id, platform, profile, selection)
}

pub(super) fn require_enabled(
    capability_id: &str,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> Result<(), String> {
    let definition = definitions()
        .into_iter()
        .find(|definition| definition.id == capability_id)
        .ok_or_else(|| format!("Capability {capability_id} is not registered"))?;
    let status = status_for_definition(definition, platform, profile, selection);
    if status.enabled {
        Ok(())
    } else if let Some(reason) = status.unavailable_reason {
        Err(reason)
    } else if !status.available {
        Err(format!("capability {capability_id} is unavailable"))
    } else {
        Err(format!("capability {capability_id} is disabled"))
    }
}
