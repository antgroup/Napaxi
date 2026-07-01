use super::{McpServer, McpTool};

pub(super) fn prefixed_tool_name(server_name: &str, tool_name: &str) -> String {
    format!("{}_{}", server_name, tool_name)
}

pub(super) fn remote_tool_name(server_name: &str, tool_name: &str) -> Option<String> {
    tool_name
        .strip_prefix(&format!("{server_name}_"))
        .map(str::to_string)
}

pub(super) fn tool_json(server: &McpServer, tool: &McpTool) -> serde_json::Value {
    serde_json::json!({
        "name": prefixed_tool_name(&server.name, &tool.name),
        "serverName": server.name,
        "description": tool.description,
        "inputSchema": tool.input_schema,
        "requiresApproval": tool.requires_approval,
    })
}

pub(super) fn result_json_for_tools(name: &str, tools_loaded: &[McpTool], error: &str) -> String {
    let tool_names: Vec<String> = tools_loaded
        .iter()
        .map(|tool| prefixed_tool_name(name, &tool.name))
        .collect();
    super::result_json(name, &tool_names, error)
}
