//! File-backed MCP server state for the standalone mobile SDK runtime.
//!
//! Public surface preserved through pub use below. Implementation split into:
//!
//! - [`types`]: public DTOs (McpServer, McpTool, OAuth types, transport)
//! - [`helpers`]: JSON formatters, header parsing, transport hinting, JSON-RPC envelopes
//! - [`servers`]: add / remove / list / activate / deactivate
//! - [`tools`]: list_tools / tool_descriptors / call_tool / load_remote_tools
//! - [`oauth_flow`]: start_oauth / finish_oauth
//! - [`handles`]: engine-handle wrappers used by the bridge
//! - [`headers`]: effective/dynamic header resolution (pre-existing)
//! - [`oauth`]: low-level OAuth metadata, PKCE, token exchange (pre-existing)
//! - [`store`]: catalog persistence (pre-existing)
//! - [`tool_descriptor`]: tool name prefixing and JSON shape (pre-existing)
//! - [`transport`]: HTTP/SSE/stdio/unix request transports (pre-existing)

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod handles;
mod headers;
mod helpers;
mod oauth;
mod oauth_flow;
mod security;
mod servers;
mod store;
mod tool_descriptor;
mod tools;
mod transport;
mod types;

#[cfg(test)]
mod tests;

// LEGACY_DEFAULT_ACCOUNT_ID is the historical user_id used before per-account
// scoping; the store layer reads it from `super::LEGACY_DEFAULT_ACCOUNT_ID`.
pub(crate) const LEGACY_DEFAULT_ACCOUNT_ID: &str = "flutter_user";

// Internal re-exports so existing submodules (store/oauth/transport/
// tool_descriptor/headers) keep their `use super::{...}` paths after the split.
// Rustc cannot tell that these are consumed via `use super::X` in sibling
// modules, so we allow the warning rather than rewrite each existing import.
#[allow(unused_imports)]
pub(in crate::mcp) use helpers::{
    McpHttpResponse, McpRequest, McpResponse, result_json, safe_truncate, sanitize_error_body,
};
#[allow(unused_imports)]
pub(in crate::mcp) use types::{McpSecretEntry, McpSecretState, McpState, default_token_type};

pub(crate) use headers::update_dynamic_headers;

// Public API surface for `crate::mcp::*` and `api::mcp::*`.
pub use handles::{
    activate_server_handle, add_server_handle, deactivate_server_handle, finish_oauth_handle,
    list_servers_handle, list_tools_handle, remove_server_handle, start_oauth_handle,
};
pub use oauth_flow::{finish_oauth, start_oauth};
#[allow(unused_imports)]
pub use servers::set_server_active;
pub use servers::{activate_server, add_server, deactivate_server, list_servers, remove_server};
pub use tools::{call_tool, list_tools, tool_descriptors};
pub use types::{
    McpOAuthConfig, McpOAuthPending, McpOAuthStartOptions, McpOAuthTokens, McpServer, McpTool,
    McpTransport,
};
