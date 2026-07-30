//! Codex app-server process environment helpers.
//!
//! These are intentionally narrow and engine-owned. They let hosts pass
//! network routing settings into the sandboxed Codex CLI without changing the
//! Rust-native Napaxi engine/provider path and without logging credentials.

use serde_json::Value;

const MAX_ENV_VALUE_LEN: usize = 2048;
const NETWORK_ENV_KEYS: &[(&str, &str)] = &[
    ("http_proxy", "HTTP_PROXY"),
    ("https_proxy", "HTTPS_PROXY"),
    ("all_proxy", "ALL_PROXY"),
    ("no_proxy", "NO_PROXY"),
];

pub(super) fn codex_process_env(engine_config: &Value) -> Vec<(String, String)> {
    let mut env = Vec::new();
    for (lower, upper) in NETWORK_ENV_KEYS {
        let Some(value) = configured_env_value(engine_config, lower, upper) else {
            continue;
        };
        if !is_safe_env_value(&value) {
            continue;
        }
        if *lower != "no_proxy" && !is_supported_proxy_url(&value) {
            continue;
        }
        env.push((upper.to_string(), value.clone()));
        env.push((lower.to_string(), value));
    }
    env
}

pub(super) fn runtime_fingerprint(config_fingerprint: &str, engine_config: &Value) -> String {
    let env = codex_process_env(engine_config);
    if env.is_empty() {
        return config_fingerprint.to_string();
    }
    let raw = serde_json::to_vec(&(config_fingerprint, env)).unwrap_or_default();
    crate::crypto::sha256_base64_no_pad(&raw)
}

pub(super) fn shell_export_prefix(env: &[(String, String)]) -> String {
    if env.is_empty() {
        return String::new();
    }
    env.iter()
        .map(|(name, value)| format!("export {name}={};", shell_quote(value)))
        .collect::<Vec<_>>()
        .join(" ")
        + " "
}

fn configured_env_value(engine_config: &Value, lower: &str, upper: &str) -> Option<String> {
    [
        engine_config.get("network_env"),
        engine_config.get("networkEnv"),
    ]
    .into_iter()
    .flatten()
    .chain(std::iter::once(engine_config))
    .find_map(|scope| {
        scope
            .get(upper)
            .or_else(|| scope.get(lower))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
    })
}

fn is_safe_env_value(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_ENV_VALUE_LEN
        && !value.chars().any(|ch| matches!(ch, '\0' | '\n' | '\r'))
}

fn is_supported_proxy_url(value: &str) -> bool {
    reqwest::Url::parse(value).ok().is_some_and(|url| {
        matches!(url.scheme(), "http" | "https" | "socks4" | "socks5") && url.host().is_some()
    })
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn reads_network_env_from_engine_config_without_logging_or_invalid_values() {
        let env = codex_process_env(&json!({
            "network_env": {
                "https_proxy": " http://127.0.0.1:7890 ",
                "no_proxy": "localhost,127.0.0.1",
                "http_proxy": "file:///tmp/not-a-proxy",
                "all_proxy": "http://bad\nvalue"
            }
        }));
        assert!(env.contains(&(
            "HTTPS_PROXY".to_string(),
            "http://127.0.0.1:7890".to_string()
        )));
        assert!(env.contains(&(
            "https_proxy".to_string(),
            "http://127.0.0.1:7890".to_string()
        )));
        assert!(env.contains(&("NO_PROXY".to_string(), "localhost,127.0.0.1".to_string())));
        assert!(!env.iter().any(|(key, _)| key == "HTTP_PROXY"));
        assert!(!env.iter().any(|(key, _)| key == "ALL_PROXY"));
    }

    #[test]
    fn shell_export_prefix_quotes_values() {
        let line = shell_export_prefix(&[("HTTPS_PROXY".to_string(), "http://a'b".to_string())]);
        assert_eq!(line, "export HTTPS_PROXY='http://a'\\''b'; ");
    }

    #[test]
    fn runtime_fingerprint_tracks_network_env_changes() {
        let first =
            runtime_fingerprint("base", &json!({"network_env":{"https_proxy":"http://a:1"}}));
        let second =
            runtime_fingerprint("base", &json!({"network_env":{"https_proxy":"http://b:1"}}));
        assert_ne!(first, second);
        assert_eq!(runtime_fingerprint("base", &json!({})), "base");
    }
}
