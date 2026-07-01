use serde_json::{Map, Value, json};

use crate::channel::{ChannelMedia, ChannelModality};

pub(super) fn attachments_json_from_channel_media(media: &[ChannelMedia]) -> String {
    if media.is_empty() {
        return "[]".to_string();
    }
    let attachments = media
        .iter()
        .take(20)
        .filter_map(attachment_from_channel_media)
        .collect::<Vec<_>>();
    serde_json::to_string(&attachments).unwrap_or_else(|_| "[]".to_string())
}

fn attachment_from_channel_media(media: &ChannelMedia) -> Option<Value> {
    let mime_type = media
        .mime_type
        .as_deref()
        .map(str::trim)
        .unwrap_or_default();
    let name = media.name.as_deref().map(str::trim).unwrap_or_default();
    let uri = media.uri.as_deref().map(str::trim).unwrap_or_default();
    if mime_type.is_empty() && name.is_empty() && uri.is_empty() && media.raw.is_none() {
        return None;
    }
    let mut out = Map::new();
    out.insert("kind".to_string(), json!(channel_media_kind(media.kind)));
    if !mime_type.is_empty() {
        out.insert("mime_type".to_string(), json!(mime_type));
    }
    if !name.is_empty() {
        out.insert("filename".to_string(), json!(name));
    }
    if let Some(size) = media.size_bytes {
        out.insert("size_bytes".to_string(), json!(size));
    }
    if let Some(raw) = media.raw.as_ref() {
        if let Some(text) = metadata_string(raw, &["extractedText", "extracted_text", "text"]) {
            out.insert("extracted_text".to_string(), json!(text));
        }
        if let Some(data) = metadata_string(raw, &["dataBase64", "data_base64"]) {
            if data.len() <= 12 * 1024 * 1024 {
                out.insert("data_base64".to_string(), json!(data));
            }
        }
        if let Some(sandbox_path) = metadata_string(raw, &["sandboxPath", "sandbox_path"]) {
            out.insert("sandbox_path".to_string(), json!(sandbox_path));
            return Some(Value::Object(out));
        }
    }
    if uri.starts_with("/workspace/") {
        out.insert("sandbox_path".to_string(), json!(uri));
    } else if let Some(local_path) = uri.strip_prefix("file://") {
        out.insert("path".to_string(), json!(local_path));
    } else if !uri.is_empty() {
        out.insert("source_url".to_string(), json!(uri));
    }
    Some(Value::Object(out))
}

fn channel_media_kind(kind: ChannelModality) -> &'static str {
    match kind {
        ChannelModality::Image => "image",
        ChannelModality::Audio => "audio",
        _ => "document",
    }
}

fn metadata_string(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(Value::as_str))
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_string)
}

fn metadata_u64(value: &Value, keys: &[&str]) -> Option<u64> {
    keys.iter().find_map(|key| {
        let value = value.get(*key)?;
        value
            .as_u64()
            .or_else(|| value.as_str().and_then(|item| item.trim().parse().ok()))
    })
}

pub(super) fn append_tool_result_media(out: &mut Vec<ChannelMedia>, event: &Value) {
    if out.len() >= 12 {
        return;
    }
    let Some(tool_name) = metadata_string(event, &["name", "tool_name", "toolName"]) else {
        return;
    };
    if !matches!(
        tool_name.as_str(),
        "media_library" | "pick_media" | "take_photo" | "record_audio"
    ) {
        return;
    }
    if event
        .get("is_error")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return;
    }
    let Some(output) = metadata_string(event, &["output"]) else {
        return;
    };
    let Ok(value) = serde_json::from_str::<Value>(&output) else {
        return;
    };
    append_channel_media_from_artifact_value(out, &value);
    for key in ["artifacts", "attachments"] {
        let Some(items) = value.get(key).and_then(Value::as_array) else {
            continue;
        };
        for item in items {
            append_channel_media_from_artifact_value(out, item);
            if out.len() >= 12 {
                return;
            }
        }
    }
}

fn append_channel_media_from_artifact_value(out: &mut Vec<ChannelMedia>, value: &Value) {
    if out.len() >= 12 {
        return;
    }
    let Some(media) = channel_media_from_artifact_value(value) else {
        return;
    };
    if out
        .iter()
        .any(|existing| same_channel_media(existing, &media))
    {
        return;
    }
    out.push(media);
}

fn channel_media_from_artifact_value(value: &Value) -> Option<ChannelMedia> {
    let uri = metadata_string(
        value,
        &[
            "uri",
            "sandbox_path",
            "sandboxPath",
            "file_path",
            "filePath",
            "path",
        ],
    );
    let mime_type = metadata_string(value, &["mime_type", "mimeType"]);
    let name = metadata_string(value, &["name", "filename", "fileName"]);
    if uri.is_none() && mime_type.is_none() && name.is_none() {
        return None;
    }
    Some(ChannelMedia {
        kind: channel_media_modality_from_artifact(value, mime_type.as_deref()),
        uri,
        mime_type,
        name,
        size_bytes: metadata_u64(value, &["size_bytes", "sizeBytes"]),
        raw: Some(value.clone()),
    })
}

fn channel_media_modality_from_artifact(value: &Value, mime_type: Option<&str>) -> ChannelModality {
    if let Some(kind) = metadata_string(value, &["kind", "type", "modality"]) {
        match kind.as_str() {
            "image" => return ChannelModality::Image,
            "audio" => return ChannelModality::Audio,
            "file" | "document" => return ChannelModality::File,
            _ => {}
        }
    }
    let mime = mime_type.unwrap_or_default().trim().to_lowercase();
    if mime.starts_with("image/") {
        ChannelModality::Image
    } else if mime.starts_with("audio/") {
        ChannelModality::Audio
    } else {
        ChannelModality::File
    }
}

fn same_channel_media(left: &ChannelMedia, right: &ChannelMedia) -> bool {
    left.uri == right.uri
        && left.mime_type == right.mime_type
        && left.name == right.name
        && left.size_bytes == right.size_bytes
}
