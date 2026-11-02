//! Resolution and status queries over the capability registry.
//!
//! Converts a host-supplied (platform, profile, selection) tuple into either a
//! per-capability status view or an LLM provider route, after running the
//! admission gate.

use serde::Deserialize;

use super::admission::{self, admit_provider};
use super::definitions::{definitions, platform_tool_capability_id};
use super::types::{
    CapabilityActivation, CapabilityDefinition, CapabilityProfile, CapabilitySelection,
    CapabilityStatus, LlmProviderRoute,
};

pub fn definitions_json() -> String {
    serde_json::to_string(&definitions()).unwrap_or_else(|_| "[]".to_string())
}

pub fn status_json(platform: &str, profile_json: &str, selection_json: &str) -> String {
    serde_json::to_string(&status(platform, profile_json, selection_json))
        .unwrap_or_else(|_| "[]".to_string())
}

pub fn status(platform: &str, profile_json: &str, selection_json: &str) -> Vec<CapabilityStatus> {
    let profile = profile_from_json(profile_json);
    let selection = selection_from_json(selection_json);
    let platform = profile.platform.as_deref().unwrap_or(platform);
    definitions()
        .into_iter()
        .map(|definition| status_for_definition(definition, platform, &profile, &selection))
        .collect()
}

pub fn profile_from_json(raw: &str) -> CapabilityProfile {
    parse_json_or_default(raw)
}

pub fn selection_from_json(raw: &str) -> CapabilitySelection {
    parse_json_or_default(raw)
}

pub fn provider_capability_id(provider: &str) -> Option<&'static str> {
    match provider.trim().to_ascii_lowercase().as_str() {
        "openai" => Some("napaxi.llm.openai"),
        "openai_compatible" | "glm" | "zai" | "zhipu" | "bigmodel" | "nearai" => {
            Some("napaxi.llm.openai_compatible")
        }
        "anthropic" => Some("napaxi.llm.anthropic"),
        "gemini" => Some("napaxi.llm.gemini"),
        _ => None,
    }
}

pub fn provider_capability_id_json(provider: &str) -> String {
    provider_capability_id(provider).unwrap_or("").to_string()
}

pub fn agent_engine_capability_id(engine_id: &str) -> Option<&'static str> {
    match normalize_agent_engine_id(engine_id).as_str() {
        "napaxi_core" | "napaxi.agent_engine.napaxi_core" => {
            Some("napaxi.agent_engine.napaxi_core")
        }
        "external_host" | "napaxi.agent_engine.external_host" => {
            Some("napaxi.agent_engine.external_host")
        }
        "codex" | "napaxi.agent_engine.codex" => Some("napaxi.agent_engine.codex"),
        _ => None,
    }
}

pub fn agent_engine_capability_id_json(engine_id: &str) -> String {
    agent_engine_capability_id(engine_id)
        .unwrap_or("")
        .to_string()
}

pub fn normalize_agent_engine_id(engine_id: &str) -> String {
    let trimmed = engine_id.trim();
    if trimmed.is_empty() {
        "napaxi_core".to_string()
    } else {
        trimmed.to_ascii_lowercase()
    }
}

pub fn resolve_llm_provider(provider: &str) -> Result<LlmProviderRoute, String> {
    admit_provider(provider)?;
    match provider.trim().to_ascii_lowercase().as_str() {
        "openai" | "openai_compatible" | "glm" | "zai" | "zhipu" | "bigmodel" | "nearai" => {
            Ok(LlmProviderRoute::OpenAiCompatible)
        }
        "anthropic" => Ok(LlmProviderRoute::Anthropic),
        "gemini" => Ok(LlmProviderRoute::Gemini),
        other => Err(format!("Unsupported mobile LLM provider: {other}")),
    }
}

pub fn resolve_llm_provider_for_config(
    provider: &str,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> Result<LlmProviderRoute, String> {
    let route = resolve_llm_provider(provider)?;
    let capability_id = provider_capability_id(provider)
        .ok_or_else(|| format!("Unsupported mobile LLM provider: {}", provider.trim()))?;
    admission::require_enabled(capability_id, platform, profile, selection)?;
    Ok(route)
}

pub fn require_agent_engine_enabled_for_config(
    engine_id: &str,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> Result<(), String> {
    let capability_id = agent_engine_capability_id(engine_id)
        .ok_or_else(|| format!("Unsupported agent engine: {}", engine_id.trim()))?;
    admission::require_enabled(capability_id, platform, profile, selection)?;
    admission::admit_agent_engine(engine_id)?;
    Ok(())
}

/// Closed set of all local builtin tool names that the runtime advertises as
/// first-party capabilities (idea reference: OpenClaw #190863). Used by the
/// runtime entry to decide when an unrecognized name is a host/custom tool
/// (admitted via the `napaxi.tool.custom_host` fallback) versus an ambiguous
/// request that looks like a local builtin but does not resolve to a stable
/// capability id (rejected). Define as a `&str` slice so the compiler pins the
/// set at build time even though resolution itself is a `match` expression.
#[allow(dead_code)] // consumed by capability tests; kept public for cross-crate assertions.
pub const LOCAL_TOOL_NAMES: &[&str] = &[
    // ask_human / human loop
    "ask_human",
    // memory
    "memory_read",
    "memory_write",
    "memory_append",
    "memory_search",
    "session_recall",
    "profile_read",
    "profile_write",
    // file
    "read_file",
    "apply_patch",
    "write_file",
    "append_file",
    "delete_file",
    "list_files",
    "search_files",
    "import_file",
    // web
    "web_search",
    "web_fetch",
    // http
    "http_request",
    // shell
    "shell",
    "shell_remote",
    // git (host-carried, but capability-scoped to napaxi.tool.git)
    "git",
    "git_status",
    "git_diff",
    "git_apply",
    "git_clone",
    "git_list_branches",
    "git_switch_branch",
    "git_list_remotes",
    "git_set_remote",
    "git_fetch",
    // image
    "image_analyze",
    "image_generate",
    // skill
    "skill_list",
    "skill_search",
    "skill_install",
    "skill_remove",
    "skill_info",
    "review_skill",
    "skill_load",
    // group
    "send_to_group_member",
    "list_group_members",
    // mcp management (local builtin; mcp_<server>_<tool> canonical form)
    "mcp_server_list",
    "mcp_server_add",
    "mcp_server_activate",
    "mcp_server_deactivate",
    "mcp_server_remove",
    "mcp_tool_list",
];

/// Names that previously aliased to a real capability but were never the
/// canonical subject. They are reserved as ambiguous capability-scoped
/// request paths so a host-custom descriptor with one of these names does
/// not silently pick up the aliased capability and is rejected at the
/// runtime entry (used by `tools::loop::runtime::assert_unambiguous_local_capability`).
pub const AMBIGUOUS_LOCAL_TOOL_ALIASES: &[&str] = &["remote_shell"];

pub fn tool_capability_id(tool_name: &str) -> Option<String> {
    if crate::platform_capabilities::is_platform_tool(tool_name) {
        return Some(platform_tool_capability_id(tool_name));
    }
    if crate::agents::agent_app::is_agent_app_action_tool_name(tool_name) {
        return Some(crate::agents::agent_app::AGENT_APP_ACTION_CAPABILITY_ID.to_string());
    }
    if crate::browser_tools::is_browser_tool(tool_name) {
        return Some(crate::browser_tools::BROWSER_CAPABILITY_ID.to_string());
    }
    if crate::a2a::is_a2a_tool_name(tool_name) {
        return Some(crate::a2a::A2A_TOOL_CAPABILITY_ID.to_string());
    }
    match tool_name {
        "ask_human" => Some("napaxi.tool.ask_human".to_string()),
        "memory_read" | "memory_write" | "memory_append" | "memory_search" | "session_recall"
        | "profile_read" | "profile_write" => Some("napaxi.tool.memory".to_string()),
        "read_file" | "apply_patch" | "write_file" | "append_file" | "delete_file"
        | "list_files" | "search_files" | "import_file" => Some("napaxi.tool.file".to_string()),
        "web_search" => Some("napaxi.tool.web_search".to_string()),
        "web_fetch" => Some("napaxi.tool.web_fetch".to_string()),
        "http_request" => Some("napaxi.tool.http".to_string()),
        "shell" => Some("napaxi.tool.shell".to_string()),
        "git" | "git_status" | "git_diff" | "git_apply" | "git_clone" | "git_list_branches"
        | "git_switch_branch" | "git_list_remotes" | "git_set_remote" | "git_fetch" => {
            Some("napaxi.tool.git".to_string())
        }
        // Canonical remote-shell subject. The earlier `remote_shell` alias is
        // intentionally NOT accepted (idea reference: OpenClaw #190863): an
        // ambiguous capability-scoped request path must fail closed at the
        // entry so a host-custom `remote_shell` tool does not silently pick up
        // `napaxi.tool.shell_remote` admission. Callers must use
        // `shell_remote`.
        "shell_remote" => Some("napaxi.tool.shell_remote".to_string()),
        "image_analyze" => Some("napaxi.tool.image_analysis".to_string()),
        "image_generate" => Some("napaxi.tool.image_generation".to_string()),
        "skill_list" | "skill_search" | "skill_install" | "skill_remove" | "skill_info"
        | "review_skill" | "skill_load" => Some("napaxi.tool.skill".to_string()),
        "send_to_group_member" | "list_group_members" => Some("napaxi.tool.group".to_string()),
        // MCP runtime builtin tools follow `mcp_<server>_<tool>` (e.g.
        // `mcp_server_list`, `mcp_tool_list`). A bare `mcp_` prefix with fewer
        // than two non-empty segments after `mcp_` is ambiguous and falls into
        // the `_ => None` branch, where the runtime entry rejects it as an
        // ambiguous mcp capability scope instead of admitting it via the
        // `napaxi.tool.custom_host` fallback.
        name if is_mcp_management_name(name) => Some("napaxi.mcp.runtime".to_string()),
        _ => None,
    }
}

/// Decide whether `name` looks like a canonical MCP management tool name
/// (`mcp_<server>_<tool>` with exactly three underscore-separated segments,
/// each non-empty). Used by [`tool_capability_id`] to scope the `mcp_` prefix
/// down to its canonical shape so a host-custom tool named e.g. `mcp_alone`
/// no longer picks up the `napaxi.mcp.runtime` capability.
pub(crate) fn is_mcp_management_name(name: &str) -> bool {
    let mut segments = name.split('_');
    let first = segments.next();
    let second = segments.next();
    let third = segments.next();
    let has_more = segments.next().is_some();
    matches!(first, Some("mcp"))
        && second.is_some_and(|s| !s.is_empty())
        && third.is_some_and(|s| !s.is_empty())
        && !has_more
}

pub fn tool_capability_id_json(tool_name: &str) -> String {
    tool_capability_id(tool_name).unwrap_or_default()
}

#[allow(dead_code)]
pub fn selection_from_llm_config(config: &crate::types::PlatformLlmConfig) -> CapabilitySelection {
    let mut selection = config.capability_selection.clone();
    if config.context_engine.enabled {
        selection
            .enabled_capabilities
            .push("napaxi.service.context_engine".to_string());
    } else {
        selection
            .disabled_capabilities
            .push("napaxi.service.context_engine".to_string());
    }
    if config
        .image_analysis_model
        .as_deref()
        .is_some_and(|model| !model.trim().is_empty())
    {
        selection
            .enabled_capabilities
            .push("napaxi.tool.image_analysis".to_string());
    }
    if config
        .image_model
        .as_deref()
        .is_some_and(|model| !model.trim().is_empty())
    {
        selection
            .enabled_capabilities
            .push("napaxi.tool.image_generation".to_string());
    }
    if let Some(configs) = config.capability_configs.as_ref() {
        if configs.contains_key("imageAnalysis") {
            selection
                .enabled_capabilities
                .push("napaxi.tool.image_analysis".to_string());
        }
        if configs.contains_key("imageGeneration") {
            selection
                .enabled_capabilities
                .push("napaxi.tool.image_generation".to_string());
        }
    }
    selection.enabled_capabilities.sort();
    selection.enabled_capabilities.dedup();
    selection.disabled_capabilities.sort();
    selection.disabled_capabilities.dedup();
    selection
}

pub(super) fn status_for_definition(
    definition: CapabilityDefinition,
    platform: &str,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
) -> CapabilityStatus {
    let platform_available = platform_matches(&definition, platform);
    let host_available = match definition.activation {
        CapabilityActivation::Host => {
            supports_capability(&profile.supported_capabilities, &definition.id)
        }
        _ => true,
    };
    let disabled_by_profile = supports_capability(&profile.disabled_capabilities, &definition.id);
    let available = platform_available && host_available && !disabled_by_profile;
    let explicitly_enabled = supports_capability(&selection.enabled_capabilities, &definition.id);
    let explicitly_disabled = supports_capability(&selection.disabled_capabilities, &definition.id);
    let enabled =
        available && !explicitly_disabled && (explicitly_enabled || definition.default_enabled);
    let unavailable_reason = if available {
        None
    } else if !platform_available {
        Some(format!(
            "capability {} is not available on platform {}",
            definition.id,
            if platform.trim().is_empty() {
                "unknown"
            } else {
                platform
            }
        ))
    } else if disabled_by_profile {
        Some(format!(
            "capability {} is disabled by host profile",
            definition.id
        ))
    } else if !host_available {
        Some(format!(
            "capability {} requires host support declaration",
            definition.id
        ))
    } else {
        Some(format!("capability {} is unavailable", definition.id))
    };
    CapabilityStatus {
        definition,
        registered: true,
        available,
        enabled,
        unavailable_reason,
    }
}

fn platform_matches(definition: &CapabilityDefinition, platform: &str) -> bool {
    definition.platforms.is_empty()
        || definition.platforms.iter().any(|candidate| {
            candidate == "all" || (!platform.trim().is_empty() && candidate == platform)
        })
}

fn supports_capability(patterns: &[String], id: &str) -> bool {
    patterns.iter().any(|pattern| {
        let pattern = pattern.trim();
        if pattern == "*" || pattern == id {
            return true;
        }
        pattern
            .strip_suffix('*')
            .is_some_and(|prefix| id.starts_with(prefix))
    })
}

fn parse_json_or_default<T>(raw: &str) -> T
where
    T: for<'de> Deserialize<'de> + Default,
{
    if raw.trim().is_empty() {
        return T::default();
    }
    serde_json::from_str(raw).unwrap_or_default()
}
