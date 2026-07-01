//! Skill curator: stale → archive lifecycle, plus evolution action dispatch.

use chrono::{Duration, Utc};
use napaxi_skills::SkillRegistry;

use super::lifecycle::{archive_skill_dir, skill_is_protected, with_skill_backup};
use super::limits::{
    ARCHIVE_STALE_AFTER_DAYS, MAX_EXTRA_FILE_SIZE, STALE_AFTER_DAYS, invalid_handle_json,
};
use super::paths::{agent_skills_dir, normalize_agent_id, skill_target_path};
use super::types::{CuratorRunSummary, SkillLifecycleState};
use super::usage::{
    is_record_protected, latest_record_activity, load_usage_map, record_skill_created_by_agent,
    record_skill_patch, update_usage_record,
};

pub async fn run_skill_curator(
    files_dir: &str,
    agent_id: &str,
    dry_run: bool,
) -> CuratorRunSummary {
    let agent_id = normalize_agent_id(agent_id);
    let usage = load_usage_map(files_dir, &agent_id).await;
    let now = Utc::now();
    let stale_after = Duration::days(STALE_AFTER_DAYS);
    let archive_after = Duration::days(ARCHIVE_STALE_AFTER_DAYS);
    let mut summary = CuratorRunSummary {
        dry_run,
        checked: usage.len(),
        marked_stale: 0,
        archived: 0,
        restored_active: 0,
        protected_skipped: 0,
        actions: Vec::new(),
    };

    for record in usage.values() {
        if is_record_protected(record) {
            summary.protected_skipped += 1;
            summary
                .actions
                .push(format!("skip protected {}", record.skill_name));
            continue;
        }
        if record.pinned || record.state == SkillLifecycleState::Archived {
            continue;
        }
        if record.created_by.as_deref() != Some("agent") {
            continue;
        }
        let inactive_for = latest_record_activity(record)
            .map(|last| now.signed_duration_since(last))
            .unwrap_or_else(|| archive_after + Duration::days(1));
        if record.state == SkillLifecycleState::Stale && inactive_for >= archive_after {
            if dry_run {
                summary.archived += 1;
                summary
                    .actions
                    .push(format!("archive stale skill {}", record.skill_name));
            } else {
                match archive_skill_dir(files_dir, &agent_id, &record.skill_name, None).await {
                    Ok(_) => {
                        summary.archived += 1;
                        summary
                            .actions
                            .push(format!("archive stale skill {}", record.skill_name));
                    }
                    Err(error) => summary
                        .actions
                        .push(format!("failed to archive {}: {error}", record.skill_name)),
                }
            }
            continue;
        }
        if record.state == SkillLifecycleState::Active && inactive_for >= stale_after {
            if dry_run {
                summary.marked_stale += 1;
                summary
                    .actions
                    .push(format!("mark stale {}", record.skill_name));
            } else {
                match update_usage_record(files_dir, &agent_id, &record.skill_name, |usage| {
                    usage.state = SkillLifecycleState::Stale;
                })
                .await
                {
                    Ok(_) => {
                        summary.marked_stale += 1;
                        summary
                            .actions
                            .push(format!("mark stale {}", record.skill_name));
                    }
                    Err(error) => summary.actions.push(format!(
                        "failed to mark stale {}: {error}",
                        record.skill_name
                    )),
                }
            }
        }
    }
    summary
}

pub async fn run_skill_curator_handle(handle: i64, agent_id: &str, dry_run: bool) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    serde_json::to_string(&run_skill_curator(&files_dir, agent_id, dry_run).await)
        .unwrap_or_else(|_| "{}".to_string())
}

pub async fn apply_evolution_action(
    files_dir: &str,
    agent_id: &str,
    action: &napaxi_evolution::PendingActionType,
) -> Result<String, String> {
    use napaxi_evolution::PendingActionType;

    let agent_id = normalize_agent_id(agent_id);
    match action {
        PendingActionType::Create {
            skill_name,
            content,
            category: _,
        } => {
            let name = install_or_replace_skill(files_dir, &agent_id, skill_name, content).await?;
            record_skill_created_by_agent(files_dir, &agent_id, &name).await;
            Ok(format!("Skill '{name}' installed"))
        }
        PendingActionType::Edit {
            skill_name,
            new_content,
        } => {
            let result = with_skill_backup(files_dir, &agent_id, skill_name, "edit", || async {
                install_or_replace_skill(files_dir, &agent_id, skill_name, new_content)
                    .await
                    .map(|name| format!("Skill '{name}' updated"))
            })
            .await?;
            record_skill_patch(files_dir, &agent_id, skill_name).await;
            Ok(result)
        }
        PendingActionType::Patch {
            skill_name,
            old_string,
            new_string,
            file_path,
            replace_all,
        } => {
            let result = with_skill_backup(files_dir, &agent_id, skill_name, "patch", || async {
                let target =
                    skill_target_path(files_dir, &agent_id, skill_name, file_path.as_deref())?;
                let content = tokio::fs::read_to_string(&target)
                    .await
                    .map_err(|e| format!("read {}: {e}", target.display()))?;
                let (new_content, count, strategy, _) = napaxi_evolution::fuzzy_find_and_replace(
                    &content,
                    old_string,
                    new_string,
                    *replace_all,
                )?;
                if target.file_name().and_then(|name| name.to_str()) == Some("SKILL.md") {
                    let normalized = napaxi_skills::normalize_line_endings(&new_content);
                    let parsed = napaxi_skills::parse_skill_md(&normalized)
                        .map_err(|e| format!("invalid patched SKILL.md: {e}"))?;
                    if parsed.manifest.name != *skill_name {
                        return Err(format!(
                            "patched SKILL.md changes skill name from '{}' to '{}'",
                            skill_name, parsed.manifest.name
                        ));
                    }
                    napaxi_evolution::atomic_write_text(&target, &normalized)
                        .await
                        .map_err(|e| format!("write {}: {e}", target.display()))?;
                } else {
                    napaxi_evolution::atomic_write_text(&target, &new_content)
                        .await
                        .map_err(|e| format!("write {}: {e}", target.display()))?;
                }
                Ok(format!(
                    "Skill '{}' patched ({count} replacement{}, strategy: {})",
                    skill_name,
                    if count == 1 { "" } else { "s" },
                    strategy.unwrap_or_else(|| "unknown".to_string())
                ))
            })
            .await?;
            record_skill_patch(files_dir, &agent_id, skill_name).await;
            Ok(result)
        }
        PendingActionType::Delete {
            skill_name,
            absorbed_into,
        } => {
            if skill_is_protected(files_dir, &agent_id, skill_name).await {
                return Err(format!(
                    "Skill '{}' is protected and cannot be archived by evolution",
                    skill_name
                ));
            }
            let result = with_skill_backup(files_dir, &agent_id, skill_name, "archive", || async {
                let archived =
                    archive_skill_dir(files_dir, &agent_id, skill_name, absorbed_into.as_deref())
                        .await?;
                Ok(format!(
                    "Skill '{}' archived to {}",
                    skill_name, archived.archive_path
                ))
            })
            .await?;
            record_skill_patch(files_dir, &agent_id, skill_name).await;
            Ok(result)
        }
        PendingActionType::WriteFile {
            skill_name,
            file_path,
            file_content,
        } => {
            let result =
                with_skill_backup(files_dir, &agent_id, skill_name, "write-file", || async {
                    let target =
                        skill_target_path(files_dir, &agent_id, skill_name, Some(file_path))?;
                    if target.file_name().and_then(|name| name.to_str()) == Some("SKILL.md") {
                        return Err("use SkillEdit to replace SKILL.md".to_string());
                    }
                    if file_content.len() as u64 > MAX_EXTRA_FILE_SIZE {
                        return Err(format!(
                            "skill support file too large (max {MAX_EXTRA_FILE_SIZE} bytes)"
                        ));
                    }
                    napaxi_evolution::atomic_write_text(&target, file_content)
                        .await
                        .map_err(|e| format!("write {}: {e}", target.display()))?;
                    Ok(format!("File '{}' written for {}", file_path, skill_name))
                })
                .await?;
            record_skill_patch(files_dir, &agent_id, skill_name).await;
            Ok(result)
        }
        PendingActionType::RemoveFile {
            skill_name,
            file_path,
        } => {
            let result =
                with_skill_backup(files_dir, &agent_id, skill_name, "remove-file", || async {
                    let target =
                        skill_target_path(files_dir, &agent_id, skill_name, Some(file_path))?;
                    if target.file_name().and_then(|name| name.to_str()) == Some("SKILL.md") {
                        return Err("use SkillDelete to remove a skill".to_string());
                    }
                    tokio::fs::remove_file(&target)
                        .await
                        .map_err(|e| format!("remove {}: {e}", target.display()))?;
                    Ok(format!("File '{}' removed from {}", file_path, skill_name))
                })
                .await?;
            record_skill_patch(files_dir, &agent_id, skill_name).await;
            Ok(result)
        }
        PendingActionType::MemoryWrite { .. } => {
            Err("memory evolution actions are handled by mobile_evolution".to_string())
        }
    }
}

async fn install_or_replace_skill(
    files_dir: &str,
    agent_id: &str,
    requested_skill_name: &str,
    content: &str,
) -> Result<String, String> {
    let normalized = napaxi_skills::normalize_line_endings(content);
    let normalized = ensure_skill_frontmatter(requested_skill_name, &normalized);
    let (skill_name, install_content) =
        SkillRegistry::resolve_install_content(&normalized, Some(requested_skill_name))
            .map_err(|e| e.to_string())?;
    let parsed = napaxi_skills::parse_skill_md(&install_content).map_err(|e| e.to_string())?;
    if parsed.manifest.name != skill_name {
        return Err(format!(
            "resolved skill name '{}' does not match parsed name '{}'",
            skill_name, parsed.manifest.name
        ));
    }
    let skill_dir = agent_skills_dir(files_dir, agent_id).join(&skill_name);
    tokio::fs::create_dir_all(&skill_dir)
        .await
        .map_err(|e| format!("create {}: {e}", skill_dir.display()))?;
    let target = skill_dir.join("SKILL.md");
    napaxi_evolution::atomic_write_text(&target, &install_content)
        .await
        .map_err(|e| format!("write {}: {e}", target.display()))?;
    Ok(skill_name)
}

fn ensure_skill_frontmatter(requested_skill_name: &str, normalized_content: &str) -> String {
    if normalized_content
        .trim_start_matches(['\n', '\r'])
        .starts_with("---")
    {
        return normalized_content.to_string();
    }

    let description =
        inferred_skill_description(normalized_content).unwrap_or("Generated skill suggestion");
    format!(
        "---\nname: {}\ndescription: {}\n---\n\n{}",
        requested_skill_name,
        yaml_double_quoted(description),
        normalized_content.trim_start_matches(['\n', '\r'])
    )
}

fn inferred_skill_description(content: &str) -> Option<&str> {
    content
        .lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix("# ").map(str::trim))
        .filter(|line| !line.is_empty())
}

fn yaml_double_quoted(value: &str) -> String {
    let mut quoted = String::with_capacity(value.len() + 2);
    quoted.push('"');
    for ch in value.chars() {
        match ch {
            '\\' => quoted.push_str("\\\\"),
            '"' => quoted.push_str("\\\""),
            '\n' => quoted.push_str("\\n"),
            '\r' => quoted.push_str("\\r"),
            '\t' => quoted.push_str("\\t"),
            _ => quoted.push(ch),
        }
    }
    quoted.push('"');
    quoted
}
