//! Per-agent skill configuration, remediation audit, and readiness merging.

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use chrono::Utc;
use serde::{Deserialize, Serialize};

use super::paths::{normalize_agent_id, skills_root};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(super) struct SkillConfigStore {
    #[serde(default)]
    pub(super) entries: BTreeMap<String, SkillConfigEntry>,
    #[serde(default)]
    pub(super) remediation_log: Vec<SkillRequirementResolutionRecord>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(super) struct SkillConfigEntry {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) enabled: Option<bool>,
    #[serde(default)]
    pub(super) env_keys: BTreeSet<String>,
    #[serde(default)]
    pub(super) config_flags: BTreeSet<String>,
    #[serde(default)]
    pub(super) secret_sources: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct SkillRequirementResolutionRecord {
    pub(super) skill_name: String,
    pub(super) action_id: String,
    pub(super) result: serde_json::Value,
    pub(super) recorded_at: String,
}

impl SkillConfigStore {
    pub(super) fn entry_for_manifest(
        &self,
        manifest: &napaxi_skills::SkillManifest,
    ) -> Option<&SkillConfigEntry> {
        skill_config_keys(manifest)
            .into_iter()
            .find_map(|key| self.entries.get(&key))
    }

    pub(super) fn is_enabled(&self, manifest: &napaxi_skills::SkillManifest) -> bool {
        self.entry_for_manifest(manifest)
            .and_then(|entry| entry.enabled)
            .unwrap_or(true)
    }

    pub(super) fn apply_to_readiness(
        &self,
        base: &napaxi_skills::SkillReadinessContext,
    ) -> napaxi_skills::SkillReadinessContext {
        let mut merged = base.clone();
        append_unique(
            &mut merged.env_keys,
            self.entries
                .values()
                .flat_map(|entry| entry.env_keys.iter().cloned()),
        );
        append_unique(
            &mut merged.config_flags,
            self.entries
                .values()
                .flat_map(|entry| entry.config_flags.iter().cloned()),
        );
        merged
    }
}

pub(super) fn skill_config_key(manifest: &napaxi_skills::SkillManifest) -> String {
    manifest
        .metadata_string("skillKey")
        .unwrap_or_else(|| manifest.name.clone())
}

pub(super) fn skill_config_keys(manifest: &napaxi_skills::SkillManifest) -> Vec<String> {
    let primary = skill_config_key(manifest);
    if primary == manifest.name {
        vec![primary]
    } else {
        vec![primary, manifest.name.clone()]
    }
}

pub(super) async fn load_skill_config(files_dir: &str, agent_id: &str) -> SkillConfigStore {
    let path = skill_config_path(files_dir, agent_id);
    let content = match tokio::fs::read_to_string(&path).await {
        Ok(content) => content,
        Err(_) => return SkillConfigStore::default(),
    };
    serde_json::from_str(&content).unwrap_or_default()
}

async fn save_skill_config(
    files_dir: &str,
    agent_id: &str,
    config: &SkillConfigStore,
) -> Result<(), String> {
    let path = skill_config_path(files_dir, agent_id);
    let content = serde_json::to_string_pretty(config).map_err(|e| e.to_string())?;
    napaxi_evolution::atomic_write_text(&path, &content)
        .await
        .map_err(|e| e.to_string())
}

pub(super) async fn set_skill_enabled(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    enabled: bool,
) -> String {
    let mut config = load_skill_config(files_dir, agent_id).await;
    let entry = config
        .entries
        .entry(skill_name.trim().to_string())
        .or_default();
    entry.enabled = Some(enabled);
    entry.updated_at = Some(Utc::now().to_rfc3339());
    match save_skill_config(files_dir, agent_id, &config).await {
        Ok(()) => serde_json::json!({
            "success": true,
            "skill_key": skill_name,
            "enabled": enabled,
        })
        .to_string(),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn set_skill_enabled_handle(
    handle: i64,
    agent_id: &str,
    skill_name: &str,
    enabled: bool,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    set_skill_enabled(&files_dir, agent_id, skill_name, enabled).await
}

pub(super) async fn update_skill_config(
    files_dir: &str,
    agent_id: &str,
    skill_key: &str,
    patch_json: &str,
) -> String {
    let patch = match serde_json::from_str::<serde_json::Value>(patch_json) {
        Ok(value) => value,
        Err(error) => {
            return serde_json::json!({"error": format!("invalid patch JSON: {error}")})
                .to_string();
        }
    };
    let mut config = load_skill_config(files_dir, agent_id).await;
    let response_config = {
        let entry = config
            .entries
            .entry(skill_key.trim().to_string())
            .or_default();

        if let Some(enabled) = patch.get("enabled").and_then(serde_json::Value::as_bool) {
            entry.enabled = Some(enabled);
        }
        for key in string_array_field(&patch, "env_keys")
            .into_iter()
            .chain(object_keys_field(&patch, "env"))
        {
            entry.env_keys.insert(key);
        }
        for key in string_array_field(&patch, "remove_env_keys") {
            entry.env_keys.remove(&key);
        }
        for (key, source) in string_string_object_field(&patch, "secret_sources") {
            entry.secret_sources.insert(key, source);
        }
        for key in string_array_field(&patch, "config_flags")
            .into_iter()
            .chain(object_truthy_keys_field(&patch, "config"))
        {
            entry.config_flags.insert(key);
        }
        entry.updated_at = Some(Utc::now().to_rfc3339());
        sanitized_entry(entry)
    };

    match save_skill_config(files_dir, agent_id, &config).await {
        Ok(()) => serde_json::json!({
            "success": true,
            "skill_key": skill_key,
            "config": response_config,
        })
        .to_string(),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn update_skill_config_handle(
    handle: i64,
    agent_id: &str,
    skill_key: &str,
    patch_json: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    update_skill_config(&files_dir, agent_id, skill_key, patch_json).await
}

pub(super) async fn record_skill_requirement_resolution(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    action_id: &str,
    result_json: &str,
) -> String {
    let result = serde_json::from_str::<serde_json::Value>(result_json)
        .unwrap_or_else(|_| serde_json::Value::String(result_json.to_string()));
    let mut config = load_skill_config(files_dir, agent_id).await;
    config
        .remediation_log
        .push(SkillRequirementResolutionRecord {
            skill_name: skill_name.to_string(),
            action_id: action_id.to_string(),
            result: result.clone(),
            recorded_at: Utc::now().to_rfc3339(),
        });
    if config.remediation_log.len() > 200 {
        let drop_count = config.remediation_log.len() - 200;
        config.remediation_log.drain(0..drop_count);
    }
    super::remediation::record_fulfilled_resolution_run(
        files_dir, agent_id, skill_name, action_id, result,
    )
    .await;
    match save_skill_config(files_dir, agent_id, &config).await {
        Ok(()) => serde_json::json!({"success": true}).to_string(),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn record_skill_requirement_resolution_handle(
    handle: i64,
    agent_id: &str,
    skill_name: &str,
    action_id: &str,
    result_json: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    record_skill_requirement_resolution(
        files_dir.as_str(),
        agent_id,
        skill_name,
        action_id,
        result_json,
    )
    .await
}

fn skill_config_path(files_dir: &str, agent_id: &str) -> PathBuf {
    skills_root(files_dir)
        .join("config")
        .join(format!("{}.json", normalize_agent_id(agent_id)))
}

fn append_unique(target: &mut Vec<String>, values: impl IntoIterator<Item = String>) {
    let mut seen = target
        .iter()
        .map(|value| value.trim().to_lowercase())
        .collect::<BTreeSet<_>>();
    for value in values {
        let value = value.trim();
        if value.is_empty() {
            continue;
        }
        if seen.insert(value.to_lowercase()) {
            target.push(value.to_string());
        }
    }
}

fn string_array_field(value: &serde_json::Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(serde_json::Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(serde_json::Value::as_str)
                .map(str::trim)
                .filter(|item| !item.is_empty())
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn object_keys_field(value: &serde_json::Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(serde_json::Value::as_object)
        .map(|items| {
            items
                .keys()
                .map(|item| item.trim())
                .filter(|item| !item.is_empty())
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn object_truthy_keys_field(value: &serde_json::Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(serde_json::Value::as_object)
        .map(|items| {
            items
                .iter()
                .filter(|(_, value)| value.as_bool().unwrap_or(true))
                .map(|(item, _)| item.trim())
                .filter(|item| !item.is_empty())
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn string_string_object_field(value: &serde_json::Value, key: &str) -> Vec<(String, String)> {
    value
        .get(key)
        .and_then(serde_json::Value::as_object)
        .map(|items| {
            items
                .iter()
                .filter_map(|(item, value)| {
                    let item = item.trim();
                    let value = value.as_str()?.trim();
                    if item.is_empty() || value.is_empty() {
                        None
                    } else {
                        Some((item.to_string(), value.to_string()))
                    }
                })
                .collect()
        })
        .unwrap_or_default()
}

fn sanitized_entry(entry: &SkillConfigEntry) -> serde_json::Value {
    serde_json::json!({
        "enabled": entry.enabled,
        "env_keys": entry.env_keys.iter().collect::<Vec<_>>(),
        "config_flags": entry.config_flags.iter().collect::<Vec<_>>(),
        "secret_sources": entry.secret_sources,
        "updated_at": entry.updated_at,
    })
}
