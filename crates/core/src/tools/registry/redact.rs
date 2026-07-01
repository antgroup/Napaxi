//! Secret redaction for tool arguments and output, plus output truncation.

use serde_json::Value;

pub(super) const MAX_TOOL_OUTPUT_SIZE: usize = 64 * 1024;
pub(super) const REDACTED: &str = "[REDACTED]";

pub fn redact_tool_arguments_json(arguments: &str) -> String {
    let Ok(value) = serde_json::from_str::<Value>(arguments) else {
        return arguments.to_string();
    };
    serde_json::to_string(&redact_sensitive_json(&value)).unwrap_or_else(|_| arguments.to_string())
}

pub fn sanitize_tool_output(output: &str) -> String {
    let redacted = if let Ok(value) = serde_json::from_str::<Value>(output) {
        serde_json::to_string_pretty(&redact_sensitive_json(&value))
            .unwrap_or_else(|_| redact_sensitive_text(output))
    } else {
        redact_sensitive_text(output)
    };
    truncate_tool_output(&redacted)
}

pub fn redact_sensitive_json(value: &Value) -> Value {
    let mut cloned = value.clone();
    redact_json_in_place(&mut cloned);
    cloned
}

fn redact_json_in_place(value: &mut Value) {
    match value {
        Value::Object(map) => {
            for (key, value) in map {
                if is_sensitive_key(key) {
                    *value = Value::String(REDACTED.to_string());
                } else {
                    redact_json_in_place(value);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                redact_json_in_place(item);
            }
        }
        _ => {}
    }
}

fn redact_sensitive_text(text: &str) -> String {
    text.lines()
        .map(redact_sensitive_line)
        .collect::<Vec<_>>()
        .join("\n")
}

fn redact_sensitive_line(line: &str) -> String {
    let lower = line.to_ascii_lowercase();
    if let Some(redacted) = redact_bearer_token(line, &lower) {
        return redacted;
    }
    for delimiter in ['=', ':'] {
        if let Some(idx) = line.find(delimiter) {
            let key = line[..idx].trim();
            if is_sensitive_key(key) {
                return format!("{}{} {}", line[..idx].trim_end(), delimiter, REDACTED);
            }
        }
    }
    line.to_string()
}

fn redact_bearer_token(line: &str, lower: &str) -> Option<String> {
    let idx = lower.find("bearer ")?;
    Some(format!("{}Bearer {}", &line[..idx], REDACTED))
}

fn is_sensitive_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    if SENSITIVE_EXACT.contains(&lower.as_str()) {
        return true;
    }
    let parts = tokenize_key_parts(key);
    if parts.is_empty() {
        return false;
    }
    if has_candidate_or_numbered_variant(&parts, SENSITIVE_PARTS) {
        return true;
    }
    let has_token = has_candidate_or_numbered_variant(&parts, TOKEN_PARTS);
    let has_key = has_candidate_or_numbered_variant(&parts, KEY_PARTS);
    if has_token && has_key {
        return true;
    }
    if has_contextual_suffix(&parts, TOKEN_PARTS) || has_contextual_suffix(&parts, KEY_PARTS) {
        return true;
    }
    let has_context = has_exact(&parts, CONTEXT_PARTS);
    has_context && (has_token || has_key)
}

fn tokenize_key_parts(key: &str) -> Vec<String> {
    let mut parts = Vec::new();
    for segment in key.split(|c: char| !c.is_ascii_alphanumeric()) {
        if segment.is_empty() {
            continue;
        }
        parts.extend(split_camel_case_key_parts(segment));
    }
    parts
        .into_iter()
        .map(|part| part.to_ascii_lowercase())
        .collect()
}

fn split_camel_case_key_parts(key: &str) -> Vec<String> {
    if key.is_empty() {
        return Vec::new();
    }
    let chars: Vec<char> = key.chars().collect();
    let mut parts = Vec::new();
    let mut start = 0;
    for i in 1..chars.len() {
        let prev = chars[i - 1];
        let cur = chars[i];
        let next = chars.get(i + 1).copied();
        let boundary = (prev.is_ascii_lowercase() && cur.is_ascii_uppercase())
            || (prev.is_ascii_alphabetic() && cur.is_ascii_digit())
            || (prev.is_ascii_digit() && cur.is_ascii_alphabetic())
            || (prev.is_ascii_uppercase()
                && cur.is_ascii_uppercase()
                && next.map(|n| n.is_ascii_lowercase()).unwrap_or(false));
        if boundary {
            parts.push(chars[start..i].iter().collect());
            start = i;
        }
    }
    parts.push(chars[start..].iter().collect());
    parts
}

fn has_exact(parts: &[String], candidates: &[&str]) -> bool {
    parts
        .iter()
        .any(|part| candidates.iter().any(|candidate| part == candidate))
}

fn has_candidate_or_numbered_variant(parts: &[String], candidates: &[&str]) -> bool {
    parts.iter().any(|part| {
        candidates.iter().any(|candidate| {
            if part == candidate {
                return true;
            }
            let Some(suffix) = part.strip_prefix(candidate) else {
                return false;
            };
            !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_digit())
        })
    })
}

fn has_contextual_suffix(parts: &[String], candidates: &[&str]) -> bool {
    parts.iter().any(|part| {
        candidates.iter().any(|candidate| {
            let Some(prefix) = part.strip_suffix(candidate) else {
                return false;
            };
            !prefix.is_empty() && CONTEXT_PARTS.contains(&prefix)
        })
    })
}

fn truncate_tool_output(output: &str) -> String {
    if output.len() <= MAX_TOOL_OUTPUT_SIZE {
        return output.to_string();
    }
    let half = MAX_TOOL_OUTPUT_SIZE / 2;
    let head_end = floor_char_boundary(output, half);
    let tail_start = floor_char_boundary(output, output.len() - half);
    format!(
        "{}\n\n... [truncated {} bytes] ...\n\n{}",
        &output[..head_end],
        output.len() - MAX_TOOL_OUTPUT_SIZE,
        &output[tail_start..]
    )
}

fn floor_char_boundary(s: &str, mut idx: usize) -> usize {
    idx = idx.min(s.len());
    while idx > 0 && !s.is_char_boundary(idx) {
        idx -= 1;
    }
    idx
}

const SENSITIVE_EXACT: &[&str] = &[
    "authorization",
    "proxy-authorization",
    "cookie",
    "set-cookie",
    "x-api-key",
    "api-key",
    "api_key",
    "access_token",
    "refresh_token",
    "session_token",
    "id_token",
    "token",
    "password",
    "passwd",
    "secret",
    "client_secret",
    "private_key",
    "apikey",
    "apisecret",
];

const SENSITIVE_PARTS: &[&str] = &[
    "password",
    "passwd",
    "secret",
    "credential",
    "authorization",
    "cookie",
    "apikey",
    "apisecret",
];
const TOKEN_PARTS: &[&str] = &["token", "jwt"];
const KEY_PARTS: &[&str] = &["key"];
const CONTEXT_PARTS: &[&str] = &[
    "auth",
    "oauth",
    "authorization",
    "api",
    "access",
    "refresh",
    "session",
    "bearer",
    "private",
    "client",
    "id",
    "app",
    "user",
    "application",
    "account",
];
