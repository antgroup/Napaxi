//! Agent App package and action proposal runtime.
//!
//! Napaxi turns conversation intent into auditable action proposals. The
//! app provider owns confirmation, risk checks, execution, and result
//! trust.
//!
//! Splits across submodules:
//! - [`types`]: public package / action / proposal / trigger structs
//!   and the serde default-value callbacks they reference.
//! - [`signing`]: HMAC-SHA256 proposal and trigger signing + canonical
//!   JSON.
//! - [`persistence`]: filesystem load/save for packages, proposals, and
//!   triggers.

mod persistence;
mod signing;
#[cfg(test)]
mod tests;
mod types;

use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

use chrono::{DateTime, Duration as ChronoDuration, SecondsFormat, Utc};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::agent_definitions::{AgentDefinition, AgentSource, ToolFilter};
use crate::crypto::{constant_time_eq, hmac_sha256_base64_no_pad};
use crate::tool_loop::{InternalToolHandler, InternalToolResult};
use crate::tool_registry::{
    ToolDescriptor, ToolRequestBridge, normalize_parameters_schema, request_host_tool_execution,
};
use crate::types::ChatEvent;

pub use types::{
    ActionProposal, ActionResult, AgentAppActionManifest, AgentAppInstallBinding, AgentAppPackage,
    AgentTriggerRequest,
};

use persistence::{
    list_packages, list_proposal_records, load_package, load_proposal_record, load_trigger_record,
    package_file, persist_proposal, save_package, save_proposal_record, save_trigger_record,
};
use signing::{sign_proposal_if_possible, trigger_signature_payload};
use types::{AgentTriggerRecord, now};

const PACKAGE_DIR: &str = "agent_app_packages";
const PROPOSAL_DIR: &str = "agent_app_action_proposals";
const TRIGGER_DIR: &str = "agent_app_triggers";
const DEFAULT_TIMEOUT_SECONDS: u64 = 600;
const MIN_TIMEOUT_SECONDS: u64 = 30;
const MAX_TIMEOUT_SECONDS: u64 = 24 * 60 * 60;
const DEFAULT_CONFIRMATION_POLICY: &str = "provider_required";
const DEFAULT_RISK: &str = "high";
const ACTION_DISPATCH_TOOL_NAME: &str = "__napaxi_agent_app_action__";
const SIGNATURE_ALGORITHM_HMAC_SHA256_V1: &str = "hmac-sha256-v1";
pub const AGENT_APP_ACTION_TOOL_PREFIX: &str = "app_action_";
pub const AGENT_APP_ACTION_CAPABILITY_ID: &str = "napaxi.tool.agent_app_action";

pub fn is_agent_app_action_tool_name(tool_name: &str) -> bool {
    tool_name.starts_with(AGENT_APP_ACTION_TOOL_PREFIX)
}

pub fn register_package(files_dir: &str, package_json: &str) -> String {
    match serde_json::from_str::<AgentAppPackage>(package_json) {
        Ok(package) => register_package_value(files_dir, package),
        Err(error) => error_json(format!("Invalid agent app package: {error}")),
    }
}

pub fn register_package_handle(handle: i64, package_json: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return error_json("invalid engine handle");
    };
    register_package(&files_dir, package_json)
}

fn register_package_value(files_dir: &str, package: AgentAppPackage) -> String {
    match prepare_package(package) {
        Ok(package) => {
            if !save_package(files_dir, &package) {
                return error_json("Failed to save agent app package");
            }
            let mut definition = AgentDefinition::new(package.display_name.clone(), String::new());
            definition.id = package.agent_id.clone();
            definition.description = package.description.clone();
            definition.provider = String::new();
            definition.model = String::new();
            definition.system_prompt = package.system_prompt.clone();
            definition.tool_filter = ToolFilter::AllTools;
            definition.source = AgentSource::UserCreated;
            let created = super::create_definition_value(files_dir, definition);
            if created.contains(r#""error""#) {
                return created;
            }
            serde_json::to_string(&package)
                .unwrap_or_else(|_| error_json("Failed to serialize package"))
        }
        Err(error) => error_json(error),
    }
}

pub fn get_package_json(files_dir: &str, agent_id: &str) -> String {
    load_package(files_dir, agent_id)
        .and_then(|package| serde_json::to_string(&package).ok())
        .unwrap_or_else(|| "null".to_string())
}

pub fn get_package_json_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "null".to_string();
    };
    get_package_json(&files_dir, agent_id)
}

pub fn list_packages_json(files_dir: &str) -> String {
    serde_json::to_string(&list_packages(files_dir)).unwrap_or_else(|_| "[]".to_string())
}

pub fn list_packages_json_handle(handle: i64) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_packages_json(&files_dir)
}

pub fn delete_package(files_dir: &str, agent_id: &str) -> bool {
    let path = package_file(files_dir, agent_id);
    std::fs::remove_file(path).is_ok()
}

pub fn delete_package_handle(handle: i64, agent_id: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    delete_package(&files_dir, agent_id)
}

pub fn action_tools_and_handler(
    files_dir: &str,
    agent_id: &str,
    bridge: Option<ToolRequestBridge>,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let Some(package) = load_package(files_dir, agent_id) else {
        return (Vec::new(), fallback);
    };
    let descriptors = if bridge.is_some() {
        descriptors_for_package(&package)
    } else {
        Vec::new()
    };
    let files_dir = files_dir.to_string();
    let package = Arc::new(package);
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        let Some(action) = package
            .actions
            .iter()
            .find(|action| action.tool_name == tool_name)
            .cloned()
        else {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        };
        let files_dir = files_dir.clone();
        let package = Arc::clone(&package);
        let bridge = bridge.clone();
        Some(Box::pin(async move {
            execute_action(&files_dir, &package, &action, params, bridge).await
        }))
    });
    (descriptors, Some(handler))
}

async fn execute_action(
    files_dir: &str,
    package: &AgentAppPackage,
    action: &AgentAppActionManifest,
    arguments: Value,
    bridge: Option<ToolRequestBridge>,
) -> Result<InternalToolResult, String> {
    let Some(bridge) = bridge else {
        return Err("agent app action dispatcher is not registered".to_string());
    };
    let proposal = create_proposal(package, action, arguments);
    persist_proposal(files_dir, &proposal)?;
    let handoff_mode = action
        .execution_modes
        .first()
        .cloned()
        .unwrap_or_else(|| "host_dispatcher".to_string());
    let mut events = vec![
        ChatEvent::ActionProposalCreated {
            request_id: proposal.request_id.clone(),
            provider_id: proposal.provider_id.clone(),
            agent_id: proposal.agent_id.clone(),
            action_id: proposal.action_id.clone(),
            tool_name: proposal.tool_name.clone(),
            risk: proposal.risk.clone(),
            expires_at: proposal.expires_at.clone(),
        },
        ChatEvent::ActionHandoffStarted {
            request_id: proposal.request_id.clone(),
            mode: handoff_mode,
        },
        ChatEvent::ActionWaitingForProvider {
            request_id: proposal.request_id.clone(),
            provider_id: proposal.provider_id.clone(),
        },
    ];
    let dispatch_payload = json!({
        "proposal": proposal,
        "action": action,
        "package": {
            "provider_id": package.provider_id,
            "agent_id": package.agent_id,
            "handoff": package.handoff,
            "result": package.result,
            "install_binding": public_install_binding(package.install_binding.as_ref())
        }
    });
    let timeout = Duration::from_secs(
        action
            .timeout_seconds
            .clamp(MIN_TIMEOUT_SECONDS, MAX_TIMEOUT_SECONDS),
    );
    let response =
        request_host_tool_execution(bridge, ACTION_DISPATCH_TOOL_NAME, dispatch_payload, timeout)
            .await;
    let result = match response {
        Ok(raw) => parse_action_result(&proposal.request_id, &raw),
        Err(error) => ActionResult {
            request_id: proposal.request_id.clone(),
            status: if proposal_is_expired(&proposal) {
                "expired".to_string()
            } else {
                "failed".to_string()
            },
            result: Value::Null,
            error: Some(error),
            provider_trace_id: None,
            completed_at: now(),
            signature: None,
        },
    };
    let stored = submit_result(
        files_dir,
        &serde_json::to_string(&result).unwrap_or_default(),
    );
    if stored.contains(r#""error""#) {
        events.push(ChatEvent::ActionFailed {
            request_id: proposal.request_id.clone(),
            message: stored,
        });
    } else if result.status == "succeeded" {
        events.push(ChatEvent::ActionResultReceived {
            request_id: result.request_id.clone(),
            status: result.status.clone(),
            provider_trace_id: result.provider_trace_id.clone(),
        });
    } else if result.status == "expired" {
        events.push(ChatEvent::ActionExpired {
            request_id: result.request_id.clone(),
        });
    } else {
        events.push(ChatEvent::ActionFailed {
            request_id: result.request_id.clone(),
            message: result
                .error
                .clone()
                .unwrap_or_else(|| format!("agent app action ended with status {}", result.status)),
        });
    }
    Ok(InternalToolResult {
        output: action_result_tool_output(&result),
        events,
    })
}

pub fn submit_result(files_dir: &str, result_json: &str) -> String {
    let result = match serde_json::from_str::<ActionResult>(result_json) {
        Ok(result) => result,
        Err(error) => return error_json(format!("Invalid agent app action result: {error}")),
    };
    let Some(mut record) = load_proposal_record(files_dir, &result.request_id) else {
        return error_json("agent app action proposal not found");
    };
    if is_terminal_status(&record.status) {
        return error_json("agent app action proposal already completed");
    }
    if proposal_is_expired(&record.proposal) && result.status == "succeeded" {
        record.status = "expired".to_string();
        record.updated_at = now();
        let _ = save_proposal_record(files_dir, &record);
        return error_json("agent app action proposal expired");
    }
    record.status = result.status.clone();
    record.result = Some(result.clone());
    record.updated_at = result.completed_at.clone();
    if !save_proposal_record(files_dir, &record) {
        return error_json("Failed to save agent app action result");
    }
    serde_json::to_string(&record).unwrap_or_else(|_| error_json("Failed to serialize result"))
}

pub fn submit_result_handle(handle: i64, result_json: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return error_json("invalid engine handle");
    };
    submit_result(&files_dir, result_json)
}

pub fn get_proposal_json(files_dir: &str, request_id: &str) -> String {
    load_proposal_record(files_dir, request_id)
        .and_then(|record| serde_json::to_string(&record).ok())
        .unwrap_or_else(|| "null".to_string())
}

pub fn get_proposal_json_handle(handle: i64, request_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "null".to_string();
    };
    get_proposal_json(&files_dir, request_id)
}

pub fn list_proposals_json(files_dir: &str, agent_id: &str) -> String {
    let mut records = list_proposal_records(files_dir)
        .into_iter()
        .filter(|record| agent_id.trim().is_empty() || record.proposal.agent_id == agent_id)
        .collect::<Vec<_>>();
    records.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    serde_json::to_string(&records).unwrap_or_else(|_| "[]".to_string())
}

pub fn list_proposals_json_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_proposals_json(&files_dir, agent_id)
}

pub fn accept_trigger(files_dir: &str, trigger_json: &str) -> String {
    let trigger = match serde_json::from_str::<AgentTriggerRequest>(trigger_json) {
        Ok(trigger) => trigger,
        Err(error) => return error_json(format!("Invalid agent app trigger: {error}")),
    };
    if trigger.protocol_version < 2 {
        return error_json("agent app trigger protocol v2 is required");
    }
    if trigger.request_id.trim().is_empty()
        || trigger.provider_id.trim().is_empty()
        || trigger.agent_id.trim().is_empty()
        || trigger.message.trim().is_empty()
        || trigger.nonce.trim().is_empty()
        || trigger.idempotency_key.trim().is_empty()
    {
        return error_json("agent app trigger missing required fields");
    }
    if trigger_is_expired(&trigger) {
        return error_json("agent app trigger expired");
    }
    if load_trigger_record(files_dir, &trigger.request_id).is_some() {
        return error_json("agent app trigger already consumed");
    }
    let Some(package) = load_package(files_dir, &trigger.agent_id) else {
        return error_json("triggered agent app package not found");
    };
    if package.provider_id != trigger.provider_id {
        return error_json("agent app trigger provider mismatch");
    }
    let Some(binding) = package.install_binding.as_ref() else {
        return error_json("agent app trigger package has no trusted binding");
    };
    if binding.host_instance_id.trim().is_empty()
        || binding.host_shared_secret.trim().is_empty()
        || binding.host_instance_id != trigger.host_instance_id
    {
        return error_json("agent app trigger is not bound to this host");
    }
    if trigger.signature_algorithm != SIGNATURE_ALGORITHM_HMAC_SHA256_V1
        || trigger
            .signature
            .as_ref()
            .map(|value| value.trim().is_empty())
            .unwrap_or(true)
    {
        return error_json("agent app trigger missing trusted signature fields");
    }
    let expected = hmac_sha256_base64_no_pad(
        binding.host_shared_secret.as_bytes(),
        trigger_signature_payload(&trigger).as_bytes(),
    );
    if !trigger
        .signature
        .as_deref()
        .is_some_and(|sig| constant_time_eq(sig, &expected))
    {
        return error_json("agent app trigger signature is invalid");
    }
    let timestamp = now();
    let record = AgentTriggerRecord {
        trigger,
        status: "accepted".to_string(),
        created_at: timestamp.clone(),
        updated_at: timestamp,
    };
    if !save_trigger_record(files_dir, &record) {
        return error_json("Failed to save agent app trigger");
    }
    serde_json::to_string(&record).unwrap_or_else(|_| error_json("Failed to serialize trigger"))
}

pub fn accept_trigger_handle(handle: i64, trigger_json: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return error_json("invalid engine handle");
    };
    accept_trigger(&files_dir, trigger_json)
}

fn descriptors_for_package(package: &AgentAppPackage) -> Vec<ToolDescriptor> {
    package
        .actions
        .iter()
        .map(|action| ToolDescriptor {
            name: action.tool_name.clone(),
            description: action.description.clone(),
            parameters: action.parameters.clone(),
            effect: crate::tool_registry::ToolEffect::External,
        })
        .collect()
}

fn prepare_package(mut package: AgentAppPackage) -> Result<AgentAppPackage, String> {
    package.provider_id = package.provider_id.trim().to_string();
    package.agent_id = package.agent_id.trim().to_string();
    package.display_name = package.display_name.trim().to_string();
    package.description = package.description.trim().to_string();
    if package.provider_id.is_empty() {
        return Err("agent app package missing provider_id".to_string());
    }
    if package.agent_id.is_empty() {
        return Err("agent app package missing agent_id".to_string());
    }
    if package.display_name.is_empty() {
        return Err("agent app package missing display_name".to_string());
    }
    let mut tool_names = HashSet::new();
    let mut action_ids = HashSet::new();
    for action in &mut package.actions {
        action.action_id = action.action_id.trim().to_string();
        action.tool_name = action.tool_name.trim().to_string();
        action.description = action.description.trim().to_string();
        action.risk = normalize_risk(&action.risk)?;
        action.confirmation_policy = normalize_confirmation_policy(&action.confirmation_policy);
        action.timeout_seconds = action
            .timeout_seconds
            .clamp(MIN_TIMEOUT_SECONDS, MAX_TIMEOUT_SECONDS);
        if action.action_id.is_empty() {
            return Err("agent app action missing action_id".to_string());
        }
        if action.tool_name.is_empty() {
            return Err(format!(
                "agent app action '{}' missing tool_name",
                action.action_id
            ));
        }
        if !is_valid_tool_name(&action.tool_name) {
            return Err(format!(
                "agent app action tool '{}' has invalid name; use letters, numbers, '_', '-', or '.'",
                action.tool_name
            ));
        }
        if !is_agent_app_action_tool_name(&action.tool_name) {
            return Err(format!(
                "agent app action tool '{}' must start with '{}'",
                action.tool_name, AGENT_APP_ACTION_TOOL_PREFIX
            ));
        }
        if action.description.is_empty() {
            return Err(format!(
                "agent app action '{}' missing description",
                action.action_id
            ));
        }
        action.parameters = normalize_parameters_schema(&action.parameters).map_err(|error| {
            format!(
                "agent app action '{}' invalid parameters: {error}",
                action.action_id
            )
        })?;
        if !action_ids.insert(action.action_id.clone()) {
            return Err(format!(
                "duplicate agent app action_id '{}'",
                action.action_id
            ));
        }
        if !tool_names.insert(action.tool_name.clone()) {
            return Err(format!(
                "duplicate agent app action tool_name '{}'",
                action.tool_name
            ));
        }
    }
    let timestamp = now();
    if package.created_at.trim().is_empty() {
        package.created_at = timestamp.clone();
    }
    package.updated_at = timestamp;
    Ok(package)
}

fn create_proposal(
    package: &AgentAppPackage,
    action: &AgentAppActionManifest,
    arguments: Value,
) -> ActionProposal {
    let request_id = Uuid::new_v4().to_string();
    let created_at = Utc::now();
    let expires_at = created_at
        + ChronoDuration::seconds(
            action
                .timeout_seconds
                .clamp(MIN_TIMEOUT_SECONDS, MAX_TIMEOUT_SECONDS) as i64,
        );
    let mut proposal = ActionProposal {
        request_id: request_id.clone(),
        provider_id: package.provider_id.clone(),
        agent_id: package.agent_id.clone(),
        action_id: action.action_id.clone(),
        tool_name: action.tool_name.clone(),
        arguments,
        user_intent_summary: String::new(),
        created_at: created_at.to_rfc3339_opts(SecondsFormat::Millis, true),
        expires_at: expires_at.to_rfc3339_opts(SecondsFormat::Millis, true),
        nonce: Uuid::new_v4().to_string(),
        idempotency_key: request_id,
        callback: json!({
            "type": "napaxi_action_result",
            "request_id_required": true
        }),
        risk: action.risk.clone(),
        confirmation_policy: action.confirmation_policy.clone(),
        host_instance_id: package
            .install_binding
            .as_ref()
            .map(|binding| binding.host_instance_id.clone())
            .unwrap_or_default(),
        signature_algorithm: String::new(),
        signature: None,
    };
    sign_proposal_if_possible(&mut proposal, package.install_binding.as_ref());
    proposal
}

fn parse_action_result(request_id: &str, raw: &str) -> ActionResult {
    if let Ok(mut result) = serde_json::from_str::<ActionResult>(raw) {
        if result.request_id.trim().is_empty() {
            result.request_id = request_id.to_string();
        }
        if result.completed_at.trim().is_empty() {
            result.completed_at = now();
        }
        return result;
    }
    ActionResult {
        request_id: request_id.to_string(),
        status: "succeeded".to_string(),
        result: json!({ "content": raw }),
        error: None,
        provider_trace_id: None,
        completed_at: now(),
        signature: None,
    }
}

fn action_result_tool_output(result: &ActionResult) -> String {
    serde_json::to_string(&json!({
        "request_id": result.request_id,
        "status": result.status,
        "result": result.result,
        "error": result.error,
        "provider_trace_id": result.provider_trace_id,
        "completed_at": result.completed_at,
    }))
    .unwrap_or_else(|_| "{}".to_string())
}

fn public_install_binding(binding: Option<&AgentAppInstallBinding>) -> Value {
    let Some(binding) = binding else {
        return Value::Null;
    };
    json!({
        "platform": binding.platform,
        "app_package_name": binding.app_package_name,
        "activity_name": binding.activity_name,
        "signing_cert_sha256": binding.signing_cert_sha256,
        "installed_at": binding.installed_at,
        "install_request_id": binding.install_request_id,
        "protocol_version": binding.protocol_version,
        "host_package_name": binding.host_package_name,
        "host_signing_cert_sha256": binding.host_signing_cert_sha256,
        "host_instance_id": binding.host_instance_id,
        "ios_bundle_id": binding.ios_bundle_id,
        "ios_team_id": binding.ios_team_id,
        "install_url": binding.install_url,
        "action_url": binding.action_url,
        "universal_link_domain": binding.universal_link_domain,
        "host_bundle_id": binding.host_bundle_id,
        "host_team_id": binding.host_team_id,
        "host_callback_scheme": binding.host_callback_scheme,
        "background_trigger_supported": binding.background_trigger_supported,
        "host_background_trigger_service": binding.host_background_trigger_service
    })
}

fn is_terminal_status(status: &str) -> bool {
    matches!(status, "succeeded" | "failed" | "canceled" | "expired")
}

fn proposal_is_expired(proposal: &ActionProposal) -> bool {
    DateTime::parse_from_rfc3339(&proposal.expires_at)
        .map(|expires_at| Utc::now() > expires_at.with_timezone(&Utc))
        .unwrap_or(false)
}

fn trigger_is_expired(trigger: &AgentTriggerRequest) -> bool {
    DateTime::parse_from_rfc3339(&trigger.expires_at)
        .map(|expires_at| Utc::now() > expires_at.with_timezone(&Utc))
        .unwrap_or(true)
}

fn normalize_risk(value: &str) -> Result<String, String> {
    let risk = value.trim().to_ascii_lowercase();
    match risk.as_str() {
        "low" | "medium" | "high" | "critical" => Ok(risk),
        _ => Err(format!("unsupported agent app action risk '{value}'")),
    }
}

fn normalize_confirmation_policy(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        DEFAULT_CONFIRMATION_POLICY.to_string()
    } else {
        trimmed.to_string()
    }
}

fn is_valid_tool_name(name: &str) -> bool {
    name.chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' || ch == '.')
}

fn error_json(message: impl Into<String>) -> String {
    serde_json::json!({ "error": message.into() }).to_string()
}
