//! Tool listing, descriptor enumeration, remote tool loading, and tool calls.

use std::collections::HashMap;

use super::headers::{effective_headers, is_http_like_transport};
use super::helpers::{CallToolResult, ListToolsResult, McpRequest, McpResponse};
use super::oauth::refresh_server_oauth_if_needed;
use super::store::{default_user, load_state, save_state};
use super::tool_descriptor::{prefixed_tool_name, remote_tool_name, tool_json};
use super::transport::{send_mcp_request, send_mcp_sse_sequence, send_mcp_transport_sequence};
use super::types::{McpTool, McpTransport};

pub fn list_tools(files_dir: &str, server_name: &str, user_id: &str) -> String {
    let user_id = default_user(user_id);
    let state = load_state(files_dir);
    let tools: Vec<_> = state
        .servers
        .iter()
        .filter(|server| server.user_id == user_id && server.active)
        .filter(|server| server_name.trim().is_empty() || server.name == server_name)
        .flat_map(|server| server.tools.iter().map(|tool| tool_json(server, tool)))
        .collect();
    serde_json::to_string(&tools).unwrap_or_else(|_| "[]".to_string())
}

pub fn tool_descriptors(
    files_dir: &str,
    user_id: &str,
) -> Vec<crate::tool_registry::ToolDescriptor> {
    let user_id = default_user(user_id);
    let state = load_state(files_dir);
    state
        .servers
        .iter()
        .filter(|server| server.user_id == user_id && server.active)
        .flat_map(|server| {
            server
                .tools
                .iter()
                .map(|tool| crate::tool_registry::ToolDescriptor {
                    name: prefixed_tool_name(&server.name, &tool.name),
                    description: if tool.description.trim().is_empty() {
                        format!("MCP tool '{}' from server '{}'", tool.name, server.name)
                    } else {
                        format!("{} (MCP server: {})", tool.description, server.name)
                    },
                    parameters: tool.input_schema.clone(),
                    effect: crate::tool_registry::ToolEffect::External,
                })
        })
        // Run descriptor admission so policy hooks can hide MCP tools from
        // the agent's tool list. `admit_tool_descriptor` falls back to the
        // tool name as the capability id when no static mapping matches
        // (MCP tool names are `{server}_{name}`); policy hooks can branch
        // on either the subject prefix or the `napaxi.mcp.runtime`
        // capability id.
        .filter(|descriptor| crate::capabilities::admit_tool_descriptor(&descriptor.name).is_ok())
        .collect()
}

pub async fn call_tool(
    files_dir: &str,
    tool_name: &str,
    arguments: serde_json::Value,
    user_id: &str,
) -> Result<String, String> {
    // Invocation admission must pass before any network IO. Policy hooks can
    // deny by subject (the prefixed MCP tool name) or by capability id;
    // unresolved capability ids fall back to the subject name.
    crate::capabilities::admit_tool_invocation(tool_name)?;

    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    let Some((index, remote_tool)) = state
        .servers
        .iter()
        .enumerate()
        .filter(|(_, server)| server.user_id == user_id && server.active)
        .find_map(|(index, server)| {
            remote_tool_name(&server.name, tool_name).map(|tool| (index, tool))
        })
    else {
        return Err(format!("MCP tool not found: {tool_name}"));
    };

    let result = if is_http_like_transport(&state.servers[index].transport) {
        let refreshed = refresh_server_oauth_if_needed(&mut state.servers[index])
            .await
            .map_err(|error| format!("MCP OAuth refresh failed: {error}"))?;
        if refreshed && !save_state(files_dir, &state) {
            return Err("Failed to save refreshed MCP OAuth token".to_string());
        }
        let http_result = if let McpTransport::Sse { sse_path } = &state.servers[index].transport {
            let responses = send_mcp_sse_sequence(
                &state.servers[index].url,
                sse_path,
                &effective_headers(files_dir, &state.servers[index]),
                vec![
                    McpRequest::initialize(),
                    McpRequest::initialized_notification(),
                    McpRequest::call_tool(&remote_tool, arguments),
                ],
            )
            .await?;
            responses
                .into_iter()
                .last()
                .ok_or_else(|| "No result in MCP tool response".to_string())?
        } else {
            send_mcp_request(
                &state.servers[index].url,
                &state.servers[index].transport,
                &effective_headers(files_dir, &state.servers[index]),
                state.servers[index].session_id.as_deref(),
                McpRequest::call_tool(&remote_tool, arguments),
            )
            .await?
        };
        if http_result.session_id != state.servers[index].session_id {
            state.servers[index].session_id = http_result.session_id.clone();
            let _ = save_state(files_dir, &state);
        }
        http_result.response
    } else {
        let responses = send_mcp_transport_sequence(
            &state.servers[index].transport,
            vec![
                McpRequest::initialize(),
                McpRequest::initialized_notification(),
                McpRequest::call_tool(&remote_tool, arguments),
            ],
        )
        .await?;
        responses
            .into_iter()
            .last()
            .map(|response| response.response)
            .ok_or_else(|| "No result in MCP tool response".to_string())?
    };

    let result: CallToolResult = result
        .result
        .ok_or_else(|| "No result in MCP tool response".to_string())
        .and_then(|value| {
            serde_json::from_value(value).map_err(|e| format!("Invalid MCP tool result: {e}"))
        })?;
    let content = result
        .content
        .iter()
        .map(|block| {
            block
                .text
                .clone()
                .unwrap_or_else(|| serde_json::to_string(block).unwrap_or_default())
        })
        .collect::<Vec<_>>()
        .join("\n");
    if result.is_error {
        Err(content)
    } else {
        Ok(content)
    }
}

pub(super) struct McpActivation {
    pub(super) tools: Vec<McpTool>,
    pub(super) session_id: Option<String>,
}

/// Inspect an [initialize, initialized, tools/list] response batch and decide
/// whether the server advertises the `tools` capability. The initialize
/// response is the first entry in the batch.
fn sequence_advertises_tools(responses: &[super::helpers::McpHttpResponse]) -> bool {
    match responses.first() {
        Some(initialized) => super::helpers::initialize_advertises_tools(&initialized.response),
        None => true,
    }
}

pub(super) async fn load_remote_tools(
    server_name: &str,
    url: &str,
    transport: &McpTransport,
    headers: &HashMap<String, String>,
    initial_session_id: Option<&str>,
) -> Result<McpActivation, String> {
    if let McpTransport::Sse { sse_path } = transport {
        let responses = send_mcp_sse_sequence(
            url,
            sse_path,
            headers,
            vec![
                McpRequest::initialize(),
                McpRequest::initialized_notification(),
                McpRequest::list_tools(),
            ],
        )
        .await?;
        if !sequence_advertises_tools(&responses) {
            return Ok(McpActivation {
                tools: Vec::new(),
                session_id: None,
            });
        }
        let listed = responses
            .into_iter()
            .last()
            .ok_or_else(|| "No result in MCP tools/list response".to_string())?;
        return tools_activation_from_response(server_name, listed.response, None);
    }

    if !matches!(transport, McpTransport::Http) {
        let responses = send_mcp_transport_sequence(
            transport,
            vec![
                McpRequest::initialize(),
                McpRequest::initialized_notification(),
                McpRequest::list_tools(),
            ],
        )
        .await?;
        if !sequence_advertises_tools(&responses) {
            return Ok(McpActivation {
                tools: Vec::new(),
                session_id: None,
            });
        }
        let listed = responses
            .into_iter()
            .last()
            .ok_or_else(|| "No result in MCP tools/list response".to_string())?;
        return tools_activation_from_response(server_name, listed.response, None);
    }

    let initialized = send_mcp_request(
        url,
        transport,
        headers,
        initial_session_id,
        McpRequest::initialize(),
    )
    .await?;
    let mut session_id = initialized.session_id;
    let advertises_tools = super::helpers::initialize_advertises_tools(&initialized.response);
    let _ = send_mcp_request(
        url,
        transport,
        headers,
        session_id.as_deref(),
        McpRequest::initialized_notification(),
    )
    .await;
    if !advertises_tools {
        return Ok(McpActivation {
            tools: Vec::new(),
            session_id,
        });
    }
    let listed = send_mcp_request(
        url,
        transport,
        headers,
        session_id.as_deref(),
        McpRequest::list_tools(),
    )
    .await?;
    if listed.session_id.is_some() {
        session_id = listed.session_id.clone();
    }
    tools_activation_from_response(server_name, listed.response, session_id)
}

fn tools_activation_from_response(
    server_name: &str,
    response: McpResponse,
    session_id: Option<String>,
) -> Result<McpActivation, String> {
    if let Some(error) = response.error {
        return Err(format!(
            "MCP error: {} (code {})",
            error.message, error.code
        ));
    }
    let result: ListToolsResult = response
        .result
        .ok_or_else(|| "No result in MCP tools/list response".to_string())
        .and_then(|value| {
            serde_json::from_value(value).map_err(|e| format!("Invalid MCP tools/list result: {e}"))
        })?;
    let tools = result
        .tools
        .into_iter()
        .map(|tool| McpTool {
            name: tool.name,
            description: tool.description,
            input_schema: tool.input_schema,
            requires_approval: tool
                .annotations
                .as_ref()
                .map(|annotations| annotations.destructive_hint)
                .unwrap_or(false),
        })
        .inspect(|tool| {
            tracing::debug!(server = server_name, tool = tool.name, "Loaded MCP tool");
        })
        .collect();
    Ok(McpActivation { tools, session_id })
}
