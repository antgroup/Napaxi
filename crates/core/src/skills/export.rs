#![cfg_attr(not(any(target_os = "android", test)), allow(dead_code))]

//! Codex-facing skill export mirror.
//!
//! Napaxi's authoritative skill store lives under `agent_runtime/skills`.  This
//! module publishes a read-only-by-convention mirror at `<files_dir>/prompt_skills`
//! so external sandboxes can mount it as `/skills` without depending on the
//! internal runtime layout.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::afs::registry;
use super::paths::{normalize_agent_id, safe_skill_name};

const PROMPT_SKILLS_DIR: &str = "prompt_skills";
const SKILL_MD: &str = "SKILL.md";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SkillExportReport {
    pub success: bool,
    pub agent_id: String,
    pub root: String,
    #[serde(default)]
    pub exported: Vec<String>,
    #[serde(default)]
    pub skipped: Vec<String>,
    pub error: Option<String>,
}

pub(crate) async fn export_prompt_skills(
    files_dir: &str,
    agent_id: &str,
) -> Result<SkillExportReport, String> {
    let agent_id = normalize_agent_id(agent_id);
    let target_root = prompt_skills_dir(files_dir);
    prepare_mirror_root(&target_root).await?;

    let registry = registry(files_dir, &agent_id).await;
    let mut exported = Vec::new();
    let mut skipped = Vec::new();
    let mut active_safe_names = std::collections::BTreeSet::new();
    for skill in registry.skills_for_user(&agent_id) {
        let name = skill.name();
        let Ok(safe_name) = safe_skill_name(name) else {
            skipped.push(name.to_string());
            continue;
        };
        active_safe_names.insert(safe_name.to_string());
        let Some(source_dir) = skill_source_dir(&skill) else {
            skipped.push(name.to_string());
            continue;
        };
        let target_dir = target_root.join(safe_name);
        match copy_skill_dir(source_dir, &target_dir).await {
            Ok(()) if target_dir.join(SKILL_MD).exists() => exported.push(name.to_string()),
            Ok(()) => {
                let _ = tokio::fs::remove_dir_all(&target_dir).await;
                skipped.push(name.to_string());
            }
            Err(_) => {
                let _ = tokio::fs::remove_dir_all(&target_dir).await;
                skipped.push(name.to_string());
            }
        }
    }
    remove_stale_skill_dirs(&target_root, &active_safe_names).await?;
    exported.sort();
    skipped.sort();
    Ok(SkillExportReport {
        success: true,
        agent_id,
        root: target_root.display().to_string(),
        exported,
        skipped,
        error: None,
    })
}

pub(crate) fn prompt_skills_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join(PROMPT_SKILLS_DIR)
}

async fn prepare_mirror_root(path: &Path) -> Result<(), String> {
    if let Ok(metadata) = tokio::fs::symlink_metadata(path).await
        && (metadata.file_type().is_symlink() || metadata.is_file())
    {
        tokio::fs::remove_file(path)
            .await
            .map_err(|e| format!("remove prompt skills file {}: {e}", path.display()))?;
    }
    tokio::fs::create_dir_all(path)
        .await
        .map_err(|e| format!("create prompt skills mirror {}: {e}", path.display()))
}

async fn remove_stale_skill_dirs(
    target_root: &Path,
    active_safe_names: &std::collections::BTreeSet<String>,
) -> Result<(), String> {
    let mut entries = tokio::fs::read_dir(target_root)
        .await
        .map_err(|e| format!("read prompt skills mirror {}: {e}", target_root.display()))?;
    while let Some(entry) = entries.next_entry().await.map_err(|e| {
        format!(
            "read prompt skills mirror entry {}: {e}",
            target_root.display()
        )
    })? {
        let file_name = entry.file_name();
        let Some(name) = file_name.to_str() else {
            continue;
        };
        if active_safe_names.contains(name) {
            continue;
        }
        let path = entry.path();
        let Ok(metadata) = tokio::fs::symlink_metadata(&path).await else {
            continue;
        };
        if metadata.is_dir() && !metadata.file_type().is_symlink() {
            tokio::fs::remove_dir_all(&path)
                .await
                .map_err(|e| format!("remove stale exported skill {}: {e}", path.display()))?;
        } else {
            tokio::fs::remove_file(&path)
                .await
                .map_err(|e| format!("remove stale exported skill file {}: {e}", path.display()))?;
        }
    }
    Ok(())
}

fn skill_source_dir(skill: &napaxi_skills::LoadedSkill) -> Option<&Path> {
    match &skill.source {
        napaxi_skills::SkillSource::Workspace(path)
        | napaxi_skills::SkillSource::User(path)
        | napaxi_skills::SkillSource::Installed(path)
        | napaxi_skills::SkillSource::Bundled(path) => Some(path.as_path()),
    }
}

async fn copy_skill_dir(source: &Path, target: &Path) -> Result<(), String> {
    let source_root = tokio::fs::canonicalize(source)
        .await
        .map_err(|e| format!("canonicalize skill source {}: {e}", source.display()))?;
    tokio::fs::create_dir_all(target)
        .await
        .map_err(|e| format!("create exported skill {}: {e}", target.display()))?;
    copy_dir_entries(&source_root, &source_root, target).await
}

async fn copy_dir_entries(
    source_root: &Path,
    source_dir: &Path,
    target_root: &Path,
) -> Result<(), String> {
    let mut entries = tokio::fs::read_dir(source_dir)
        .await
        .map_err(|e| format!("read skill dir {}: {e}", source_dir.display()))?;
    while let Some(entry) = entries
        .next_entry()
        .await
        .map_err(|e| format!("read skill dir entry {}: {e}", source_dir.display()))?
    {
        let path = entry.path();
        let metadata = tokio::fs::symlink_metadata(&path)
            .await
            .map_err(|e| format!("stat skill path {}: {e}", path.display()))?;
        if metadata.file_type().is_symlink() {
            continue;
        }
        let relative = path
            .strip_prefix(source_root)
            .map_err(|_| format!("skill path escaped source root: {}", path.display()))?;
        if !is_safe_relative_path(relative) {
            continue;
        }
        let target = target_root.join(relative);
        if metadata.is_dir() {
            tokio::fs::create_dir_all(&target)
                .await
                .map_err(|e| format!("create exported skill dir {}: {e}", target.display()))?;
            Box::pin(copy_dir_entries(source_root, &path, target_root)).await?;
        } else if metadata.is_file() {
            if let Some(parent) = target.parent() {
                tokio::fs::create_dir_all(parent).await.map_err(|e| {
                    format!("create exported skill parent {}: {e}", parent.display())
                })?;
            }
            tokio::fs::copy(&path, &target).await.map_err(|e| {
                format!(
                    "copy skill file {} -> {}: {e}",
                    path.display(),
                    target.display()
                )
            })?;
        }
    }
    Ok(())
}

fn is_safe_relative_path(path: &Path) -> bool {
    !path.as_os_str().is_empty()
        && path
            .components()
            .all(|component| matches!(component, std::path::Component::Normal(_)))
}
