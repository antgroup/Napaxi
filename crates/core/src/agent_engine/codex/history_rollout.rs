use serde_json::Value;

#[cfg(target_os = "android")]
use super::config;
#[cfg(target_os = "android")]
use super::map_history_items;

#[cfg(target_os = "android")]
pub(super) fn read_persisted_rollout_messages(
    files_dir: &str,
    thread_id: &str,
) -> Option<Vec<Value>> {
    let sessions_dir = config::config_dir(files_dir).join("sessions");
    let rollout = find_rollout_file(&sessions_dir, thread_id, 0)?;
    let content = std::fs::read_to_string(rollout).ok()?;
    let items = content
        .lines()
        .filter_map(|line| serde_json::from_str::<Value>(line.trim()).ok())
        .collect::<Vec<_>>();
    let messages = map_history_items(&items);
    (!messages.is_empty()).then_some(messages)
}

#[cfg(not(target_os = "android"))]
#[cfg_attr(test, allow(dead_code))]
pub(super) fn read_persisted_rollout_messages(
    _files_dir: &str,
    _thread_id: &str,
) -> Option<Vec<Value>> {
    None
}

#[cfg(target_os = "android")]
fn find_rollout_file(
    dir: &std::path::Path,
    thread_id: &str,
    depth: usize,
) -> Option<std::path::PathBuf> {
    if depth > 5 {
        return None;
    }
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let path = entry.path();
        if path.is_file()
            && path
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.contains(thread_id) && name.ends_with(".jsonl"))
        {
            return Some(path);
        }
        if path.is_dir() {
            if let Some(found) = find_rollout_file(&path, thread_id, depth + 1) {
                return Some(found);
            }
        }
    }
    None
}

pub(super) fn history_messages_are_more_complete(candidate: &[Value], current: &[Value]) -> bool {
    let (candidate_score, current_score) = (
        history_message_score(candidate),
        history_message_score(current),
    );
    candidate_score > current_score
        || (candidate_score == current_score && candidate.len() > current.len())
}

fn history_message_score(messages: &[Value]) -> usize {
    messages
        .iter()
        .map(
            |message| match message.get("role").and_then(Value::as_str) {
                Some("reasoning") => 3,
                Some("tool_calls") => 3,
                Some("assistant") | Some("user") => 1,
                _ => 0,
            },
        )
        .sum()
}
