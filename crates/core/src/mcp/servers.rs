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
    let activation = load_remote_tools(name, &server_url, &transport, &headers, None).await;
    let mut state = load_state(files_dir);
    let (active, tools, session_id, activation_error) = match activation {
        Ok(activation) => (true, activation.tools, activation.session_id, None),
        Err(error) => (
            false,
            Vec::new(),
            None,
            Some(format!("Activation failed: {error}")),
        ),
    };
    let server = McpServer {
        name: name.to_string(),
        url: server_url,
        transport,
        headers,
        user_id: user_id.clone(),
        active,
        tools,
        session_id,
        activation_error,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    };
    if let Some(existing) = state
        .servers
        .iter_mut()
        .find(|server| server.name == name && server.user_id == user_id)
    {
        *existing = server;
    } else {
        state.servers.push(server);
    }
    if !save_state(files_dir, &state) {
        return result_json(name, &[], "Failed to save MCP server");
    }
    let Some(saved) = state
        .servers
        .iter()
        .find(|server| server.name == name && server.user_id == user_id)
    else {
        return result_json(name, &[], "Failed to save MCP server");
    };
    result_json_for_tools(
        name,
        &saved.tools,
        saved.activation_error.as_deref().unwrap_or(""),
    )
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
    let loaded = load_remote_tools(
        name,
        &state.servers[index].url,
        &state.servers[index].transport,
        &effective_headers(files_dir, &state.servers[index]),
        state.servers[index].session_id.as_deref(),
    )
    .await;
    let server = &mut state.servers[index];
    match loaded {
        Ok(activation) => {
            server.active = true;
            server.tools = activation.tools;
            server.session_id = activation.session_id;
            server.activation_error = None;
        }
        Err(error) => {
            server.active = false;
            server.tools.clear();
            server.session_id = None;
            server.activation_error = Some(format!("Activation failed: {error}"));
        }
    }
    let tools = server.tools.clone();
    let error = server.activation_error.clone().unwrap_or_default();
    if !save_state(files_dir, &state) {
        return result_json(name, &[], "Failed to save MCP servers");
    }
    result_json_for_tools(name, &tools, &error)
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
