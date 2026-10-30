//! Server lifecycle: add / remove / list / activate / deactivate.

use super::headers::effective_headers;
use super::helpers::{
    extract_transport_hint, parse_headers, resolve_add_transport, result_json, server_json,
    success_json,
};
use super::oauth::refresh_server_oauth_if_needed;
use super::store::{default_user, load_state, save_state};
use super::tool_descriptor::result_json_for_tools;
use super::tools::load_remote_tools;
use super::types::McpServer;

pub async fn add_server(
    files_dir: &str,
    name: &str,
    url: &str,
    headers_json: &str,
    user_id: &str,
) -> String {
    let name = name.trim();
    let url = url.trim();
    if name.is_empty() {
        return result_json(name, &[], "MCP server name is required");
    }
    if url.is_empty() {
        return result_json(name, &[], "MCP server URL is required");
    }
    let mut headers = match parse_headers(headers_json) {
        Ok(headers) => headers,
        Err(e) => return result_json(name, &[], &e),
    };
    let transport_hint = extract_transport_hint(&mut headers);
    let (server_url, transport) = match resolve_add_transport(url, transport_hint.as_deref()) {
        Ok(resolved) => resolved,
        Err(error) => return result_json(name, &[], &error),
    };

    let user_id = default_user(user_id);
    // Lazy-load discovery (idea reference: OpenClaw #186776 `32f9477bf4`):
    // server add and activation only validate configuration; `tools` are no
    // longer eagerly fetched on activation. The first `list_tools` /
    // `tool_descriptors` / `call_tool` request triggers a single remote
    // `tools/list` call, caches the result in `McpServer::tools`, and flips
    // `tools_loaded` to `true`. Failing the initial fetch records
    // `tools_error` and a back-off timestamp instead of leaving the server
    // stuck in an inactive state.
    let mut state = load_state(files_dir);
    let server = McpServer {
        name: name.to_string(),
        url: server_url,
        transport,
        headers,
        user_id: user_id.clone(),
        active: false,
        tools: Vec::new(),
        tools_loaded: false,
        tools_error: None,
        last_tools_attempt_at: None,
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    };
    if let Some(existing) = state
        .servers
        .iter_mut()
        .find(|server| server.name == name && server.user_id == user_id)
    {
        // Preserve OAuth metadata and any prior activation state across edits.
        let oauth = existing.oauth.clone();
        let oauth_pending = existing.oauth_pending.clone();
        let oauth_tokens = existing.oauth_tokens.clone();
        *existing = server;
        existing.oauth = oauth;
        existing.oauth_pending = oauth_pending;
        existing.oauth_tokens = oauth_tokens;
    } else {
        state.servers.push(server);
    }
    if !save_state(files_dir, &state) {
        return result_json(name, &[], "Failed to save MCP server");
    }
    result_json_for_tools(name, &[], "")
}

pub fn remove_server(files_dir: &str, name: &str, user_id: &str) -> String {
    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    let old_len = state.servers.len();
    state
        .servers
        .retain(|server| !(server.name == name && server.user_id == user_id));
    if state.servers.len() == old_len {
        return success_json(false, Some(format!("MCP server not found: {name}")));
    }
    if save_state(files_dir, &state) {
        success_json(true, None)
    } else {
        success_json(false, Some("Failed to save MCP servers".to_string()))
    }
}

pub fn list_servers(files_dir: &str, user_id: &str) -> String {
    let user_id = default_user(user_id);
    let state = load_state(files_dir);
    let items: Vec<_> = state
        .servers
        .iter()
        .filter(|server| server.user_id == user_id)
        .map(server_json)
        .collect();
    serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string())
}

pub async fn activate_server(files_dir: &str, name: &str, user_id: &str) -> String {
    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    let Some(index) = state
        .servers
        .iter()
        .position(|server| server.name == name && server.user_id == user_id)
    else {
        return result_json(name, &[], "MCP server not found");
    };
    if let Err(error) = refresh_server_oauth_if_needed(&mut state.servers[index]).await {
        let server = &mut state.servers[index];
        server.active = false;
        server.tools.clear();
        server.session_id = None;
        server.activation_error = Some(format!("OAuth refresh failed: {error}"));
        let activation_error = server.activation_error.clone().unwrap_or_default();
        let _ = save_state(files_dir, &state);
        return result_json(name, &[], &activation_error);
    }
    // Lazy-load discovery: activation only marks the server usable. The
    // remote `tools/list` call is deferred to the first
    // `list_tools` / `tool_descriptors` / `call_tool` request.
    let server = &mut state.servers[index];
    server.active = true;
    server.tools.clear();
    server.tools_loaded = false;
    server.tools_error = None;
    server.last_tools_attempt_at = None;
    server.session_id = None;
    server.activation_error = None;
    if !save_state(files_dir, &state) {
        return result_json(name, &[], "Failed to save MCP servers");
    }
    result_json_for_tools(name, &[], "")
}

#[allow(dead_code)] // Direct activation helper kept alongside handle-routed entry point.
pub fn set_server_active(files_dir: &str, name: &str, user_id: &str) -> String {
    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    let Some(server) = state
        .servers
        .iter_mut()
        .find(|server| server.name == name && server.user_id == user_id)
    else {
        return result_json(name, &[], "MCP server not found");
    };
    server.active = true;
    server.activation_error = None;
    // Preserve any cached tools across a purely-synchronous re-activation. The
    // lazy-load machinery (`tools_loaded` / `tools_error`) is left untouched
    // so an already-loaded server does not get re-fetched, and an unloaded
    // one is still fetched on the next `list_tools` / `tool_descriptors` /
    // `call_tool` request. `set_server_active` is a local flag flip, not a
    // remote re-handshake — clearing the cache here would force a network
    // round-trip on servers that have never needed one (idea reference:
    // OpenClaw #186776 `32f9477bf4`).
    let tools = server.tools.clone();
    if !save_state(files_dir, &state) {
        return result_json(name, &[], "Failed to save MCP servers");
    }
    result_json_for_tools(name, &tools, "")
}

pub fn deactivate_server(files_dir: &str, name: &str, user_id: &str) -> String {
    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    let Some(server) = state
        .servers
        .iter_mut()
        .find(|server| server.name == name && server.user_id == user_id)
    else {
        return success_json(false, Some(format!("MCP server not found: {name}")));
    };
    server.active = false;
    if save_state(files_dir, &state) {
        success_json(true, None)
    } else {
        success_json(false, Some("Failed to save MCP servers".to_string()))
    }
}
