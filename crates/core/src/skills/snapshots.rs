//! Immutable skill catalog/command snapshots for run auditability.

use std::collections::BTreeMap;
use std::path::PathBuf;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::commands::SkillCommand;
use super::paths::{normalize_agent_id, snapshot_dir, snapshot_index_path};
use super::source_registry::source_versions;
use super::types::SkillCatalogEntry;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSnapshotList {
    pub snapshots: Vec<SkillSnapshotIndexEntry>,
    pub total: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSnapshotIndexEntry {
    pub snapshot_id: String,
    pub agent_id: String,
    pub purpose: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSnapshot {
    pub snapshot_id: String,
    pub agent_id: String,
    pub purpose: String,
    pub source_versions: BTreeMap<String, u64>,
    pub catalog_entries: Vec<SkillSnapshotCatalogEntry>,
    pub command_entries: Vec<SkillCommand>,
    pub status_counts: SkillSnapshotStatusCounts,
    pub catalog_plan: SkillCatalogPlan,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSnapshotCatalogEntry {
    pub name: String,
    pub version: String,
    pub description: String,
    pub trust: String,
    pub activation_hint: String,
    pub content_hash: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SkillSnapshotStatusCounts {
    pub ready: usize,
    pub disabled: usize,
    pub blocked: usize,
    pub missing_requirements: usize,
    pub parse_error: usize,
    pub security_blocked: usize,
    pub too_large: usize,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SkillCatalogPlan {
    pub total_available: usize,
    pub included: usize,
    pub omitted: usize,
    pub reason: String,
}

pub(super) async fn create_skill_snapshot(
    files_dir: &str,
    agent_id: &str,
    purpose: &str,
    catalog_entries: &[SkillCatalogEntry],
    total_available: usize,
    commands: Vec<SkillCommand>,
    status_counts: SkillSnapshotStatusCounts,
) -> Option<SkillSnapshot> {
    let agent_id = normalize_agent_id(agent_id);
    let snapshot = SkillSnapshot {
        snapshot_id: Uuid::new_v4().to_string(),
        agent_id: agent_id.clone(),
        purpose: purpose.to_string(),
        source_versions: source_versions(files_dir, &agent_id).await,
        catalog_entries: catalog_entries
            .iter()
            .map(|entry| SkillSnapshotCatalogEntry {
                name: entry.name.clone(),
                version: entry.version.clone(),
                description: entry.description.clone(),
                trust: entry.trust.clone(),
                activation_hint: entry.activation_hint.to_string(),
                content_hash: entry.content_hash.clone(),
            })
            .collect(),
        command_entries: commands,
        status_counts,
        catalog_plan: SkillCatalogPlan {
            total_available,
            included: catalog_entries.len(),
            omitted: total_available.saturating_sub(catalog_entries.len()),
            reason: if total_available > catalog_entries.len() {
                "catalog_entry_limit".to_string()
            } else {
                "all_included".to_string()
            },
        },
        created_at: Utc::now().to_rfc3339(),
    };
    save_snapshot(files_dir, &agent_id, &snapshot)
        .await
        .ok()
        .map(|()| snapshot)
}

pub async fn list_skill_snapshots(
    files_dir: &str,
    agent_id: &str,
    limit: usize,
    offset: usize,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let mut entries = load_index(files_dir, &agent_id).await;
    entries.sort_by(|left, right| right.created_at.cmp(&left.created_at));
    let total = entries.len();
    let limit = if limit == 0 { 50 } else { limit.min(200) };
    let snapshots = entries.into_iter().skip(offset).take(limit).collect();
    serde_json::to_string(&SkillSnapshotList { snapshots, total })
        .unwrap_or_else(|_| r#"{"snapshots":[],"total":0}"#.to_string())
}

pub async fn get_skill_snapshot(files_dir: &str, snapshot_id: &str) -> String {
    let root = super::paths::skills_root(files_dir).join("snapshots");
    let Some(path) = find_snapshot_path(&root, snapshot_id).await else {
        return "null".to_string();
    };
    tokio::fs::read_to_string(path)
        .await
        .unwrap_or_else(|_| "null".to_string())
}

pub async fn list_skill_snapshots_handle(
    handle: i64,
    agent_id: &str,
    limit: usize,
    offset: usize,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    list_skill_snapshots(&files_dir, agent_id, limit, offset).await
}

pub async fn get_skill_snapshot_handle(handle: i64, snapshot_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    get_skill_snapshot(&files_dir, snapshot_id).await
}

pub(super) fn status_counts_from_report(
    report: &super::status::SkillStatusReport,
) -> SkillSnapshotStatusCounts {
    SkillSnapshotStatusCounts {
        ready: report.ready,
        disabled: report.disabled,
        blocked: report.blocked,
        missing_requirements: report.missing_requirements,
        parse_error: report.parse_error,
        security_blocked: report.security_blocked,
        too_large: report.too_large,
    }
}

async fn save_snapshot(
    files_dir: &str,
    agent_id: &str,
    snapshot: &SkillSnapshot,
) -> Result<(), String> {
    let dir = snapshot_dir(files_dir, agent_id);
    tokio::fs::create_dir_all(&dir)
        .await
        .map_err(|e| e.to_string())?;
    let path = dir.join(format!("{}.json", snapshot.snapshot_id));
    let content = serde_json::to_string_pretty(snapshot).map_err(|e| e.to_string())?;
    napaxi_evolution::atomic_write_text(&path, &content)
        .await
        .map_err(|e| e.to_string())?;
    append_index(files_dir, agent_id, snapshot).await
}

async fn append_index(
    files_dir: &str,
    agent_id: &str,
    snapshot: &SkillSnapshot,
) -> Result<(), String> {
    let path = snapshot_index_path(files_dir, agent_id);
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| e.to_string())?;
    }
    let entry = SkillSnapshotIndexEntry {
        snapshot_id: snapshot.snapshot_id.clone(),
        agent_id: snapshot.agent_id.clone(),
        purpose: snapshot.purpose.clone(),
        created_at: snapshot.created_at.clone(),
    };
    let line = serde_json::to_string(&entry).map_err(|e| e.to_string())?;
    use tokio::io::AsyncWriteExt;
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .await
        .map_err(|e| e.to_string())?;
    file.write_all(line.as_bytes())
        .await
        .map_err(|e| e.to_string())?;
    file.write_all(b"\n").await.map_err(|e| e.to_string())
}

async fn load_index(files_dir: &str, agent_id: &str) -> Vec<SkillSnapshotIndexEntry> {
    let Ok(content) = tokio::fs::read_to_string(snapshot_index_path(files_dir, agent_id)).await
    else {
        return Vec::new();
    };
    content
        .lines()
        .filter_map(|line| serde_json::from_str::<SkillSnapshotIndexEntry>(line).ok())
        .collect()
}

async fn find_snapshot_path(root: &PathBuf, snapshot_id: &str) -> Option<PathBuf> {
    let mut agents = tokio::fs::read_dir(root).await.ok()?;
    while let Ok(Some(agent)) = agents.next_entry().await {
        let path = agent.path().join(format!("{snapshot_id}.json"));
        if path.exists() {
            return Some(path);
        }
    }
    None
}
