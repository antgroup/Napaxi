//! Core-owned skill source registry and source version state.

use std::collections::BTreeMap;
use std::path::PathBuf;

use chrono::Utc;
use serde::{Deserialize, Serialize};

use super::paths::{
    agent_skills_dir, app_bundled_skills_dir, host_installed_skills_dir, installed_skills_dir,
    legacy_agent_skills_dir, legacy_installed_skills_dir, normalize_agent_id, source_state_path,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSourceReport {
    pub agent_id: String,
    pub sources: Vec<SkillSourceEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSourceEntry {
    pub id: String,
    pub kind: String,
    pub root: String,
    pub priority: u8,
    pub trust: String,
    pub exists: bool,
    pub version: u64,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRefreshResult {
    pub success: bool,
    pub agent_id: String,
    pub source_id: String,
    pub version: u64,
    pub recorded_at: String,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub(super) struct SkillSourceRoot {
    pub(super) id: String,
    pub(super) kind: String,
    pub(super) root: PathBuf,
    pub(super) priority: u8,
    pub(super) trust: &'static str,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct SkillSourceState {
    #[serde(default)]
    sources: BTreeMap<String, SkillSourceVersion>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct SkillSourceVersion {
    #[serde(default)]
    version: u64,
    updated_at: Option<String>,
}

pub(super) fn source_roots(files_dir: &str, agent_id: &str) -> Vec<SkillSourceRoot> {
    let agent_id = normalize_agent_id(agent_id);
    vec![
        SkillSourceRoot {
            id: "agent_created".to_string(),
            kind: "agent_created".to_string(),
            root: agent_skills_dir(files_dir, &agent_id),
            priority: 0,
            trust: "trusted",
        },
        SkillSourceRoot {
            id: "catalog_installed".to_string(),
            kind: "catalog_installed".to_string(),
            root: installed_skills_dir(files_dir, &agent_id),
            priority: 1,
            trust: "installed",
        },
        SkillSourceRoot {
            id: "host_installed".to_string(),
            kind: "host_installed".to_string(),
            root: host_installed_skills_dir(files_dir, &agent_id),
            priority: 2,
            trust: "installed",
        },
        SkillSourceRoot {
            id: "app_bundled".to_string(),
            kind: "app_bundled".to_string(),
            root: app_bundled_skills_dir(files_dir),
            priority: 3,
            trust: "trusted",
        },
        SkillSourceRoot {
            id: "legacy_agent_created".to_string(),
            kind: "legacy".to_string(),
            root: legacy_agent_skills_dir(files_dir, &agent_id),
            priority: 4,
            trust: "trusted",
        },
        SkillSourceRoot {
            id: "legacy_catalog_installed".to_string(),
            kind: "legacy".to_string(),
            root: legacy_installed_skills_dir(files_dir, &agent_id),
            priority: 5,
            trust: "installed",
        },
    ]
}

pub(super) async fn source_versions(files_dir: &str, agent_id: &str) -> BTreeMap<String, u64> {
    let state = load_state(files_dir, agent_id).await;
    source_roots(files_dir, agent_id)
        .into_iter()
        .map(|source| {
            let version = state
                .sources
                .get(&source.id)
                .map(|entry| entry.version)
                .unwrap_or(0);
            (source.id, version)
        })
        .collect()
}

pub async fn list_skill_sources(files_dir: &str, agent_id: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let state = load_state(files_dir, &agent_id).await;
    let sources = source_roots(files_dir, &agent_id)
        .into_iter()
        .map(|source| {
            let version = state.sources.get(&source.id);
            SkillSourceEntry {
                id: source.id,
                kind: source.kind,
                root: source.root.display().to_string(),
                priority: source.priority,
                trust: source.trust.to_string(),
                exists: source.root.exists(),
                version: version.map(|entry| entry.version).unwrap_or(0),
                updated_at: version.and_then(|entry| entry.updated_at.clone()),
            }
        })
        .collect();
    serde_json::to_string(&SkillSourceReport { agent_id, sources })
        .unwrap_or_else(|_| r#"{"sources":[]}"#.to_string())
}

pub async fn record_skill_source_changed(
    files_dir: &str,
    agent_id: &str,
    source_id: &str,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let valid = source_roots(files_dir, &agent_id)
        .into_iter()
        .any(|source| source.id == source_id);
    if !valid {
        return serde_json::to_string(&SkillRefreshResult {
            success: false,
            agent_id,
            source_id: source_id.to_string(),
            version: 0,
            recorded_at: Utc::now().to_rfc3339(),
            error: Some(format!("unknown skill source: {source_id}")),
        })
        .unwrap_or_else(|_| "{}".to_string());
    }

    let mut state = load_state(files_dir, &agent_id).await;
    let now = Utc::now().to_rfc3339();
    let entry = state.sources.entry(source_id.to_string()).or_default();
    entry.version = entry.version.saturating_add(1);
    entry.updated_at = Some(now.clone());
    let version = entry.version;
    let error = save_state(files_dir, &agent_id, &state).await.err();
    serde_json::to_string(&SkillRefreshResult {
        success: error.is_none(),
        agent_id,
        source_id: source_id.to_string(),
        version,
        recorded_at: now,
        error,
    })
    .unwrap_or_else(|_| "{}".to_string())
}

pub async fn list_skill_sources_handle(handle: i64, agent_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    list_skill_sources(&files_dir, agent_id).await
}

pub async fn record_skill_source_changed_handle(
    handle: i64,
    agent_id: &str,
    source_id: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    record_skill_source_changed(&files_dir, agent_id, source_id).await
}

async fn load_state(files_dir: &str, agent_id: &str) -> SkillSourceState {
    match tokio::fs::read_to_string(source_state_path(files_dir, agent_id)).await {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => SkillSourceState::default(),
    }
}

async fn save_state(
    files_dir: &str,
    agent_id: &str,
    state: &SkillSourceState,
) -> Result<(), String> {
    let path = source_state_path(files_dir, agent_id);
    let content = serde_json::to_string_pretty(state).map_err(|e| e.to_string())?;
    napaxi_evolution::atomic_write_text(&path, &content)
        .await
        .map_err(|e| e.to_string())
}
