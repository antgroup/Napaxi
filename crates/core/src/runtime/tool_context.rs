//! Session tool context assembly + tool request dispatcher registry +
//! `available_tool_infos_json` queries.

use std::sync::{Mutex, OnceLock};

use crate::error::{CoreError, CoreResult, ToolError};
use crate::tool_loop::InternalToolHandler;
use crate::tool_registry::{ToolDescriptor, ToolRequestBridge, ToolRequestDispatcher};
use crate::types::PlatformLlmConfig;

use super::engine::{DEFAULT_ACCOUNT_ID, Engine, normalize_agent_id};
use super::handle::handle_to_arc;
use super::sessions::scoped_workspace_files_dir;

pub struct SessionToolContext {
    #[allow(dead_code)] // Carried for adapter scoping; not read by current dispatch.
    pub account_id: String,
    pub workspace_files_dir: String,
    pub extra_tools: Vec<ToolDescriptor>,
    pub internal_tool_handler: Option<InternalToolHandler>,
}

fn tool_request_dispatcher_cell() -> &'static Mutex<Option<ToolRequestDispatcher>> {
    static DISPATCHER: OnceLock<Mutex<Option<ToolRequestDispatcher>>> = OnceLock::new();
    DISPATCHER.get_or_init(|| Mutex::new(None))
}

pub fn set_tool_request_dispatcher(dispatcher: ToolRequestDispatcher) {
    if let Ok(mut guard) = tool_request_dispatcher_cell().lock() {
        *guard = Some(dispatcher);
    }
}

pub fn tool_request_dispatcher() -> Option<ToolRequestDispatcher> {
    tool_request_dispatcher_cell()
        .lock()
        .ok()
        .and_then(|guard| guard.clone())
}

pub fn prepare_session_tool_context(
    engine: &Engine,
    account_id: &str,
    agent_id: &str,
) -> SessionToolContext {
    prepare_session_tool_context_with_config_and_thread(
        engine,
        account_id,
        agent_id,
        engine.config_with_capabilities(engine.config()),
        None,
    )
}

pub(super) fn prepare_session_tool_context_with_config(
    engine: &Engine,
    account_id: &str,
    agent_id: &str,
    llm_config: PlatformLlmConfig,
) -> SessionToolContext {
    prepare_session_tool_context_with_config_and_thread(
        engine, account_id, agent_id, llm_config, None,
    )
}

pub(super) fn prepare_session_tool_context_with_config_and_thread(
    engine: &Engine,
    account_id: &str,
    agent_id: &str,
    llm_config: PlatformLlmConfig,
    current_thread_id: Option<String>,
) -> SessionToolContext {
    let account_id = if account_id.trim().is_empty() {
        DEFAULT_ACCOUNT_ID.to_string()
    } else {
        account_id.to_string()
    };
    let agent_id = normalize_agent_id(agent_id);
    let workspace_files_dir =
        scoped_workspace_files_dir(engine.files_dir(), &account_id, &agent_id);
    let (mcp_tools, mcp_handler) =
        crate::builtin_tools::mcp_tools_and_handler(engine.files_dir(), &account_id);
    let tool_bridge = engine
        .tools()
        .request_bridge()
        .or_else(|| tool_request_dispatcher().map(ToolRequestBridge::process_scoped));
    let (mut app_action_tools, app_action_handler) =
        crate::agents::agent_app::action_tools_and_handler(
            engine.files_dir(),
            &agent_id,
            tool_bridge.clone(),
            mcp_handler,
        );
    let mut extra_tools = mcp_tools;
    extra_tools.append(&mut app_action_tools);
    let (extra_tools, internal_tool_handler) = crate::builtin_tools::builtin_tools_and_handler(
        crate::builtin_tools::BuiltinToolContext {
            files_dir: engine.files_dir().to_string(),
            workspace_files_dir: workspace_files_dir.clone(),
            agent_id,
            platform: engine.platform().to_string(),
            native_library_dir: engine.native_library_dir().map(str::to_string),
            account_id: account_id.clone(),
            approval_bridge: tool_bridge,
            llm_config,
            current_thread_id,
        },
        extra_tools,
        app_action_handler,
    );
    SessionToolContext {
        account_id,
        workspace_files_dir,
        extra_tools,
        internal_tool_handler,
    }
}

pub(crate) fn prepare_session_tool_context_with_config_for_core(
    engine: &Engine,
    account_id: &str,
    agent_id: &str,
    llm_config: PlatformLlmConfig,
) -> SessionToolContext {
    prepare_session_tool_context_with_config(engine, account_id, agent_id, llm_config)
}

pub(crate) fn prepare_session_tool_context_with_config_and_thread_for_core(
    engine: &Engine,
    account_id: &str,
    agent_id: &str,
    llm_config: PlatformLlmConfig,
    current_thread_id: Option<String>,
) -> SessionToolContext {
    prepare_session_tool_context_with_config_and_thread(
        engine,
        account_id,
        agent_id,
        llm_config,
        current_thread_id,
    )
}

pub async fn available_tool_infos_json(
    engine: &Engine,
    account_id: &str,
    agent_id: &str,
) -> String {
    let tool_context = prepare_session_tool_context(engine, account_id, agent_id);
    let tools = engine.tools();
    let mut tools = crate::tool_loop::gather_tool_descriptors_for_config(
        &engine.config_with_capabilities(engine.config()),
        Some(&tools),
        tool_context.extra_tools,
    )
    .await;
    tools.sort_by(|a, b| a.name.cmp(&b.name));
    let infos: Vec<_> = tools
        .into_iter()
        .map(|tool| {
            serde_json::json!({
                "name": tool.name,
                "description": tool.description,
            })
        })
        .collect();
    serde_json::to_string(&infos).unwrap_or_else(|_| "[]".to_string())
}

pub async fn available_tool_infos_json_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return "[]".to_string();
    };
    available_tool_infos_json(&engine, account_id, agent_id).await
}

pub async fn update_custom_tools_handle(handle: i64, tools_json: &str) -> bool {
    match update_custom_tools_handle_typed(handle, tools_json).await {
        Ok(count) => {
            tracing::info!("update_custom_tools: {count} tools registered");
            true
        }
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                handle,
                "update_custom_tools_handle failed"
            );
            false
        }
    }
}

/// Result-returning variant. `Ok(count)` returns the number of registered
/// custom tools; errors distinguish missing dispatcher (`tool_execution`),
/// stale handle (`invalid_handle`), and dispatcher registration failure
/// (`tool_execution`).
pub async fn update_custom_tools_handle_typed(handle: i64, tools_json: &str) -> CoreResult<usize> {
    let dispatcher = tool_request_dispatcher()
        .ok_or_else(|| ToolError::Execution("no tool request dispatcher registered".into()))?;
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { handle_to_arc(handle) }.ok_or(CoreError::InvalidHandle(handle))?;
    let tools = engine.tools();
    if !tools.set_dispatcher(dispatcher) {
        return Err(ToolError::Execution("failed to register dispatcher".into()).into());
    }
    tools
        .replace_custom_tools(tools_json)
        .await
        .map_err(|e| ToolError::InvalidParams(e.to_string()).into())
}
