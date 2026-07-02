//! Profile JSON storage and derived prompt-document synchronization.
//!
//! `context/profile.json` is the structured user profile. When it is written,
//! we also derive matching markdown sections in `USER.md`, the assistant
//! directives, and `HEARTBEAT.md` so the prompt assembler can pick them up.

use super::files::{read_workspace_file_content, write_workspace_file_checked};
use super::paths::{
    ASSISTANT_DIRECTIVES, BOOTSTRAP, HEARTBEAT, PROFILE, PROFILE_SECTION_BEGIN,
    PROFILE_SECTION_END, USER,
};

pub fn write_profile_json(files_dir: &str, content: &str, merge: bool) -> Result<String, String> {
    let content = if merge {
        merge_profile_json(files_dir, content)?
    } else {
        content.to_string()
    };
    let path = write_workspace_file_checked(files_dir, PROFILE, &content)?;
    let _ = sync_profile_documents(files_dir)?;
    Ok(path)
}

pub fn sync_profile_documents(files_dir: &str) -> Result<bool, String> {
    let Some(content) = read_workspace_file_content(files_dir, PROFILE)? else {
        return Ok(false);
    };
    let Ok(profile) = serde_json::from_str::<serde_json::Value>(&content) else {
        return Ok(false);
    };
    if !is_populated_json(&profile) {
        return Ok(false);
    }

    let user_md = profile_to_user_md(&profile);
    if !user_md.trim().is_empty() {
        let existing = read_workspace_file_content(files_dir, USER)?.unwrap_or_default();
        let merged = merge_profile_section(&existing, &user_md);
        write_workspace_file_checked(files_dir, USER, &merged)?;
    }

    let directives = profile_to_assistant_directives(&profile);
    if !directives.trim().is_empty() {
        write_workspace_file_checked(files_dir, ASSISTANT_DIRECTIVES, &directives)?;
    }

    let existing_heartbeat = read_workspace_file_content(files_dir, HEARTBEAT)?;
    if existing_heartbeat
        .as_deref()
        .map(is_heartbeat_seed_template)
        .unwrap_or(true)
    {
        let heartbeat = profile_to_heartbeat_md(&profile);
        if !heartbeat.trim().is_empty() {
            write_workspace_file_checked(files_dir, HEARTBEAT, &heartbeat)?;
        }
    }

    let _ = write_workspace_file_checked(files_dir, BOOTSTRAP, "");
    Ok(true)
}

pub(crate) fn is_profile_populated(files_dir: &str) -> bool {
    let Ok(Some(content)) = read_workspace_file_content(files_dir, PROFILE) else {
        return false;
    };
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&content) else {
        return false;
    };
    is_populated_json(&value)
}

fn is_populated_json(value: &serde_json::Value) -> bool {
    match value {
        serde_json::Value::Object(map) => map.values().any(is_populated_json),
        serde_json::Value::Array(items) => items.iter().any(is_populated_json),
        serde_json::Value::String(text) => !text.trim().is_empty() && text.trim() != "unknown",
        serde_json::Value::Number(_) | serde_json::Value::Bool(_) => true,
        serde_json::Value::Null => false,
    }
}

fn merge_profile_json(files_dir: &str, incoming: &str) -> Result<String, String> {
    let mut incoming_value =
        serde_json::from_str::<serde_json::Value>(incoming).map_err(|e| e.to_string())?;
    let Some(existing_content) = read_workspace_file_content(files_dir, PROFILE)? else {
        return serde_json::to_string_pretty(&incoming_value).map_err(|e| e.to_string());
    };
    let Ok(mut existing_value) = serde_json::from_str::<serde_json::Value>(&existing_content)
    else {
        return serde_json::to_string_pretty(&incoming_value).map_err(|e| e.to_string());
    };
    merge_json_values(&mut existing_value, incoming_value.take());
    serde_json::to_string_pretty(&existing_value).map_err(|e| e.to_string())
}

fn merge_json_values(base: &mut serde_json::Value, incoming: serde_json::Value) {
    match (base, incoming) {
        (serde_json::Value::Object(base), serde_json::Value::Object(incoming)) => {
            for (key, value) in incoming {
                match base.get_mut(&key) {
                    Some(base_value) => merge_json_values(base_value, value),
                    None => {
                        base.insert(key, value);
                    }
                }
            }
        }
        (base, incoming) => {
            *base = incoming;
        }
    }
}

fn profile_to_user_md(profile: &serde_json::Value) -> String {
    let mut lines = vec!["# Profile Summary".to_string()];
    flatten_profile_lines(profile, "", &mut lines, 0);
    lines.join("\n")
}

fn flatten_profile_lines(
    value: &serde_json::Value,
    prefix: &str,
    lines: &mut Vec<String>,
    depth: usize,
) {
    if depth > 4 {
        return;
    }
    match value {
        serde_json::Value::Object(map) => {
            for (key, value) in map {
                let label = if prefix.is_empty() {
                    humanize_key(key)
                } else {
                    format!("{prefix} / {}", humanize_key(key))
                };
                flatten_profile_lines(value, &label, lines, depth + 1);
            }
        }
        serde_json::Value::Array(items) => {
            let values: Vec<String> = items
                .iter()
                .filter_map(profile_scalar)
                .filter(|value| !value.is_empty() && value != "unknown")
                .collect();
            if !values.is_empty() && !prefix.is_empty() {
                lines.push(format!("- **{prefix}:** {}", values.join(", ")));
            }
        }
        _ => {
            if let Some(value) = profile_scalar(value)
                && !value.is_empty()
                && value != "unknown"
                && !prefix.is_empty()
            {
                lines.push(format!("- **{prefix}:** {value}"));
            }
        }
    }
}

fn profile_scalar(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(text) => Some(text.trim().to_string()),
        serde_json::Value::Number(number) => Some(number.to_string()),
        serde_json::Value::Bool(value) => Some(value.to_string()),
        _ => None,
    }
}

fn profile_to_assistant_directives(profile: &serde_json::Value) -> String {
    let mut lines = vec![
        "# Assistant Directives",
        "",
        "Use these profile-derived preferences when responding to the user.",
    ]
    .into_iter()
    .map(str::to_string)
    .collect::<Vec<_>>();
    for key in [
        "communication",
        "interaction_preferences",
        "assistance",
        "preferences",
        "style",
    ] {
        if let Some(value) = profile.get(key)
            && is_populated_json(value)
        {
            flatten_profile_lines(value, "", &mut lines, 0);
        }
    }
    lines.join("\n")
}

fn profile_to_heartbeat_md(profile: &serde_json::Value) -> String {
    let mut lines = vec![
        "# Heartbeat Notes".to_string(),
        String::new(),
        "Profile-derived follow-up guidance.".to_string(),
    ];
    for key in ["goals", "needs", "reminders", "notification_preferences"] {
        if let Some(value) = find_profile_key(profile, key)
            && is_populated_json(value)
        {
            flatten_profile_lines(value, &humanize_key(key), &mut lines, 0);
        }
    }
    lines.join("\n")
}

fn find_profile_key<'a>(
    value: &'a serde_json::Value,
    wanted: &str,
) -> Option<&'a serde_json::Value> {
    match value {
        serde_json::Value::Object(map) => {
            if let Some(found) = map.get(wanted) {
                return Some(found);
            }
            map.values()
                .find_map(|value| find_profile_key(value, wanted))
        }
        serde_json::Value::Array(items) => items
            .iter()
            .find_map(|value| find_profile_key(value, wanted)),
        _ => None,
    }
}

fn humanize_key(key: &str) -> String {
    key.replace(['_', '-'], " ")
}

fn wrap_profile_section(content: &str) -> String {
    format!("{PROFILE_SECTION_BEGIN}\n{content}\n{PROFILE_SECTION_END}")
}

fn merge_profile_section(existing: &str, new_content: &str) -> String {
    let delimited = wrap_profile_section(new_content);
    if let Some(begin) = existing.find(PROFILE_SECTION_BEGIN)
        && let Some(end_offset) = existing[begin..].find(PROFILE_SECTION_END)
    {
        let end_start = begin + end_offset;
        let end = end_start + PROFILE_SECTION_END.len();
        let mut result = String::with_capacity(existing.len());
        result.push_str(&existing[..begin]);
        result.push_str(&delimited);
        result.push_str(&existing[end..]);
        return result;
    }
    if existing.starts_with("<!-- Auto-generated from context/profile.json")
        || is_user_seed_template(existing)
        || existing.trim().is_empty()
    {
        return delimited;
    }
    format!("{}\n\n{}", existing.trim_end(), delimited)
}

fn is_user_seed_template(content: &str) -> bool {
    let trimmed = content.trim();
    // When evolution has already appended entries (## Memory Evolution), don't
    // treat this as a pristine seed — let merge_profile_section append rather
    // than replace, preserving evolution-added content alongside the profile.
    if trimmed.contains("## Memory Evolution") {
        return false;
    }
    trimmed.starts_with("# User Context")
        && (trimmed.contains("- **Name:**")
            || trimmed.contains("No user profile has been established yet"))
}

fn is_heartbeat_seed_template(content: &str) -> bool {
    let trimmed = content.trim();
    trimmed.starts_with("# Heartbeat Checklist") && trimmed.contains("HEARTBEAT_OK")
}
