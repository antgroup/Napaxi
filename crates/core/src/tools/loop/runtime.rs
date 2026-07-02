//! Per-tool-call runtime preparation for the mobile tool loop.
//!
//! Codex has a broad tool orchestrator because desktop tools need sandbox and
//! approval routing. Napaxi keeps this boundary mobile-native: capability
//! admission remains the hard gate, and host/platform execution still happens
//! through SDK bridges after this preparation step succeeds.

use crate::tool_registry::{
    ToolDescriptor, check_tool_rate_limit, prepare_tool_arguments, redact_tool_arguments_json,
};
use crate::types::{GitMode, PlatformLlmConfig};
use crate::{
    builtin_tools::{GitShellIntent, git_shell_intent},
    capabilities::MOBILE_DEVELOPMENT_SCENARIO_ID,
};

#[derive(Debug)]
pub(super) struct PreparedToolInvocation<'a> {
    pub(super) name: String,
    pub(super) params: serde_json::Value,
    pub(super) route: Option<ToolIntentRouteMetadata>,
    #[allow(dead_code)] // Retained for the next ToolRuntime slice: effect/policy orchestration.
    pub(super) descriptor: &'a ToolDescriptor,
}

#[derive(Debug, Clone)]
pub(super) struct ToolIntentRouteMetadata {
    pub(super) intent_id: &'static str,
    pub(super) source_tool: &'static str,
    pub(super) target_tool: &'static str,
}

#[derive(Debug)]
pub(super) enum ToolRuntimePreparationError {
    ModelVisible(String),
}

impl ToolRuntimePreparationError {
    pub(super) fn into_model_output(self) -> String {
        match self {
            Self::ModelVisible(message) => message,
        }
    }
}

pub(super) fn prepare_tool_invocation<'a>(
    config: &PlatformLlmConfig,
    descriptors: &'a [ToolDescriptor],
    name: &str,
    arguments: &str,
) -> Result<PreparedToolInvocation<'a>, ToolRuntimePreparationError> {
    let argument_summary = || summarize_tool_arguments(arguments);
    let params = serde_json::from_str::<serde_json::Value>(arguments).map_err(|error| {
        ToolRuntimePreparationError::ModelVisible(format!(
            "Invalid arguments for tool '{name}': arguments must be valid JSON: {error}; received {}. Retry this tool call with one complete JSON object matching the tool schema.",
            argument_summary()
        ))
    })?;

    let Some(descriptor) = descriptors
        .iter()
        .find(|descriptor| descriptor.name == name)
    else {
        return Err(ToolRuntimePreparationError::ModelVisible(format!(
            "Tool not found: {name}"
        )));
    };

    if let Some(route) = mediate_tool_intent(config, descriptors, name, &params)? {
        return prepare_routed_tool_invocation(config, descriptors, route, &argument_summary);
    }

    let platform = config
        .capability_profile
        .platform
        .as_deref()
        .unwrap_or("unknown");
    crate::capabilities::admit_tool_invocation_for_config(
        name,
        platform,
        &config.capability_profile,
        &config.capability_selection,
    )
    .map_err(ToolRuntimePreparationError::ModelVisible)?;

    check_tool_rate_limit(name).map_err(ToolRuntimePreparationError::ModelVisible)?;

    let params = prepare_tool_arguments(descriptor, params).map_err(|error| {
        ToolRuntimePreparationError::ModelVisible(format!(
            "Invalid arguments for tool '{name}': {error}; received {}",
            argument_summary()
        ))
    })?;

    if name == "shell" {
        enforce_git_shell_intent(config, descriptors, &params)?;
    }

    Ok(PreparedToolInvocation {
        name: descriptor.name.clone(),
        params,
        route: None,
        descriptor,
    })
}

struct ToolIntentRoute {
    intent_id: &'static str,
    source_tool: &'static str,
    target_tool: &'static str,
    params: serde_json::Value,
}

fn prepare_routed_tool_invocation<'a, F>(
    config: &PlatformLlmConfig,
    descriptors: &'a [ToolDescriptor],
    route: ToolIntentRoute,
    argument_summary: &F,
) -> Result<PreparedToolInvocation<'a>, ToolRuntimePreparationError>
where
    F: Fn() -> String,
{
    let Some(descriptor) = descriptors
        .iter()
        .find(|descriptor| descriptor.name == route.target_tool)
    else {
        return Err(ToolRuntimePreparationError::ModelVisible(format!(
            "The active scenario maps `{}` to `{}`, but that tool is not available. Refresh the scenario tools before retrying.",
            route.intent_id, route.target_tool
        )));
    };
    let platform = config
        .capability_profile
        .platform
        .as_deref()
        .unwrap_or("unknown");
    crate::capabilities::admit_tool_invocation_for_config(
        &descriptor.name,
        platform,
        &config.capability_profile,
        &config.capability_selection,
    )
    .map_err(ToolRuntimePreparationError::ModelVisible)?;
    check_tool_rate_limit(&descriptor.name).map_err(ToolRuntimePreparationError::ModelVisible)?;
    let params = prepare_tool_arguments(descriptor, route.params).map_err(|error| {
        ToolRuntimePreparationError::ModelVisible(format!(
            "Invalid routed arguments for tool '{}': {error}; source_tool={}; intent={}; received {}",
            descriptor.name,
            route.source_tool,
            route.intent_id,
            argument_summary()
        ))
    })?;
    let metadata = ToolIntentRouteMetadata {
        intent_id: route.intent_id,
        source_tool: route.source_tool,
        target_tool: route.target_tool,
    };
    Ok(PreparedToolInvocation {
        name: descriptor.name.clone(),
        params,
        route: Some(metadata),
        descriptor,
    })
}

fn mediate_tool_intent(
    config: &PlatformLlmConfig,
    descriptors: &[ToolDescriptor],
    name: &str,
    params: &serde_json::Value,
) -> Result<Option<ToolIntentRoute>, ToolRuntimePreparationError> {
    if name != "shell" || !repo_intents_enabled(config) {
        return Ok(None);
    }
    let Some(command) = params.get("command").and_then(serde_json::Value::as_str) else {
        return Ok(None);
    };
    let Some(intent) = git_shell_intent(command) else {
        return Ok(None);
    };

    match intent {
        GitShellIntent::InstallGit => Err(ToolRuntimePreparationError::ModelVisible(
            "Installing Git through shell is not the active scenario path. Use the dedicated Git tools exposed by the mobile development scenario."
                .to_string(),
        )),
        GitShellIntent::GitCommand {
            preferred_tool,
            args,
        } => {
            let Some(tool_name) = preferred_tool else {
                return Ok(None);
            };
            if !descriptors
                .iter()
                .any(|descriptor| descriptor.name == tool_name)
            {
                return Err(ToolRuntimePreparationError::ModelVisible(format!(
                    "The active scenario maps this repository intent to `{tool_name}`, but that tool is not available. Refresh the mobile development scenario tools before retrying."
                )));
            }
            route_repo_git_command(tool_name, &args)
                .map(Some)
                .ok_or_else(|| {
                    ToolRuntimePreparationError::ModelVisible(format!(
                        "This shell Git command matches a repository intent handled by `{tool_name}`, but its arguments are outside the supported mobile repository contract. Retry with `{tool_name}` using explicit structured arguments."
                    ))
                })
        }
    }
}

/// Whether the runtime is configured to execute shell `git` directly against the
/// sandbox rootfs binary (paseo-style), instead of redirecting to the host's
/// dedicated structured git tools.
fn native_git_mode_enabled(config: &PlatformLlmConfig) -> bool {
    config
        .git
        .as_ref()
        .map(|git| git.mode == GitMode::Native)
        .unwrap_or(false)
}

fn enforce_git_shell_intent(
    config: &PlatformLlmConfig,
    descriptors: &[ToolDescriptor],
    params: &serde_json::Value,
) -> Result<(), ToolRuntimePreparationError> {
    // Native (paseo-style) git mode: shell `git` runs directly against the real
    // `git` binary baked into the sandbox rootfs, exactly like any other shell
    // command. Skip the structured-tool redirect entirely; the read-only
    // allow-list (`shell_safe`) and the shell approval posture still gate it.
    if native_git_mode_enabled(config) {
        return Ok(());
    }
    let Some(command) = params.get("command").and_then(serde_json::Value::as_str) else {
        return Ok(());
    };
    let Some(intent) = git_shell_intent(command) else {
        return Ok(());
    };
    let selection = &config.capability_selection;
    let scenario_id = selection
        .config
        .get("scenario_id")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();
    let mobile_development = scenario_id == MOBILE_DEVELOPMENT_SCENARIO_ID;
    let git_capability_enabled = selection
        .enabled_capabilities
        .iter()
        .any(|id| id == "napaxi.tool.git")
        && !selection
            .disabled_capabilities
            .iter()
            .any(|id| id == "napaxi.tool.git");
    if !mobile_development && !git_capability_enabled {
        return Ok(());
    }

    match intent {
        GitShellIntent::InstallGit => Err(ToolRuntimePreparationError::ModelVisible(
            "Installing Git through shell is not the active scenario path. Use the dedicated Git tools exposed by the mobile development scenario."
                .to_string(),
        )),
        GitShellIntent::GitCommand { preferred_tool, .. } => {
            if let Some(tool_name) = preferred_tool {
                if descriptors
                    .iter()
                    .any(|descriptor| descriptor.name == tool_name)
                {
                    return Err(ToolRuntimePreparationError::ModelVisible(format!(
                        "Use the dedicated `{tool_name}` tool instead of shell for this Git operation."
                    )));
                }
                return Err(ToolRuntimePreparationError::ModelVisible(format!(
                    "The active scenario expects a dedicated `{tool_name}` tool for this Git operation, but it is not available in the current tool set. Refresh the mobile development scenario tools before retrying."
                )));
            }
            Ok(())
        }
    }
}

fn repo_intents_enabled(config: &PlatformLlmConfig) -> bool {
    // Native git mode does not redirect shell git to structured tools; the
    // shell `git` command is executed directly in the rootfs instead.
    if native_git_mode_enabled(config) {
        return false;
    }
    let selection = &config.capability_selection;
    let scenario_id = selection
        .config
        .get("scenario_id")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();
    let mobile_development = scenario_id == MOBILE_DEVELOPMENT_SCENARIO_ID;
    let git_capability_enabled = selection
        .enabled_capabilities
        .iter()
        .any(|id| id == "napaxi.tool.git")
        && !selection
            .disabled_capabilities
            .iter()
            .any(|id| id == "napaxi.tool.git");
    mobile_development && git_capability_enabled
}

struct GitCommandParts<'a> {
    workdir: Option<String>,
    subcommand: &'a str,
    subcommand_args: &'a [String],
}

fn route_repo_git_command(tool_name: &'static str, args: &[String]) -> Option<ToolIntentRoute> {
    let parts = split_git_command(args)?;
    match (tool_name, parts.subcommand) {
        ("git_clone", "clone") => route_git_clone(parts.subcommand_args),
        ("git_status", "status") => {
            route_git_status(parts.workdir.as_deref(), parts.subcommand_args)
        }
        ("git_diff", "diff") => route_git_diff(parts.workdir.as_deref(), parts.subcommand_args),
        ("git_list_branches", "branch") => {
            route_git_list_branches(parts.workdir.as_deref(), parts.subcommand_args)
        }
        ("git_switch_branch", "checkout" | "switch") => {
            route_git_switch_branch(parts.workdir.as_deref(), parts.subcommand_args)
        }
        ("git_list_remotes", "remote") => {
            route_git_list_remotes(parts.workdir.as_deref(), parts.subcommand_args)
        }
        ("git_set_remote", "remote") => {
            route_git_set_remote(parts.workdir.as_deref(), parts.subcommand_args)
        }
        ("git_fetch", "fetch") => route_git_fetch(parts.workdir.as_deref(), parts.subcommand_args),
        _ => None,
    }
}

fn split_git_command(args: &[String]) -> Option<GitCommandParts<'_>> {
    let mut index = 0;
    let mut workdir = None;
    while index < args.len() {
        let arg = args[index].as_str();
        if arg == "-C" {
            workdir = args.get(index + 1).cloned();
            index += 2;
            continue;
        }
        if matches!(arg, "-c" | "--git-dir" | "--work-tree") {
            index += 2;
            continue;
        }
        if arg.starts_with("--git-dir=") || arg.starts_with("--work-tree=") {
            index += 1;
            continue;
        }
        if arg.starts_with('-') {
            index += 1;
            continue;
        }
        return Some(GitCommandParts {
            workdir,
            subcommand: arg,
            subcommand_args: &args[index + 1..],
        });
    }
    None
}

fn route_git_clone(args: &[String]) -> Option<ToolIntentRoute> {
    let mut branch = None;
    let mut depth = None;
    let mut positionals = Vec::new();
    let mut index = 0;
    while index < args.len() {
        let arg = args[index].as_str();
        match arg {
            "--" => {
                positionals.extend(args[index + 1..].iter().cloned());
                break;
            }
            "-b" | "--branch" => {
                branch = args.get(index + 1).cloned();
                index += 2;
            }
            "--depth" => {
                depth = args
                    .get(index + 1)
                    .and_then(|value| value.parse::<i64>().ok());
                index += 2;
            }
            "--single-branch" | "--no-tags" => {
                index += 1;
            }
            value if value.starts_with("--branch=") => {
                branch = Some(value.trim_start_matches("--branch=").to_string());
                index += 1;
            }
            value if value.starts_with("--depth=") => {
                depth = value.trim_start_matches("--depth=").parse::<i64>().ok();
                index += 1;
            }
            value if value.starts_with('-') => return None,
            _ => {
                positionals.push(arg.to_string());
                index += 1;
            }
        }
    }
    let url = positionals.first()?.trim();
    if url.is_empty() || positionals.len() > 2 {
        return None;
    }
    let mut params = serde_json::Map::from_iter([(
        "url".to_string(),
        serde_json::Value::String(url.to_string()),
    )]);
    if let Some(directory) = positionals
        .get(1)
        .and_then(|value| normalize_repo_directory(value))
    {
        params.insert(
            "directory".to_string(),
            serde_json::Value::String(directory),
        );
    }
    if let Some(branch) = branch.filter(|value| !value.trim().is_empty()) {
        params.insert("branch".to_string(), serde_json::Value::String(branch));
    }
    if let Some(depth) = depth.filter(|value| *value > 0) {
        params.insert("depth".to_string(), serde_json::Value::Number(depth.into()));
    }
    Some(ToolIntentRoute {
        intent_id: "repo.clone",
        source_tool: "shell",
        target_tool: "git_clone",
        params: serde_json::Value::Object(params),
    })
}

fn route_git_status(workdir: Option<&str>, args: &[String]) -> Option<ToolIntentRoute> {
    if !args.iter().all(|arg| {
        matches!(
            arg.as_str(),
            "--short" | "--branch" | "-s" | "-b" | "--porcelain"
        )
    }) {
        return None;
    }
    let directory = normalize_repo_directory(workdir?)?;
    Some(repo_directory_route(
        "repo.status",
        "git_status",
        directory,
        None,
    ))
}

fn route_git_diff(workdir: Option<&str>, args: &[String]) -> Option<ToolIntentRoute> {
    let mut stat = false;
    for arg in args {
        match arg.as_str() {
            "--stat" => stat = true,
            "--" => {}
            value if value.starts_with('-') => return None,
            _ => return None,
        }
    }
    let directory = normalize_repo_directory(workdir?)?;
    Some(repo_directory_route(
        "repo.diff",
        "git_diff",
        directory,
        Some(("stat", serde_json::Value::Bool(stat))),
    ))
}

fn route_git_list_branches(workdir: Option<&str>, args: &[String]) -> Option<ToolIntentRoute> {
    if !args.iter().all(|arg| {
        matches!(
            arg.as_str(),
            "--list" | "-l" | "--all" | "-a" | "--remotes" | "-r" | "-v" | "-vv"
        )
    }) {
        return None;
    }
    let directory = normalize_repo_directory(workdir?)?;
    Some(repo_directory_route(
        "repo.branch.list",
        "git_list_branches",
        directory,
        None,
    ))
}

fn route_git_switch_branch(workdir: Option<&str>, args: &[String]) -> Option<ToolIntentRoute> {
    let directory = normalize_repo_directory(workdir?)?;
    let mut remote = false;
    let mut positionals = Vec::new();
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--track" => {
                remote = true;
                index += 1;
            }
            "--" => {
                positionals.extend(args[index + 1..].iter().cloned());
                break;
            }
            value if value.starts_with('-') => return None,
            value => {
                positionals.push(value.to_string());
                index += 1;
            }
        }
    }
    if positionals.len() != 1 {
        return None;
    }
    let branch = normalize_git_ref(positionals.first()?)?;
    let mut params = serde_json::Map::from_iter([
        (
            "directory".to_string(),
            serde_json::Value::String(directory),
        ),
        ("branch".to_string(), serde_json::Value::String(branch)),
    ]);
    if remote {
        params.insert("remote".to_string(), serde_json::Value::Bool(true));
    }
    Some(ToolIntentRoute {
        intent_id: "repo.branch.switch",
        source_tool: "shell",
        target_tool: "git_switch_branch",
        params: serde_json::Value::Object(params),
    })
}

fn route_git_list_remotes(workdir: Option<&str>, args: &[String]) -> Option<ToolIntentRoute> {
    if !args
        .iter()
        .all(|arg| matches!(arg.as_str(), "-v" | "--verbose"))
    {
        return None;
    }
    let directory = normalize_repo_directory(workdir?)?;
    Some(repo_directory_route(
        "repo.remote.list",
        "git_list_remotes",
        directory,
        None,
    ))
}

fn route_git_set_remote(workdir: Option<&str>, args: &[String]) -> Option<ToolIntentRoute> {
    let directory = normalize_repo_directory(workdir?)?;
    let subcommand = args.first()?.as_str();
    match subcommand {
        "add" | "set-url" => {
            if args.len() != 3 {
                return None;
            }
            let name = normalize_remote_name(&args[1])?;
            let url = normalize_remote_url(&args[2])?;
            Some(repo_remote_route(
                "repo.remote.set",
                directory,
                name,
                Some(url),
                "upsert",
            ))
        }
        "remove" | "rm" => {
            if args.len() != 2 {
                return None;
            }
            let name = normalize_remote_name(&args[1])?;
            Some(repo_remote_route(
                "repo.remote.remove",
                directory,
                name,
                None,
                "remove",
            ))
        }
        _ => None,
    }
}

fn route_git_fetch(workdir: Option<&str>, args: &[String]) -> Option<ToolIntentRoute> {
    let directory = normalize_repo_directory(workdir?)?;
    let mut remote = None;
    let mut prune = true;
    for arg in args {
        match arg.as_str() {
            "--all" | "--multiple" => {}
            "--prune" | "-p" => prune = true,
            "--no-prune" => prune = false,
            value if value.starts_with('-') => return None,
            value => {
                if remote.is_some() {
                    return None;
                }
                remote = Some(normalize_remote_name(value)?);
            }
        }
    }
    let mut params = serde_json::Map::from_iter([
        (
            "directory".to_string(),
            serde_json::Value::String(directory),
        ),
        ("prune".to_string(), serde_json::Value::Bool(prune)),
    ]);
    if let Some(remote) = remote {
        params.insert("remote".to_string(), serde_json::Value::String(remote));
    }
    Some(ToolIntentRoute {
        intent_id: "repo.fetch",
        source_tool: "shell",
        target_tool: "git_fetch",
        params: serde_json::Value::Object(params),
    })
}

fn repo_remote_route(
    intent_id: &'static str,
    directory: String,
    name: String,
    url: Option<String>,
    action: &'static str,
) -> ToolIntentRoute {
    let mut params = serde_json::Map::from_iter([
        (
            "directory".to_string(),
            serde_json::Value::String(directory),
        ),
        ("name".to_string(), serde_json::Value::String(name)),
        (
            "action".to_string(),
            serde_json::Value::String(action.to_string()),
        ),
    ]);
    if let Some(url) = url {
        params.insert("url".to_string(), serde_json::Value::String(url));
    }
    ToolIntentRoute {
        intent_id,
        source_tool: "shell",
        target_tool: "git_set_remote",
        params: serde_json::Value::Object(params),
    }
}

fn repo_directory_route(
    intent_id: &'static str,
    target_tool: &'static str,
    directory: String,
    extra: Option<(&str, serde_json::Value)>,
) -> ToolIntentRoute {
    let mut params = serde_json::Map::from_iter([(
        "directory".to_string(),
        serde_json::Value::String(directory),
    )]);
    if let Some((key, value)) = extra {
        params.insert(key.to_string(), value);
    }
    ToolIntentRoute {
        intent_id,
        source_tool: "shell",
        target_tool,
        params: serde_json::Value::Object(params),
    }
}

fn normalize_repo_directory(value: &str) -> Option<String> {
    let trimmed = value.trim().trim_end_matches('/');
    let stripped = trimmed
        .strip_prefix("/workspace/")
        .or_else(|| trimmed.strip_prefix("./"))
        .unwrap_or(trimmed);
    if stripped.is_empty()
        || stripped == "."
        || stripped.starts_with('/')
        || stripped.contains("://")
        || stripped
            .split('/')
            .any(|part| part.is_empty() || part == "..")
    {
        return None;
    }
    Some(stripped.to_string())
}

fn normalize_git_ref(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty()
        || trimmed.starts_with('-')
        || trimmed.starts_with('/')
        || trimmed.ends_with('/')
        || trimmed.contains("..")
        || trimmed.contains('\0')
        || trimmed.chars().any(char::is_whitespace)
        || trimmed
            .chars()
            .any(|ch| matches!(ch, '^' | '~' | ':' | '?' | '*' | '[' | '\\'))
    {
        return None;
    }
    Some(trimmed.to_string())
}

fn normalize_remote_name(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed.starts_with('-') {
        return None;
    }
    if trimmed
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
    {
        Some(trimmed.to_string())
    } else {
        None
    }
}

fn normalize_remote_url(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty()
        || trimmed.starts_with('-')
        || trimmed.contains('\0')
        || trimmed.contains('\r')
        || trimmed.contains('\n')
    {
        return None;
    }
    if trimmed.starts_with("https://")
        || trimmed.starts_with("ssh://")
        || trimmed.starts_with("file://")
        || (trimmed.contains('@')
            && trimmed.contains(':')
            && !trimmed.chars().any(char::is_whitespace))
    {
        Some(trimmed.to_string())
    } else {
        None
    }
}

fn summarize_tool_arguments(arguments: &str) -> String {
    const PREFIX_CHARS: usize = 300;
    const SUFFIX_CHARS: usize = 160;
    let redacted = redact_tool_arguments_json(arguments);
    let char_count = redacted.chars().count();
    if char_count <= PREFIX_CHARS + SUFFIX_CHARS {
        return format!("arguments_len_chars={char_count}; arguments={redacted}");
    }

    let prefix: String = redacted.chars().take(PREFIX_CHARS).collect();
    let suffix_start = char_count.saturating_sub(SUFFIX_CHARS);
    let suffix: String = redacted.chars().skip(suffix_start).collect();
    format!(
        "arguments_len_chars={char_count}; arguments_prefix={prefix}...; arguments_suffix={suffix}"
    )
}

#[cfg(test)]
mod runtime_tests;
