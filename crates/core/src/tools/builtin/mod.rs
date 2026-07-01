//! Napaxi-owned mobile builtin tool composition.
//!
//! Public surface: `BuiltinToolContext`, `mcp_tools_and_handler`,
//! `builtin_tools_and_handler`. Implementation split across:
//!
//! - [`mcp`]: MCP server management tool group
//! - [`handlers`]: per-group handler adapters (skill, memory, file, web, http, media)
//! - [`shell`]: shell tool descriptor + dispatch + per-platform execution
//! - [`shell_policy`]: shell command security decision (hard gate + mode)
//! - [`shell_safe`]: known-safe command allow-list with per-argument validation
//! - [`shell_inject`]: shell injection / netcat data piping detection

mod handlers;
mod mcp;
mod shell;
mod shell_inject;
mod shell_policy;
mod shell_safe;
mod shell_util;

#[cfg(test)]
mod tests;

pub(crate) use shell_policy::{GitShellIntent, git_shell_intent};

use crate::tool_loop::InternalToolHandler;
use crate::tool_registry::{ToolDescriptor, ToolRequestBridge};
use crate::types::PlatformLlmConfig;

pub(super) const APPROVAL_TOOL_NAME: &str = "__napaxi_approval__";

#[derive(Clone)]
pub struct BuiltinToolContext {
    pub files_dir: String,
    pub workspace_files_dir: String,
    pub agent_id: String,
    pub platform: String,
    pub native_library_dir: Option<String>,
    pub account_id: String,
    pub approval_bridge: Option<ToolRequestBridge>,
    pub llm_config: PlatformLlmConfig,
    pub current_thread_id: Option<String>,
}

pub use mcp::mcp_tools_and_handler;

pub fn builtin_tools_and_handler(
    context: BuiltinToolContext,
    mut extra_tools: Vec<ToolDescriptor>,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let (mut mcp_management_tools, mcp_management_handler) =
        mcp::mcp_management_handler(&context, fallback);
    let (mut skill_tools, skill_handler) =
        handlers::skill_handler(&context, mcp_management_handler);
    let (mut memory_tools, memory_handler) = handlers::memory_handler(&context, skill_handler);
    let (mut file_tools, file_handler) = handlers::file_handler(&context, memory_handler);
    let (mut web_tools, web_handler) = handlers::web_search_handler(file_handler);
    let (mut fetch_tools, fetch_handler) = handlers::web_fetch_handler(web_handler);
    let (mut http_tools, http_handler) = handlers::http_handler(&context, fetch_handler);
    let (mut media_tools, media_handler) = handlers::media_handler(&context, http_handler);
    let (mut shell_tools, handler) = shell::shell_handler(&context, media_handler);
    skill_tools.append(&mut mcp_management_tools);
    skill_tools.push(crate::human_loop::descriptor());
    skill_tools.append(&mut memory_tools);
    skill_tools.append(&mut file_tools);
    skill_tools.append(&mut web_tools);
    skill_tools.append(&mut fetch_tools);
    skill_tools.append(&mut http_tools);
    skill_tools.append(&mut media_tools);
    skill_tools.append(&mut shell_tools);
    skill_tools.append(&mut extra_tools);
    (skill_tools, handler)
}

pub(super) fn parse_approval_response(response: &str) -> Result<(), String> {
    let value: serde_json::Value = serde_json::from_str(response)
        .map_err(|e| format!("Invalid approval response JSON: {e}"))?;
    if value
        .get("approved")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
    {
        Ok(())
    } else {
        let message = value
            .get("message")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("Tool execution denied by user");
        Err(message.to_string())
    }
}

pub(super) fn normalize_agent_id(agent_id: &str) -> String {
    let trimmed = agent_id.trim();
    if trimmed.is_empty() {
        crate::runtime::DEFAULT_AGENT_ID.to_string()
    } else {
        trimmed.to_string()
    }
}
