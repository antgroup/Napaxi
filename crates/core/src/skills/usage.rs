//! Usage record persistence and lifecycle JSON helpers.

use std::collections::HashMap;
use std::sync::OnceLock;

use chrono::{DateTime, Utc};
use tokio::sync::Mutex;

use super::paths::{legacy_usage_path, usage_path};
use super::types::{SkillLifecycleState, SkillUsageRecord};

fn usage_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

pub(super) async fn load_usage_map(
    files_dir: &str,
    agent_id: &str,
) -> HashMap<String, SkillUsageRecord> {
    let path = usage_path(files_dir, agent_id);
    let legacy_path = legacy_usage_path(files_dir, agent_id);
    let content = match tokio::fs::read_to_string(&path).await {
        Ok(content) => Some(content),
        Err(_) => tokio::fs::read_to_string(legacy_path).await.ok(),
    };
    content
        .and_then(|content| serde_json::from_str::<Vec<SkillUsageRecord>>(&content).ok())
        .unwrap_or_default()
        .into_iter()
        .map(|record| (record.skill_name.clone(), record))
        .collect()
}

async fn save_usage_map(
    files_dir: &str,
    agent_id: &str,
    usage: &HashMap<String, SkillUsageRecord>,
) -> Result<(), String> {
    let mut records: Vec<_> = usage.values().cloned().collect();
    records.sort_by(|a, b| a.skill_name.cmp(&b.skill_name));
    let content = serde_json::to_string_pretty(&records).map_err(|e| e.to_string())?;
    napaxi_evolution::atomic_write_text(&usage_path(files_dir, agent_id), &content)
        .await
        .map_err(|e| e.to_string())
}

pub(super) async fn update_usage_record<F>(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    update: F,
) -> Result<SkillUsageRecord, String>
where
    F: FnOnce(&mut SkillUsageRecord),
{
    let _guard = usage_lock().lock().await;
    let mut usage = load_usage_map(files_dir, agent_id).await;
    let record = usage
        .entry(skill_name.to_string())
        .or_insert_with(|| SkillUsageRecord::new(skill_name));
    update(record);
    let record = record.clone();
    save_usage_map(files_dir, agent_id, &usage).await?;
    Ok(record)
}

pub(super) async fn record_skill_use(files_dir: &str, agent_id: &str, skill_name: &str) {
    let now = Utc::now().to_rfc3339();
    let _ = update_usage_record(files_dir, agent_id, skill_name, |record| {
        record.use_count = record.use_count.saturating_add(1);
        record.last_used_at = Some(now);
        if record.state == SkillLifecycleState::Stale {
            record.state = SkillLifecycleState::Active;
        }
    })
    .await;
}

pub(super) async fn record_skill_view(files_dir: &str, agent_id: &str, skill_name: &str) {
    let now = Utc::now().to_rfc3339();
    let _ = update_usage_record(files_dir, agent_id, skill_name, |record| {
        record.view_count = record.view_count.saturating_add(1);
        record.last_viewed_at = Some(now);
    })
    .await;
}

pub(super) async fn record_skill_patch(files_dir: &str, agent_id: &str, skill_name: &str) {
    let now = Utc::now().to_rfc3339();
    let _ = update_usage_record(files_dir, agent_id, skill_name, |record| {
        record.patch_count = record.patch_count.saturating_add(1);
        record.last_patched_at = Some(now);
        if record.state == SkillLifecycleState::Stale {
            record.state = SkillLifecycleState::Active;
        }
    })
    .await;
}

pub(super) async fn record_skill_created_by_agent(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
) {
    let now = Utc::now().to_rfc3339();
    let _ = update_usage_record(files_dir, agent_id, skill_name, |record| {
        record.created_by = Some("agent".to_string());
        record.created_at.get_or_insert_with(|| now.clone());
        record.state = SkillLifecycleState::Active;
        record.archived_at = None;
    })
    .await;
}

pub(super) fn lifecycle_json(record: Option<&SkillUsageRecord>) -> serde_json::Value {
    match record {
        Some(record) => serde_json::json!({
            "state": &record.state,
            "pinned": record.pinned,
            "protected": record.protected,
            "created_by": record.created_by,
            "use_count": record.use_count,
            "view_count": record.view_count,
            "patch_count": record.patch_count,
            "last_used_at": record.last_used_at,
            "last_viewed_at": record.last_viewed_at,
            "last_patched_at": record.last_patched_at,
            "archived_at": record.archived_at,
            "absorbed_into": record.absorbed_into,
        }),
        None => serde_json::json!({
            "state": SkillLifecycleState::Active,
            "pinned": false,
            "protected": false,
            "use_count": 0,
            "view_count": 0,
            "patch_count": 0,
        }),
    }
}

pub(super) fn lifecycle_json_for_skill(
    skill: &napaxi_skills::LoadedSkill,
    record: Option<&SkillUsageRecord>,
) -> serde_json::Value {
    let mut value = lifecycle_json(record);
    let source_protected = is_source_protected(skill);
    if let Some(object) = value.as_object_mut() {
        let protected = object
            .get("protected")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
            || source_protected;
        object.insert("protected".to_string(), serde_json::json!(protected));
        if source_protected
            && object
                .get("created_by")
                .is_none_or(serde_json::Value::is_null)
        {
            object.insert("created_by".to_string(), serde_json::json!("system"));
        }
    }
    value
}

pub(super) fn skill_summary(
    skill: &napaxi_skills::LoadedSkill,
    usage: Option<&SkillUsageRecord>,
) -> serde_json::Value {
    serde_json::json!({
        "name": skill.name(),
        "version": skill.version(),
        "description": skill.manifest.description,
        "always": false,
        "allowed_agents": [],
        "trust": skill.trust.to_string(),
        "source": format!("{:?}", skill.source),
        "keywords": skill.manifest.activation.keywords,
        "tags": skill.manifest.activation.tags,
        "lifecycle": lifecycle_json_for_skill(skill, usage),
    })
}

pub(super) fn is_record_protected(record: &SkillUsageRecord) -> bool {
    record.protected || record.created_by.as_deref() == Some("system")
}

pub(super) fn is_source_protected(skill: &napaxi_skills::LoadedSkill) -> bool {
    match &skill.source {
        napaxi_skills::SkillSource::Bundled(_) => true,
        napaxi_skills::SkillSource::Workspace(path)
        | napaxi_skills::SkillSource::User(path)
        | napaxi_skills::SkillSource::Installed(path) => path.components().any(|component| {
            component
                .as_os_str()
                .to_str()
                .is_some_and(|part| matches!(part, "app_bundled" | "host_installed"))
        }),
    }
}

fn parse_record_time(value: &Option<String>) -> Option<DateTime<Utc>> {
    value
        .as_deref()
        .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
        .map(|value| value.with_timezone(&Utc))
}

pub(super) fn latest_record_activity(record: &SkillUsageRecord) -> Option<DateTime<Utc>> {
    [
        parse_record_time(&record.last_used_at),
        parse_record_time(&record.last_patched_at),
        parse_record_time(&record.last_viewed_at),
        parse_record_time(&record.created_at),
    ]
    .into_iter()
    .flatten()
    .max()
}
