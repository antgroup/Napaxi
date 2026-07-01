//! Read/list/get/pin/archive/restore + backup-with-rollback wrappers.

use std::path::Path;

use chrono::Utc;

use super::afs::registry;
use super::limits::{MAX_EXTRA_FILE_SIZE, invalid_handle_json};
use super::paths::{
    agent_skills_dir, archive_dir, backups_dir, normalize_agent_id, safe_skill_relative_path,
    skill_dir_path, skill_target_path, validate_delete_target,
};
use super::types::{ArchivedSkillRecord, SkillBackup, SkillLifecycleState};
use super::usage::{
    is_record_protected, is_source_protected, lifecycle_json_for_skill, load_usage_map,
    record_skill_view, skill_summary, update_usage_record,
};

pub async fn list_skills(files_dir: &str, agent_id: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let registry = registry(files_dir, &agent_id).await;
    let usage = load_usage_map(files_dir, &agent_id).await;
    let skills: Vec<_> = registry
        .skills_for_user(&agent_id)
        .iter()
        .map(|skill| skill_summary(skill, usage.get(skill.name())))
        .collect();
    serde_json::to_string(&skills).unwrap_or_else(|_| "[]".to_string())
}

pub async fn list_skills_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_skills(&files_dir, agent_id).await
}

pub async fn remove_skill(files_dir: &str, agent_id: &str, skill_name: &str) -> bool {
    let agent_id = normalize_agent_id(agent_id);
    let registry = registry(files_dir, &agent_id).await;
    registry.remove_skill(skill_name, &agent_id).await.is_ok()
}

pub async fn remove_skill_handle(handle: i64, agent_id: &str, skill_name: &str) -> bool {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return false;
    };
    remove_skill(&files_dir, agent_id, skill_name).await
}

pub async fn reload_skills(files_dir: &str, agent_id: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let registry = registry(files_dir, &agent_id).await;
    let names: Vec<_> = registry
        .skills_for_user(&agent_id)
        .iter()
        .map(|skill| skill.name().to_string())
        .collect();
    serde_json::to_string(&names).unwrap_or_else(|_| "[]".to_string())
}

pub async fn reload_skills_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    reload_skills(&files_dir, agent_id).await
}

pub async fn get_skill(files_dir: &str, agent_id: &str, skill_name: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let registry = registry(files_dir, &agent_id).await;
    match registry.find_by_name_for_user(skill_name, &agent_id) {
        Some(skill) => {
            record_skill_view(files_dir, &agent_id, skill_name).await;
            let usage = load_usage_map(files_dir, &agent_id).await;
            let support_files = match skill_source_dir(&skill) {
                Some(dir) => list_support_files_for_skill(dir).await,
                None => Vec::new(),
            };
            serde_json::to_string(&serde_json::json!({
                "name": skill.name(),
                "version": skill.version(),
                "description": skill.manifest.description,
                "always": false,
                "allowed_agents": [],
                "trust": skill.trust.to_string(),
                "source": format!("{:?}", skill.source),
                "keywords": skill.manifest.activation.keywords,
                "tags": skill.manifest.activation.tags,
                "prompt_content": skill.prompt_content,
                "content_hash": skill.content_hash,
                "support_files": support_files,
                "lifecycle": lifecycle_json_for_skill(&skill, usage.get(skill.name())),
            }))
            .unwrap_or_else(|_| "null".to_string())
        }
        None => "null".to_string(),
    }
}

pub async fn get_skill_handle(handle: i64, agent_id: &str, skill_name: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "null".to_string();
    };
    get_skill(&files_dir, agent_id, skill_name).await
}

pub async fn list_skill_usage(files_dir: &str, agent_id: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let usage = load_usage_map(files_dir, &agent_id).await;
    let mut records: Vec<_> = usage.into_values().collect();
    records.sort_by(|a, b| a.skill_name.cmp(&b.skill_name));
    serde_json::to_string(&records).unwrap_or_else(|_| "[]".to_string())
}

pub async fn list_skill_usage_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_skill_usage(&files_dir, agent_id).await
}

pub async fn pin_skill(files_dir: &str, agent_id: &str, skill_name: &str, pinned: bool) -> String {
    let agent_id = normalize_agent_id(agent_id);
    match update_usage_record(files_dir, &agent_id, skill_name, |record| {
        record.pinned = pinned;
    })
    .await
    {
        Ok(record) => serde_json::json!({"success": true, "usage": record}).to_string(),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn pin_skill_handle(
    handle: i64,
    agent_id: &str,
    skill_name: &str,
    pinned: bool,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    pin_skill(&files_dir, agent_id, skill_name, pinned).await
}

pub async fn archive_skill(files_dir: &str, agent_id: &str, skill_name: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    match archive_skill_dir(files_dir, &agent_id, skill_name, None).await {
        Ok(record) => serde_json::json!({"success": true, "archive": record}).to_string(),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn archive_skill_handle(handle: i64, agent_id: &str, skill_name: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    archive_skill(&files_dir, agent_id, skill_name).await
}

pub async fn restore_skill(files_dir: &str, agent_id: &str, skill_name: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    match restore_archived_skill_dir(files_dir, &agent_id, skill_name).await {
        Ok(record) => serde_json::json!({"success": true, "restore": record}).to_string(),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn restore_skill_handle(handle: i64, agent_id: &str, skill_name: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    restore_skill(&files_dir, agent_id, skill_name).await
}

pub async fn read_skill_support_file(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    file_path: &str,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let relative_path = match safe_skill_relative_path(Some(file_path)) {
        Ok(path) if path != Path::new("SKILL.md") => path,
        Ok(_) => {
            return serde_json::json!({"error": "SKILL.md is not a support file"}).to_string();
        }
        Err(error) => return serde_json::json!({"error": error}).to_string(),
    };
    let target = match skill_target_path(
        files_dir,
        &agent_id,
        skill_name,
        Some(&relative_path.display().to_string()),
    ) {
        Ok(path) => path,
        Err(error) => return serde_json::json!({"error": error}).to_string(),
    };
    if let Err(error) =
        ensure_support_path_contained(files_dir, &agent_id, skill_name, &target).await
    {
        return serde_json::json!({"error": error}).to_string();
    }
    match tokio::fs::metadata(&target).await {
        Ok(metadata) if metadata.len() > MAX_EXTRA_FILE_SIZE => {
            return serde_json::json!({"error": "support file too large"}).to_string();
        }
        Ok(metadata) if metadata.is_file() => {}
        Ok(_) => return serde_json::json!({"error": "support path is not a file"}).to_string(),
        Err(error) => {
            return serde_json::json!({"error": format!("stat {}: {error}", target.display())})
                .to_string();
        }
    }
    match tokio::fs::read_to_string(&target).await {
        Ok(content) => serde_json::json!({
            "success": true,
            "skill_name": skill_name,
            "file_path": relative_path.display().to_string(),
            "content": content,
        })
        .to_string(),
        Err(error) => {
            serde_json::json!({"error": format!("read {}: {error}", target.display())}).to_string()
        }
    }
}

pub async fn read_skill_support_file_handle(
    handle: i64,
    agent_id: &str,
    skill_name: &str,
    file_path: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    read_skill_support_file(&files_dir, agent_id, skill_name, file_path).await
}

fn skill_source_dir(skill: &napaxi_skills::LoadedSkill) -> Option<&Path> {
    match &skill.source {
        napaxi_skills::SkillSource::Workspace(path)
        | napaxi_skills::SkillSource::User(path)
        | napaxi_skills::SkillSource::Installed(path)
        | napaxi_skills::SkillSource::Bundled(path) => Some(path.as_path()),
    }
}

async fn list_support_files_for_skill(skill_dir: &Path) -> Vec<String> {
    let mut out = Vec::new();
    collect_support_files(skill_dir, skill_dir, &mut out).await;
    out.sort();
    out
}

async fn collect_support_files(skill_dir: &Path, dir: &Path, out: &mut Vec<String>) {
    let Ok(mut entries) = tokio::fs::read_dir(dir).await else {
        return;
    };
    while let Ok(Some(entry)) = entries.next_entry().await {
        let path = entry.path();
        let Ok(metadata) = tokio::fs::symlink_metadata(&path).await else {
            continue;
        };
        if metadata.file_type().is_symlink() {
            continue;
        }
        if is_hidden_skill_path(&path, skill_dir) {
            continue;
        }
        if metadata.is_dir() {
            Box::pin(collect_support_files(skill_dir, &path, out)).await;
        } else if metadata.is_file()
            && metadata.len() <= MAX_EXTRA_FILE_SIZE
            && let Ok(relative) = path.strip_prefix(skill_dir)
            && relative != Path::new("SKILL.md")
            && relative != Path::new("_meta.json")
        {
            out.push(relative.display().to_string());
        }
    }
}

fn is_hidden_skill_path(path: &Path, skill_dir: &Path) -> bool {
    path.strip_prefix(skill_dir)
        .ok()
        .and_then(|relative| relative.components().next())
        .and_then(|component| match component {
            std::path::Component::Normal(part) => part.to_str(),
            _ => None,
        })
        .map(|part| part.starts_with('.'))
        .unwrap_or(false)
}

async fn ensure_support_path_contained(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    target: &Path,
) -> Result<(), String> {
    let skill_dir = skill_dir_path(files_dir, agent_id, skill_name)?;
    let root = tokio::fs::canonicalize(&skill_dir)
        .await
        .map_err(|e| format!("canonicalize {}: {e}", skill_dir.display()))?;
    let target = tokio::fs::canonicalize(target)
        .await
        .map_err(|e| format!("canonicalize support file: {e}"))?;
    if target.starts_with(&root) {
        Ok(())
    } else {
        Err("support file resolves outside the skill directory".to_string())
    }
}

pub(super) async fn create_skill_backup(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    operation: &str,
) -> Result<Option<SkillBackup>, String> {
    let Ok(skill_dir) = skill_dir_path(files_dir, agent_id, skill_name) else {
        return Ok(None);
    };
    let backup_path = backups_dir(files_dir, agent_id).join(format!(
        "{}-{}-{}",
        Utc::now().timestamp_millis(),
        operation,
        skill_name
    ));
    napaxi_evolution::atomic_copy_dir(&skill_dir, &backup_path)
        .await
        .map_err(|e| format!("backup {}: {e}", skill_dir.display()))?;
    Ok(Some(SkillBackup {
        backup_path,
        shadow_path: {
            let agent_dir = agent_skills_dir(files_dir, agent_id).join(skill_name);
            (agent_dir != skill_dir).then_some(agent_dir)
        },
        original_path: skill_dir,
    }))
}

pub(super) async fn restore_skill_backup(backup: Option<&SkillBackup>) -> Result<(), String> {
    let Some(backup) = backup else {
        return Ok(());
    };
    if backup.original_path.exists() {
        tokio::fs::remove_dir_all(&backup.original_path)
            .await
            .map_err(|e| format!("remove partial {}: {e}", backup.original_path.display()))?;
    }
    napaxi_evolution::atomic_copy_dir(&backup.backup_path, &backup.original_path)
        .await
        .map_err(|e| format!("restore {}: {e}", backup.backup_path.display()))?;
    if let Some(shadow_path) = &backup.shadow_path
        && shadow_path.exists()
    {
        tokio::fs::remove_dir_all(shadow_path)
            .await
            .map_err(|e| format!("remove partial shadow {}: {e}", shadow_path.display()))?;
    }
    Ok(())
}

pub(super) async fn with_skill_backup<F, Fut>(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    operation: &str,
    action: F,
) -> Result<String, String>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<String, String>>,
{
    let backup = create_skill_backup(files_dir, agent_id, skill_name, operation).await?;
    match action().await {
        Ok(message) => Ok(message),
        Err(error) => {
            if let Err(restore_error) = restore_skill_backup(backup.as_ref()).await {
                Err(format!("{error}; rollback failed: {restore_error}"))
            } else {
                Err(error)
            }
        }
    }
}

pub(super) async fn archive_skill_dir(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    absorbed_into: Option<&str>,
) -> Result<ArchivedSkillRecord, String> {
    if skill_is_protected(files_dir, agent_id, skill_name).await {
        return Err(format!(
            "Skill '{}' is protected and cannot be archived automatically",
            skill_name
        ));
    }
    let source = skill_dir_path(files_dir, agent_id, skill_name)?;
    let mut target = archive_dir(files_dir, agent_id).join(skill_name);
    if target.exists() {
        target = archive_dir(files_dir, agent_id).join(format!(
            "{}-{}",
            skill_name,
            Utc::now().timestamp_millis()
        ));
    }
    napaxi_evolution::atomic_copy_dir(&source, &target)
        .await
        .map_err(|e| format!("archive {}: {e}", source.display()))?;
    validate_delete_target(files_dir, &source)?;
    tokio::fs::remove_dir_all(&source)
        .await
        .map_err(|e| format!("remove archived source {}: {e}", source.display()))?;
    let archived_at = Utc::now().to_rfc3339();
    let _ = update_usage_record(files_dir, agent_id, skill_name, |record| {
        record.state = SkillLifecycleState::Archived;
        record.archived_at = Some(archived_at.clone());
        record.absorbed_into = absorbed_into.map(str::to_string);
    })
    .await;
    Ok(ArchivedSkillRecord {
        skill_name: skill_name.to_string(),
        archived_at,
        archive_path: target.display().to_string(),
        original_path: source.display().to_string(),
        absorbed_into: absorbed_into.map(str::to_string),
    })
}

pub(super) async fn skill_is_protected(files_dir: &str, agent_id: &str, skill_name: &str) -> bool {
    let usage = load_usage_map(files_dir, agent_id).await;
    if usage.get(skill_name).is_some_and(is_record_protected) {
        return true;
    }
    let registry = registry(files_dir, agent_id).await;
    registry
        .find_by_name_for_user(skill_name, agent_id)
        .as_ref()
        .is_some_and(|skill| is_source_protected(skill))
}

async fn restore_archived_skill_dir(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
) -> Result<ArchivedSkillRecord, String> {
    let archive_root = archive_dir(files_dir, agent_id);
    let exact = archive_root.join(skill_name);
    let source = if exact.exists() {
        exact
    } else {
        let mut entries = tokio::fs::read_dir(&archive_root)
            .await
            .map_err(|e| format!("read archive {}: {e}", archive_root.display()))?;
        let mut match_path = None;
        while let Some(entry) = entries
            .next_entry()
            .await
            .map_err(|e| format!("read archive entry: {e}"))?
        {
            let file_name = entry.file_name().to_string_lossy().to_string();
            if file_name.starts_with(&format!("{skill_name}-")) {
                match_path = Some(entry.path());
                break;
            }
        }
        match_path.ok_or_else(|| format!("Archived skill '{}' was not found", skill_name))?
    };
    let target = agent_skills_dir(files_dir, agent_id).join(skill_name);
    if target.exists() {
        return Err(format!("Skill '{}' already exists", skill_name));
    }
    napaxi_evolution::atomic_copy_dir(&source, &target)
        .await
        .map_err(|e| format!("restore archive {}: {e}", source.display()))?;
    validate_delete_target(files_dir, &source)?;
    tokio::fs::remove_dir_all(&source)
        .await
        .map_err(|e| format!("remove archive {}: {e}", source.display()))?;
    let restored_at = Utc::now().to_rfc3339();
    let _ = update_usage_record(files_dir, agent_id, skill_name, |record| {
        record.state = SkillLifecycleState::Active;
        record.archived_at = None;
        record.absorbed_into = None;
    })
    .await;
    Ok(ArchivedSkillRecord {
        skill_name: skill_name.to_string(),
        archived_at: restored_at,
        archive_path: source.display().to_string(),
        original_path: target.display().to_string(),
        absorbed_into: None,
    })
}
