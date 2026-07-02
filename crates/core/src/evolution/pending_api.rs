use std::collections::HashSet;

use chrono::Utc;
use serde::Serialize;

use super::executor::apply_mobile_action;
use super::store::{
    append_diagnostic_record, load_diagnostics_store, load_pending_store, load_run_store,
    refresh_expired, refresh_stale_runs, save_pending_store, save_run_store,
};
use super::{EvolutionDiagnosticRecord, PendingStatus, invalid_handle_json, review_type_name};

#[derive(Debug, Clone, Serialize)]
struct AppliedAction {
    action_type: String,
    result: String,
}

pub fn list_pending_evolution(files_dir: &str) -> String {
    let mut pending = load_pending_store(files_dir);
    refresh_expired(&mut pending);
    let _ = save_pending_store(files_dir, &pending);
    let visible: Vec<_> = pending
        .into_iter()
        .filter(|item| item.status == PendingStatus::Pending)
        .collect();
    serde_json::to_string(&visible).unwrap_or_else(|_| "[]".to_string())
}

pub fn list_pending_evolution_handle(handle: i64) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    let scoped =
        crate::workspace::default_scoped_files_dir(&files_dir, crate::runtime::DEFAULT_AGENT_ID);
    list_pending_evolution(&scoped)
}

pub fn list_evolution_runs(files_dir: &str, run_ids_json: &str) -> String {
    let run_ids = serde_json::from_str::<Vec<String>>(run_ids_json)
        .ok()
        .filter(|ids| !ids.is_empty());
    let mut runs = load_run_store(files_dir);
    if refresh_stale_runs(&mut runs) {
        let _ = save_run_store(files_dir, &runs);
    }
    runs.sort_by(|a, b| b.queued_at.cmp(&a.queued_at));
    let visible: Vec<_> = match run_ids {
        Some(ids) => {
            let ids: HashSet<_> = ids.into_iter().collect();
            runs.into_iter()
                .filter(|record| ids.contains(&record.id))
                .collect()
        }
        None => runs,
    };
    serde_json::to_string(&visible).unwrap_or_else(|_| "[]".to_string())
}

pub fn list_evolution_runs_handle(handle: i64, run_ids_json: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_evolution_runs(&files_dir, run_ids_json)
}

pub fn list_evolution_diagnostics(files_dir: &str) -> String {
    let mut records = load_diagnostics_store(files_dir);
    records.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    serde_json::to_string(&records).unwrap_or_else(|_| "[]".to_string())
}

pub fn list_evolution_diagnostics_handle(handle: i64) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    let scoped =
        crate::workspace::default_scoped_files_dir(&files_dir, crate::runtime::DEFAULT_AGENT_ID);
    list_evolution_diagnostics(&scoped)
}

pub fn reject_pending_evolution(files_dir: &str, pending_id: &str) -> String {
    let mut pending = load_pending_store(files_dir);
    refresh_expired(&mut pending);
    let result = if let Some(item) = pending.iter_mut().find(|item| item.id == pending_id) {
        match item.status {
            PendingStatus::Pending => {
                item.status = PendingStatus::Rejected;
                serde_json::json!({"success": true, "status": "rejected"})
            }
            PendingStatus::Rejected => {
                serde_json::json!({"success": true, "status": "rejected", "already_handled": true})
            }
            PendingStatus::Expired => {
                serde_json::json!({"success": true, "status": "expired", "already_handled": true})
            }
            PendingStatus::Executed => {
                serde_json::json!({"success": true, "status": "executed", "already_handled": true})
            }
        }
    } else {
        serde_json::json!({"success": true, "status": "not_found", "already_handled": true})
    };
    let _ = save_pending_store(files_dir, &pending);
    result.to_string()
}

pub fn reject_pending_evolution_handle(handle: i64, pending_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    let scoped =
        crate::workspace::default_scoped_files_dir(&files_dir, crate::runtime::DEFAULT_AGENT_ID);
    reject_pending_evolution(&scoped, pending_id)
}

pub async fn apply_pending_evolution(files_dir: &str, pending_id: &str) -> String {
    let mut pending = load_pending_store(files_dir);
    refresh_expired(&mut pending);
    let Some(index) = pending.iter().position(|item| item.id == pending_id) else {
        let _ = save_pending_store(files_dir, &pending);
        return serde_json::json!({
            "success": true,
            "status": "not_found",
            "already_handled": true
        })
        .to_string();
    };

    if pending[index].status != PendingStatus::Pending {
        let status = format!("{:?}", pending[index].status);
        let _ = save_pending_store(files_dir, &pending);
        return serde_json::json!({
            "success": true,
            "status": status.to_lowercase(),
            "already_handled": true
        })
        .to_string();
    }

    let item = pending[index].clone();
    let actions = if item.aggregated_actions.is_empty() {
        vec![item.action.clone()]
    } else {
        item.aggregated_actions.clone()
    };
    let mut results = Vec::new();
    for action in &actions {
        match apply_mobile_action(files_dir, &item.agent_id, action).await {
            Ok(result) => results.push(AppliedAction {
                action_type: action.action_type_name().to_string(),
                result,
            }),
            Err(error) => {
                let partial_success = !results.is_empty();
                if partial_success {
                    pending[index].status = PendingStatus::Executed;
                }
                let _ = save_pending_store(files_dir, &pending);
                append_diagnostic_record(
                    files_dir,
                    EvolutionDiagnosticRecord {
                        id: uuid::Uuid::new_v4().to_string(),
                        created_at: Utc::now().to_rfc3339(),
                        agent_id: item.agent_id.clone(),
                        thread_id: item.thread_id.clone(),
                        review_type: review_type_name(item.review_type).to_string(),
                        trigger_reason: "apply_pending".to_string(),
                        input_summary: serde_json::json!({
                            "pending_id": item.id,
                            "action_count": results.len() + 1,
                            "failed_action": action.action_type_name(),
                        }),
                        provenance: serde_json::json!({
                            "source_kinds": ["pending_evolution"],
                            "pending_id": item.id,
                            "review_type": review_type_name(item.review_type),
                            "context_isolated": true,
                        }),
                        tool_calls: vec![],
                        suggestions_count: 0,
                        pending_count: if partial_success { 0 } else { 1 },
                        auto_applied_count: results.len(),
                        apply_result: serde_json::to_string(&results).ok(),
                        failure_reason: Some(error.clone()),
                    },
                );
                if partial_success {
                    return serde_json::json!({
                        "success": true,
                        "status": "partial",
                        "partial": true,
                        "warning": error,
                        "executed": results,
                    })
                    .to_string();
                }
                return serde_json::json!({
                    "error": error,
                    "executed": results,
                })
                .to_string();
            }
        }
    }

    pending[index].status = PendingStatus::Executed;
    let _ = save_pending_store(files_dir, &pending);
    let response = serde_json::json!({
        "success": true,
        "status": "executed",
        "executed": results,
    });
    append_diagnostic_record(
        files_dir,
        EvolutionDiagnosticRecord {
            id: uuid::Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            agent_id: item.agent_id.clone(),
            thread_id: item.thread_id.clone(),
            review_type: review_type_name(item.review_type).to_string(),
            trigger_reason: "apply_pending".to_string(),
            input_summary: serde_json::json!({
                "pending_id": item.id,
                "action_count": actions.len(),
            }),
            provenance: serde_json::json!({
                "source_kinds": ["pending_evolution"],
                "pending_id": item.id,
                "review_type": review_type_name(item.review_type),
                "context_isolated": true,
            }),
            tool_calls: vec![],
            suggestions_count: actions.len(),
            pending_count: 0,
            auto_applied_count: 0,
            apply_result: Some(response.to_string()),
            failure_reason: None,
        },
    );
    response.to_string()
}

pub async fn apply_pending_evolution_handle(handle: i64, pending_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    let scoped =
        crate::workspace::default_scoped_files_dir(&files_dir, crate::runtime::DEFAULT_AGENT_ID);
    apply_pending_evolution(&scoped, pending_id).await
}
