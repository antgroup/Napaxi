use serde::Deserialize;
use serde_json::json;

#[cfg(test)]
use super::config;
#[cfg(any(target_os = "android", target_os = "ios"))]
use super::config::{self, CodexConfigError, PreparedCodexConfig};
#[cfg(not(any(target_os = "android", target_os = "ios")))]
const CODEX_UNSUPPORTED: &str = "napaxi.agent_engine.codex is unsupported on this platform";
#[cfg(any(target_os = "android", target_os = "ios"))]
use super::state::{invalidate_sessions_for_config, set_current_config_fingerprint};

#[cfg_attr(not(any(target_os = "android", target_os = "ios")), allow(dead_code))]
#[derive(Debug, Deserialize)]
struct ConfigureCodexRequest {
    #[serde(default)]
    files_dir: String,
    #[serde(default)]
    config_toml: String,
    #[serde(default)]
    auth_json: String,
    #[serde(default)]
    llm_config_json: String,
    #[serde(default)]
    clear: bool,
}

pub(crate) fn configure_codex_agent_engine_json(_handle: i64, request_json: &str) -> String {
    if super::history::is_history_request(request_json) {
        return super::history::handle_request_json(_handle, request_json);
    }
    let mut request = match serde_json::from_str::<ConfigureCodexRequest>(request_json) {
        Ok(request) => request,
        Err(error) => {
            return config_result_json(
                false,
                false,
                false,
                Some("model_check_failed"),
                Some(format!("Invalid Codex config request JSON: {error}")),
                "",
                false,
            );
        }
    };
    if let Some(files_dir) = crate::runtime::files_dir_from_handle(_handle) {
        request.files_dir = files_dir;
    }
    if request.files_dir.trim().is_empty() {
        return json!({
            "success": false,
            "providerAvailable": false,
            "modelUsable": false,
            "errorCode": "unsupported_platform",
            "error": "invalid engine handle or missing files_dir",
            "model": model_from_config_json(&request.llm_config_json),
            "configChanged": false,
        })
        .to_string();
    }
    configure_codex_agent_engine(request)
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn configure_codex_agent_engine(request: ConfigureCodexRequest) -> String {
    let model = model_from_config_json(&request.llm_config_json);
    json!({
        "success": false,
        "providerAvailable": false,
        "modelUsable": false,
        "errorCode": "unsupported_platform",
        "error": CODEX_UNSUPPORTED,
        "model": model,
        "configChanged": false,
    })
    .to_string()
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn configure_codex_agent_engine(request: ConfigureCodexRequest) -> String {
    if request.clear {
        return match config::clear(&request.files_dir) {
            Ok(result) => {
                set_current_config_fingerprint(&request.files_dir, None);
                invalidate_sessions_for_config(&request.files_dir, None);
                config_result_json(true, true, false, None, None, "", result.changed)
            }
            Err(error) => config_error_json(error, true),
        };
    }
    if !request.llm_config_json.trim().is_empty() {
        let prepared = match config::prepare_from_json(&request.llm_config_json) {
            Ok(prepared) => prepared,
            Err(error) => {
                if let Err(clear_error) = clear_config_and_sessions(&request.files_dir) {
                    return config_error_json(clear_error, true);
                }
                return config_error_json(error, true);
            }
        };
        return match sync_prepared_config(&request.files_dir, &prepared) {
            Ok(changed) => {
                config_result_json(true, true, true, None, None, &prepared.model, changed)
            }
            Err(error) => config_error_json(error, true),
        };
    }

    configure_legacy_raw(&request)
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn configure_legacy_raw(request: &ConfigureCodexRequest) -> String {
    let codex_dir = config::config_dir(&request.files_dir);
    let before_config = std::fs::read_to_string(codex_dir.join("config.toml")).ok();
    let before_auth = std::fs::read_to_string(codex_dir.join("auth.json")).ok();
    let result = (|| -> anyhow::Result<()> {
        std::fs::create_dir_all(&codex_dir)?;
        if !request.config_toml.is_empty() {
            std::fs::write(codex_dir.join("config.toml"), &request.config_toml)?;
        }
        if !request.auth_json.is_empty() {
            std::fs::write(codex_dir.join("auth.json"), &request.auth_json)?;
        }
        Ok(())
    })();
    match result {
        Ok(()) => {
            let changed = (!request.config_toml.is_empty()
                && before_config.as_deref() != Some(request.config_toml.as_str()))
                || (!request.auth_json.is_empty()
                    && before_auth.as_deref() != Some(request.auth_json.as_str()));
            set_current_config_fingerprint(&request.files_dir, None);
            if changed {
                invalidate_sessions_for_config(&request.files_dir, None);
            }
            config_result_json(true, true, true, None, None, "", changed)
        }
        Err(error) => config_result_json(
            false,
            true,
            false,
            Some("config_write_failed"),
            Some(error.to_string()),
            "",
            false,
        ),
    }
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(super) fn sync_prepared_config(
    files_dir: &str,
    prepared: &PreparedCodexConfig,
) -> Result<bool, CodexConfigError> {
    let result = config::write_prepared(files_dir, prepared)?;
    set_current_config_fingerprint(files_dir, Some(&prepared.fingerprint));
    invalidate_sessions_for_config(files_dir, Some(&prepared.fingerprint));
    Ok(result.changed)
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub(super) fn clear_config_and_sessions(files_dir: &str) -> Result<bool, CodexConfigError> {
    let result = config::clear(files_dir)?;
    set_current_config_fingerprint(files_dir, None);
    invalidate_sessions_for_config(files_dir, None);
    Ok(result.changed)
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn config_error_json(error: CodexConfigError, provider_available: bool) -> String {
    config_result_json(
        false,
        provider_available,
        false,
        Some(error.code),
        Some(error.message),
        &error.model,
        false,
    )
}

fn config_result_json(
    success: bool,
    provider_available: bool,
    model_usable: bool,
    error_code: Option<&str>,
    error: Option<String>,
    model: &str,
    config_changed: bool,
) -> String {
    json!({
        "success": success,
        "providerAvailable": provider_available,
        "modelUsable": model_usable,
        "errorCode": error_code,
        "error": error,
        "model": model,
        "configChanged": config_changed,
    })
    .to_string()
}

fn model_from_config_json(raw: &str) -> String {
    serde_json::from_str::<serde_json::Value>(raw)
        .ok()
        .and_then(|value| {
            value
                .get("model")
                .and_then(|model| model.as_str())
                .map(str::to_string)
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_config_dir_targets_linux_env_rootfs_home() {
        assert_eq!(
            config::config_dir("app_files"),
            std::path::Path::new("app_files")
                .join("linux-env")
                .join("rootfs")
                .join("root")
                .join(".codex"),
        );
    }
}
