use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::Serialize;
use serde_json::json;

use crate::types::PlatformLlmConfig;

const CODEX_PROVIDER_NAME: &str = "napaxi_main";
const CODEX_WORKSPACE: &str = "/workspace";
const CODEX_WIRE_API: &str = "responses";
const DEFAULT_OPENAI_BASE_URL: &str = "https://api.openai.com/v1";

#[derive(Debug, Clone)]
pub(crate) struct PreparedCodexConfig {
    pub(crate) model: String,
    pub(crate) config_toml: String,
    pub(crate) auth_json: String,
    pub(crate) fingerprint: String,
}

#[derive(Debug, Clone)]
pub(crate) struct CodexConfigError {
    pub(crate) code: &'static str,
    pub(crate) message: String,
    pub(crate) model: String,
}

impl std::fmt::Display for CodexConfigError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for CodexConfigError {}

#[derive(Debug, Clone, Copy)]
pub(crate) struct CodexConfigWriteResult {
    pub(crate) changed: bool,
}

pub(crate) fn prepare_from_json(raw: &str) -> Result<PreparedCodexConfig, CodexConfigError> {
    let config =
        serde_json::from_str::<PlatformLlmConfig>(raw).map_err(|error| CodexConfigError {
            code: "model_check_failed",
            message: format!("Invalid main model configuration: {error}"),
            model: String::new(),
        })?;
    prepare(&config)
}

pub(crate) fn prepare(config: &PlatformLlmConfig) -> Result<PreparedCodexConfig, CodexConfigError> {
    let model = config.model.trim();
    if model.is_empty() {
        return Err(config_error(
            "missing_main_model",
            "Choose a main model before running Codex",
            model,
        ));
    }
    let api_key = config.api_key.trim();
    if api_key.is_empty() {
        return Err(config_error(
            "missing_api_key",
            "Add an API key to the selected main model before running Codex",
            model,
        ));
    }

    let provider = normalize_provider(&config.provider);
    let base_url = match provider.as_str() {
        "openai" => config
            .base_url
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or(DEFAULT_OPENAI_BASE_URL),
        "openai_compatible" => {
            let Some(base_url) = config
                .base_url
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
            else {
                return Err(config_error(
                    "missing_base_url",
                    "Add a Base URL to the selected OpenAI-compatible main model before running Codex",
                    model,
                ));
            };
            base_url
        }
        _ => {
            return Err(config_error(
                "unsupported_provider",
                format!(
                    "The selected main model provider '{}' is not compatible with Codex",
                    config.provider.trim()
                ),
                model,
            ));
        }
    };
    if !valid_http_base_url(base_url) {
        return Err(config_error(
            "missing_base_url",
            "The selected main model Base URL must be a valid HTTP or HTTPS URL",
            model,
        ));
    }

    let provider_name = toml_string(CODEX_PROVIDER_NAME);
    let model_value = toml_string(model);
    let base_url_value = toml_string(base_url);
    let wire_api_value = toml_string(CODEX_WIRE_API);
    let workspace_value = toml_string(CODEX_WORKSPACE);
    let config_toml = format!(
        "model_provider = {provider_name}\n\
         model = {model_value}\n\
         model_reasoning_effort = \"high\"\n\
         disable_response_storage = true\n\n\
         [model_providers.{CODEX_PROVIDER_NAME}]\n\
         name = {provider_name}\n\
         base_url = {base_url_value}\n\
         wire_api = {wire_api_value}\n\
         requires_openai_auth = true\n\n\
         [projects.{workspace_value}]\n\
         trust_level = \"trusted\"\n"
    );
    let auth_json =
        serde_json::to_string(&json!({"OPENAI_API_KEY": api_key})).map_err(|error| {
            CodexConfigError {
                code: "model_check_failed",
                message: format!("Failed to encode Codex authentication: {error}"),
                model: model.to_string(),
            }
        })?;
    let api_key_hash = crate::crypto::sha256_base64_no_pad(api_key.as_bytes());
    let fingerprint = config_fingerprint(&FingerprintInput {
        provider: &provider,
        base_url,
        model,
        wire_api: CODEX_WIRE_API,
        api_key_hash: &api_key_hash,
    });

    Ok(PreparedCodexConfig {
        model: model.to_string(),
        config_toml,
        auth_json,
        fingerprint,
    })
}

pub(crate) fn config_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir)
        .join("linux-env")
        .join("rootfs")
        .join("root")
        .join(".codex")
}

pub(crate) fn write_prepared(
    files_dir: &str,
    prepared: &PreparedCodexConfig,
) -> Result<CodexConfigWriteResult, CodexConfigError> {
    let codex_dir = config_dir(files_dir);
    fs::create_dir_all(&codex_dir).map_err(|error| write_error(&prepared.model, error))?;
    let config_path = codex_dir.join("config.toml");
    let auth_path = codex_dir.join("auth.json");
    let changed = file_differs(&config_path, &prepared.config_toml)
        || file_differs(&auth_path, &prepared.auth_json);
    if !changed {
        restrict_credentials_permissions(&auth_path, &prepared.model)?;
        return Ok(CodexConfigWriteResult { changed: false });
    }

    let config_temp = write_temp_file(&config_path, &prepared.config_toml, &prepared.model)?;
    let auth_temp = match write_temp_file(&auth_path, &prepared.auth_json, &prepared.model) {
        Ok(path) => path,
        Err(error) => {
            let _ = fs::remove_file(&config_temp);
            return Err(error);
        }
    };
    if let Err(error) = fs::rename(&auth_temp, &auth_path) {
        let _ = fs::remove_file(&config_temp);
        let _ = fs::remove_file(&auth_temp);
        return Err(write_error(&prepared.model, error));
    }
    if let Err(error) = fs::rename(&config_temp, &config_path) {
        let _ = fs::remove_file(&config_temp);
        return Err(write_error(&prepared.model, error));
    }
    restrict_credentials_permissions(&auth_path, &prepared.model)?;
    Ok(CodexConfigWriteResult { changed: true })
}

pub(crate) fn clear(files_dir: &str) -> Result<CodexConfigWriteResult, CodexConfigError> {
    let codex_dir = config_dir(files_dir);
    let mut changed = false;
    for name in ["config.toml", "auth.json"] {
        let path = codex_dir.join(name);
        match fs::remove_file(path) {
            Ok(()) => changed = true,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(write_error("", error)),
        }
    }
    Ok(CodexConfigWriteResult { changed })
}

fn normalize_provider(provider: &str) -> String {
    match provider.trim().to_ascii_lowercase().as_str() {
        "openai" | "open_ai" => "openai".to_string(),
        "openai_compatible" | "openai-compatible" | "compatible" | "glm" | "zai" | "zhipu"
        | "bigmodel" | "nearai" | "deepseek" | "qwen" | "moonshot" => {
            "openai_compatible".to_string()
        }
        other => other.to_string(),
    }
}

fn valid_http_base_url(value: &str) -> bool {
    reqwest::Url::parse(value)
        .ok()
        .is_some_and(|url| matches!(url.scheme(), "http" | "https") && url.host().is_some())
}

fn toml_string(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string())
}

#[derive(Serialize)]
struct FingerprintInput<'a> {
    provider: &'a str,
    base_url: &'a str,
    model: &'a str,
    wire_api: &'a str,
    api_key_hash: &'a str,
}

fn config_fingerprint(input: &FingerprintInput<'_>) -> String {
    let raw = serde_json::to_vec(input).unwrap_or_default();
    crate::crypto::sha256_base64_no_pad(&raw)
}

fn file_differs(path: &Path, expected: &str) -> bool {
    fs::read_to_string(path).map_or(true, |current| current != expected)
}

fn write_temp_file(target: &Path, content: &str, model: &str) -> Result<PathBuf, CodexConfigError> {
    let file_name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("codex-config");
    let temp = target.with_file_name(format!(".{file_name}.{}.tmp", uuid::Uuid::new_v4()));
    let mut options = OpenOptions::new();
    options.create_new(true).write(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&temp)
        .map_err(|error| write_error(model, error))?;
    if let Err(error) = file
        .write_all(content.as_bytes())
        .and_then(|()| file.sync_all())
    {
        let _ = fs::remove_file(&temp);
        return Err(write_error(model, error));
    }
    Ok(temp)
}

fn restrict_credentials_permissions(path: &Path, model: &str) -> Result<(), CodexConfigError> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))
            .map_err(|error| write_error(model, error))?;
    }
    #[cfg(not(unix))]
    let _ = (path, model);
    Ok(())
}

fn config_error(code: &'static str, message: impl Into<String>, model: &str) -> CodexConfigError {
    CodexConfigError {
        code,
        message: message.into(),
        model: model.to_string(),
    }
}

fn write_error(model: &str, error: impl std::fmt::Display) -> CodexConfigError {
    CodexConfigError {
        code: "config_write_failed",
        message: format!("Failed to update the Codex sandbox configuration: {error}"),
        model: model.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(
        provider: &str,
        base_url: Option<&str>,
        model: &str,
        api_key: &str,
    ) -> PlatformLlmConfig {
        PlatformLlmConfig {
            provider: provider.to_string(),
            base_url: base_url.map(str::to_string),
            model: model.to_string(),
            api_key: api_key.to_string(),
            ..PlatformLlmConfig::default()
        }
    }

    #[test]
    fn openai_uses_responses_and_default_url() {
        let prepared = prepare(&config("openai", None, "gpt-5", "secret")).unwrap();
        assert!(prepared.config_toml.contains("wire_api = \"responses\""));
        assert!(prepared.config_toml.contains(DEFAULT_OPENAI_BASE_URL));
        assert_eq!(prepared.model, "gpt-5");
    }

    #[test]
    fn compatible_provider_uses_responses_and_requires_url() {
        let prepared = prepare(&config(
            "openai-compatible",
            Some("https://models.example/v1"),
            "custom-model",
            "secret",
        ))
        .unwrap();
        assert!(prepared.config_toml.contains("wire_api = \"responses\""));

        let error = prepare(&config("openai_compatible", None, "model", "secret")).unwrap_err();
        assert_eq!(error.code, "missing_base_url");
    }

    #[test]
    fn rejects_missing_and_incompatible_main_model_fields() {
        assert_eq!(
            prepare(&config("openai", None, "", "secret"))
                .unwrap_err()
                .code,
            "missing_main_model"
        );
        assert_eq!(
            prepare(&config("openai", None, "gpt-5", ""))
                .unwrap_err()
                .code,
            "missing_api_key"
        );
        let error = prepare(&config("anthropic", None, "claude", "secret")).unwrap_err();
        assert_eq!(error.code, "unsupported_provider");
        assert_eq!(error.model, "claude");
        assert_eq!(
            prepare_from_json(
                &serde_json::to_string(&config("openai", None, "gpt-5", "secret")).unwrap()
            )
            .unwrap()
            .model,
            "gpt-5"
        );
    }

    #[test]
    fn serialization_escapes_user_values_and_fingerprint_tracks_credentials() {
        let first = prepare(&config(
            "openai_compatible",
            Some("https://models.example/v1"),
            "model\"with-quote",
            "secret-one",
        ))
        .unwrap();
        let second = prepare(&config(
            "openai_compatible",
            Some("https://models.example/v1"),
            "model\"with-quote",
            "secret-two",
        ))
        .unwrap();
        assert!(first.config_toml.contains("model\\\"with-quote"));
        assert_ne!(first.fingerprint, second.fingerprint);
        assert!(!first.fingerprint.contains("secret"));
    }

    #[test]
    fn writes_idempotently_and_clears_both_files() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy();
        let prepared = prepare(&config("openai", None, "gpt-5", "secret")).unwrap();
        assert!(write_prepared(&files_dir, &prepared).unwrap().changed);
        assert!(!write_prepared(&files_dir, &prepared).unwrap().changed);
        let dir = config_dir(&files_dir);
        assert_eq!(
            fs::read_to_string(dir.join("config.toml")).unwrap(),
            prepared.config_toml
        );
        assert_eq!(
            fs::read_to_string(dir.join("auth.json")).unwrap(),
            prepared.auth_json
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(dir.join("auth.json"), fs::Permissions::from_mode(0o644)).unwrap();
            assert!(!write_prepared(&files_dir, &prepared).unwrap().changed);
            assert_eq!(
                fs::metadata(dir.join("auth.json"))
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
        assert!(clear(&files_dir).unwrap().changed);
        assert!(!dir.join("config.toml").exists());
        assert!(!dir.join("auth.json").exists());
    }
}
