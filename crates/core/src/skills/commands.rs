//! User-invocable skill commands and `/skill` fallback resolution.

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use super::limits::invalid_handle_json;
use super::snapshots::{create_skill_snapshot, status_counts_from_report};
use super::status::{SkillStatusEntry, SkillStatusReport, list_skill_status};

const SKILL_COMMAND_MAX_LENGTH: usize = 32;
const DEFAULT_RESERVED_COMMANDS: &[&str] = &[
    "help", "commands", "status", "context", "ctx", "compact", "stop", "new", "model", "models",
    "tools", "tasks", "skill",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillCommandReport {
    pub commands: Vec<SkillCommand>,
    pub total: usize,
    pub snapshot_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillCommand {
    pub name: String,
    pub skill_name: String,
    pub description: String,
    pub dispatch: Option<SkillCommandDispatch>,
    pub arg_mode: Option<String>,
    pub eligible: bool,
    pub disabled_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillCommandDispatch {
    pub kind: String,
    pub tool_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillCommandResolution {
    pub matched: bool,
    pub command: Option<SkillCommand>,
    pub args: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillCommandRun {
    pub success: bool,
    pub status: String,
    pub command_name: String,
    pub skill_name: Option<String>,
    pub args: Option<String>,
    pub session_key: Option<String>,
    pub message: Option<String>,
    pub dispatch: Option<SkillCommandDispatch>,
    pub error: Option<String>,
}

// Lower-level (non-handle) entrypoint; the adapter path uses the
// `*_handle` variant. Kept as the typed building block it wraps.
#[allow(dead_code)]
pub async fn list_skill_commands(files_dir: &str, agent_id: &str) -> String {
    let Some((commands, status, snapshot_id)) =
        skill_commands_for_agent_with_reserved(files_dir, agent_id, &Default::default(), &[]).await
    else {
        return serde_json::json!({"commands": [], "total": 0}).to_string();
    };
    let _ = status;
    serde_json::to_string(&SkillCommandReport {
        total: commands.len(),
        commands,
        snapshot_id,
    })
    .unwrap_or_else(|_| r#"{"commands":[],"total":0}"#.to_string())
}

pub async fn list_skill_commands_handle(handle: i64, agent_id: &str) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return invalid_handle_json();
    };
    let Some((commands, _, snapshot_id)) =
        skill_commands_for_agent_with_reserved(&files_dir, agent_id, &readiness, &[]).await
    else {
        return serde_json::json!({"commands": [], "total": 0}).to_string();
    };
    serde_json::to_string(&SkillCommandReport {
        total: commands.len(),
        commands,
        snapshot_id,
    })
    .unwrap_or_else(|_| r#"{"commands":[],"total":0}"#.to_string())
}

pub async fn resolve_skill_command(files_dir: &str, agent_id: &str, text: &str) -> String {
    let Some((commands, _, _)) =
        skill_commands_for_agent_with_reserved(files_dir, agent_id, &Default::default(), &[]).await
    else {
        return resolution_json(SkillCommandResolution {
            matched: false,
            command: None,
            args: None,
            error: Some("skill command status unavailable".to_string()),
        });
    };
    resolution_json(resolve_skill_command_from_list(&commands, text))
}

pub async fn resolve_skill_command_handle(handle: i64, agent_id: &str, text: &str) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return invalid_handle_json();
    };
    let Some((commands, _, _)) =
        skill_commands_for_agent_with_reserved(&files_dir, agent_id, &readiness, &[]).await
    else {
        return resolution_json(SkillCommandResolution {
            matched: false,
            command: None,
            args: None,
            error: Some("skill command status unavailable".to_string()),
        });
    };
    resolution_json(resolve_skill_command_from_list(&commands, text))
}

pub async fn run_skill_command(
    files_dir: &str,
    agent_id: &str,
    command_name: &str,
    args: Option<&str>,
    session_key_json: Option<&str>,
) -> String {
    let text = if command_name.trim_start().starts_with('/') {
        format_command_text(command_name, args)
    } else {
        format_command_text(&format!("/{command_name}"), args)
    };
    let resolution_raw = resolve_skill_command(files_dir, agent_id, &text).await;
    let resolution = serde_json::from_str::<SkillCommandResolution>(&resolution_raw).ok();
    let Some(resolution) = resolution else {
        return serde_json::json!({
            "success": false,
            "status": "failed",
            "command_name": command_name,
            "error": "failed to resolve skill command",
        })
        .to_string();
    };
    let Some(command) = resolution.command else {
        return serde_json::json!({
            "success": false,
            "status": "not_found",
            "command_name": command_name,
            "args": args,
            "error": resolution.error.unwrap_or_else(|| "skill command not found".to_string()),
        })
        .to_string();
    };
    let args = resolution.args.or_else(|| args.map(str::to_string));
    let message = format_command_text(&format!("/{}", command.skill_name), args.as_deref());
    serde_json::to_string(&SkillCommandRun {
        success: true,
        status: if command.dispatch.is_some() {
            "requires_host_tool_dispatch".to_string()
        } else {
            "agent_turn_required".to_string()
        },
        command_name: command.name.clone(),
        skill_name: Some(command.skill_name.clone()),
        args,
        session_key: session_key_json.map(str::to_string),
        message: Some(message),
        dispatch: command.dispatch.clone(),
        error: None,
    })
    .unwrap_or_else(|_| r#"{"success":false,"status":"failed"}"#.to_string())
}

pub async fn run_skill_command_handle(
    handle: i64,
    agent_id: &str,
    command_name: &str,
    args: Option<&str>,
    session_key_json: Option<&str>,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    run_skill_command(&files_dir, agent_id, command_name, args, session_key_json).await
}

pub(super) async fn skill_commands_for_agent_with_reserved(
    files_dir: &str,
    agent_id: &str,
    readiness: &napaxi_skills::SkillReadinessContext,
    reserved_names: &[String],
) -> Option<(Vec<SkillCommand>, SkillStatusReport, Option<String>)> {
    let status_raw = list_skill_status(files_dir, agent_id, readiness).await;
    let status = serde_json::from_str::<SkillStatusReport>(&status_raw).ok()?;
    let commands = build_skill_commands(status.entries.clone(), reserved_names);
    let snapshot = create_skill_snapshot(
        files_dir,
        agent_id,
        "skill_command",
        &[],
        status.entries.len(),
        commands.clone(),
        status_counts_from_report(&status),
    )
    .await;
    Some((
        commands,
        status,
        snapshot.map(|snapshot| snapshot.snapshot_id),
    ))
}

pub(super) fn build_skill_commands(
    entries: Vec<SkillStatusEntry>,
    reserved_names: &[String],
) -> Vec<SkillCommand> {
    let mut used = DEFAULT_RESERVED_COMMANDS
        .iter()
        .map(|name| normalize_command_lookup(name))
        .chain(
            reserved_names
                .iter()
                .map(|name| normalize_command_lookup(name)),
        )
        .collect::<HashSet<_>>();
    let mut commands = Vec::new();
    for entry in entries {
        if !entry.metadata.user_invocable {
            continue;
        }
        let eligible = command_entry_is_eligible(&entry);
        let base = sanitize_skill_command_name(&entry.name);
        let normalized = normalize_command_lookup(&base);
        let disabled_reason = if !eligible {
            Some(entry.status.clone())
        } else if DEFAULT_RESERVED_COMMANDS
            .iter()
            .map(|name| normalize_command_lookup(name))
            .chain(
                reserved_names
                    .iter()
                    .map(|name| normalize_command_lookup(name)),
            )
            .any(|name| name == normalized)
        {
            Some("reserved_name".to_string())
        } else if !used.insert(normalized) {
            Some("duplicate_name".to_string())
        } else {
            None
        };
        let command_eligible = disabled_reason.is_none();
        let dispatch = match (
            entry.metadata.command_dispatch.as_deref(),
            entry.metadata.command_tool.clone(),
        ) {
            (Some("tool"), Some(tool_name)) if !tool_name.trim().is_empty() => {
                Some(SkillCommandDispatch {
                    kind: "tool".to_string(),
                    tool_name: Some(tool_name),
                })
            }
            _ => None,
        };
        commands.push(SkillCommand {
            name: base,
            skill_name: entry.name,
            description: entry.description,
            dispatch,
            arg_mode: entry.metadata.command_arg_mode,
            eligible: command_eligible,
            disabled_reason,
        });
    }
    commands
}

fn readiness_from_handle(handle: i64) -> Option<(String, napaxi_skills::SkillReadinessContext)> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { crate::runtime::handle_to_arc(handle) }?;
    Some((
        engine.files_dir().to_string(),
        engine.skill_readiness_context(),
    ))
}

fn command_entry_is_eligible(entry: &SkillStatusEntry) -> bool {
    entry.status == "ready"
        || (entry.status == "disabled"
            && entry.enabled
            && entry.metadata.disable_model_invocation
            && entry.metadata.user_invocable)
}

fn resolve_skill_command_from_list(
    commands: &[SkillCommand],
    text: &str,
) -> SkillCommandResolution {
    let trimmed = text.trim();
    if !trimmed.starts_with('/') {
        return SkillCommandResolution {
            matched: false,
            command: None,
            args: None,
            error: None,
        };
    }
    let Some((raw_command, remainder)) = split_command(trimmed) else {
        return SkillCommandResolution {
            matched: false,
            command: None,
            args: None,
            error: Some("invalid skill command".to_string()),
        };
    };
    if raw_command == "skill" {
        let Some(remainder) = remainder else {
            return SkillCommandResolution {
                matched: false,
                command: None,
                args: None,
                error: Some("missing skill name after /skill".to_string()),
            };
        };
        let Some((skill_name, args)) = split_command(remainder) else {
            return SkillCommandResolution {
                matched: false,
                command: None,
                args: None,
                error: Some("missing skill name after /skill".to_string()),
            };
        };
        return find_command(commands, &skill_name)
            .map(|command| SkillCommandResolution {
                matched: true,
                command: Some(command.clone()),
                args: args.map(str::to_string),
                error: None,
            })
            .unwrap_or_else(|| SkillCommandResolution {
                matched: false,
                command: None,
                args: args.map(str::to_string),
                error: Some(format!("skill command not found: {skill_name}")),
            });
    }
    find_command(commands, &raw_command)
        .map(|command| SkillCommandResolution {
            matched: true,
            command: Some(command.clone()),
            args: remainder.map(str::to_string),
            error: None,
        })
        .unwrap_or_else(|| SkillCommandResolution {
            matched: false,
            command: None,
            args: remainder.map(str::to_string),
            error: Some(format!("skill command not found: {raw_command}")),
        })
}

fn split_command(text: &str) -> Option<(String, Option<&str>)> {
    let trimmed = text.trim();
    let without_slash = trimmed.strip_prefix('/').unwrap_or(trimmed);
    let mut parts = without_slash.splitn(2, char::is_whitespace);
    let command = parts.next()?.trim().to_lowercase();
    if command.is_empty() {
        return None;
    }
    let args = parts
        .next()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    Some((command, args))
}

fn find_command<'a>(commands: &'a [SkillCommand], name: &str) -> Option<&'a SkillCommand> {
    let normalized = normalize_command_lookup(name);
    commands.iter().find(|command| {
        command.eligible
            && (command.name.eq_ignore_ascii_case(name)
                || command.skill_name.eq_ignore_ascii_case(name)
                || normalize_command_lookup(&command.name) == normalized
                || normalize_command_lookup(&command.skill_name) == normalized)
    })
}

fn sanitize_skill_command_name(raw: &str) -> String {
    let mut out = String::new();
    let mut last_underscore = false;
    for ch in raw.chars().flat_map(char::to_lowercase) {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            last_underscore = false;
        } else if (ch == '_' || ch == '-' || ch == '.') && !last_underscore && !out.is_empty() {
            out.push('_');
            last_underscore = true;
        }
        if out.len() >= SKILL_COMMAND_MAX_LENGTH {
            break;
        }
    }
    while out.ends_with('_') {
        out.pop();
    }
    if out.is_empty() {
        "skill".to_string()
    } else {
        out
    }
}

fn normalize_command_lookup(value: &str) -> String {
    value.trim().to_lowercase().replace([' ', '_', '.'], "-")
}

fn format_command_text(command: &str, args: Option<&str>) -> String {
    let command = command.trim();
    let args = args.map(str::trim).filter(|value| !value.is_empty());
    match args {
        Some(args) => format!("{command} {args}"),
        None => command.to_string(),
    }
}

fn resolution_json(resolution: SkillCommandResolution) -> String {
    serde_json::to_string(&resolution).unwrap_or_else(|_| {
        r#"{"matched":false,"command":null,"args":null,"error":"serialize failed"}"#.to_string()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn command(name: &str, skill_name: &str) -> SkillCommand {
        SkillCommand {
            name: name.to_string(),
            skill_name: skill_name.to_string(),
            description: String::new(),
            dispatch: None,
            arg_mode: None,
            eligible: true,
            disabled_reason: None,
        }
    }

    #[test]
    fn resolves_direct_command_and_skill_fallback() {
        let commands = vec![command("github_issues", "github-issues")];
        let direct = resolve_skill_command_from_list(&commands, "/github_issues list open");
        assert!(direct.matched);
        assert_eq!(direct.args.as_deref(), Some("list open"));

        let fallback = resolve_skill_command_from_list(&commands, "/skill github-issues list open");
        assert!(fallback.matched);
        assert_eq!(fallback.args.as_deref(), Some("list open"));
    }
}
