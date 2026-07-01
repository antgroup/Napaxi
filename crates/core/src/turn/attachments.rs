use std::fs;
use std::path::{Path, PathBuf};

use base64::Engine;

use crate::types::{AttachmentKind, IncomingAttachment, PlatformLlmConfig};

pub(super) fn persist_attachments(
    files_dir: &str,
    session_key_json: &str,
    attachments_json: &str,
) -> bool {
    if attachments_json.trim().is_empty() || attachments_json.trim() == "[]" {
        return true;
    }
    let Ok(key) = serde_json::from_str::<serde_json::Value>(session_key_json) else {
        return false;
    };
    let Some(thread_id) = key.get("thread_id").and_then(serde_json::Value::as_str) else {
        return false;
    };
    let user_index = user_message_index(files_dir, thread_id);
    crate::storage::save_message_attachments(files_dir, thread_id, user_index, attachments_json)
}

fn user_message_index(files_dir: &str, thread_id: &str) -> i32 {
    serde_json::from_str::<Vec<serde_json::Value>>(&crate::session::get_history(
        files_dir, thread_id,
    ))
    .map(|messages| {
        messages
            .iter()
            .filter(|message| {
                message
                    .get("role")
                    .and_then(serde_json::Value::as_str)
                    .is_some_and(|role| role == "user")
            })
            .count()
            .saturating_sub(1) as i32
    })
    .unwrap_or(0)
}

pub(crate) fn parse_scene_prompt_attachments(attachments_json: &str) -> Vec<IncomingAttachment> {
    let Ok(serde_json::Value::Array(items)) = serde_json::from_str(attachments_json) else {
        return Vec::new();
    };

    items
        .into_iter()
        .filter_map(|item| {
            let mime_type = string_value(&item, "mime_type")
                .or_else(|| string_value(&item, "mimeType"))
                .unwrap_or_default();
            let filename = string_value(&item, "filename").or_else(|| string_value(&item, "name"));
            if mime_type.is_empty() && filename.is_none() {
                return None;
            }

            let data = string_value(&item, "data_base64")
                .and_then(|data| base64::engine::general_purpose::STANDARD.decode(data).ok())
                .unwrap_or_default();
            let size_bytes = item
                .get("size_bytes")
                .and_then(serde_json::Value::as_u64)
                .or_else(|| (!data.is_empty()).then_some(data.len() as u64));

            Some(IncomingAttachment {
                id: string_value(&item, "id").unwrap_or_default(),
                kind: AttachmentKind::from_mime_type(&mime_type),
                mime_type,
                filename,
                size_bytes,
                source_url: string_value(&item, "source_url"),
                storage_key: string_value(&item, "sandbox_path")
                    .or_else(|| string_value(&item, "storage_key"))
                    .or_else(|| {
                        string_value(&item, "path").filter(|path| is_legacy_path_sandbox_path(path))
                    }),
                local_path: string_value(&item, "local_path")
                    .or_else(|| string_value(&item, "localPath"))
                    .or_else(|| string_value(&item, "host_path"))
                    .or_else(|| string_value(&item, "hostPath"))
                    .or_else(|| {
                        string_value(&item, "path")
                            .filter(|path| !is_legacy_path_sandbox_path(path))
                    }),
                extracted_text: string_value(&item, "extracted_text"),
                data,
                duration_secs: item
                    .get("duration_secs")
                    .and_then(serde_json::Value::as_u64)
                    .and_then(|value| value.try_into().ok()),
            })
        })
        .collect()
}

pub(crate) fn persist_attachment_files(
    files_dir: &str,
    workspace_files_dir: &str,
    thread_id: &str,
    attachments: &mut [IncomingAttachment],
) {
    let bridge =
        crate::storage::FileBridge::new_with_workspace_files_dir(files_dir, workspace_files_dir);
    let target_dir = bridge
        .workspace_dir()
        .join("attachments")
        .join(safe_path_segment(thread_id));
    if fs::create_dir_all(&target_dir).is_err() {
        return;
    }

    for (index, attachment) in attachments.iter_mut().enumerate() {
        if attachment.data.is_empty() {
            continue;
        }
        let filename = attachment
            .filename
            .as_deref()
            .map(safe_filename)
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| default_attachment_filename(index, attachment));
        let target = unique_attachment_path(&target_dir, index, &filename);
        if fs::write(&target, &attachment.data).is_ok()
            && let Some(path) = bridge.real_to_sandbox(&target.display().to_string())
        {
            attachment.storage_key = Some(path);
        }
    }
}

pub(crate) fn attachment_metadata_json(attachments: &[IncomingAttachment]) -> String {
    let items = attachments
        .iter()
        .map(|attachment| {
            let mut item = serde_json::Map::new();
            item.insert(
                "kind".to_string(),
                serde_json::Value::String(
                    match attachment.kind {
                        AttachmentKind::Audio => "audio",
                        AttachmentKind::Image => "image",
                        AttachmentKind::Document => "document",
                    }
                    .to_string(),
                ),
            );
            item.insert(
                "mime_type".to_string(),
                serde_json::Value::String(attachment.mime_type.clone()),
            );
            if let Some(filename) = &attachment.filename {
                item.insert(
                    "filename".to_string(),
                    serde_json::Value::String(filename.clone()),
                );
            }
            if let Some(sandbox_path) = &attachment.storage_key {
                item.insert(
                    "sandbox_path".to_string(),
                    serde_json::Value::String(sandbox_path.clone()),
                );
            }
            if let Some(local_path) = &attachment.local_path {
                item.insert(
                    "path".to_string(),
                    serde_json::Value::String(local_path.clone()),
                );
            }
            serde_json::Value::Object(item)
        })
        .collect::<Vec<_>>();
    serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string())
}

fn safe_path_segment(value: &str) -> String {
    let segment = value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_') {
                ch
            } else {
                '_'
            }
        })
        .collect::<String>();
    if segment.is_empty() {
        "thread".to_string()
    } else {
        segment
    }
}

fn is_legacy_path_sandbox_path(path: &str) -> bool {
    path == "/workspace"
        || path.starts_with("/workspace/")
        || path == "/skills"
        || path.starts_with("/skills/")
}

fn safe_filename(value: &str) -> String {
    let name = Path::new(value)
        .file_name()
        .map(|part| part.to_string_lossy().into_owned())
        .unwrap_or_default();
    let name = name
        .chars()
        .map(|ch| {
            if ch == '/' || ch == '\\' || ch == '\0' {
                '_'
            } else {
                ch
            }
        })
        .collect::<String>();
    name.trim_start_matches('.').trim().to_string()
}

fn default_attachment_filename(index: usize, attachment: &IncomingAttachment) -> String {
    let extension = match attachment.mime_type.as_str() {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp",
        "image/gif" => "gif",
        "application/pdf" => "pdf",
        "text/plain" => "txt",
        _ if attachment.mime_type.starts_with("image/") => "img",
        _ if attachment.mime_type.starts_with("audio/") => "audio",
        _ => "bin",
    };
    format!("attachment-{}.{}", index + 1, extension)
}

fn unique_attachment_path(target_dir: &Path, index: usize, filename: &str) -> PathBuf {
    let path = target_dir.join(filename);
    if !path.exists() {
        return path;
    }
    let original = Path::new(filename);
    let stem = original
        .file_stem()
        .map(|part| part.to_string_lossy().into_owned())
        .unwrap_or_else(|| "attachment".to_string());
    let ext = original
        .extension()
        .map(|part| format!(".{}", part.to_string_lossy()))
        .unwrap_or_default();
    target_dir.join(format!("{stem}-{}{}", index + 1, ext))
}

#[cfg(test)]
pub(crate) fn raw_history_with_attachments(
    history: &[crate::session::SessionMessage],
    attachments: &[IncomingAttachment],
) -> Vec<serde_json::Value> {
    raw_history_with_attachment_mode(history, attachments, true)
}

pub(super) fn raw_history_with_attachments_for_config(
    history: &[crate::session::SessionMessage],
    attachments: &[IncomingAttachment],
    _config: &PlatformLlmConfig,
) -> Vec<serde_json::Value> {
    raw_history_with_attachment_mode(history, attachments, false)
}

fn raw_history_with_attachment_mode(
    history: &[crate::session::SessionMessage],
    attachments: &[IncomingAttachment],
    include_visual_parts: bool,
) -> Vec<serde_json::Value> {
    let mut messages = crate::llm::openai_messages_from_mobile_history(history);
    if attachments.is_empty() {
        return messages;
    }
    let Some(message) = messages
        .iter_mut()
        .rev()
        .find(|message| message.get("role").and_then(serde_json::Value::as_str) == Some("user"))
    else {
        return messages;
    };
    let content = message
        .get("content")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    message["content"] =
        attachment_content_parts_with_mode(content, attachments, include_visual_parts);
    messages
}

pub(crate) fn attachment_content_parts_with_mode(
    content: &str,
    attachments: &[IncomingAttachment],
    include_visual_parts: bool,
) -> serde_json::Value {
    let mut parts = Vec::new();
    parts.push(serde_json::json!({
        "type": "text",
        "text": augment_attachment_text(content, attachments),
    }));
    if !include_visual_parts {
        return serde_json::Value::Array(parts);
    }
    for attachment in attachments {
        if attachment.kind != AttachmentKind::Image || attachment.data.is_empty() {
            continue;
        }
        let b64 = base64::engine::general_purpose::STANDARD.encode(&attachment.data);
        parts.push(serde_json::json!({
            "type": "image_url",
            "image_url": {
                "url": format!("data:{};base64,{}", attachment.mime_type, b64),
                "detail": "auto",
            },
        }));
    }
    serde_json::Value::Array(parts)
}

fn augment_attachment_text(content: &str, attachments: &[IncomingAttachment]) -> String {
    let mut text = content.to_string();
    text.push_str("\n\n<attachments>");
    for (index, attachment) in attachments.iter().enumerate() {
        text.push('\n');
        text.push_str(&format_attachment(index + 1, attachment));
    }
    text.push_str("\n</attachments>");
    text
}

fn format_attachment(index: usize, attachment: &IncomingAttachment) -> String {
    let filename = escape_xml_attr(attachment.filename.as_deref().unwrap_or("unknown"));
    let mime = escape_xml_attr(&attachment.mime_type);
    let sandbox_path_attr = attachment
        .storage_key
        .as_deref()
        .map(escape_xml_attr)
        .map(|path| format!(" sandbox_path=\"{path}\""))
        .unwrap_or_default();
    let size_attr = attachment
        .size_bytes
        .or_else(|| (!attachment.data.is_empty()).then_some(attachment.data.len() as u64))
        .map(|size| format!(" size=\"{}\"", format_size(size)))
        .unwrap_or_default();
    match attachment.kind {
        AttachmentKind::Audio => {
            let duration_attr = attachment
                .duration_secs
                .map(|duration| format!(" duration=\"{duration}s\""))
                .unwrap_or_default();
            let body = attachment
                .extracted_text
                .as_deref()
                .map(|text| format!("Transcript: {}", escape_xml_text(text)))
                .unwrap_or_else(|| "Audio transcript unavailable.".to_string());
            format!(
                "<attachment index=\"{index}\" type=\"audio\" filename=\"{filename}\" mime=\"{mime}\"{duration_attr}{size_attr}>\n{body}\n</attachment>"
            )
        }
        AttachmentKind::Image => {
            let body = if attachment.data.is_empty() {
                "[Image attached - visual content unavailable]"
            } else if attachment.storage_key.is_some() {
                "[Image attached as a workspace file. Visual inspection requires an image analysis tool.]"
            } else {
                "[Image attached - visual content unavailable]"
            };
            format!(
                "<attachment index=\"{index}\" type=\"image\" filename=\"{filename}\" mime=\"{mime}\"{sandbox_path_attr}{size_attr}>\n{body}\n</attachment>"
            )
        }
        AttachmentKind::Document => {
            let body = attachment
                .extracted_text
                .as_deref()
                .map(escape_xml_text)
                .unwrap_or_else(|| "[Document attached - text extraction unavailable]".to_string());
            format!(
                "<attachment index=\"{index}\" type=\"document\" filename=\"{filename}\" mime=\"{mime}\"{size_attr}>\n{body}\n</attachment>"
            )
        }
    }
}

fn escape_xml_attr(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn escape_xml_text(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn format_size(bytes: u64) -> String {
    if bytes < 1024 {
        format!("{bytes}B")
    } else if bytes < 1024 * 1024 {
        format!("{}KB", bytes / 1024)
    } else {
        format!("{}MB", bytes / (1024 * 1024))
    }
}

fn string_value(value: &serde_json::Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(ToString::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attachment_metadata_preserves_local_path_without_sandbox_path() {
        let attachments = parse_scene_prompt_attachments(
            r#"[{"kind":"document","mime_type":"text/plain","filename":"notes.txt","path":"/tmp/notes.txt","data_base64":"aGVsbG8="}]"#,
        );

        assert_eq!(attachments.len(), 1);
        assert_eq!(attachments[0].local_path.as_deref(), Some("/tmp/notes.txt"));
        assert!(attachments[0].storage_key.is_none());

        let metadata: serde_json::Value =
            serde_json::from_str(&attachment_metadata_json(&attachments)).unwrap();
        assert_eq!(metadata[0]["path"].as_str(), Some("/tmp/notes.txt"));
        assert!(metadata[0].get("sandbox_path").is_none());
        assert!(metadata[0].get("data_base64").is_none());
    }

    #[test]
    fn legacy_path_workspace_metadata_remains_sandbox_path() {
        let attachments = parse_scene_prompt_attachments(
            r#"[{"kind":"document","mime_type":"text/plain","filename":"notes.txt","path":"/workspace/notes.txt"}]"#,
        );

        assert_eq!(attachments.len(), 1);
        assert_eq!(
            attachments[0].storage_key.as_deref(),
            Some("/workspace/notes.txt")
        );
        assert!(attachments[0].local_path.is_none());
    }
}
