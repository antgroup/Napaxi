//! MCP server management tools (list/add/activate/deactivate/remove + tool list).

use std::sync::Arc;

use crate::tool_loop::{InternalToolHandler, InternalToolResult};
use crate::tool_registry::ToolDescriptor;

use super::BuiltinToolContext;

pub fn mcp_tools_and_handler(
    files_dir: &str,
    account_id: &str,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let descriptors = crate::mcp::tool_descriptors(files_dir, account_id);
    let files_dir = files_dir.to_string();
    let account_id = account_id.to_string();
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if !crate::mcp::tool_descriptors(&files_dir, &account_id)
            .iter()
            .any(|tool| tool.name == tool_name)
        {
            return None;
        }
        let files_dir = files_dir.clone();
        let account_id = account_id.clone();
        let tool_name = tool_name.to_string();
        Some(Box::pin(async move {
            let output = crate::mcp::call_tool(&files_dir, &tool_name, params, &account_id).await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (descriptors, Some(handler))
}

pub(super) fn mcp_management_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let files_dir = context.files_dir.clone();
    let account_id = context.account_id.clone();
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if !is_mcp_management_tool(tool_name) {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let files_dir = files_dir.clone();
        let account_id = account_id.clone();
        let tool_name = tool_name.to_string();
        Some(Box::pin(async move {
            let output =
                execute_mcp_management_tool(&files_dir, &account_id, &tool_name, params).await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (mcp_management_descriptors(), Some(handler))
}

fn is_mcp_management_tool(name: &str) -> bool {
    matches!(
        name,
        "mcp_server_list"
            | "mcp_server_add"
            | "mcp_server_activate"
            | "mcp_server_deactivate"
            | "mcp_server_remove"
            | "mcp_tool_list"
    )
}

fn mcp_management_descriptors() -> Vec<ToolDescriptor> {
    vec![
        ToolDescriptor {
            name: "mcp_server_list".to_string(),
            description: "List MCP servers configured for the current account, including active state and activation errors.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {}
            }),
            effect: crate::tool_registry::ToolEffect::Read,
        },
        ToolDescriptor {
            name: "mcp_server_add".to_string(),
            description: "Install an HTTP MCP server for the current account and activate it immediately. Use this when the user asks to add or install an MCP server and provides its name and URL.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Unique local server name, for example `github` or `notion`."
                    },
                    "url": {
                        "type": "string",
                        "description": "HTTP MCP endpoint URL."
                    },
                    "headers": {
                        "type": "object",
                        "description": "Optional HTTP headers for the MCP endpoint.",
                        "additionalProperties": { "type": "string" }
                    },
                    "transport": {
                        "type": "string",
                        "enum": ["http", "sse"],
                        "description": "Optional MCP transport. Defaults to HTTP, with SSE auto-detected for /sse URLs."
                    }
                },
                "required": ["name", "url"]
            }),
            effect: crate::tool_registry::ToolEffect::Write,
        },
        ToolDescriptor {
            name: "mcp_server_activate".to_string(),
            description: "Activate a configured MCP server and refresh its tool list.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "name": { "type": "string", "description": "Configured MCP server name." }
                },
                "required": ["name"]
            }),
            effect: crate::tool_registry::ToolEffect::External,
        },
        ToolDescriptor {
            name: "mcp_server_deactivate".to_string(),
            description: "Deactivate a configured MCP server so its tools are no longer exposed to the model.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "name": { "type": "string", "description": "Configured MCP server name." }
                },
                "required": ["name"]
            }),
            effect: crate::tool_registry::ToolEffect::Write,
        },
        ToolDescriptor {
            name: "mcp_server_remove".to_string(),
            description: "Remove a configured MCP server from the current account.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "name": { "type": "string", "description": "Configured MCP server name." }
                },
                "required": ["name"]
            }),
            effect: crate::tool_registry::ToolEffect::Write,
        },
        ToolDescriptor {
            name: "mcp_tool_list".to_string(),
            description: "List tools exposed by active MCP servers for the current account. Optionally filter by server name.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "server_name": {
                        "type": "string",
                        "description": "Optional MCP server name filter."
                    }
                }
            }),
            effect: crate::tool_registry::ToolEffect::Read,
        },
    ]
}

async fn execute_mcp_management_tool(
    files_dir: &str,
    account_id: &str,
    tool_name: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    match tool_name {
        "mcp_server_list" => Ok(crate::mcp::list_servers(files_dir, account_id)),
        "mcp_tool_list" => {
            let server_name = params
                .get("server_name")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("");
            Ok(crate::mcp::list_tools(files_dir, server_name, account_id))
        }
        "mcp_server_add" => {
            let name = required_string_param(&params, "name")?;
            let url = required_string_param(&params, "url")?;
            let headers = params
                .get("headers")
                .cloned()
                .unwrap_or_else(|| serde_json::json!({}));
            if !headers.is_object() {
                return Err("headers must be an object when provided".to_string());
            }
            let mut headers = headers;
            if let Some(transport) = params.get("transport").and_then(serde_json::Value::as_str)
                && !transport.trim().is_empty()
                && let Some(map) = headers.as_object_mut()
            {
                map.insert(
                    "__napaxi_transport".to_string(),
                    serde_json::Value::String(transport.trim().to_string()),
                );
            }
            let headers_json = serde_json::to_string(&headers)
                .map_err(|e| format!("Invalid MCP headers JSON: {e}"))?;
            Ok(crate::mcp::add_server(files_dir, &name, &url, &headers_json, account_id).await)
        }
        "mcp_server_activate" => {
            let name = required_string_param(&params, "name")?;
            Ok(crate::mcp::activate_server(files_dir, &name, account_id).await)
        }
        "mcp_server_deactivate" => {
            let name = required_string_param(&params, "name")?;
            Ok(crate::mcp::deactivate_server(files_dir, &name, account_id))
        }
        "mcp_server_remove" => {
            let name = required_string_param(&params, "name")?;
            Ok(crate::mcp::remove_server(files_dir, &name, account_id))
        }
        _ => Err(format!("Unknown MCP management tool: {tool_name}")),
    }
}

fn required_string_param(params: &serde_json::Value, name: &str) -> Result<String, String> {
    params
        .get(name)
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| format!("{name} is required"))
}
