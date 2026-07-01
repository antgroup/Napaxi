//! File-backed A2A peers, tasks, and event records.

use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

use super::json_string;
use super::types::{
    A2ADeliveryRecord, A2AEventRecord, A2APeer, A2APeerMessage, A2APeerSession, A2ATaskRecord,
};

pub(super) fn save_peer(files_dir: &str, peer: &A2APeer) -> bool {
    let mut peers = load_peers(files_dir);
    peers.retain(|existing| existing.peer_id != peer.peer_id);
    peers.push(peer.clone());
    save_peers(files_dir, &peers)
}

pub(super) fn load_peers(files_dir: &str) -> Vec<A2APeer> {
    fs::read_to_string(peers_path(files_dir))
        .ok()
        .and_then(|content| serde_json::from_str::<Vec<A2APeer>>(&content).ok())
        .unwrap_or_default()
}

pub(super) fn save_session(files_dir: &str, session: &A2APeerSession) -> bool {
    let path = session_path(files_dir, &session.session_id);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    serde_json::to_string_pretty(session)
        .ok()
        .and_then(|content| fs::write(path, content).ok())
        .is_some()
}

pub(super) fn load_session(files_dir: &str, session_id: &str) -> Option<A2APeerSession> {
    fs::read_to_string(session_path(files_dir, session_id))
        .ok()
        .and_then(|content| serde_json::from_str::<A2APeerSession>(&content).ok())
}

pub(super) fn list_sessions(files_dir: &str) -> Vec<A2APeerSession> {
    let Ok(entries) = fs::read_dir(sessions_dir(files_dir)) else {
        return Vec::new();
    };
    let mut sessions = entries
        .flatten()
        .filter(|entry| entry.path().extension().and_then(|ext| ext.to_str()) == Some("json"))
        .filter_map(|entry| fs::read_to_string(entry.path()).ok())
        .filter_map(|content| serde_json::from_str::<A2APeerSession>(&content).ok())
        .collect::<Vec<_>>();
    sessions.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    sessions
}

pub(super) fn append_message(files_dir: &str, message: &A2APeerMessage) -> bool {
    append_jsonl(&messages_path(files_dir, &message.session_id), message)
}

pub(super) fn read_messages(files_dir: &str, session_id: &str) -> Vec<A2APeerMessage> {
    read_jsonl(messages_path(files_dir, session_id))
}

pub(super) fn message_seen(
    files_dir: &str,
    session_id: &str,
    message_id: &str,
    idempotency_key: &str,
) -> bool {
    read_messages(files_dir, session_id)
        .into_iter()
        .any(|message| {
            message.message_id == message_id
                || (!idempotency_key.trim().is_empty()
                    && message.idempotency_key == idempotency_key)
        })
}

pub(super) fn append_delivery(files_dir: &str, delivery: &A2ADeliveryRecord) -> bool {
    append_jsonl(&deliveries_path(files_dir, &delivery.session_id), delivery)
}

pub(super) fn read_deliveries(files_dir: &str, session_id: &str) -> Vec<A2ADeliveryRecord> {
    read_jsonl(deliveries_path(files_dir, session_id))
}

pub(super) fn find_peer(files_dir: &str, peer_id: &str) -> Option<A2APeer> {
    load_peers(files_dir)
        .into_iter()
        .find(|peer| peer.peer_id == peer_id)
}

pub(super) fn delete_peer(files_dir: &str, peer_id: &str) -> bool {
    let mut peers = load_peers(files_dir);
    let old_len = peers.len();
    peers.retain(|peer| peer.peer_id != peer_id);
    old_len != peers.len() && save_peers(files_dir, &peers)
}

fn save_peers(files_dir: &str, peers: &[A2APeer]) -> bool {
    let path = peers_path(files_dir);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    serde_json::to_string_pretty(peers)
        .ok()
        .and_then(|content| fs::write(path, content).ok())
        .is_some()
}

pub(super) fn save_task(files_dir: &str, task: &A2ATaskRecord) -> bool {
    let path = task_path(files_dir, &task.task_id);
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    serde_json::to_string_pretty(task)
        .ok()
        .and_then(|content| fs::write(path, content).ok())
        .is_some()
}

pub(super) fn load_task(files_dir: &str, task_id: &str) -> Option<A2ATaskRecord> {
    fs::read_to_string(task_path(files_dir, task_id))
        .ok()
        .and_then(|content| serde_json::from_str::<A2ATaskRecord>(&content).ok())
}

pub(super) fn list_tasks(files_dir: &str) -> Vec<A2ATaskRecord> {
    let Ok(entries) = fs::read_dir(tasks_dir(files_dir)) else {
        return Vec::new();
    };
    let mut tasks = entries
        .flatten()
        .filter(|entry| entry.path().extension().and_then(|ext| ext.to_str()) == Some("json"))
        .filter_map(|entry| fs::read_to_string(entry.path()).ok())
        .filter_map(|content| serde_json::from_str::<A2ATaskRecord>(&content).ok())
        .collect::<Vec<_>>();
    tasks.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    tasks
}

pub(super) fn idempotency_seen(files_dir: &str, idempotency_key: &str) -> bool {
    if idempotency_key.trim().is_empty() {
        return false;
    }
    list_tasks(files_dir).into_iter().any(|task| {
        task.idempotency_key == idempotency_key
            || task.envelope_id == idempotency_key
            || task.request.task_id == idempotency_key
    }) || read_events(files_dir)
        .into_iter()
        .any(|event| event.envelope_id == idempotency_key)
}

pub(super) fn append_event(files_dir: &str, event: &A2AEventRecord) {
    let path = events_path(files_dir);
    let Some(parent) = path.parent() else {
        return;
    };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) else {
        return;
    };
    let _ = writeln!(file, "{}", json_string(event));
}

pub(super) fn read_events(files_dir: &str) -> Vec<A2AEventRecord> {
    fs::read_to_string(events_path(files_dir))
        .ok()
        .map(|content| {
            content
                .lines()
                .filter_map(|line| serde_json::from_str::<A2AEventRecord>(line).ok())
                .collect()
        })
        .unwrap_or_default()
}

pub(super) fn latest_tasks(tasks: Vec<A2ATaskRecord>) -> Vec<A2ATaskRecord> {
    let mut by_id = HashMap::<String, A2ATaskRecord>::new();
    for task in tasks {
        by_id
            .entry(task.task_id.clone())
            .and_modify(|existing| {
                if task.updated_at >= existing.updated_at {
                    *existing = task.clone();
                }
            })
            .or_insert(task);
    }
    by_id.into_values().collect()
}

fn domain_dir(files_dir: &str) -> PathBuf {
    crate::agent_runtime::domain_dir(files_dir, "a2a")
}

fn peers_path(files_dir: &str) -> PathBuf {
    domain_dir(files_dir).join("peers.json")
}

fn tasks_dir(files_dir: &str) -> PathBuf {
    domain_dir(files_dir).join("tasks")
}

fn task_path(files_dir: &str, task_id: &str) -> PathBuf {
    tasks_dir(files_dir).join(format!("{}.json", safe_file_component(task_id)))
}

fn sessions_dir(files_dir: &str) -> PathBuf {
    domain_dir(files_dir).join("sessions")
}

fn session_path(files_dir: &str, session_id: &str) -> PathBuf {
    sessions_dir(files_dir).join(format!("{}.json", safe_file_component(session_id)))
}

fn messages_dir(files_dir: &str) -> PathBuf {
    domain_dir(files_dir).join("messages")
}

fn messages_path(files_dir: &str, session_id: &str) -> PathBuf {
    messages_dir(files_dir).join(format!("{}.jsonl", safe_file_component(session_id)))
}

fn deliveries_dir(files_dir: &str) -> PathBuf {
    domain_dir(files_dir).join("deliveries")
}

fn deliveries_path(files_dir: &str, session_id: &str) -> PathBuf {
    deliveries_dir(files_dir).join(format!("{}.jsonl", safe_file_component(session_id)))
}

fn events_path(files_dir: &str) -> PathBuf {
    domain_dir(files_dir).join("events.jsonl")
}

fn safe_file_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.') {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn append_jsonl<T: serde::Serialize>(path: &PathBuf, value: &T) -> bool {
    let Some(parent) = path.parent() else {
        return false;
    };
    if fs::create_dir_all(parent).is_err() {
        return false;
    }
    let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) else {
        return false;
    };
    writeln!(file, "{}", json_string(value)).is_ok()
}

fn read_jsonl<T: for<'de> serde::Deserialize<'de>>(path: PathBuf) -> Vec<T> {
    fs::read_to_string(path)
        .ok()
        .map(|content| {
            content
                .lines()
                .filter_map(|line| serde_json::from_str::<T>(line).ok())
                .collect()
        })
        .unwrap_or_default()
}
