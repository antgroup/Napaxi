//! Public DTOs for MCP server state.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct McpTool {
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default = "default_input_schema")]
    pub input_schema: serde_json::Value,
    #[serde(default)]
    pub requires_approval: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct McpServer {
    pub name: String,
    pub url: String,
    #[serde(default)]
    pub transport: McpTransport,
    #[serde(default)]
    pub headers: HashMap<String, String>,
    #[serde(default)]
    pub user_id: String,
    #[serde(default)]
    pub active: bool,
    #[serde(default)]
    pub tools: Vec<McpTool>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub activation_error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub oauth: Option<McpOAuthConfig>,
    #[serde(default, skip_serializing)]
    pub oauth_pending: Option<McpOAuthPending>,
    #[serde(default, skip_serializing)]
    pub oauth_tokens: Option<McpOAuthTokens>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct McpOAuthConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_id: Option<String>,
    #[serde(default, skip_serializing)]
    pub client_secret: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authorization_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_url: Option<String>,
    #[serde(default)]
    pub scopes: Vec<String>,
    #[serde(default = "default_true")]
    pub use_pkce: bool,
    #[serde(default)]
    pub extra_params: HashMap<String, String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub redirect_uri: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resource: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpOAuthPending {
    pub state: String,
    pub code_verifier: Option<String>,
    pub redirect_uri: String,
    pub authorization_url: String,
    pub token_url: String,
    pub client_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_secret: Option<String>,
    #[serde(default)]
    pub scopes: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resource: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpOAuthTokens {
    pub access_token: String,
    #[serde(default = "default_token_type")]
    pub token_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct McpOAuthStartOptions {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_secret: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authorization_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_url: Option<String>,
    #[serde(default)]
    pub scopes: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub use_pkce: Option<bool>,
    #[serde(default)]
    pub extra_params: HashMap<String, String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resource: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(tag = "transport", rename_all = "lowercase")]
pub enum McpTransport {
    #[default]
    Http,
    Stdio {
        command: String,
        #[serde(default)]
        args: Vec<String>,
        #[serde(default)]
        env: HashMap<String, String>,
    },
    Unix {
        socket_path: String,
    },
    Sse {
        #[serde(default = "default_sse_path")]
        sse_path: String,
    },
}

pub(super) fn default_sse_path() -> String {
    "/sse".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(super) struct McpState {
    pub(super) servers: Vec<McpServer>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(super) struct McpSecretState {
    pub(super) entries: Vec<McpSecretEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct McpSecretEntry {
    pub(super) name: String,
    pub(super) user_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) client_secret: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) oauth_pending: Option<McpOAuthPending>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) oauth_tokens: Option<McpOAuthTokens>,
}

pub(super) fn default_input_schema() -> serde_json::Value {
    serde_json::json!({"type": "object", "properties": {}})
}

pub(super) fn default_true() -> bool {
    true
}

pub(super) fn default_token_type() -> String {
    "Bearer".to_string()
}
