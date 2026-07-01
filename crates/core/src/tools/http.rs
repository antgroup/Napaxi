//! Mobile HTTP request builtin tool.

use std::fs;
use std::path::Path;
use std::time::Duration;

use crate::net::UrlPolicy;
use crate::storage::FileBridge;
use crate::tool_registry::ToolDescriptor;

pub const HTTP_TOOL_NAME: &str = "http";

pub(crate) const DEFAULT_TIMEOUT_SECS: u64 = 30;
const MAX_TIMEOUT_SECS: u64 = 120;
const MAX_INLINE_BODY_BYTES: usize = 128 * 1024;
const MAX_RESPONSE_BYTES: u64 = 25 * 1024 * 1024;

pub fn descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: HTTP_TOOL_NAME.to_string(),
        description: "Make HTTP requests to external APIs. Supports GET, POST, PUT, DELETE, and PATCH. Use save_to to download response bytes to /workspace or Linux sandbox paths.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "method": {
                    "type": "string",
                    "enum": ["GET", "POST", "PUT", "DELETE", "PATCH"],
                    "description": "HTTP method. Defaults to GET."
                },
                "url": {
                    "type": "string",
                    "description": "External HTTP or HTTPS URL to request."
                },
                "headers": {
                    "type": "array",
                    "description": "Optional headers as a list of {name, value} objects.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": { "type": "string" },
                            "value": { "type": "string" }
                        },
                        "required": ["name", "value"],
                        "additionalProperties": false
                    }
                },
                "body": {
                    "description": "Request body for POST, PUT, or PATCH. Objects and arrays are sent as JSON."
                },
                "timeout_secs": {
                    "type": "integer",
                    "description": "Request timeout in seconds. Defaults to 30, maximum 120."
                },
                "save_to": {
                    "type": "string",
                    "description": "Optional sandbox path for raw response bytes, such as /workspace/downloads/file.pdf or /tmp/file.bin."
                }
            },
            "required": ["url"]
        }),
        effect: crate::tool_registry::ToolEffect::External,
    }
}

pub async fn execute(
    files_dir: &str,
    workspace_files_dir: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    let method = params
        .get("method")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("GET")
        .to_ascii_uppercase();
    if !matches!(method.as_str(), "GET" | "POST" | "PUT" | "DELETE" | "PATCH") {
        return Err(format!("unsupported HTTP method: {method}"));
    }

    let url = params
        .get("url")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "http url is required".to_string())?;
    let url = UrlPolicy::strict().validate_url(url)?;
    let resolved_addrs = UrlPolicy::strict().validate_dns_target(&url).await?;
    let host = url
        .host_str()
        .ok_or_else(|| "URL missing host".to_string())?
        .to_string();

    let timeout_secs = params
        .get("timeout_secs")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(DEFAULT_TIMEOUT_SECS)
        .clamp(1, MAX_TIMEOUT_SECS);
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(timeout_secs))
        .user_agent("napaxi-mobile-http/1.0")
        .resolve_to_addrs(&host, &resolved_addrs)
        .build()
        .map_err(|error| format!("failed to build HTTP client: {error}"))?;

    let req_method = reqwest::Method::from_bytes(method.as_bytes())
        .map_err(|error| format!("invalid HTTP method: {error}"))?;
    let mut request = client.request(req_method, url.clone());
    request = apply_headers(request, params.get("headers"))?;
    if matches!(method.as_str(), "POST" | "PUT" | "PATCH")
        && let Some(body) = params.get("body")
    {
        request = apply_body(request, body);
    }

    let response = request
        .send()
        .await
        .map_err(|error| format!("HTTP request failed: {error}"))?;
    let status = response.status();
    let headers = headers_json(response.headers());
    if response
        .content_length()
        .is_some_and(|length| length > MAX_RESPONSE_BYTES)
    {
        return Err(format!(
            "HTTP response is too large: max {} bytes",
            MAX_RESPONSE_BYTES
        ));
    }
    let bytes = response
        .bytes()
        .await
        .map_err(|error| format!("failed to read HTTP response: {error}"))?;
    if bytes.len() as u64 > MAX_RESPONSE_BYTES {
        return Err(format!(
            "HTTP response is too large: max {} bytes",
            MAX_RESPONSE_BYTES
        ));
    }

    if let Some(save_to) = params
        .get("save_to")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let real_path = resolve_save_path(files_dir, workspace_files_dir, save_to)?;
        if let Some(parent) = real_path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        fs::write(&real_path, &bytes).map_err(|error| error.to_string())?;
        return Ok(serde_json::json!({
            "status": status.as_u16(),
            "success": status.is_success(),
            "headers": headers,
            "saved_to": save_to,
            "size_bytes": bytes.len(),
        })
        .to_string());
    }

    let body = if bytes.len() > MAX_INLINE_BODY_BYTES {
        String::from_utf8_lossy(&bytes[..MAX_INLINE_BODY_BYTES]).to_string()
    } else {
        String::from_utf8_lossy(&bytes).to_string()
    };
    Ok(serde_json::json!({
        "status": status.as_u16(),
        "success": status.is_success(),
        "headers": headers,
        "body": body,
        "truncated": bytes.len() > MAX_INLINE_BODY_BYTES,
        "size_bytes": bytes.len(),
    })
    .to_string())
}

pub(crate) fn requires_explicit_approval(params: &serde_json::Value) -> bool {
    let method = params
        .get("method")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("GET")
        .to_ascii_uppercase();
    matches!(method.as_str(), "POST" | "PUT" | "PATCH" | "DELETE")
}

pub(crate) async fn get_external_url_bytes(
    url: &str,
    timeout_secs: u64,
    max_bytes: u64,
) -> Result<(reqwest::StatusCode, reqwest::header::HeaderMap, Vec<u8>), String> {
    let url = UrlPolicy::strict().validate_url(url)?;
    let resolved_addrs = UrlPolicy::strict().validate_dns_target(&url).await?;
    let host = url
        .host_str()
        .ok_or_else(|| "URL missing host".to_string())?
        .to_string();
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(timeout_secs.clamp(1, MAX_TIMEOUT_SECS)))
        .user_agent("napaxi-mobile-web-fetch/1.0")
        .resolve_to_addrs(&host, &resolved_addrs)
        .build()
        .map_err(|error| format!("failed to build HTTP client: {error}"))?;
    let response = client
        .get(url)
        .header(
            reqwest::header::ACCEPT,
            "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5",
        )
        .send()
        .await
        .map_err(|error| format!("HTTP request failed: {error}"))?;
    let status = response.status();
    let headers = response.headers().clone();
    if response
        .content_length()
        .is_some_and(|length| length > max_bytes)
    {
        return Err(format!("HTTP response is too large: max {max_bytes} bytes"));
    }
    let bytes = response
        .bytes()
        .await
        .map_err(|error| format!("failed to read HTTP response: {error}"))?;
    if bytes.len() as u64 > max_bytes {
        return Err(format!("HTTP response is too large: max {max_bytes} bytes"));
    }
    Ok((status, headers, bytes.to_vec()))
}

pub(crate) fn headers_json(headers: &reqwest::header::HeaderMap) -> serde_json::Value {
    let mut object = serde_json::Map::new();
    for (name, value) in headers {
        if let Ok(value) = value.to_str() {
            object.insert(
                name.as_str().to_string(),
                serde_json::Value::String(value.to_string()),
            );
        }
    }
    serde_json::Value::Object(object)
}

fn apply_headers(
    mut request: reqwest::RequestBuilder,
    headers: Option<&serde_json::Value>,
) -> Result<reqwest::RequestBuilder, String> {
    let Some(headers) = headers else {
        return Ok(request);
    };
    let Some(items) = headers.as_array() else {
        return Err("headers must be an array".to_string());
    };
    for item in items {
        let name = item
            .get("name")
            .and_then(serde_json::Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| "header name is required".to_string())?;
        let value = item
            .get("value")
            .and_then(serde_json::Value::as_str)
            .ok_or_else(|| "header value is required".to_string())?;
        if matches!(
            name.to_ascii_lowercase().as_str(),
            "host" | "content-length" | "connection" | "transfer-encoding"
        ) {
            return Err(format!("header is not allowed: {name}"));
        }
        request = request.header(name, value);
    }
    Ok(request)
}

fn apply_body(
    request: reqwest::RequestBuilder,
    body: &serde_json::Value,
) -> reqwest::RequestBuilder {
    match body {
        serde_json::Value::String(value) => request.body(value.clone()),
        _ => request.json(body),
    }
}

fn resolve_save_path(
    files_dir: &str,
    workspace_files_dir: &str,
    save_to: &str,
) -> Result<std::path::PathBuf, String> {
    let normalized = save_to.trim();
    if normalized == "/skills" || normalized.starts_with("/skills/") {
        return Err("save_to cannot write under /skills".to_string());
    }
    let bridge = FileBridge::new_with_workspace_files_dir(files_dir, workspace_files_dir);
    let real = bridge.sandbox_to_real(normalized).ok_or_else(|| {
        "save_to must be a sandbox path such as /workspace/file or /tmp/file".to_string()
    })?;
    let path = Path::new(&real);
    if path.components().any(|component| {
        matches!(
            component,
            std::path::Component::ParentDir | std::path::Component::CurDir
        )
    }) {
        return Err("save_to contains invalid path segments".to_string());
    }
    Ok(path.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn descriptor_exposes_http_tool() {
        let descriptor = descriptor();
        assert_eq!(descriptor.name, "http");
        assert!(
            descriptor.parameters["required"]
                .as_array()
                .unwrap()
                .iter()
                .any(|value| value.as_str() == Some("url"))
        );
    }

    #[test]
    fn url_validation_blocks_local_targets() {
        assert!(
            UrlPolicy::strict()
                .validate_url("https://example.com/data.json")
                .is_ok()
        );
        assert!(
            UrlPolicy::strict()
                .validate_url("file:///etc/passwd")
                .is_err()
        );
        assert!(
            UrlPolicy::strict()
                .validate_url("http://127.0.0.1/")
                .is_err()
        );
        assert!(
            UrlPolicy::strict()
                .validate_url("https://localhost/")
                .is_err()
        );
        assert!(
            UrlPolicy::strict()
                .validate_url("https://metadata.google.internal/")
                .is_err()
        );
    }

    #[test]
    fn mutating_methods_require_approval() {
        assert!(!requires_explicit_approval(&serde_json::json!({
            "url": "https://example.com"
        })));
        assert!(!requires_explicit_approval(&serde_json::json!({
            "method": "GET",
            "url": "https://example.com"
        })));
        assert!(requires_explicit_approval(&serde_json::json!({
            "method": "POST",
            "url": "https://example.com"
        })));
        assert!(requires_explicit_approval(&serde_json::json!({
            "method": "DELETE",
            "url": "https://example.com"
        })));
    }

    #[test]
    fn save_path_uses_scoped_workspace_mapping() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().join("files");
        let scoped_dir = dir.path().join("scope");
        let path = resolve_save_path(
            files_dir.to_str().unwrap(),
            scoped_dir.to_str().unwrap(),
            "/workspace/downloads/a.txt",
        )
        .unwrap();
        assert!(path.ends_with("scope/linux-env/workspace/downloads/a.txt"));
        assert!(
            resolve_save_path(
                files_dir.to_str().unwrap(),
                scoped_dir.to_str().unwrap(),
                "/skills/tool.txt",
            )
            .is_err()
        );
    }
}
