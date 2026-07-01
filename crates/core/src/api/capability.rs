//! Adapter-facing capability registry API.
//!
//! Two layers (mirrors `api::engine` / `api::session`):
//!
//! - **Legacy JSON layer**: `list_capability_definitions_json`,
//!   `list_capability_status_json_handle`, `provider_capability_id`,
//!   `tool_capability_id` — stable for the FRB bridge.
//! - **Typed layer**: `EngineHandle::capability_status()` returns
//!   `Vec<CapabilityStatus>` directly; the free `*_typed` functions and
//!   the new `CapabilityDecision` DTO prepare the ground for Tier-3
//!   admission trace work.

use serde::{Deserialize, Serialize};

use crate::api::engine::EngineHandle;
use crate::error::{CoreError, CoreResult};
use crate::runtime::handle_to_arc;

pub use crate::capabilities::{
    AdmissionDecisionRecord, CapabilityActivation, CapabilityAdmission,
    CapabilityAdmissionDecision, CapabilityAdmissionKind, CapabilityDefinition, CapabilityKind,
    CapabilityPolicyHook, CapabilityProfile, CapabilityRisk, CapabilitySelection, CapabilityStatus,
    GENERAL_SCENARIO_ID, MOBILE_DEVELOPMENT_SCENARIO_ID, PolicyHookGuard, ScenarioActivation,
    ScenarioActivationPlan, ScenarioExecutionPlane, ScenarioPackDefinition,
    ScenarioPackInstallResult, ScenarioPackRemovalResult, ScenarioPackResolution,
    ScenarioPackStatus, clear_admission_decisions, recent_admission_decisions,
    register_policy_hook,
};

/// All registered capability definitions as a JSON array.
pub fn list_capability_definitions_json() -> String {
    crate::capabilities::definitions_json()
}

/// Capability status (registered/available/enabled) for a platform + profile +
/// selection, as a JSON array.
pub fn list_capability_status_json(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
) -> String {
    crate::capabilities::status_json(platform, profile_json, selection_json)
}

/// Capability status resolved from a live engine handle, as a JSON array.
pub fn list_capability_status_json_handle(
    handle: i64,
    profile_json: &str,
    selection_json: &str,
) -> String {
    crate::runtime::capability_status_json_handle(handle, profile_json, selection_json)
}

/// All built-in and installed scenario pack definitions as a JSON array.
pub fn list_scenario_packs_json() -> String {
    crate::capabilities::scenario_packs_json()
}

/// Scenario pack definitions resolved from a live engine handle as JSON.
pub fn list_scenario_packs_json_handle(handle: i64) -> String {
    let Ok(files_dir) = files_dir_from_engine_handle(EngineHandle::new(handle)) else {
        return list_scenario_packs_json();
    };
    crate::capabilities::scenario_packs_json_for_files_dir(&files_dir)
}

/// Install or update a scenario pack for the engine workspace, returning JSON.
pub fn install_scenario_pack_json_handle(handle: i64, pack_json: &str) -> String {
    let Ok(files_dir) = files_dir_from_engine_handle(EngineHandle::new(handle)) else {
        return CoreError::InvalidHandle(handle).to_wire_json();
    };
    crate::capabilities::install_scenario_pack_json(&files_dir, pack_json)
}

/// Remove an installed scenario pack by scenario id, returning JSON.
pub fn remove_scenario_pack_json_handle(handle: i64, scenario_id: &str) -> String {
    let Ok(files_dir) = files_dir_from_engine_handle(EngineHandle::new(handle)) else {
        return CoreError::InvalidHandle(handle).to_wire_json();
    };
    crate::capabilities::remove_scenario_pack_json(&files_dir, scenario_id)
}

/// Scenario activation status for a platform + profile + selection as JSON.
pub fn list_scenario_status_json(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
) -> String {
    crate::capabilities::scenario_status_json(platform, profile_json, selection_json)
}

/// Scenario activation status resolved from a live engine handle as JSON.
pub fn list_scenario_status_json_handle(
    handle: i64,
    profile_json: &str,
    selection_json: &str,
) -> String {
    let Some((files_dir, platform, profile, selection)) =
        capability_context_from_handle(handle, profile_json, selection_json)
    else {
        return "[]".to_string();
    };
    let profile_serialized = serde_json::to_string(&profile).unwrap_or_else(|_| "{}".to_string());
    let selection_serialized =
        serde_json::to_string(&selection).unwrap_or_else(|_| "{}".to_string());
    crate::capabilities::scenario_status_json_for_files_dir(
        &files_dir,
        &platform,
        &profile_serialized,
        &selection_serialized,
    )
}

/// Resolve a scenario pack for a platform + profile + selection as JSON.
pub fn resolve_scenario_json(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> String {
    crate::capabilities::resolve_scenario_json(platform, profile_json, selection_json, scenario_id)
}

/// Resolve a scenario pack from a live engine handle as JSON.
pub fn resolve_scenario_json_handle(
    handle: i64,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> String {
    let Some((files_dir, platform, profile, selection)) =
        capability_context_from_handle(handle, profile_json, selection_json)
    else {
        return r#"{"error":{"code":"invalid_handle","message":"invalid engine handle"}}"#
            .to_string();
    };
    let profile_serialized = serde_json::to_string(&profile).unwrap_or_else(|_| "{}".to_string());
    let selection_serialized =
        serde_json::to_string(&selection).unwrap_or_else(|_| "{}".to_string());
    crate::capabilities::resolve_scenario_json_for_files_dir(
        &files_dir,
        &platform,
        &profile_serialized,
        &selection_serialized,
        scenario_id,
    )
}

/// The capability id routing a given LLM provider, as JSON (`null` if none).
pub fn provider_capability_id(provider: &str) -> String {
    crate::capabilities::provider_capability_id_json(provider)
}

/// The capability id routing a given agent engine, as JSON (`null` if none).
pub fn agent_engine_capability_id(engine_id: &str) -> String {
    crate::capabilities::agent_engine_capability_id_json(engine_id)
}

/// The capability id gating a given tool, as JSON (`null` if none).
pub fn tool_capability_id(tool_name: &str) -> String {
    crate::capabilities::tool_capability_id_json(tool_name)
}

// ---------------------------------------------------------------------------
// Typed layer
// ---------------------------------------------------------------------------

/// Typed counterpart of `list_capability_definitions_json` — returns the
/// registered capability set without a JSON round-trip.
pub fn list_capability_definitions() -> Vec<CapabilityDefinition> {
    crate::capabilities::definitions()
}

/// Typed scenario pack definitions without a JSON round-trip.
pub fn list_scenario_packs() -> Vec<ScenarioPackDefinition> {
    crate::capabilities::scenario_packs()
}

/// Typed scenario activation status for a platform + profile + selection.
pub fn list_scenario_status(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
) -> Vec<ScenarioPackStatus> {
    crate::capabilities::scenario_status(platform, profile_json, selection_json)
}

/// Resolve a typed scenario pack for a platform + profile + selection.
pub fn resolve_scenario(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> Option<ScenarioPackResolution> {
    crate::capabilities::resolve_scenario(platform, profile_json, selection_json, scenario_id)
}

/// Typed counterpart of `provider_capability_id` — `None` when the provider
/// has no registered capability route.
pub fn provider_capability_id_typed(provider: &str) -> Option<&'static str> {
    crate::capabilities::provider_capability_id(provider)
}

/// Typed counterpart for agent engine capability lookup.
#[allow(dead_code)] // Reserved for non-FRB adapters adopting typed capability APIs.
pub fn agent_engine_capability_id_typed(engine_id: &str) -> Option<&'static str> {
    crate::capabilities::agent_engine_capability_id(engine_id)
}

/// Typed counterpart of `tool_capability_id` — `None` when the tool name has
/// no registered capability mapping.
pub fn tool_capability_id_typed(tool_name: &str) -> Option<String> {
    crate::capabilities::tool_capability_id(tool_name)
}

impl EngineHandle {
    /// Resolve capability status against the engine's stored profile and
    /// selection. Blank inputs (`""` / `"{}"`) fall back to the engine's
    /// own profile/selection — matches the legacy `_handle` semantics.
    /// `Err(InvalidHandle)` for stale handles.
    pub fn capability_status(
        self,
        profile_json: &str,
        selection_json: &str,
    ) -> CoreResult<Vec<CapabilityStatus>> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        let profile = if is_blank(profile_json) {
            engine.capability_profile()
        } else {
            crate::capabilities::profile_from_json(profile_json)
        };
        let selection = if is_blank(selection_json) {
            engine.capability_selection()
        } else {
            crate::capabilities::selection_from_json(selection_json)
        };
        let platform = profile
            .platform
            .as_deref()
            .unwrap_or_else(|| engine.platform())
            .to_string();
        let profile_serialized =
            serde_json::to_string(&profile).unwrap_or_else(|_| "{}".to_string());
        let selection_serialized =
            serde_json::to_string(&selection).unwrap_or_else(|_| "{}".to_string());
        Ok(crate::capabilities::status(
            &platform,
            &profile_serialized,
            &selection_serialized,
        ))
    }

    /// Snapshot of this engine's admission decisions for diagnostics / trace
    /// UI (most recent last). Scoped to this engine: admissions produced by
    /// this engine's operations record into its own sink, so two engines on
    /// the same process no longer share one history.
    ///
    /// Admissions that happen outside any engine operation scope (e.g. in a
    /// spawned sub-task that escapes the scope) fall back to the process-global
    /// buffer, readable via `recent_admission_decisions()`.
    ///
    /// `Err(InvalidHandle)` for stale handles.
    pub fn admission_trace(self) -> CoreResult<Vec<AdmissionDecisionRecord>> {
        let engine =
            // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
            unsafe { handle_to_arc(self.raw()) }.ok_or(CoreError::InvalidHandle(self.raw()))?;
        Ok(engine.admission_trace())
    }

    /// Scenario activation status for this engine's workspace/profile.
    pub fn scenario_status(
        self,
        profile_json: &str,
        selection_json: &str,
    ) -> CoreResult<Vec<ScenarioPackStatus>> {
        let (files_dir, platform, profile, selection) =
            capability_context_from_engine_handle(self, profile_json, selection_json)?;
        let profile_serialized =
            serde_json::to_string(&profile).unwrap_or_else(|_| "{}".to_string());
        let selection_serialized =
            serde_json::to_string(&selection).unwrap_or_else(|_| "{}".to_string());
        Ok(crate::capabilities::scenario_status_for_files_dir(
            &files_dir,
            &platform,
            &profile_serialized,
            &selection_serialized,
        ))
    }

    /// Resolve a scenario pack for this engine's workspace/profile.
    pub fn resolve_scenario(
        self,
        profile_json: &str,
        selection_json: &str,
        scenario_id: &str,
    ) -> CoreResult<Option<ScenarioPackResolution>> {
        let (files_dir, platform, profile, selection) =
            capability_context_from_engine_handle(self, profile_json, selection_json)?;
        let profile_serialized =
            serde_json::to_string(&profile).unwrap_or_else(|_| "{}".to_string());
        let selection_serialized =
            serde_json::to_string(&selection).unwrap_or_else(|_| "{}".to_string());
        Ok(crate::capabilities::resolve_scenario_for_files_dir(
            &files_dir,
            &platform,
            &profile_serialized,
            &selection_serialized,
            scenario_id,
        ))
    }

    /// Scenario pack definitions available to this engine.
    pub fn scenario_packs(self) -> CoreResult<Vec<ScenarioPackDefinition>> {
        let files_dir = files_dir_from_engine_handle(self)?;
        Ok(crate::capabilities::scenario_packs_for_files_dir(
            &files_dir,
        ))
    }

    /// Install or update a scenario pack in this engine's workspace.
    pub fn install_scenario_pack(self, pack_json: &str) -> CoreResult<ScenarioPackInstallResult> {
        let files_dir = files_dir_from_engine_handle(self)?;
        crate::capabilities::install_scenario_pack(&files_dir, pack_json)
            .map_err(CoreError::InvalidInput)
    }

    /// Remove an installed scenario pack from this engine's workspace.
    pub fn remove_scenario_pack(self, scenario_id: &str) -> CoreResult<ScenarioPackRemovalResult> {
        let files_dir = files_dir_from_engine_handle(self)?;
        crate::capabilities::remove_scenario_pack(&files_dir, scenario_id)
            .map_err(CoreError::InvalidInput)
    }
}

fn is_blank(raw: &str) -> bool {
    let trimmed = raw.trim();
    trimmed.is_empty() || trimmed == "{}" || trimmed == "null"
}

fn capability_context_from_handle(
    handle: i64,
    profile_json: &str,
    selection_json: &str,
) -> Option<(String, String, CapabilityProfile, CapabilitySelection)> {
    capability_context_from_engine_handle(EngineHandle::new(handle), profile_json, selection_json)
        .ok()
}

fn capability_context_from_engine_handle(
    handle: EngineHandle,
    profile_json: &str,
    selection_json: &str,
) -> CoreResult<(String, String, CapabilityProfile, CapabilitySelection)> {
    let engine =
        // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
        unsafe { handle_to_arc(handle.raw()) }.ok_or(CoreError::InvalidHandle(handle.raw()))?;
    let profile = if is_blank(profile_json) {
        engine.capability_profile()
    } else {
        crate::capabilities::profile_from_json(profile_json)
    };
    let selection = if is_blank(selection_json) {
        engine.capability_selection()
    } else {
        crate::capabilities::selection_from_json(selection_json)
    };
    let platform = profile
        .platform
        .as_deref()
        .unwrap_or_else(|| engine.platform())
        .to_string();
    Ok((engine.files_dir().to_string(), platform, profile, selection))
}

fn files_dir_from_engine_handle(handle: EngineHandle) -> CoreResult<String> {
    let engine =
        // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
        unsafe { handle_to_arc(handle.raw()) }.ok_or(CoreError::InvalidHandle(handle.raw()))?;
    Ok(engine.files_dir().to_string())
}

// ---------------------------------------------------------------------------
// Admission trace DTO (foundation for Tier-3 capability admission work)
// ---------------------------------------------------------------------------

/// Single capability admission decision. Tier-3 will fill this in from the
/// admission chain; for now the type exists so adapters can pin against it
/// and tooling (Demo trace panel) can be built incrementally.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityDecision {
    /// Capability id (e.g. `napaxi.tool.shell`).
    pub capability_id: String,
    /// Which admission gate produced the decision.
    pub kind: CapabilityAdmissionKind,
    /// True when the capability was admitted; false when policy denied it.
    pub allowed: bool,
    /// Short machine-readable reason. Examples: `not_registered`,
    /// `policy_denied`, `not_enabled`, `admitted`.
    pub reason: String,
    /// RFC3339 timestamp of when the decision was recorded.
    pub recorded_at: String,
}

impl CapabilityDecision {
    /// Build an `allowed` decision with reason `"admitted"`.
    pub fn admitted(capability_id: impl Into<String>, kind: CapabilityAdmissionKind) -> Self {
        Self {
            capability_id: capability_id.into(),
            kind,
            allowed: true,
            reason: "admitted".to_string(),
            recorded_at: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// Build a denied decision carrying a machine-readable `reason`.
    pub fn denied(
        capability_id: impl Into<String>,
        kind: CapabilityAdmissionKind,
        reason: impl Into<String>,
    ) -> Self {
        Self {
            capability_id: capability_id.into(),
            kind,
            allowed: false,
            reason: reason.into(),
            recorded_at: chrono::Utc::now().to_rfc3339(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_definitions_match_json_count() {
        let typed = list_capability_definitions();
        let json = list_capability_definitions_json();
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        assert_eq!(typed.len(), parsed.len());
    }

    #[test]
    fn provider_capability_id_typed_returns_none_for_unknown() {
        assert!(provider_capability_id_typed("nonexistent-provider").is_none());
    }

    #[test]
    fn capability_status_rejects_invalid_handle() {
        let err = EngineHandle::new(0).capability_status("", "").unwrap_err();
        assert_eq!(err.code(), "invalid_handle");
    }

    #[test]
    fn capability_decision_admitted_and_denied_are_distinguishable() {
        let ok =
            CapabilityDecision::admitted("napaxi.tool.shell", CapabilityAdmissionKind::Invocation);
        let no = CapabilityDecision::denied(
            "napaxi.tool.shell",
            CapabilityAdmissionKind::Invocation,
            "policy_denied",
        );
        assert!(ok.allowed);
        assert_eq!(ok.reason, "admitted");
        assert!(!no.allowed);
        assert_eq!(no.reason, "policy_denied");
    }

    #[test]
    fn capability_decision_round_trips_through_json() {
        let d = CapabilityDecision::admitted("napaxi.llm.openai", CapabilityAdmissionKind::Provider);
        let s = serde_json::to_string(&d).unwrap();
        let back: CapabilityDecision = serde_json::from_str(&s).unwrap();
        assert_eq!(d, back);
    }

    #[test]
    fn tool_capability_id_typed_known_tools() {
        assert_eq!(
            tool_capability_id_typed("shell").as_deref(),
            Some("napaxi.tool.shell")
        );
        assert_eq!(
            tool_capability_id_typed("web_search").as_deref(),
            Some("napaxi.tool.web_search")
        );
        assert!(tool_capability_id_typed("nonexistent_tool").is_none());
    }

    #[test]
    fn tool_capability_id_json_returns_json_string() {
        let id = tool_capability_id("shell");
        assert!(id.contains("napaxi.tool.shell"), "shell id: {id}");
        let unknown = tool_capability_id("nonexistent_tool");
        assert!(unknown.is_empty() || unknown.contains("null") || unknown == "\"\"");
    }

    #[test]
    fn agent_engine_capability_id_json_and_typed() {
        // Unknown engine ids return an empty/null JSON marker, not a panic.
        let json = agent_engine_capability_id("nonexistent-engine");
        assert!(
            json.is_empty() || json.contains("null") || json == "\"\"",
            "unknown engine json: {json}"
        );
        // Typed variant returns None for unknown ids.
        assert!(agent_engine_capability_id_typed("nonexistent-engine").is_none());
    }

    #[test]
    fn provider_capability_id_json_returns_known_providers() {
        let id = provider_capability_id("openai");
        assert!(id.contains("napaxi.llm.openai"), "openai: {id}");
        let unknown = provider_capability_id("nonexistent");
        assert!(unknown.is_empty() || unknown == "null" || unknown.contains("null"));
    }

    #[test]
    fn list_capability_status_json_returns_json_array() {
        let status = list_capability_status_json("test", "{}", "{}");
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&status)
            .expect("list_capability_status_json should return a valid JSON array");
        assert!(
            !parsed.is_empty(),
            "at least one capability should be defined"
        );
        for entry in &parsed {
            assert!(
                entry.get("definition").is_some(),
                "entry missing 'definition': {entry}"
            );
            assert!(
                entry.get("registered").is_some(),
                "entry missing 'registered': {entry}"
            );
            assert!(
                entry.get("available").is_some(),
                "entry missing 'available': {entry}"
            );
            assert!(
                entry.get("enabled").is_some(),
                "entry missing 'enabled': {entry}"
            );
        }
    }

    fn make_handle() -> (i64, tempfile::TempDir) {
        let temp = tempfile::tempdir().unwrap();
        let config = serde_json::json!({
            "provider": "openai", "api_key": "test", "base_url": null,
            "model": "m", "system_prompt": "", "max_tokens": 128
        })
        .to_string();
        let ctx = serde_json::json!({
            "platform": "test",
            "files_dir": temp.path().to_str().unwrap(),
            "native_library_dir": null
        })
        .to_string();
        let h = crate::runtime::create_engine_handle(&config, &ctx).unwrap();
        (h, temp)
    }

    #[test]
    fn valid_handle_capability_status_returns_vec() {
        let (h, _tmp) = make_handle();
        let statuses = EngineHandle::new(h).capability_status("", "").unwrap();
        assert!(!statuses.is_empty(), "should have registered capabilities");
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn valid_handle_capability_status_with_explicit_profile_and_selection() {
        let (h, _tmp) = make_handle();
        let profile = serde_json::json!({
            "supported_capabilities": ["napaxi.tool.shell"],
            "platform": "test"
        })
        .to_string();
        let selection = serde_json::json!({
            "enabled_capabilities": ["napaxi.tool.shell"]
        })
        .to_string();
        let statuses = EngineHandle::new(h)
            .capability_status(&profile, &selection)
            .unwrap();
        assert!(!statuses.is_empty());
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn valid_handle_admission_trace_returns_vec() {
        let (h, _tmp) = make_handle();
        let trace = EngineHandle::new(h).admission_trace().unwrap();
        // May be empty (no admissions have run), but should not fail.
        let _ = trace;
        crate::runtime::dispose_engine_handle(h);
    }

    #[test]
    fn list_capability_status_json_handle_returns_array_or_error() {
        let result = list_capability_status_json_handle(0, "{}", "{}");
        assert!(
            result.starts_with('[') || result.contains("error"),
            "handle 0: {result}"
        );
    }
}
