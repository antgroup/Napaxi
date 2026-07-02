//! Core-owned capability registry and admission hooks.
//!
//! Capabilities are compiled into the SDK and explicitly enabled by runtime
//! config or host declarations. This module is the single place where core
//! names capability contracts, maps legacy entrypoints to those contracts, and
//! reserves the policy gate that future security capability implementations use.
//!
//! Splits across submodules:
//! - [`types`]: capability domain types (kind/risk/activation/definition/profile/selection/status/admission).
//! - [`definitions`]: built-in capability table + platform-tool capability synthesis.
//! - [`resolve`]: status queries, LLM provider routing, tool capability ID lookup.
//! - [`admission`]: descriptor / invocation / provider admission gates.
//! - [`hooks`]: policy hook chain + RAII registration guard.
//! - [`decisions`]: ring-buffer of admission outcomes for observability.

mod admission;
mod decisions;
mod definitions;
mod hooks;
mod resolve;
mod scenarios;
#[cfg(test)]
mod tests;
mod types;

pub use types::{
    CapabilityActivation, CapabilityAdmission, CapabilityAdmissionDecision,
    CapabilityAdmissionKind, CapabilityDefinition, CapabilityKind, CapabilityProfile,
    CapabilityRisk, CapabilitySelection, CapabilityStatus, LlmProviderRoute, ScenarioActivation,
    ScenarioActivationPlan, ScenarioExecutionPlane, ScenarioPackDefinition,
    ScenarioPackInstallResult, ScenarioPackRemovalResult, ScenarioPackResolution,
    ScenarioPackStatus,
};

pub use definitions::definitions;
#[cfg(test)]
pub(crate) use definitions::platform_tool_capability_id;
#[allow(unused_imports)]
pub use resolve::{
    agent_engine_capability_id, agent_engine_capability_id_json, definitions_json,
    normalize_agent_engine_id, profile_from_json, provider_capability_id,
    provider_capability_id_json, require_agent_engine_enabled_for_config, resolve_llm_provider,
    resolve_llm_provider_for_config, selection_from_json, selection_from_llm_config, status,
    status_json, tool_capability_id, tool_capability_id_json,
};
pub use scenarios::{
    GENERAL_SCENARIO_ID, MOBILE_DEVELOPMENT_SCENARIO_ID, install_scenario_pack,
    install_scenario_pack_json, remove_scenario_pack, remove_scenario_pack_json, resolve_scenario,
    resolve_scenario_for_files_dir, resolve_scenario_json, resolve_scenario_json_for_files_dir,
    scenario_packs, scenario_packs_for_files_dir, scenario_packs_json,
    scenario_packs_json_for_files_dir, scenario_status, scenario_status_for_files_dir,
    scenario_status_json, scenario_status_json_for_files_dir,
};

#[cfg(test)]
pub(crate) use admission::admit_tool_invocation_typed;
#[allow(unused_imports)]
pub(crate) use admission::{
    admit_agent_engine, admit_provider, admit_service, admit_service_for_config,
    admit_tool_descriptor, admit_tool_descriptor_for_config, admit_tool_invocation,
    admit_tool_invocation_for_config,
};
#[cfg(test)]
pub(crate) use decisions::ADMISSION_DECISION_BUFFER_CAP;
pub use decisions::{
    AdmissionDecisionRecord, clear_admission_decisions, recent_admission_decisions,
};
pub(crate) use decisions::{AdmissionSink, new_admission_sink, sink_snapshot, with_admission_sink};
pub use hooks::{CapabilityPolicyHook, PolicyHookGuard, register_policy_hook};

#[cfg(test)]
pub(crate) use hooks::set_policy_hooks_for_tests;
