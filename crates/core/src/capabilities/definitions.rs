//! Built-in capability definitions table — the canonical list of capabilities
//! the SDK ships with, plus the helpers that synthesise per-platform-tool
//! capability records from the platform tool registry.

use serde_json::{Value, json};

use super::types::{CapabilityActivation, CapabilityDefinition, CapabilityKind, CapabilityRisk};

const VERSION_1: &str = "1";

pub fn definitions() -> Vec<CapabilityDefinition> {
    let mut definitions = vec![
        tool_definition(
            "napaxi.agent_engine.napaxi_core",
            CapabilityKind::AgentEngine,
            CapabilityRisk::Medium,
            CapabilityActivation::Always,
            true,
            &["core_agent_loop"],
        ),
        tool_definition(
            "napaxi.agent_engine.external_host",
            CapabilityKind::AgentEngine,
            CapabilityRisk::High,
            CapabilityActivation::Host,
            false,
            &["host_agent_engine_executor", "tool_broker_policy_boundary"],
        ),
        llm_provider_definition(
            "napaxi.llm.openai",
            "openai",
            &["api_key", "model"],
            json!({
                "type": "object",
                "properties": {
                    "api_key": {"type": "string"},
                    "model": {"type": "string"},
                    "base_url": {"type": "string"}
                },
                "required": ["api_key", "model"]
            }),
        ),
        llm_provider_definition(
            "napaxi.llm.openai_compatible",
            "openai_compatible",
            &["api_key", "model", "chat_completions_endpoint"],
            json!({
                "type": "object",
                "properties": {
                    "api_key": {"type": "string"},
                    "model": {"type": "string"},
                    "base_url": {"type": "string"},
                    "aliases": {"type": "array", "items": {"type": "string"}}
                },
                "required": ["api_key", "model"]
            }),
        ),
        llm_provider_definition(
            "napaxi.llm.anthropic",
            "anthropic",
            &["api_key", "model"],
            json!({
                "type": "object",
                "properties": {
                    "api_key": {"type": "string"},
                    "model": {"type": "string"}
                },
                "required": ["api_key", "model"]
            }),
        ),
        llm_provider_definition(
            "napaxi.llm.gemini",
            "gemini",
            &["api_key", "model"],
            json!({
                "type": "object",
                "properties": {
                    "api_key": {"type": "string"},
                    "model": {"type": "string"}
                },
                "required": ["api_key", "model"]
            }),
        ),
        tool_definition(
            "napaxi.tool.custom_host",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Host,
            false,
            &["host_tool_dispatcher"],
        ),
        tool_definition(
            crate::agents::agent_app::AGENT_APP_ACTION_CAPABILITY_ID,
            CapabilityKind::Tool,
            CapabilityRisk::High,
            CapabilityActivation::Host,
            false,
            &[
                "host_action_dispatcher",
                "provider_confirmation_for_high_risk",
            ],
        ),
        tool_definition(
            "napaxi.tool.ask_human",
            CapabilityKind::Tool,
            CapabilityRisk::Low,
            CapabilityActivation::Always,
            true,
            &["session_context"],
        ),
        tool_definition(
            "napaxi.tool.memory",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Always,
            true,
            &["workspace_scope"],
        ),
        tool_definition(
            "napaxi.tool.file",
            CapabilityKind::Tool,
            CapabilityRisk::High,
            CapabilityActivation::Always,
            true,
            &["workspace_scope"],
        ),
        tool_definition(
            "napaxi.tool.web_search",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Always,
            true,
            &["network"],
        ),
        tool_definition(
            "napaxi.tool.web_fetch",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Always,
            true,
            &["network"],
        ),
        tool_definition(
            "napaxi.tool.http",
            CapabilityKind::Tool,
            CapabilityRisk::High,
            CapabilityActivation::Always,
            true,
            &["network", "approval_for_mutation"],
        ),
        tool_definition(
            crate::browser_tools::BROWSER_CAPABILITY_ID,
            CapabilityKind::Tool,
            CapabilityRisk::High,
            CapabilityActivation::Host,
            false,
            &[
                "host_browser_controller",
                "app_isolated_webview",
                "user_visible_session",
                "approval_for_high_risk",
            ],
        ),
        tool_definition(
            "napaxi.tool.shell",
            CapabilityKind::Tool,
            CapabilityRisk::Critical,
            CapabilityActivation::Always,
            true,
            &["platform_sandbox", "approval_for_high_risk"],
        ),
        tool_definition(
            "napaxi.tool.image_analysis",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Config,
            false,
            &["imageAnalysis provider config"],
        ),
        tool_definition(
            "napaxi.tool.image_generation",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Config,
            false,
            &["imageGeneration provider config"],
        ),
        tool_definition(
            "napaxi.tool.skill",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Always,
            true,
            &["skill_registry"],
        ),
        tool_definition(
            "napaxi.tool.group",
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Always,
            true,
            &["group_state"],
        ),
        tool_definition(
            crate::a2a::A2A_TOOL_CAPABILITY_ID,
            CapabilityKind::Tool,
            CapabilityRisk::Medium,
            CapabilityActivation::Host,
            false,
            &[
                "local_peer_transport",
                "trusted_peer_registry",
                "host_tool_dispatcher",
                "user_visible_remote_task_policy",
            ],
        ),
        tool_definition(
            "napaxi.mcp.runtime",
            CapabilityKind::Mcp,
            CapabilityRisk::High,
            CapabilityActivation::Config,
            true,
            &["mcp_server_registry", "network"],
        ),
        tool_definition(
            crate::context::CONTEXT_ENGINE_CAPABILITY_ID,
            CapabilityKind::Service,
            CapabilityRisk::Low,
            CapabilityActivation::Config,
            false,
            &["session_context", "prompt_compaction"],
        ),
        tool_definition(
            crate::automation::AUTOMATION_CAPABILITY_ID,
            CapabilityKind::Service,
            CapabilityRisk::Medium,
            CapabilityActivation::Host,
            false,
            &[
                "host_scheduler",
                "notification_permission",
                "background_execution_optional",
            ],
        ),
        tool_definition(
            "napaxi.service.scenario_registry",
            CapabilityKind::Service,
            CapabilityRisk::Low,
            CapabilityActivation::Always,
            true,
            &["capability_resolver", "scenario_pack_registry"],
        ),
        tool_definition(
            "napaxi.service.developer_workbench",
            CapabilityKind::Service,
            CapabilityRisk::High,
            CapabilityActivation::Host,
            false,
            &[
                "thread_manager",
                "run_ledger",
                "tool_approval_flow",
                "audit_timeline",
            ],
        ),
        tool_definition(
            "napaxi.service.remote_workspace",
            CapabilityKind::Service,
            CapabilityRisk::High,
            CapabilityActivation::Host,
            false,
            &[
                "remote_workspace_connection",
                "workspace_scope",
                "network",
                "user_visible_session",
            ],
        ),
        tool_definition(
            "napaxi.tool.git",
            CapabilityKind::Tool,
            CapabilityRisk::High,
            CapabilityActivation::Host,
            false,
            &[
                "workspace_scope",
                "remote_workspace_or_host_workspace",
                "approval_for_mutation",
                "audit_log",
            ],
        ),
        tool_definition(
            "napaxi.tool.shell_remote",
            CapabilityKind::Tool,
            CapabilityRisk::Critical,
            CapabilityActivation::Host,
            false,
            &[
                "remote_workspace_sandbox",
                "approval_for_high_risk",
                "network",
                "audit_log",
            ],
        ),
        tool_definition(
            crate::a2a::A2A_DEEPLINK_CAPABILITY_ID,
            CapabilityKind::Service,
            CapabilityRisk::Medium,
            CapabilityActivation::Host,
            false,
            &[
                "deep_link_ingress",
                "user_confirmation_for_untrusted_peer",
                "host_url_callback",
            ],
        ),
        tool_definition(
            crate::a2a::A2A_LOCAL_PEER_CAPABILITY_ID,
            CapabilityKind::Service,
            CapabilityRisk::Medium,
            CapabilityActivation::Host,
            false,
            &[
                "local_network_permission",
                "peer_discovery",
                "peer_transport",
                "user_confirmation_for_remote_task",
            ],
        ),
        tool_definition(
            crate::channel::CHANNEL_IM_CAPABILITY_ID,
            CapabilityKind::Service,
            CapabilityRisk::Medium,
            CapabilityActivation::Host,
            false,
            &[
                "host_channel_adapter",
                "channel_identity_policy",
                "reply_route_dispatcher",
            ],
        ),
        tool_definition(
            crate::channel::CHANNEL_DEVICE_CAPABILITY_ID,
            CapabilityKind::Service,
            CapabilityRisk::Medium,
            CapabilityActivation::Host,
            false,
            &[
                "host_device_channel_adapter",
                "nearby_device_permission",
                "microphone_permission_optional",
                "audio_output_optional",
                "user_visible_device_state",
                "reply_route_dispatcher",
            ],
        ),
        tool_definition(
            "napaxi.policy.runtime_gate",
            CapabilityKind::Policy,
            CapabilityRisk::Critical,
            CapabilityActivation::Policy,
            true,
            &[
                "descriptor_admission",
                "invocation_admission",
                "provider_admission",
            ],
        ),
        tool_definition(
            "napaxi.policy.approval",
            CapabilityKind::Policy,
            CapabilityRisk::High,
            CapabilityActivation::Host,
            false,
            &[
                "host_approval_ui",
                "user_confirmation",
                "permission_audit",
                "revocation_flow",
            ],
        ),
    ];
    definitions.extend(platform_tool_definitions());
    definitions
}

fn llm_provider_definition(
    id: &str,
    _provider: &str,
    requirements: &[&str],
    config_schema: Value,
) -> CapabilityDefinition {
    CapabilityDefinition {
        id: id.to_string(),
        kind: CapabilityKind::LlmProvider,
        version: VERSION_1.to_string(),
        platforms: vec!["all".to_string()],
        config_schema,
        risk: CapabilityRisk::Medium,
        requirements: requirements.iter().map(|item| item.to_string()).collect(),
        default_enabled: true,
        activation: CapabilityActivation::Config,
    }
}

fn tool_definition(
    id: &str,
    kind: CapabilityKind,
    risk: CapabilityRisk,
    activation: CapabilityActivation,
    default_enabled: bool,
    requirements: &[&str],
) -> CapabilityDefinition {
    CapabilityDefinition {
        id: id.to_string(),
        kind,
        version: VERSION_1.to_string(),
        platforms: vec!["all".to_string()],
        config_schema: empty_schema(),
        risk,
        requirements: requirements.iter().map(|item| item.to_string()).collect(),
        default_enabled,
        activation,
    }
}

fn platform_tool_definitions() -> Vec<CapabilityDefinition> {
    crate::platform_capabilities::platform_tool_descriptors()
        .into_iter()
        .map(|descriptor| {
            let name = descriptor.name;
            CapabilityDefinition {
                id: platform_tool_capability_id(&name),
                kind: CapabilityKind::PlatformTool,
                version: VERSION_1.to_string(),
                platforms: platform_tool_platforms(&name),
                config_schema: descriptor.parameters,
                risk: platform_tool_risk(&name),
                requirements: platform_tool_requirements(&name),
                default_enabled: true,
                activation: CapabilityActivation::Host,
            }
        })
        .collect()
}

pub(crate) fn platform_tool_capability_id(tool_name: &str) -> String {
    format!("napaxi.platform_tool.{tool_name}")
}

fn platform_tool_platforms(tool_name: &str) -> Vec<String> {
    if tool_name == crate::platform_capabilities::INSTALL_APK {
        vec!["android".to_string()]
    } else {
        vec!["android".to_string(), "ios".to_string()]
    }
}

fn platform_tool_risk(tool_name: &str) -> CapabilityRisk {
    match tool_name {
        crate::platform_capabilities::OPEN_URL
        | crate::platform_capabilities::GET_DEVICE_INFO
        | crate::platform_capabilities::GET_CLIPBOARD => CapabilityRisk::Low,
        crate::platform_capabilities::MAKE_CALL
        | crate::platform_capabilities::SEND_SMS
        | crate::platform_capabilities::SET_CLIPBOARD
        | crate::platform_capabilities::SEND_NOTIFICATION
        | crate::platform_capabilities::SET_ALARM => CapabilityRisk::Medium,
        crate::platform_capabilities::INSTALL_APK => CapabilityRisk::Critical,
        _ => CapabilityRisk::High,
    }
}

fn platform_tool_requirements(tool_name: &str) -> Vec<String> {
    let requirements = match tool_name {
        crate::platform_capabilities::GET_LOCATION => &["host_bridge", "location_permission"][..],
        crate::platform_capabilities::GET_CONTACTS => &["host_bridge", "contacts_permission"],
        crate::platform_capabilities::CREATE_CALENDAR_EVENT
        | crate::platform_capabilities::LIST_CALENDAR_EVENTS => {
            &["host_bridge", "calendar_permission"]
        }
        crate::platform_capabilities::TAKE_PHOTO => &["host_bridge", "camera_permission"],
        crate::platform_capabilities::RECORD_AUDIO => &["host_bridge", "microphone_permission"],
        crate::platform_capabilities::SEND_NOTIFICATION
        | crate::platform_capabilities::SET_ALARM => &["host_bridge", "notification_permission"],
        crate::platform_capabilities::INSTALL_APK => &[
            "host_bridge",
            "android_unknown_app_install_permission",
            "user_confirmation",
        ],
        _ => &["host_bridge"],
    };
    requirements.iter().map(|item| item.to_string()).collect()
}

fn empty_schema() -> Value {
    json!({
        "type": "object",
        "properties": {}
    })
}
