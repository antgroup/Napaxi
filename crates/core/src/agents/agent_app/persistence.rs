//! Filesystem persistence for agent app packages, action proposals, and
//! agent triggers.
//!
//! All records live under `<files_dir>/napaxi/{agent_app_packages,
//! agent_app_action_proposals, agent_app_triggers}/<key>.json`. Reads
//! tolerate missing files (return `None`/empty list); writes return
//! `bool` so callers can surface a clean error_json.

use std::fs;
use std::path::{Path, PathBuf};

use super::types::{ActionProposal, ActionProposalRecord, AgentAppPackage, AgentTriggerRecord};
use super::{PACKAGE_DIR, PROPOSAL_DIR, TRIGGER_DIR};

pub(super) fn save_package(files_dir: &str, package: &AgentAppPackage) -> bool {
    let path = package_file(files_dir, &package.agent_id);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    let Ok(content) = serde_json::to_string_pretty(package) else {
        return false;
    };
    fs::write(path, content).is_ok()
}

pub(super) fn load_package(files_dir: &str, agent_id: &str) -> Option<AgentAppPackage> {
    let content = fs::read_to_string(package_file(files_dir, agent_id)).ok()?;
    serde_json::from_str(&content).ok()
}

pub(super) fn list_packages(files_dir: &str) -> Vec<AgentAppPackage> {
    let Ok(entries) = fs::read_dir(package_dir(files_dir)) else {
        return Vec::new();
    };
    let mut packages = Vec::new();
    for entry in entries.flatten() {
        let Ok(content) = fs::read_to_string(entry.path()) else {
            continue;
        };
        if let Ok(package) = serde_json::from_str::<AgentAppPackage>(&content) {
            packages.push(package);
        }
    }
    packages.sort_by(|a, b| a.agent_id.cmp(&b.agent_id));
    packages
}

pub(super) fn persist_proposal(files_dir: &str, proposal: &ActionProposal) -> Result<(), String> {
    let record = ActionProposalRecord {
        proposal: proposal.clone(),
        status: "pending".to_string(),
        result: None,
        created_at: proposal.created_at.clone(),
        updated_at: proposal.created_at.clone(),
    };
    if save_proposal_record(files_dir, &record) {
        Ok(())
    } else {
        Err("Failed to save agent app action proposal".to_string())
    }
}

pub(super) fn save_proposal_record(files_dir: &str, record: &ActionProposalRecord) -> bool {
    let path = proposal_file(files_dir, &record.proposal.request_id);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    let Ok(content) = serde_json::to_string_pretty(record) else {
        return false;
    };
    fs::write(path, content).is_ok()
}

pub(super) fn load_proposal_record(
    files_dir: &str,
    request_id: &str,
) -> Option<ActionProposalRecord> {
    let content = fs::read_to_string(proposal_file(files_dir, request_id)).ok()?;
    serde_json::from_str(&content).ok()
}

pub(super) fn list_proposal_records(files_dir: &str) -> Vec<ActionProposalRecord> {
    let Ok(entries) = fs::read_dir(proposal_dir(files_dir)) else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter_map(|entry| fs::read_to_string(entry.path()).ok())
        .filter_map(|content| serde_json::from_str::<ActionProposalRecord>(&content).ok())
        .collect()
}

pub(super) fn save_trigger_record(files_dir: &str, record: &AgentTriggerRecord) -> bool {
    let path = trigger_file(files_dir, &record.trigger.request_id);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    let Ok(content) = serde_json::to_string_pretty(record) else {
        return false;
    };
    fs::write(path, content).is_ok()
}

pub(super) fn load_trigger_record(files_dir: &str, request_id: &str) -> Option<AgentTriggerRecord> {
    let content = fs::read_to_string(trigger_file(files_dir, request_id)).ok()?;
    serde_json::from_str(&content).ok()
}

pub(super) fn package_file(files_dir: &str, agent_id: &str) -> PathBuf {
    package_dir(files_dir).join(format!("{}.json", safe_file_component(agent_id)))
}

fn package_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join(PACKAGE_DIR)
}

fn proposal_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join(PROPOSAL_DIR)
}

fn proposal_file(files_dir: &str, request_id: &str) -> PathBuf {
    proposal_dir(files_dir).join(format!("{}.json", safe_file_component(request_id)))
}

fn trigger_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join(TRIGGER_DIR)
}

fn trigger_file(files_dir: &str, request_id: &str) -> PathBuf {
    trigger_dir(files_dir).join(format!("{}.json", safe_file_component(request_id)))
}

fn safe_file_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' || ch == '.' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}
