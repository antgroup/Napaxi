//! Thread attachment storage: save, load, delete, and history merging.
//!
//! Attachments live under `napaxi_attachments/{thread_id}.json` as an
//! array of `{user_msg_index, attachments}` entries. Helpers normalize
//! incoming metadata (sandbox vs local paths, alias keys) and strip
//! transient payloads before persistence.

use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use crate::error::StorageError;

fn attachments_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi_attachments")
}

pub(super) fn attachments_file(files_dir: &str, thread_id: &str) -> PathBuf {
    attachments_dir(files_dir).join(format!("{thread_id}.json"))
}

fn read_attachment_entries(files_dir: &str, thread_id: &str) -> Vec<Value> {
    let path = attachments_file(files_dir, thread_id);
    let Ok(content) = fs::read_to_string(path) else {
        return Vec::new();
    };
    serde_json::from_str::<Vec<Value>>(&content).unwrap_or_default()
}

fn write_attachment_entries(
    files_dir: &str,
    thread_id: &str,
    entries: &[Value],
) -> Result<(), StorageError> {
    let dir = attachments_dir(files_dir);
    fs::create_dir_all(&dir)?;
    let path = attachments_file(files_dir, thread_id);
    let content =
        serde_json::to_string(entries).map_err(|e| StorageError::Decode(e.to_string()))?;
    fs::write(path, content)?;
    Ok(())
}

/// Result-returning variant. Public `bool` wrapper logs the error and returns
/// false on failure; new code paths should prefer this inner form.
pub(crate) fn save_message_attachments_inner(
    files_dir: &str,
    thread_id: &str,
    user_msg_index: i32,
    attachments_json: &str,
) -> Result<(), StorageError> {
    let attachments: Value =
        serde_json::from_str(attachments_json).map_err(|e| StorageError::Decode(e.to_string()))?;
    let attachments = normalize_attachment_metadata_list(&attachments);
    if attachments.as_array().is_none_or(|items| items.is_empty()) {
        return Ok(());
    }

    let mut entries = read_attachment_entries(files_dir, thread_id);

    if let Some(existing) = entries.iter().position(|item| {
        item.get("user_msg_index")
            .and_then(Value::as_i64)
            .is_some_and(|idx| idx == user_msg_index as i64)
    }) {
        let previous = entries[existing].get("attachments");
        entries[existing] = serde_json::json!({
            "user_msg_index": user_msg_index,
            "attachments": merge_attachment_metadata(previous, &attachments),
        });
    } else {
        entries.push(serde_json::json!({
            "user_msg_index": user_msg_index,
            "attachments": attachments,
        }));
    }

    write_attachment_entries(files_dir, thread_id, &entries)
}

pub fn save_message_attachments(
    files_dir: &str,
    thread_id: &str,
    user_msg_index: i32,
    attachments_json: &str,
) -> bool {
    match save_message_attachments_inner(files_dir, thread_id, user_msg_index, attachments_json) {
        Ok(()) => true,
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                thread_id,
                user_msg_index,
                "save_message_attachments failed"
            );
            false
        }
    }
}

pub fn load_thread_attachments_json(files_dir: &str, thread_id: &str) -> String {
    let entries = read_attachment_entries(files_dir, thread_id);
    let mut map = serde_json::Map::new();
    for entry in entries {
        let Some(index) = entry.get("user_msg_index").and_then(Value::as_i64) else {
            continue;
        };
        let attachments = entry
            .get("attachments")
            .cloned()
            .unwrap_or_else(|| Value::Array(Vec::new()));
        map.insert(index.to_string(), attachments);
    }
    Value::Object(map).to_string()
}

pub fn delete_thread_attachments(files_dir: &str, thread_id: &str) -> bool {
    match delete_thread_attachments_inner(files_dir, thread_id) {
        Ok(()) => true,
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                thread_id,
                "delete_thread_attachments failed"
            );
            false
        }
    }
}

pub(crate) fn delete_thread_attachments_inner(
    files_dir: &str,
    thread_id: &str,
) -> Result<(), StorageError> {
    let path = attachments_file(files_dir, thread_id);
    if !path.exists() {
        return Ok(());
    }
    fs::remove_file(path)?;
    Ok(())
}

pub fn merge_attachments_into_history(files_dir: &str, thread_id: &str, messages: &mut [Value]) {
    let attachment_map: Value =
        serde_json::from_str(&load_thread_attachments_json(files_dir, thread_id))
            .unwrap_or_else(|_| Value::Object(Default::default()));
    let Some(map) = attachment_map.as_object() else {
        return;
    };
    if map.is_empty() {
        return;
    }

    let mut user_msg_index = 0;
    for message in messages.iter_mut() {
        let is_user = message
            .get("role")
            .and_then(Value::as_str)
            .is_some_and(|role| role == "user");
        if !is_user {
            continue;
        }
        if let Some(attachments) = map.get(&user_msg_index.to_string())
            && let Some(obj) = message.as_object_mut()
        {
            obj.insert("attachments".to_string(), attachments.clone());
        }
        user_msg_index += 1;
    }
}

fn normalize_attachment_metadata_list(value: &Value) -> Value {
    let Some(items) = value.as_array() else {
        return Value::Array(Vec::new());
    };
    let items = items
        .iter()
        .map(normalize_attachment_metadata)
        .filter(|item| item.as_object().is_some_and(|object| !object.is_empty()))
        .collect();
    Value::Array(items)
}

fn normalize_attachment_metadata(value: &Value) -> Value {
    let mut out = Map::new();
    copy_string_field(value, &mut out, "kind", &["type"]);
    copy_string_field(value, &mut out, "mime_type", &["mimeType"]);
    copy_string_field(value, &mut out, "filename", &["name"]);
    copy_sandbox_path_field(value, &mut out);
    copy_local_path_field(value, &mut out);
    Value::Object(out)
}

fn copy_string_field(value: &Value, out: &mut Map<String, Value>, key: &str, aliases: &[&str]) {
    if let Some(text) = value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .or_else(|| string_field(value, aliases))
    {
        out.insert(key.to_string(), Value::String(text.to_string()));
    }
}

fn copy_sandbox_path_field(value: &Value, out: &mut Map<String, Value>) {
    if let Some(path) = string_field(value, &["sandbox_path", "sandboxPath"]) {
        out.insert("sandbox_path".to_string(), Value::String(path.to_string()));
        return;
    }
    let Some(path) = string_field(value, &["path"]) else {
        return;
    };
    if is_legacy_path_sandbox_path(path) {
        out.insert("sandbox_path".to_string(), Value::String(path.to_string()));
    }
}

fn copy_local_path_field(value: &Value, out: &mut Map<String, Value>) {
    if let Some(path) = string_field(value, &["local_path", "localPath", "host_path", "hostPath"]) {
        out.insert("path".to_string(), Value::String(path.to_string()));
        return;
    }
    let Some(path) = string_field(value, &["path"]) else {
        return;
    };
    if !is_legacy_path_sandbox_path(path) {
        out.insert("path".to_string(), Value::String(path.to_string()));
    }
}

fn is_legacy_path_sandbox_path(path: &str) -> bool {
    path == "/workspace"
        || path.starts_with("/workspace/")
        || path == "/skills"
        || path.starts_with("/skills/")
}

fn string_field<'a>(value: &'a Value, keys: &[&str]) -> Option<&'a str> {
    keys.iter().find_map(|key| {
        value
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|text| !text.is_empty())
    })
}

fn merge_attachment_metadata(previous: Option<&Value>, incoming: &Value) -> Value {
    let Some(incoming_items) = incoming.as_array() else {
        return Value::Array(Vec::new());
    };
    let previous_items = previous.and_then(Value::as_array);
    let mut merged = Vec::with_capacity(incoming_items.len());
    for (index, item) in incoming_items.iter().enumerate() {
        let mut object = item.as_object().cloned().unwrap_or_default();
        if let Some(previous_object) = previous_items
            .and_then(|items| items.get(index))
            .and_then(Value::as_object)
        {
            for key in ["kind", "mime_type", "filename", "sandbox_path", "path"] {
                if !object.contains_key(key)
                    && let Some(value) = previous_object.get(key)
                {
                    object.insert(key.to_string(), value.clone());
                }
            }
        }
        merged.push(Value::Object(object));
    }
    Value::Array(merged)
}
