//! Secret requirement status without persisting secret values.

use serde::{Deserialize, Serialize};

use super::config::load_skill_config;
use super::paths::normalize_agent_id;
use super::status::{SkillStatusEntry, list_skill_status};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSecretRequirementReport {
    pub requirements: Vec<SkillSecretRequirement>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSecretRequirement {
    pub skill_name: String,
    pub skill_key: String,
    pub key: String,
    pub source: String,
    pub available: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSecretAvailability {
    pub skill_name: String,
    pub key: String,
    pub available: bool,
    pub source: String,
}

pub async fn list_skill_secret_requirements(
    files_dir: &str,
    agent_id: &str,
    skill_name: Option<&str>,
    readiness: &napaxi_skills::SkillReadinessContext,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let status_raw = list_skill_status(files_dir, &agent_id, readiness).await;
    let entries = serde_json::from_str::<super::status::SkillStatusReport>(&status_raw)
        .map(|report| report.entries)
        .unwrap_or_default();
    let config = load_skill_config(files_dir, &agent_id).await;
    let mut requirements = Vec::new();
    for entry in entries {
        if let Some(skill_name) = skill_name.filter(|value| !value.trim().is_empty())
            && entry.name != skill_name
        {
            continue;
        }
        append_entry_requirements(&mut requirements, entry, &config);
    }
    serde_json::to_string(&SkillSecretRequirementReport { requirements })
        .unwrap_or_else(|_| r#"{"requirements":[]}"#.to_string())
}

pub async fn record_skill_secret_availability(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    key: &str,
    available: bool,
    source: &str,
) -> String {
    let patch = if available {
        serde_json::json!({"env_keys": [key], "secret_sources": { key: source }})
    } else {
        serde_json::json!({"remove_env_keys": [key], "secret_sources": { key: source }})
    };
    super::config::update_skill_config(files_dir, agent_id, skill_name, &patch.to_string()).await
}

pub async fn list_skill_secret_requirements_handle(
    handle: i64,
    agent_id: &str,
    skill_name: Option<&str>,
) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    list_skill_secret_requirements(&files_dir, agent_id, skill_name, &readiness).await
}

pub async fn record_skill_secret_availability_handle(
    handle: i64,
    agent_id: &str,
    skill_name: &str,
    key: &str,
    available: bool,
    source: &str,
) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    let _ =
        record_skill_secret_availability(&files_dir, agent_id, skill_name, key, available, source)
            .await;
    super::status::list_skill_status(&files_dir, agent_id, &readiness).await
}

fn append_entry_requirements(
    out: &mut Vec<SkillSecretRequirement>,
    entry: SkillStatusEntry,
    config: &super::config::SkillConfigStore,
) {
    let skill_key = entry
        .metadata
        .skill_key
        .clone()
        .unwrap_or_else(|| entry.name.clone());
    let configured = config
        .entries
        .get(&skill_key)
        .or_else(|| config.entries.get(&entry.name));
    for key in entry.requirements.env {
        let source = configured
            .and_then(|entry| entry.secret_sources.get(&key).cloned())
            .unwrap_or_else(|| "host".to_string());
        out.push(SkillSecretRequirement {
            skill_name: entry.name.clone(),
            skill_key: skill_key.clone(),
            available: configured
                .map(|entry| entry.env_keys.contains(&key))
                .unwrap_or(false),
            key,
            source,
        });
    }
    if let Some(primary) = entry.metadata.primary_env
        && !out
            .iter()
            .any(|item| item.skill_name == entry.name && item.key == primary)
    {
        out.push(SkillSecretRequirement {
            skill_name: entry.name,
            skill_key,
            key: primary,
            source: "host".to_string(),
            available: false,
        });
    }
}

fn readiness_from_handle(handle: i64) -> Option<(String, napaxi_skills::SkillReadinessContext)> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { crate::runtime::handle_to_arc(handle) }?;
    Some((
        engine.files_dir().to_string(),
        engine.skill_readiness_context(),
    ))
}
