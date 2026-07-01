//! Agent App package and action proposal data types.
//!
//! All `pub struct` types in the agent app surface live here, along with
//! the serde default-value callbacks they reference and the
//! internal `*Record` types that the persistence layer round-trips.

use chrono::{SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::{DEFAULT_CONFIRMATION_POLICY, DEFAULT_RISK, DEFAULT_TIMEOUT_SECONDS};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentAppPackage {
    pub provider_id: String,
    pub agent_id: String,
    pub display_name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub system_prompt: String,
    #[serde(default)]
    pub actions: Vec<AgentAppActionManifest>,
    #[serde(default)]
    pub handoff: Value,
    #[serde(default)]
    pub result: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub install_binding: Option<AgentAppInstallBinding>,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentAppInstallBinding {
    pub platform: String,
    pub app_package_name: String,
    pub activity_name: String,
    pub signing_cert_sha256: String,
    pub installed_at: String,
    pub install_request_id: String,
    pub protocol_version: u32,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_package_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_signing_cert_sha256: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_instance_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_shared_secret: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub ios_bundle_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub ios_team_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub install_url: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub action_url: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub universal_link_domain: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_bundle_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_team_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_callback_scheme: String,
    #[serde(default, skip_serializing_if = "is_false")]
    pub background_trigger_supported: bool,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_background_trigger_service: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentAppActionManifest {
    pub action_id: String,
    pub tool_name: String,
    pub description: String,
    #[serde(default = "default_parameters")]
    pub parameters: Value,
    #[serde(default = "default_result_schema")]
    pub result_schema: Value,
    #[serde(default = "default_risk")]
    pub risk: String,
    #[serde(default = "default_confirmation_policy")]
    pub confirmation_policy: String,
    #[serde(default)]
    pub execution_modes: Vec<String>,
    #[serde(default = "default_timeout_seconds")]
    pub timeout_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ActionProposal {
    pub request_id: String,
    pub provider_id: String,
    pub agent_id: String,
    pub action_id: String,
    pub tool_name: String,
    #[serde(default)]
    pub arguments: Value,
    pub user_intent_summary: String,
    pub created_at: String,
    pub expires_at: String,
    pub nonce: String,
    pub idempotency_key: String,
    #[serde(default)]
    pub callback: Value,
    pub risk: String,
    pub confirmation_policy: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_instance_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub signature_algorithm: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ActionResult {
    pub request_id: String,
    pub status: String,
    #[serde(default)]
    pub result: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider_trace_id: Option<String>,
    pub completed_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentTriggerRequest {
    #[serde(default = "default_trigger_protocol_version")]
    pub protocol_version: u32,
    pub request_id: String,
    pub provider_id: String,
    pub agent_id: String,
    pub message: String,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub event_type: String,
    #[serde(default)]
    pub payload: Value,
    pub created_at: String,
    pub expires_at: String,
    pub nonce: String,
    pub idempotency_key: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host_instance_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub signature_algorithm: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub(super) struct ActionProposalRecord {
    pub(super) proposal: ActionProposal,
    pub(super) status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) result: Option<ActionResult>,
    pub(super) created_at: String,
    pub(super) updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub(super) struct AgentTriggerRecord {
    pub(super) trigger: AgentTriggerRequest,
    pub(super) status: String,
    pub(super) created_at: String,
    pub(super) updated_at: String,
}

fn default_trigger_protocol_version() -> u32 {
    2
}

fn default_parameters() -> Value {
    json!({"type": "object", "properties": {}})
}

fn default_result_schema() -> Value {
    json!({"type": "object"})
}

fn default_risk() -> String {
    DEFAULT_RISK.to_string()
}

fn default_confirmation_policy() -> String {
    DEFAULT_CONFIRMATION_POLICY.to_string()
}

fn default_timeout_seconds() -> u64 {
    DEFAULT_TIMEOUT_SECONDS
}

fn is_false(value: &bool) -> bool {
    !*value
}

pub(super) fn now() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true)
}
