//! Scenario pack registry over capability contracts.
//!
//! Scenario packs are not native plugins. They describe a governed runtime
//! posture: which capabilities a host must carry, which capabilities a
//! selection should enable, and which execution planes/UI surfaces are expected
//! for that scene.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use super::definitions::definitions as capability_definitions;
use super::resolve::{profile_from_json, selection_from_json, status as capability_status};
use super::types::{
    CapabilityActivation, CapabilityKind, CapabilityProfile, CapabilityRisk, CapabilitySelection,
    CapabilityStatus, ScenarioActivation, ScenarioActivationPlan, ScenarioExecutionPlane,
    ScenarioPackDefinition, ScenarioPackInstallResult, ScenarioPackRemovalResult,
    ScenarioPackResolution, ScenarioPackStatus, ScenarioSettingsContribution,
    ScenarioUiContribution,
};

const VERSION_1: &str = "1";

pub const GENERAL_SCENARIO_ID: &str = "napaxi.scenario.general";
pub const MOBILE_DEVELOPMENT_SCENARIO_ID: &str = "napaxi.scenario.mobile_development";

pub fn scenario_packs() -> Vec<ScenarioPackDefinition> {
    vec![general_scenario(), mobile_development_scenario()]
}

pub fn scenario_packs_json() -> String {
    serde_json::to_string(&scenario_packs()).unwrap_or_else(|_| "[]".to_string())
}

pub fn scenario_packs_for_files_dir(files_dir: &str) -> Vec<ScenarioPackDefinition> {
    merge_scenario_packs(scenario_packs(), installed_scenario_packs(files_dir))
}

pub fn scenario_packs_json_for_files_dir(files_dir: &str) -> String {
    serde_json::to_string(&scenario_packs_for_files_dir(files_dir))
        .unwrap_or_else(|_| "[]".to_string())
}

pub fn scenario_status_json(platform: &str, profile_json: &str, selection_json: &str) -> String {
    serde_json::to_string(&scenario_status(platform, profile_json, selection_json))
        .unwrap_or_else(|_| "[]".to_string())
}

pub fn scenario_status_json_for_files_dir(
    files_dir: &str,
    platform: &str,
    profile_json: &str,
    selection_json: &str,
) -> String {
    serde_json::to_string(&scenario_status_for_files_dir(
        files_dir,
        platform,
        profile_json,
        selection_json,
    ))
    .unwrap_or_else(|_| "[]".to_string())
}

pub fn scenario_status(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
) -> Vec<ScenarioPackStatus> {
    scenario_status_for_packs(scenario_packs(), platform, profile_json, selection_json)
}

pub fn scenario_status_for_files_dir(
    files_dir: &str,
    platform: &str,
    profile_json: &str,
    selection_json: &str,
) -> Vec<ScenarioPackStatus> {
    scenario_status_for_packs(
        scenario_packs_for_files_dir(files_dir),
        platform,
        profile_json,
        selection_json,
    )
}

fn scenario_status_for_packs(
    packs: Vec<ScenarioPackDefinition>,
    platform: &str,
    profile_json: &str,
    selection_json: &str,
) -> Vec<ScenarioPackStatus> {
    let capability_statuses = capability_status(platform, profile_json, selection_json);
    packs
        .into_iter()
        .map(|definition| status_for_scenario(definition, &capability_statuses))
        .collect()
}

pub fn resolve_scenario_json(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> String {
    match resolve_scenario(platform, profile_json, selection_json, scenario_id) {
        Some(resolution) => serde_json::to_string(&resolution).unwrap_or_else(|_| {
            r#"{"error":"scenario resolution serialization failed"}"#.to_string()
        }),
        None => serde_json::json!({
            "error": {
                "code": "unknown_scenario",
                "message": format!("unknown scenario pack: {}", scenario_id.trim())
            }
        })
        .to_string(),
    }
}

pub fn resolve_scenario_json_for_files_dir(
    files_dir: &str,
    platform: &str,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> String {
    match resolve_scenario_for_files_dir(
        files_dir,
        platform,
        profile_json,
        selection_json,
        scenario_id,
    ) {
        Some(resolution) => serde_json::to_string(&resolution).unwrap_or_else(|_| {
            r#"{"error":"scenario resolution serialization failed"}"#.to_string()
        }),
        None => serde_json::json!({
            "error": {
                "code": "unknown_scenario",
                "message": format!("unknown scenario pack: {}", scenario_id.trim())
            }
        })
        .to_string(),
    }
}

pub fn resolve_scenario(
    platform: &str,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> Option<ScenarioPackResolution> {
    resolve_scenario_from_packs(
        scenario_packs(),
        platform,
        profile_json,
        selection_json,
        scenario_id,
    )
}

pub fn resolve_scenario_for_files_dir(
    files_dir: &str,
    platform: &str,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> Option<ScenarioPackResolution> {
    resolve_scenario_from_packs(
        scenario_packs_for_files_dir(files_dir),
        platform,
        profile_json,
        selection_json,
        scenario_id,
    )
}

fn resolve_scenario_from_packs(
    packs: Vec<ScenarioPackDefinition>,
    platform: &str,
    profile_json: &str,
    selection_json: &str,
    scenario_id: &str,
) -> Option<ScenarioPackResolution> {
    let scenario_id = normalize_scenario_id(scenario_id);
    let definition = packs
        .into_iter()
        .find(|definition| definition.id == scenario_id)?;
    let capability_statuses = capability_status(platform, profile_json, selection_json);
    let status = status_for_scenario(definition.clone(), &capability_statuses);
    let profile = profile_from_json(profile_json);
    let selection = selection_from_json(selection_json);
    let activation_plan =
        activation_plan_for_scenario(&definition, &profile, &selection, &capability_statuses);
    Some(ScenarioPackResolution {
        status,
        activation_plan,
    })
}

pub fn install_scenario_pack_json(files_dir: &str, raw_json: &str) -> String {
    match install_scenario_pack(files_dir, raw_json) {
        Ok(result) => serde_json::to_string(&result).unwrap_or_else(|_| {
            r#"{"error":{"code":"serialization_failed","message":"scenario install result serialization failed"}}"#.to_string()
        }),
        Err(message) => serde_json::json!({
            "error": {
                "code": "invalid_scenario_pack",
                "message": message,
            }
        })
        .to_string(),
    }
}

pub fn remove_scenario_pack_json(files_dir: &str, scenario_id: &str) -> String {
    match remove_scenario_pack(files_dir, scenario_id) {
        Ok(result) => serde_json::to_string(&result).unwrap_or_else(|_| {
            r#"{"error":{"code":"serialization_failed","message":"scenario removal result serialization failed"}}"#.to_string()
        }),
        Err(message) => serde_json::json!({
            "error": {
                "code": "invalid_scenario_pack",
                "message": message,
            }
        })
        .to_string(),
    }
}

pub fn install_scenario_pack(
    files_dir: &str,
    raw_json: &str,
) -> Result<ScenarioPackInstallResult, String> {
    let pack = parse_scenario_pack(raw_json)?;
    let (pack, mut warnings) = normalize_installable_pack(pack)?;
    let mut installed = installed_scenario_packs(files_dir);
    let replaced = if let Some(existing) = installed.iter_mut().find(|item| item.id == pack.id) {
        *existing = pack.clone();
        true
    } else {
        installed.push(pack.clone());
        false
    };
    installed.sort_by(|left, right| left.id.cmp(&right.id));
    write_installed_scenario_packs(files_dir, &installed)?;
    warnings.extend(unknown_capability_warnings(&pack));
    sort_dedup(&mut warnings);
    Ok(ScenarioPackInstallResult {
        definition: pack,
        installed: true,
        replaced,
        warnings,
    })
}

pub fn remove_scenario_pack(
    files_dir: &str,
    scenario_id: &str,
) -> Result<ScenarioPackRemovalResult, String> {
    let scenario_id = normalize_scenario_id(scenario_id);
    if scenario_id.trim().is_empty() {
        return Err("scenario id is required".to_string());
    }
    if is_builtin_scenario_id(&scenario_id) {
        return Err(format!("built-in scenario {scenario_id} cannot be removed"));
    }
    let mut installed = installed_scenario_packs(files_dir);
    let before = installed.len();
    installed.retain(|pack| pack.id != scenario_id);
    let removed = installed.len() != before;
    if removed {
        write_installed_scenario_packs(files_dir, &installed)?;
    }
    Ok(ScenarioPackRemovalResult {
        scenario_id,
        removed,
    })
}

fn general_scenario() -> ScenarioPackDefinition {
    ScenarioPackDefinition {
        id: GENERAL_SCENARIO_ID.to_string(),
        version: VERSION_1.to_string(),
        label: "General".to_string(),
        description: "Chat, files, memory, and common skills.".to_string(),
        risk: CapabilityRisk::High,
        activation: ScenarioActivation::Manual,
        execution_planes: vec![
            ScenarioExecutionPlane::Core,
            ScenarioExecutionPlane::HostBridge,
        ],
        required_capabilities: vec![
            "napaxi.service.scenario_registry",
            "napaxi.agent_engine.napaxi_core",
            "napaxi.tool.ask_human",
            "napaxi.tool.memory",
            "napaxi.tool.file",
            "napaxi.policy.runtime_gate",
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        recommended_capabilities: vec![
            "napaxi.tool.web_search",
            "napaxi.tool.web_fetch",
            "napaxi.tool.skill",
            "napaxi.service.context_engine",
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        optional_capabilities: vec![
            "napaxi.tool.custom_host",
            "napaxi.service.automation",
            "napaxi.mcp.runtime",
            crate::a2a::A2A_LOCAL_PEER_CAPABILITY_ID,
            crate::a2a::A2A_DEEPLINK_CAPABILITY_ID,
            crate::a2a::A2A_TOOL_CAPABILITY_ID,
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        ui_surfaces: vec![
            "chat",
            "tool_trace",
            "memory_panel",
            "skill_panel",
            "capability_status",
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        settings_contributions: Vec::new(),
        ui_contributions: Vec::new(),
        memory_scopes: vec!["profile", "workspace", "session"]
            .into_iter()
            .map(str::to_string)
            .collect(),
        tags: vec!["default", "mobile_sdk", "assistant"]
            .into_iter()
            .map(str::to_string)
            .collect(),
    }
}

fn mobile_development_scenario() -> ScenarioPackDefinition {
    ScenarioPackDefinition {
        id: MOBILE_DEVELOPMENT_SCENARIO_ID.to_string(),
        version: VERSION_1.to_string(),
        label: "Developer Workbench".to_string(),
        description: "Android projects, Git, builds, and environment setup.".to_string(),
        risk: CapabilityRisk::Critical,
        activation: ScenarioActivation::HostPolicy,
        execution_planes: vec![
            ScenarioExecutionPlane::Core,
            ScenarioExecutionPlane::HostBridge,
        ],
        required_capabilities: vec![
            "napaxi.service.scenario_registry",
            "napaxi.agent_engine.napaxi_core",
            "napaxi.service.developer_workbench",
            "napaxi.tool.file",
            "napaxi.tool.ask_human",
            "napaxi.tool.git",
            "napaxi.tool.shell_remote",
            "napaxi.policy.approval",
            "napaxi.policy.runtime_gate",
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        recommended_capabilities: vec![
            "napaxi.service.context_engine",
            "napaxi.tool.skill",
            "napaxi.mcp.runtime",
            "napaxi.tool.custom_host",
            crate::browser_tools::BROWSER_CAPABILITY_ID,
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        optional_capabilities: vec![
            "napaxi.service.automation",
            crate::a2a::A2A_LOCAL_PEER_CAPABILITY_ID,
            crate::a2a::A2A_DEEPLINK_CAPABILITY_ID,
            crate::a2a::A2A_TOOL_CAPABILITY_ID,
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        ui_surfaces: vec![
            "chat",
            "workspace_files",
            "diff_view",
            "terminal_panel",
            "tool_approval",
            "task_timeline",
            "run_audit",
        ]
        .into_iter()
        .map(str::to_string)
        .collect(),
        settings_contributions: vec![git_settings_contribution()],
        ui_contributions: vec![
            repo_workbench_ui_contribution(),
            developer_environment_ui_contribution(),
        ],
        memory_scopes: vec!["project", "workspace", "session", "release"]
            .into_iter()
            .map(str::to_string)
            .collect(),
        tags: vec!["developer", "mobile", "workbench"]
            .into_iter()
            .map(str::to_string)
            .collect(),
    }
}

fn developer_environment_ui_contribution() -> ScenarioUiContribution {
    ScenarioUiContribution {
        id: "ui.developer_environment".to_string(),
        capability_id: "napaxi.service.developer_workbench".to_string(),
        placement: "left_menu".to_string(),
        title: "Environment".to_string(),
        description:
            "Inspect and configure the tool list declared by the mobile development build skill."
                .to_string(),
        icon: "terminal".to_string(),
        renderer: "environment".to_string(),
        data_sources: serde_json::json!({
            "tools": "environment.tools",
            "status": "environment.status"
        }),
        actions: vec![
            "install_tool".to_string(),
            "check_tools".to_string(),
            "change_tool_version".to_string(),
            "add_tool".to_string(),
        ],
    }
}

fn repo_workbench_ui_contribution() -> ScenarioUiContribution {
    ScenarioUiContribution {
        id: "ui.repo_workbench".to_string(),
        capability_id: "napaxi.tool.git".to_string(),
        placement: "left_menu".to_string(),
        title: "Projects".to_string(),
        description: "Browse cloned projects, Git status, branches, remotes, changed files, and code files with lazy loading.".to_string(),
        icon: "folder_git".to_string(),
        renderer: "repo_workbench".to_string(),
        data_sources: serde_json::json!({
            "repositories": "git.repositories",
            "status": "git.status",
            "branches": "git.branches",
            "remotes": "git.remotes",
            "changed_files": "git.changed_files",
            "file_children": "workspace.children",
            "file_search": "workspace.file_search"
        }),
        actions: vec![
            "open_repository".to_string(),
            "refresh_status".to_string(),
            "switch_branch".to_string(),
            "fetch_remote".to_string(),
            "set_remote".to_string(),
            "remove_remote".to_string(),
            "open_file".to_string(),
            "search_files".to_string(),
        ],
    }
}

fn git_settings_contribution() -> ScenarioSettingsContribution {
    ScenarioSettingsContribution {
        id: "settings.git".to_string(),
        capability_id: "napaxi.tool.git".to_string(),
        placement: "scenario_settings".to_string(),
        title: "Git".to_string(),
        description:
            "Configure Git commit identity and a default credential for private Git repositories."
                .to_string(),
        schema: serde_json::json!({
            "type": "object",
            "properties": {
                "commit_name": {
                    "type": "string",
                    "title": "Commit name (user.name)",
                    "description": "Written to the sandbox rootfs ~/.gitconfig [user] name; used as the commit author."
                },
                "commit_email": {
                    "type": "string",
                    "title": "Commit email (user.email)",
                    "format": "email",
                    "description": "Written to the sandbox rootfs ~/.gitconfig [user] email; used as the commit author email."
                },
                "server": {
                    "type": "string",
                    "title": "Git host"
                },
                "auth_method": {
                    "type": "string",
                    "title": "Auth method",
                    "enum": ["token", "ssh"],
                    "default": "token"
                },
                "username": {
                    "type": "string",
                    "title": "Username"
                },
                "token": {
                    "type": "secret",
                    "title": "Token"
                }
            },
            "required": ["server", "auth_method", "username"]
        }),
        actions: vec![
            "save".to_string(),
            "test_connection".to_string(),
            "clear_credentials".to_string(),
        ],
    }
}

fn status_for_scenario(
    definition: ScenarioPackDefinition,
    capability_statuses: &[CapabilityStatus],
) -> ScenarioPackStatus {
    let status_by_id = capability_statuses
        .iter()
        .map(|status| (status.definition.id.as_str(), status))
        .collect::<HashMap<_, _>>();
    let mut missing_required_capabilities = Vec::new();
    let mut disabled_required_capabilities = Vec::new();
    let mut unavailable_reasons = Vec::new();

    for capability_id in &definition.required_capabilities {
        match status_by_id.get(capability_id.as_str()) {
            None => missing_required_capabilities.push(capability_id.clone()),
            Some(status) if !status.available => {
                unavailable_reasons.push(status.unavailable_reason.clone().unwrap_or_else(|| {
                    format!("capability {} is unavailable", status.definition.id)
                }));
            }
            Some(status) if !status.enabled => {
                disabled_required_capabilities.push(status.definition.id.clone());
            }
            Some(_) => {}
        }
    }

    sort_dedup(&mut missing_required_capabilities);
    sort_dedup(&mut disabled_required_capabilities);
    sort_dedup(&mut unavailable_reasons);

    let available = missing_required_capabilities.is_empty() && unavailable_reasons.is_empty();
    let enabled = available && disabled_required_capabilities.is_empty();
    ScenarioPackStatus {
        definition,
        registered: true,
        available,
        enabled,
        missing_required_capabilities,
        disabled_required_capabilities,
        unavailable_reasons,
    }
}

fn activation_plan_for_scenario(
    definition: &ScenarioPackDefinition,
    profile: &CapabilityProfile,
    selection: &CapabilitySelection,
    capability_statuses: &[CapabilityStatus],
) -> ScenarioActivationPlan {
    let capability_definitions = capability_definitions()
        .into_iter()
        .map(|definition| (definition.id.clone(), definition))
        .collect::<HashMap<_, _>>();
    let status_by_id = capability_statuses
        .iter()
        .map(|status| (status.definition.id.as_str(), status))
        .collect::<HashMap<_, _>>();

    let mut plan = ScenarioActivationPlan::default();
    let mut requested = definition.required_capabilities.clone();
    requested.extend(definition.recommended_capabilities.clone());
    sort_dedup(&mut requested);

    for capability_id in requested {
        let Some(capability) = capability_definitions.get(&capability_id) else {
            plan.warnings.push(format!(
                "scenario references unknown capability {capability_id}"
            ));
            continue;
        };

        if capability.activation == CapabilityActivation::Host
            && !supports_capability(&profile.supported_capabilities, &capability.id)
        {
            plan.supported_capabilities.push(capability.id.clone());
            plan.host_required_capabilities.push(capability.id.clone());
        }

        if !supports_capability(&selection.enabled_capabilities, &capability.id)
            && !capability.default_enabled
        {
            plan.enabled_capabilities.push(capability.id.clone());
        }

        if supports_capability(&selection.disabled_capabilities, &capability.id)
            || supports_capability(&profile.disabled_capabilities, &capability.id)
        {
            plan.disabled_capabilities.push(capability.id.clone());
        }

        if capability.kind == CapabilityKind::Policy {
            plan.policy_required_capabilities
                .push(capability.id.clone());
        }
        if capability
            .requirements
            .iter()
            .any(|requirement| requirement.contains("remote"))
            || capability.id.contains("remote")
        {
            plan.remote_required_capabilities
                .push(capability.id.clone());
        }

        if let Some(status) = status_by_id.get(capability.id.as_str())
            && !status.available
        {
            plan.warnings.push(
                status.unavailable_reason.clone().unwrap_or_else(|| {
                    format!("capability {} is unavailable", status.definition.id)
                }),
            );
        }

        match capability.risk {
            CapabilityRisk::Critical => plan.warnings.push(format!(
                "capability {} is critical risk and should require explicit user approval",
                capability.id
            )),
            CapabilityRisk::High => plan.warnings.push(format!(
                "capability {} is high risk and should be visible in audit UI",
                capability.id
            )),
            CapabilityRisk::Low | CapabilityRisk::Medium => {}
        }
    }

    sort_dedup(&mut plan.supported_capabilities);
    sort_dedup(&mut plan.enabled_capabilities);
    sort_dedup(&mut plan.disabled_capabilities);
    sort_dedup(&mut plan.host_required_capabilities);
    sort_dedup(&mut plan.remote_required_capabilities);
    sort_dedup(&mut plan.policy_required_capabilities);
    sort_dedup(&mut plan.warnings);
    plan
}

fn normalize_scenario_id(scenario_id: &str) -> String {
    let trimmed = scenario_id.trim();
    if trimmed.is_empty() {
        GENERAL_SCENARIO_ID.to_string()
    } else {
        trimmed.to_ascii_lowercase()
    }
}

fn parse_scenario_pack(raw_json: &str) -> Result<ScenarioPackDefinition, String> {
    let value = serde_json::from_str::<serde_json::Value>(raw_json)
        .map_err(|error| format!("scenario pack json is invalid: {error}"))?;
    let pack_value = value
        .get("pack")
        .or_else(|| value.get("definition"))
        .unwrap_or(&value)
        .clone();
    serde_json::from_value::<ScenarioPackDefinition>(pack_value)
        .map_err(|error| format!("scenario pack shape is invalid: {error}"))
}

fn normalize_installable_pack(
    mut pack: ScenarioPackDefinition,
) -> Result<(ScenarioPackDefinition, Vec<String>), String> {
    pack.id = normalize_scenario_id(&pack.id);
    if !is_valid_scenario_id(&pack.id) {
        return Err(
            "scenario id must be reverse-domain-style, for example napaxi.scenario.devops"
                .to_string(),
        );
    }
    if is_builtin_scenario_id(&pack.id) {
        return Err(format!("built-in scenario {} cannot be replaced", pack.id));
    }
    if pack.version.trim().is_empty() {
        pack.version = VERSION_1.to_string();
    }
    if pack.label.trim().is_empty() {
        pack.label = pack.id.clone();
    }
    if pack.description.trim().is_empty() {
        pack.description = "Installed scenario pack".to_string();
    }
    normalize_strings(&mut pack.required_capabilities);
    normalize_strings(&mut pack.recommended_capabilities);
    normalize_strings(&mut pack.optional_capabilities);
    normalize_strings(&mut pack.ui_surfaces);
    normalize_strings(&mut pack.memory_scopes);
    normalize_strings(&mut pack.tags);
    normalize_settings_contributions(&mut pack.settings_contributions);
    normalize_ui_contributions(&mut pack.ui_contributions);

    let mut warnings = Vec::new();
    if !pack
        .required_capabilities
        .iter()
        .any(|id| id == "napaxi.service.scenario_registry")
    {
        pack.required_capabilities
            .push("napaxi.service.scenario_registry".to_string());
        warnings.push(
            "napaxi.service.scenario_registry was added as a required capability".to_string(),
        );
    }
    if pack.execution_planes.is_empty() {
        pack.execution_planes.push(ScenarioExecutionPlane::Core);
        warnings.push("core execution plane was added because none was declared".to_string());
    }
    sort_dedup(&mut pack.required_capabilities);
    Ok((pack, warnings))
}

fn unknown_capability_warnings(pack: &ScenarioPackDefinition) -> Vec<String> {
    let known = capability_definitions()
        .into_iter()
        .map(|definition| definition.id)
        .collect::<HashSet<_>>();
    scenario_capability_ids(pack)
        .into_iter()
        .filter(|id| !known.contains(id))
        .map(|id| format!("scenario references unknown capability {id}"))
        .collect()
}

fn scenario_capability_ids(pack: &ScenarioPackDefinition) -> Vec<String> {
    let mut ids = pack.required_capabilities.clone();
    ids.extend(pack.recommended_capabilities.clone());
    ids.extend(pack.optional_capabilities.clone());
    ids.extend(
        pack.settings_contributions
            .iter()
            .map(|contribution| contribution.capability_id.clone()),
    );
    ids.extend(
        pack.ui_contributions
            .iter()
            .map(|contribution| contribution.capability_id.clone()),
    );
    normalize_strings(&mut ids);
    ids
}

fn installed_scenario_packs(files_dir: &str) -> Vec<ScenarioPackDefinition> {
    let path = scenario_store_path(files_dir);
    let Ok(raw) = fs::read_to_string(path) else {
        return Vec::new();
    };
    serde_json::from_str::<Vec<ScenarioPackDefinition>>(&raw).unwrap_or_default()
}

fn write_installed_scenario_packs(
    files_dir: &str,
    packs: &[ScenarioPackDefinition],
) -> Result<(), String> {
    let path = scenario_store_path(files_dir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create scenario registry directory: {error}"))?;
    }
    let raw = serde_json::to_string_pretty(packs)
        .map_err(|error| format!("failed to serialize scenario registry: {error}"))?;
    fs::write(path, raw).map_err(|error| format!("failed to write scenario registry: {error}"))
}

fn scenario_store_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join("napaxi")
        .join("scenarios")
        .join("packs.json")
}

fn merge_scenario_packs(
    built_in: Vec<ScenarioPackDefinition>,
    installed: Vec<ScenarioPackDefinition>,
) -> Vec<ScenarioPackDefinition> {
    let mut seen = HashSet::new();
    let mut merged = Vec::new();
    for pack in built_in {
        seen.insert(pack.id.clone());
        merged.push(pack);
    }
    for pack in installed {
        if seen.insert(pack.id.clone()) {
            merged.push(pack);
        }
    }
    merged
}

fn is_builtin_scenario_id(id: &str) -> bool {
    id == GENERAL_SCENARIO_ID || id == MOBILE_DEVELOPMENT_SCENARIO_ID
}

fn is_valid_scenario_id(id: &str) -> bool {
    let id = id.trim();
    id.contains('.')
        && id.len() >= 5
        && id.chars().all(|ch| {
            ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '.' || ch == '_' || ch == '-'
        })
        && !id.starts_with('.')
        && !id.ends_with('.')
}

fn normalize_strings(items: &mut Vec<String>) {
    for item in items.iter_mut() {
        *item = item.trim().to_ascii_lowercase();
    }
    items.retain(|item| !item.is_empty());
    sort_dedup(items);
}

fn normalize_settings_contributions(items: &mut Vec<ScenarioSettingsContribution>) {
    for item in items.iter_mut() {
        item.id = item.id.trim().to_ascii_lowercase();
        item.capability_id = item.capability_id.trim().to_ascii_lowercase();
        item.placement = item.placement.trim().to_ascii_lowercase();
        if item.placement.is_empty() {
            item.placement = "scenario_settings".to_string();
        }
        item.title = item.title.trim().to_string();
        if item.title.is_empty() {
            item.title = item.id.clone();
        }
        item.description = item.description.trim().to_string();
        normalize_strings(&mut item.actions);
    }
    items.retain(|item| !item.id.is_empty() && !item.capability_id.is_empty());
    items.sort_by(|left, right| left.id.cmp(&right.id));
    items.dedup_by(|left, right| left.id == right.id);
}

fn normalize_ui_contributions(items: &mut Vec<ScenarioUiContribution>) {
    for item in items.iter_mut() {
        item.id = item.id.trim().to_ascii_lowercase();
        item.capability_id = item.capability_id.trim().to_ascii_lowercase();
        item.placement = item.placement.trim().to_ascii_lowercase();
        if item.placement.is_empty() {
            item.placement = "left_menu".to_string();
        }
        item.title = item.title.trim().to_string();
        if item.title.is_empty() {
            item.title = item.id.clone();
        }
        item.description = item.description.trim().to_string();
        item.icon = item.icon.trim().to_ascii_lowercase();
        item.renderer = item.renderer.trim().to_ascii_lowercase();
        normalize_strings(&mut item.actions);
    }
    items.retain(|item| {
        !item.id.is_empty() && !item.capability_id.is_empty() && !item.renderer.is_empty()
    });
    items.sort_by(|left, right| left.id.cmp(&right.id));
    items.dedup_by(|left, right| left.id == right.id);
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

fn sort_dedup(items: &mut Vec<String>) {
    items.sort();
    items.dedup();
}
