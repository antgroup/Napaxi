//! Skill remediation request/run ledger.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::paths::{normalize_agent_id, remediation_runs_path};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRemediationRunList {
    pub runs: Vec<SkillRemediationRun>,
    pub total: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRemediationRun {
    pub run_id: String,
    pub agent_id: String,
    pub skill_name: String,
    pub action_id: String,
    pub status: String,
    pub requested_at: String,
    pub updated_at: String,
    pub result: Option<serde_json::Value>,
}

pub async fn request_skill_remediation(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    action_id: &str,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let now = Utc::now().to_rfc3339();
    let run = SkillRemediationRun {
        run_id: Uuid::new_v4().to_string(),
        agent_id: agent_id.clone(),
        skill_name: skill_name.to_string(),
        action_id: action_id.to_string(),
        status: "requested".to_string(),
        requested_at: now.clone(),
        updated_at: now,
        result: None,
    };
    match append_run(files_dir, &agent_id, &run).await {
        Ok(()) => serde_json::to_string(&run).unwrap_or_else(|_| "{}".to_string()),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn update_skill_remediation_run(
    files_dir: &str,
    agent_id: &str,
    run_id: &str,
    status: &str,
    result_json: Option<&str>,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let mut runs = load_runs(files_dir, &agent_id).await;
    let Some(run) = runs.iter_mut().find(|run| run.run_id == run_id) else {
        return serde_json::json!({"error": format!("skill remediation run not found: {run_id}")})
            .to_string();
    };
    if !valid_status(status) {
        return serde_json::json!({"error": format!("invalid remediation status: {status}")})
            .to_string();
    }
    run.status = status.to_string();
    run.updated_at = Utc::now().to_rfc3339();
    run.result = result_json.map(|raw| {
        serde_json::from_str::<serde_json::Value>(raw)
            .unwrap_or_else(|_| serde_json::Value::String(raw.to_string()))
    });
    let response = run.clone();
    match rewrite_runs(files_dir, &agent_id, &runs).await {
        Ok(()) => serde_json::to_string(&response).unwrap_or_else(|_| "{}".to_string()),
        Err(error) => serde_json::json!({"error": error}).to_string(),
    }
}

pub async fn list_skill_remediation_runs(
    files_dir: &str,
    agent_id: &str,
    skill_name: Option<&str>,
    limit: usize,
    offset: usize,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let mut runs = load_runs(files_dir, &agent_id).await;
    if let Some(skill_name) = skill_name.filter(|value| !value.trim().is_empty()) {
        runs.retain(|run| run.skill_name == skill_name);
    }
    runs.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    let total = runs.len();
    let limit = if limit == 0 { 50 } else { limit.min(200) };
    let runs = runs.into_iter().skip(offset).take(limit).collect();
    serde_json::to_string(&SkillRemediationRunList { runs, total })
        .unwrap_or_else(|_| r#"{"runs":[],"total":0}"#.to_string())
}

pub(super) async fn record_fulfilled_resolution_run(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    action_id: &str,
    result: serde_json::Value,
) {
    let agent_id = normalize_agent_id(agent_id);
    let now = Utc::now().to_rfc3339();
    let run = SkillRemediationRun {
        run_id: Uuid::new_v4().to_string(),
        agent_id: agent_id.clone(),
        skill_name: skill_name.to_string(),
        action_id: action_id.to_string(),
        status: "fulfilled".to_string(),
        requested_at: now.clone(),
        updated_at: now,
        result: Some(result),
    };
    let _ = append_run(files_dir, &agent_id, &run).await;
}

pub async fn request_skill_remediation_handle(
    handle: i64,
    agent_id: &str,
    skill_name: &str,
    action_id: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    request_skill_remediation(&files_dir, agent_id, skill_name, action_id).await
}

pub async fn update_skill_remediation_run_handle(
    handle: i64,
    agent_id: &str,
    run_id: &str,
    status: &str,
    result_json: Option<&str>,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    update_skill_remediation_run(&files_dir, agent_id, run_id, status, result_json).await
}

pub async fn list_skill_remediation_runs_handle(
    handle: i64,
    agent_id: &str,
    skill_name: Option<&str>,
    limit: usize,
    offset: usize,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return super::limits::invalid_handle_json();
    };
    list_skill_remediation_runs(&files_dir, agent_id, skill_name, limit, offset).await
}

fn valid_status(status: &str) -> bool {
    matches!(
        status,
        "requested" | "pending" | "fulfilled" | "failed" | "expired" | "cancelled"
    )
}

async fn load_runs(files_dir: &str, agent_id: &str) -> Vec<SkillRemediationRun> {
    let path = remediation_runs_path(files_dir, agent_id);
    let Ok(content) = tokio::fs::read_to_string(path).await else {
        return Vec::new();
    };
    content
        .lines()
        .filter_map(|line| serde_json::from_str::<SkillRemediationRun>(line).ok())
        .collect()
}

async fn append_run(
    files_dir: &str,
    agent_id: &str,
    run: &SkillRemediationRun,
) -> Result<(), String> {
    let path = remediation_runs_path(files_dir, agent_id);
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| e.to_string())?;
    }
    let line = serde_json::to_string(run).map_err(|e| e.to_string())?;
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

async fn rewrite_runs(
    files_dir: &str,
    agent_id: &str,
    runs: &[SkillRemediationRun],
) -> Result<(), String> {
    let path = remediation_runs_path(files_dir, agent_id);
    let content = runs
        .iter()
        .map(serde_json::to_string)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?
        .join("\n");
    let content = if content.is_empty() {
        String::new()
    } else {
        format!("{content}\n")
    };
    napaxi_evolution::atomic_write_text(&path, &content)
        .await
        .map_err(|e| e.to_string())
}
