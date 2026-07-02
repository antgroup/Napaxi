//! Per-thread skill session state: which skills the user "loaded" recently.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use chrono::{DateTime, Duration, Utc};

use super::limits::{
    MAX_ACTIVE_SKILLS_PER_TURN, SKILL_SESSION_ACTIVE_MAX_AGE_MINUTES, SKILL_SESSION_ACTIVE_TURNS,
};
use super::paths::normalize_agent_id;
use super::types::{
    SkillCatalogEntry, SkillSessionActiveSkill, SkillSessionState, SkillUsageRecord,
};

pub(crate) fn delete_skill_continuation_state(files_dir: &str, thread_id: &str) -> bool {
    if thread_id.trim().is_empty() {
        return true;
    }
    let path = skill_session_state_path(files_dir, thread_id);
    let legacy_path = legacy_skill_session_state_path(files_dir, thread_id);
    let Some(path) = path else {
        return true;
    };
    if path.exists() {
        std::fs::remove_file(&path).is_ok()
            && legacy_path
                .as_ref()
                .map(|legacy| !legacy.exists() || std::fs::remove_file(legacy).is_ok())
                .unwrap_or(true)
    } else {
        legacy_path
            .as_ref()
            .map(|legacy| !legacy.exists() || std::fs::remove_file(legacy).is_ok())
            .unwrap_or(true)
    }
}

fn skill_session_state_path(files_dir: &str, thread_id: &str) -> Option<PathBuf> {
    if thread_id.trim().is_empty() {
        return None;
    }
    Some(
        crate::agent_runtime::domain_dir(files_dir, "skills")
            .join("state")
            .join(format!("{thread_id}.json")),
    )
}

fn legacy_skill_session_state_path(files_dir: &str, thread_id: &str) -> Option<PathBuf> {
    if thread_id.trim().is_empty() {
        return None;
    }
    Some(
        crate::agent_runtime::legacy_brand_domain_dir(files_dir, "skills")
            .join("state")
            .join(format!("{thread_id}.json")),
    )
}

pub(super) async fn load_skill_session_state(
    files_dir: &str,
    thread_id: &str,
) -> SkillSessionState {
    let Some(path) = skill_session_state_path(files_dir, thread_id) else {
        return SkillSessionState::default();
    };
    let content = match tokio::fs::read_to_string(&path).await {
        Ok(content) => Some(content),
        Err(_) => {
            let Some(legacy_path) = legacy_skill_session_state_path(files_dir, thread_id) else {
                return SkillSessionState::default();
            };
            tokio::fs::read_to_string(legacy_path).await.ok()
        }
    };
    content
        .and_then(|content| serde_json::from_str::<SkillSessionState>(&content).ok())
        .unwrap_or_default()
}

pub(super) async fn save_skill_session_state(
    files_dir: &str,
    thread_id: &str,
    state: &SkillSessionState,
) -> Result<(), String> {
    let Some(path) = skill_session_state_path(files_dir, thread_id) else {
        return Ok(());
    };
    let content = serde_json::to_string_pretty(state).map_err(|e| e.to_string())?;
    napaxi_evolution::atomic_write_text(&path, &content)
        .await
        .map_err(|e| e.to_string())
}

pub(super) async fn record_session_skill_load(
    files_dir: &str,
    thread_id: &str,
    agent_id: &str,
    skill: &napaxi_skills::LoadedSkill,
) {
    if thread_id.trim().is_empty() {
        return;
    }
    let agent_id = normalize_agent_id(agent_id);
    let mut state = load_skill_session_state(files_dir, thread_id).await;
    let agent = state.agents.entry(agent_id).or_default();
    agent
        .active_skills
        .retain(|entry| entry.name != skill.name());
    agent.active_skills.insert(
        0,
        SkillSessionActiveSkill {
            name: skill.name().to_string(),
            version: skill.version().to_string(),
            description: skill.manifest.description.clone(),
            trust: skill.trust.to_string(),
            loaded_at: Utc::now().to_rfc3339(),
            remaining_turns: SKILL_SESSION_ACTIVE_TURNS,
        },
    );
    agent.active_skills.truncate(MAX_ACTIVE_SKILLS_PER_TURN);
    let _ = save_skill_session_state(files_dir, thread_id, &state).await;
}

pub(super) async fn active_session_skill_entries(
    files_dir: &str,
    thread_id: &str,
    agent_id: &str,
    usage: &HashMap<String, SkillUsageRecord>,
    available: &[Arc<napaxi_skills::LoadedSkill>],
) -> Vec<SkillCatalogEntry> {
    if thread_id.trim().is_empty() {
        return Vec::new();
    }
    let mut state = load_skill_session_state(files_dir, thread_id).await;
    let mut changed = false;
    let Some(agent) = state.agents.get(&normalize_agent_id(agent_id)) else {
        return Vec::new();
    };
    let available_by_name = available
        .iter()
        .map(|skill| (skill.name().to_string(), Arc::clone(skill)))
        .collect::<HashMap<_, _>>();
    let active_skills = agent.active_skills.clone();
    let mut entries = Vec::new();
    let mut retained = Vec::new();
    let now = Utc::now();
    for mut entry in active_skills {
        if entry.remaining_turns == 0 || skill_session_entry_is_expired(&entry, now) {
            changed = true;
            continue;
        }
        let Some(skill) = available_by_name.get(&entry.name) else {
            changed = true;
            continue;
        };
        if !super::catalog::skill_is_catalog_eligible(skill, usage) {
            changed = true;
            continue;
        }
        if entries.len() < MAX_ACTIVE_SKILLS_PER_TURN {
            entries.push(SkillCatalogEntry {
                name: skill.name().to_string(),
                version: skill.version().to_string(),
                description: skill.manifest.description.clone(),
                trust: skill.trust.to_string(),
                activation_hint: "active conversation context",
                content_hash: skill.content_hash.clone(),
            });
        }
        entry.remaining_turns = entry.remaining_turns.saturating_sub(1);
        changed = true;
        if entry.remaining_turns > 0 {
            retained.push(entry);
        }
    }
    if changed {
        let agent_id = normalize_agent_id(agent_id);
        if let Some(agent) = state.agents.get_mut(&agent_id) {
            agent.active_skills = retained;
        }
        let _ = save_skill_session_state(files_dir, thread_id, &state).await;
    }
    entries
}

fn skill_session_entry_is_expired(entry: &SkillSessionActiveSkill, now: DateTime<Utc>) -> bool {
    let Ok(loaded_at) = DateTime::parse_from_rfc3339(&entry.loaded_at) else {
        return true;
    };
    now.signed_duration_since(loaded_at.with_timezone(&Utc))
        > Duration::minutes(SKILL_SESSION_ACTIVE_MAX_AGE_MINUTES)
}
