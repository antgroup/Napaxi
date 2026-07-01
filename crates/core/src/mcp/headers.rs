use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use super::{McpServer, McpTransport};

fn dynamic_headers_store() -> &'static Mutex<HashMap<String, HashMap<String, String>>> {
    static STORE: OnceLock<Mutex<HashMap<String, HashMap<String, String>>>> = OnceLock::new();
    STORE.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn update_dynamic_headers(files_dir: &str, headers: HashMap<String, String>) -> bool {
    let Ok(mut store) = dynamic_headers_store().lock() else {
        return false;
    };
    if headers.is_empty() {
        store.remove(files_dir);
    } else {
        store.insert(files_dir.to_string(), headers);
    }
    true
}

fn dynamic_headers(files_dir: &str) -> HashMap<String, String> {
    dynamic_headers_store()
        .lock()
        .ok()
        .and_then(|store| store.get(files_dir).cloned())
        .unwrap_or_default()
}

pub(super) fn effective_headers(files_dir: &str, server: &McpServer) -> HashMap<String, String> {
    // Merge static, dynamic, and OAuth headers case-insensitively. HTTP header
    // names are case-insensitive, but `HashMap<String, String>` is not, so two
    // entries differing only in case (e.g. `Authorization` from `server.headers`
    // and `authorization` from dynamic headers) would otherwise both be emitted
    // by reqwest, producing a duplicate `Authorization` header and a 401.
    let mut headers = merge_headers_ci(&server.headers, &dynamic_headers(files_dir));
    let has_custom_auth = headers
        .keys()
        .any(|key| key.eq_ignore_ascii_case("authorization"));
    if !has_custom_auth && let Some(tokens) = &server.oauth_tokens {
        let token_type = if tokens.token_type.trim().is_empty() {
            "Bearer"
        } else {
            tokens.token_type.trim()
        };
        headers.insert(
            "Authorization".to_string(),
            format!("{token_type} {}", tokens.access_token),
        );
    }
    headers
}

/// Merges `overrides` onto `base`, treating header names case-insensitively so a
/// later entry replaces any earlier one with the same name regardless of case.
/// The most recently seen spelling of each name is preserved.
fn merge_headers_ci(
    base: &HashMap<String, String>,
    overrides: &HashMap<String, String>,
) -> HashMap<String, String> {
    let mut by_lower: HashMap<String, (String, String)> = HashMap::new();
    for (name, value) in base.iter().chain(overrides.iter()) {
        by_lower.insert(name.to_ascii_lowercase(), (name.clone(), value.clone()));
    }
    by_lower.into_values().collect()
}

pub(super) fn transport_kind(transport: &McpTransport) -> &'static str {
    match transport {
        McpTransport::Http => "http",
        McpTransport::Sse { .. } => "sse",
        McpTransport::Stdio { .. } => "stdio",
        McpTransport::Unix { .. } => "unix",
    }
}

pub(super) fn is_http_like_transport(transport: &McpTransport) -> bool {
    matches!(transport, McpTransport::Http | McpTransport::Sse { .. })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_dedupes_header_names_case_insensitively() {
        let mut base = HashMap::new();
        base.insert("Authorization".to_string(), "Bearer old".to_string());
        base.insert("X-Trace".to_string(), "1".to_string());
        let mut overrides = HashMap::new();
        overrides.insert("authorization".to_string(), "Bearer new".to_string());

        let merged = merge_headers_ci(&base, &overrides);

        let auth: Vec<_> = merged
            .keys()
            .filter(|k| k.eq_ignore_ascii_case("authorization"))
            .collect();
        assert_eq!(
            auth.len(),
            1,
            "must not emit duplicate Authorization headers"
        );
        let value = merged
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("authorization"))
            .map(|(_, v)| v.as_str());
        assert_eq!(value, Some("Bearer new"), "override must win");
        assert_eq!(merged.get("X-Trace").map(String::as_str), Some("1"));
    }
}
