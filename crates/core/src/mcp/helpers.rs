//! Shared helpers: header parsing, transport hinting, JSON formatters.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};

use super::types::{McpServer, McpTransport, default_input_schema, default_sse_path};

pub(super) static REQUEST_ID_COUNTER: AtomicU64 = AtomicU64::new(1);

pub(super) fn invalid_handle_json() -> String {
    r#"{"error":"invalid engine handle"}"#.to_string()
}

/// Explicit lifecycle state for an MCP server. Adapters render this directly
/// instead of inferring from `connected`/`error`, which conflated a server
/// that was simply never activated with one whose activation failed.
pub(super) fn server_status(server: &McpServer) -> &'static str {
    if server.active {
        "connected"
    } else if server
        .activation_error
        .as_deref()
        .is_some_and(|error| !error.trim().is_empty())
    {
        "error"
    } else if server.oauth_pending.is_some() {
        "connecting"
    } else {
        // Saved but not yet activated (or explicitly deactivated). Not a failure.
        "configured"
    }
}

pub(super) fn server_json(server: &McpServer) -> serde_json::Value {
    use super::headers::transport_kind;
    use super::tool_descriptor::prefixed_tool_name;

    let tools: Vec<String> = server
        .tools
        .iter()
        .map(|tool| prefixed_tool_name(&server.name, &tool.name))
        .collect();
    serde_json::json!({
        "name": server.name,
        "url": server.url,
        "transport": transport_kind(&server.transport),
        "connected": server.active,
        "status": server_status(server),
        "tools": tools,
        "error": server.activation_error.as_deref().unwrap_or(""),
        "authRequired": server.oauth.is_some() || server.oauth_pending.is_some(),
        "oauthConnected": server.oauth_tokens.is_some(),
        "oauthPending": server.oauth_pending.is_some(),
    })
}

pub(super) fn result_json(name: &str, tools_loaded: &[String], error: &str) -> String {
    serde_json::json!({
        "name": name,
        "tools_loaded": tools_loaded,
        "error": error,
    })
    .to_string()
}

pub(super) fn success_json(success: bool, error: Option<String>) -> String {
    match error {
        Some(error) => serde_json::json!({
            "success": success,
            "error": error,
        }),
        None => serde_json::json!({
            "success": success,
        }),
    }
    .to_string()
}

pub(super) fn oauth_start_json(
    name: &str,
    authorization_url: Option<String>,
    state: Option<String>,
    redirect_uri: Option<String>,
    error: Option<String>,
) -> String {
    serde_json::json!({
        "name": name,
        "authorization_url": authorization_url.unwrap_or_default(),
        "state": state.unwrap_or_default(),
        "redirect_uri": redirect_uri.unwrap_or_default(),
        "error": error.unwrap_or_default(),
    })
    .to_string()
}

pub(super) fn parse_headers(headers_json: &str) -> Result<HashMap<String, String>, String> {
    if headers_json.trim().is_empty() || headers_json.trim() == "{}" {
        return Ok(HashMap::new());
    }
    serde_json::from_str(headers_json).map_err(|e| format!("Invalid headers JSON: {e}"))
}

pub(super) fn extract_transport_hint(headers: &mut HashMap<String, String>) -> Option<String> {
    const TRANSPORT_HINT_HEADER: &str = "__napaxi_transport";
    let key = headers
        .keys()
        .find(|key| key.eq_ignore_ascii_case(TRANSPORT_HINT_HEADER))
        .cloned()?;
    headers.remove(&key).map(|value| value.trim().to_string())
}

pub(super) fn should_auto_detect_sse(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    lower.contains("/sse") || lower.contains("transport=sse")
}

pub(super) fn split_url_for_sse(url: &str) -> (String, String) {
    let scheme_end = url.find("://").map(|index| index + 3).unwrap_or(0);
    let path_start = url[scheme_end..]
        .find('/')
        .map(|index| scheme_end + index)
        .unwrap_or(url.len());
    let base = url[..path_start].trim_end_matches('/').to_string();
    let sse_path = if path_start < url.len() {
        url[path_start..].to_string()
    } else {
        default_sse_path()
    };
    (base, sse_path)
}

pub(super) fn resolve_add_transport(
    url: &str,
    hint: Option<&str>,
) -> Result<(String, McpTransport), String> {
    match hint.unwrap_or("").trim().to_ascii_lowercase().as_str() {
        "" => {
            if should_auto_detect_sse(url) {
                let (base, sse_path) = split_url_for_sse(url);
                Ok((base, McpTransport::Sse { sse_path }))
            } else {
                Ok((url.to_string(), McpTransport::Http))
            }
        }
        "http" | "streamable_http" | "streamable-http" => Ok((url.to_string(), McpTransport::Http)),
        "sse" => {
            let (base, sse_path) = split_url_for_sse(url);
            Ok((base, McpTransport::Sse { sse_path }))
        }
        other => Err(format!("Unsupported MCP transport: {other}")),
    }
}

pub(super) fn sanitize_error_body(body: &str) -> String {
    let mut sanitized = body.replace('\n', " ");
    if sanitized.len() > 500 {
        sanitized.truncate(floor_char_boundary(&sanitized, 500));
        sanitized.push_str("...");
    }
    sanitized
}

pub(super) fn floor_char_boundary(text: &str, mut index: usize) -> usize {
    index = index.min(text.len());
    while index > 0 && !text.is_char_boundary(index) {
        index -= 1;
    }
    index
}

pub(super) fn safe_truncate(text: &str, max_bytes: usize) -> String {
    if text.len() <= max_bytes {
        return text.to_string();
    }
    let end = floor_char_boundary(text, max_bytes);
    format!("{}...", &text[..end])
}

/// Whether an MCP `initialize` response advertises the `tools` capability.
///
/// Per the MCP spec, prompt-only / resource-only servers omit the `tools`
/// entry in `InitializeResult.capabilities`. Calling `tools/list` against
/// such a server yields a `-32601 Method not found` error that would
/// otherwise abort activation. Returns `true` as a legacy fallback when the
/// response carries no usable capability map (older servers that predate
/// capability advertisement still expect `tools/list`).
pub(super) fn initialize_advertises_tools(response: &McpResponse) -> bool {
    let Some(result) = response.result.as_ref() else {
        return true;
    };
    let Some(capabilities) = result.get("capabilities") else {
        return true;
    };
    match capabilities.as_object() {
        Some(map) if map.is_empty() => true,
        Some(map) => map.contains_key("tools"),
        None => true,
    }
}

pub(super) fn strip_top_level_nulls(value: serde_json::Value) -> serde_json::Value {
    match value {
        serde_json::Value::Object(map) => serde_json::Value::Object(
            map.into_iter()
                .filter(|(_, value)| !value.is_null())
                .collect(),
        ),
        other => other,
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct McpRequest {
    pub(super) jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) id: Option<u64>,
    pub(super) method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) params: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct McpResponse {
    pub(super) jsonrpc: String,
    pub(super) id: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) error: Option<McpError>,
}

pub(super) struct McpHttpResponse {
    pub(super) response: McpResponse,
    pub(super) session_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct McpError {
    pub(super) code: i32,
    pub(super) message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) data: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ListToolsResult {
    #[serde(default)]
    pub(super) tools: Vec<RemoteMcpTool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct CallToolResult {
    #[serde(default)]
    pub(super) content: Vec<McpContentBlock>,
    #[serde(default, rename = "isError")]
    pub(super) is_error: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct McpContentBlock {
    #[serde(rename = "type")]
    pub(super) kind: String,
    #[serde(default)]
    pub(super) text: Option<String>,
    #[serde(flatten)]
    pub(super) extra: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct RemoteMcpTool {
    pub(super) name: String,
    #[serde(default)]
    pub(super) description: String,
    #[serde(
        default = "default_input_schema",
        rename = "inputSchema",
        alias = "input_schema"
    )]
    pub(super) input_schema: serde_json::Value,
    #[serde(default)]
    pub(super) annotations: Option<McpToolAnnotations>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct McpToolAnnotations {
    #[serde(default)]
    pub(super) destructive_hint: bool,
}

impl McpRequest {
    pub(super) fn new(method: &str, params: Option<serde_json::Value>) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id: Some(REQUEST_ID_COUNTER.fetch_add(1, Ordering::Relaxed)),
            method: method.to_string(),
            params,
        }
    }

    pub(super) fn initialize() -> Self {
        Self::new(
            "initialize",
            Some(serde_json::json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "roots": { "listChanged": false },
                    "sampling": {}
                },
                "clientInfo": {
                    "name": "napaxi-mobile",
                    "version": env!("CARGO_PKG_VERSION")
                }
            })),
        )
    }

    pub(super) fn initialized_notification() -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id: None,
            method: "notifications/initialized".to_string(),
            params: None,
        }
    }

    pub(super) fn list_tools() -> Self {
        Self::new("tools/list", None)
    }

    pub(super) fn call_tool(name: &str, arguments: serde_json::Value) -> Self {
        Self::new(
            "tools/call",
            Some(serde_json::json!({
                "name": name,
                "arguments": strip_top_level_nulls(arguments),
            })),
        )
    }
}
