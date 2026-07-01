//! Public capability domain types — kinds, risk levels, activation modes,
//! definition / profile / selection / status records, and admission DTOs.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityKind {
    AgentEngine,
    LlmProvider,
    Tool,
    PlatformTool,
    Mcp,
    Policy,
    Service,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityRisk {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityActivation {
    Always,
    Config,
    Host,
    Policy,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CapabilityDefinition {
    pub id: String,
    pub kind: CapabilityKind,
    pub version: String,
    #[serde(default)]
    pub platforms: Vec<String>,
    #[serde(default)]
    pub config_schema: Value,
    pub risk: CapabilityRisk,
    #[serde(default)]
    pub requirements: Vec<String>,
    pub default_enabled: bool,
    pub activation: CapabilityActivation,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityProfile {
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default, alias = "supported")]
    pub supported_capabilities: Vec<String>,
    #[serde(default, alias = "disabled")]
    pub disabled_capabilities: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct CapabilitySelection {
    #[serde(default, alias = "enabled")]
    pub enabled_capabilities: Vec<String>,
    #[serde(default, alias = "disabled")]
    pub disabled_capabilities: Vec<String>,
    #[serde(default)]
    pub config: HashMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CapabilityStatus {
    pub definition: CapabilityDefinition,
    pub registered: bool,
    pub available: bool,
    pub enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unavailable_reason: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LlmProviderRoute {
    OpenAiCompatible,
    Anthropic,
    Gemini,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityAdmissionKind {
    AgentEngine,
    Descriptor,
    Invocation,
    Provider,
    /// Admission for a Service-kind capability at the point its entry surface
    /// is invoked (e.g. accepting an A2A peer/deep-link, opening a peer
    /// session, running an automation job). Distinct from `Invocation`, which
    /// gates individual tool calls inside a session.
    Service,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityAdmission {
    pub kind: CapabilityAdmissionKind,
    pub subject: String,
    pub capability_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(dead_code)]
pub enum CapabilityAdmissionDecision {
    Allow,
    Deny(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScenarioActivation {
    Manual,
    IntentRoute,
    HostPolicy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScenarioExecutionPlane {
    Core,
    HostBridge,
    PlatformProvider,
    RemoteWorkspace,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScenarioSettingsContribution {
    pub id: String,
    pub capability_id: String,
    #[serde(default)]
    pub placement: String,
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub schema: Value,
    #[serde(default)]
    pub actions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScenarioUiContribution {
    pub id: String,
    pub capability_id: String,
    #[serde(default)]
    pub placement: String,
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub icon: String,
    pub renderer: String,
    #[serde(default)]
    pub data_sources: Value,
    #[serde(default)]
    pub actions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScenarioPackDefinition {
    pub id: String,
    pub version: String,
    pub label: String,
    pub description: String,
    pub risk: CapabilityRisk,
    pub activation: ScenarioActivation,
    #[serde(default)]
    pub execution_planes: Vec<ScenarioExecutionPlane>,
    #[serde(default)]
    pub required_capabilities: Vec<String>,
    #[serde(default)]
    pub recommended_capabilities: Vec<String>,
    #[serde(default)]
    pub optional_capabilities: Vec<String>,
    #[serde(default)]
    pub ui_surfaces: Vec<String>,
    #[serde(default)]
    pub settings_contributions: Vec<ScenarioSettingsContribution>,
    #[serde(default)]
    pub ui_contributions: Vec<ScenarioUiContribution>,
    #[serde(default)]
    pub memory_scopes: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScenarioPackStatus {
    pub definition: ScenarioPackDefinition,
    pub registered: bool,
    pub available: bool,
    pub enabled: bool,
    #[serde(default)]
    pub missing_required_capabilities: Vec<String>,
    #[serde(default)]
    pub disabled_required_capabilities: Vec<String>,
    #[serde(default)]
    pub unavailable_reasons: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScenarioActivationPlan {
    #[serde(default)]
    pub supported_capabilities: Vec<String>,
    #[serde(default)]
    pub enabled_capabilities: Vec<String>,
    #[serde(default)]
    pub disabled_capabilities: Vec<String>,
    #[serde(default)]
    pub host_required_capabilities: Vec<String>,
    #[serde(default)]
    pub remote_required_capabilities: Vec<String>,
    #[serde(default)]
    pub policy_required_capabilities: Vec<String>,
    #[serde(default)]
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScenarioPackResolution {
    pub status: ScenarioPackStatus,
    pub activation_plan: ScenarioActivationPlan,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScenarioPackInstallResult {
    pub definition: ScenarioPackDefinition,
    pub installed: bool,
    pub replaced: bool,
    #[serde(default)]
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScenarioPackRemovalResult {
    pub scenario_id: String,
    pub removed: bool,
}
