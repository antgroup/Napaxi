//! Small filesystem and time utilities shared across workspace submodules.

use std::fs;
use std::path::Path;

use chrono::{DateTime, Utc};

pub(super) fn invalid_handle_json() -> String {
    r#"{"error":"invalid engine handle"}"#.to_string()
}

pub(super) fn error_json(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

pub(super) fn modified_rfc3339(path: &Path) -> Option<String> {
    let modified = path.metadata().ok()?.modified().ok()?;
    let dt: DateTime<Utc> = modified.into();
    Some(dt.to_rfc3339())
}

pub(super) fn newest_rfc3339(left: Option<String>, right: Option<String>) -> Option<String> {
    match (left, right) {
        (Some(left), Some(right)) => {
            if left >= right {
                Some(left)
            } else {
                Some(right)
            }
        }
        (Some(value), None) | (None, Some(value)) => Some(value),
        (None, None) => None,
    }
}

pub(super) fn read_preview(path: &Path) -> Option<String> {
    let content = fs::read_to_string(path).ok()?;
    let preview: String = content.chars().take(200).collect();
    Some(preview)
}
