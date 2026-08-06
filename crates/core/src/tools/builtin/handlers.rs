//! Per-tool-group internal handler adapters: skill / memory / file / web /
//! HTTP / media.

use std::sync::Arc;
use std::time::Duration;

use crate::tool_loop::{InternalToolHandler, InternalToolResult};
use crate::tool_registry::{
    ToolDescriptor, ToolExecutionContext, ToolRequestBridge, request_host_tool_execution,
    request_host_tool_execution_with_context,
};

use super::{APPROVAL_TOOL_NAME, BuiltinToolContext, normalize_agent_id, parse_approval_response};

pub(super) fn skill_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let files_dir = context.files_dir.clone();
    let agent_id = normalize_agent_id(&context.agent_id);
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if !crate::skill_tools::is_skill_tool(tool_name) {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let files_dir = files_dir.clone();
        let agent_id = agent_id.clone();
        let tool_name = tool_name.to_string();
        Some(Box::pin(async move {
            let output =
                crate::skill_tools::execute(&files_dir, &agent_id, &tool_name, params).await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (crate::skill_tools::descriptors(), Some(handler))
}

pub(super) fn memory_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let files_dir = context.workspace_files_dir.clone();
    let llm_config = context.llm_config.clone();
    let current_thread_id = context.current_thread_id.clone();
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if !crate::memory_tools::is_memory_tool(tool_name) {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let files_dir = files_dir.clone();
        let llm_config = llm_config.clone();
        let current_thread_id = current_thread_id.clone();
        let tool_name = tool_name.to_string();
        Some(Box::pin(async move {
            let output = crate::memory_tools::execute_with_context(
                crate::memory_tools::MemoryToolContext {
                    files_dir,
                    llm_config: Some(llm_config),
                    current_thread_id,
                },
                &tool_name,
                params,
            )
            .await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (crate::memory_tools::descriptors(), Some(handler))
}

pub(super) fn file_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let files_dir = context.files_dir.clone();
    let workspace_files_dir = context.workspace_files_dir.clone();
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, progress| {
        if !crate::file_tools::is_file_tool(tool_name) {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, progress));
        }
        let files_dir = files_dir.clone();
        let workspace_files_dir = workspace_files_dir.clone();
        let tool_name = tool_name.to_string();
        Some(Box::pin(async move {
            let result = crate::file_tools::execute(
                &files_dir,
                &workspace_files_dir,
                &tool_name,
                params,
                progress,
            )?;
            Ok(InternalToolResult {
                output: result.output,
                events: Vec::new(),
            })
        }))
    });
    (crate::file_tools::descriptors(), Some(handler))
}

pub(super) fn web_search_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let browser_context = browser_search_context(context);
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if tool_name != crate::web_search_tool::WEB_SEARCH_TOOL_NAME {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let browser_context = browser_context.clone();
        Some(Box::pin(async move {
            let output =
                crate::web_search_tool::execute_with_browser(params, browser_context).await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (vec![crate::web_search_tool::descriptor()], Some(handler))
}

fn browser_search_context(
    context: &BuiltinToolContext,
) -> Option<crate::web_search_tool::BrowserSearchContext> {
    // Treat the browser as the preferred implementation detail of `web_search`,
    // not as a requirement that callers explicitly enable the public browser
    // tool surface. If the host bridge cannot actually dispatch browser tools,
    // the browser request will fail and `web_search` will fall back to its HTTP
    // providers without changing the public tool contract.
    let Some(bridge) = context.approval_bridge.clone() else {
        tracing::info!("web_search browser path unavailable: no host tool bridge");
        return None;
    };
    Some(crate::web_search_tool::BrowserSearchContext {
        bridge,
        tool_context: ToolExecutionContext {
            files_dir: context.files_dir.clone(),
            workspace_files_dir: context.workspace_files_dir.clone(),
            agent_id: context.agent_id.clone(),
            session_key_json: None,
        },
    })
}

fn browser_fetch_context(
    context: &BuiltinToolContext,
) -> Option<crate::web_fetch_tool::BrowserFetchContext> {
    let Some(bridge) = context.approval_bridge.clone() else {
        tracing::info!("web_fetch browser path unavailable: no host tool bridge");
        return None;
    };
    Some(crate::web_fetch_tool::BrowserFetchContext {
        bridge,
        tool_context: ToolExecutionContext {
            files_dir: context.files_dir.clone(),
            workspace_files_dir: context.workspace_files_dir.clone(),
            agent_id: context.agent_id.clone(),
            session_key_json: None,
        },
    })
}

pub(super) fn web_fetch_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let browser_context = browser_fetch_context(context);
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if tool_name != crate::web_fetch_tool::WEB_FETCH_TOOL_NAME {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let browser_context = browser_context.clone();
        Some(Box::pin(async move {
            let output =
                crate::web_fetch_tool::execute_with_browser(params, browser_context).await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (vec![crate::web_fetch_tool::descriptor()], Some(handler))
}

pub(super) fn http_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let files_dir = context.files_dir.clone();
    let workspace_files_dir = context.workspace_files_dir.clone();
    let approval_bridge = context.approval_bridge.clone();
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if tool_name != crate::http_tool::HTTP_TOOL_NAME {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let files_dir = files_dir.clone();
        let workspace_files_dir = workspace_files_dir.clone();
        let approval_bridge = approval_bridge.clone();
        Some(Box::pin(async move {
            ensure_http_request_allowed(&params, approval_bridge).await?;
            let output =
                crate::http_tool::execute(&files_dir, &workspace_files_dir, params).await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (vec![crate::http_tool::descriptor()], Some(handler))
}

pub(super) fn platform_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let Some(bridge) = context.approval_bridge.clone() else {
        return (Vec::new(), fallback);
    };
    let platform = context.platform.trim().to_ascii_lowercase();
    if platform != "android" && platform != "ios" {
        return (Vec::new(), fallback);
    }
    let tool_context = ToolExecutionContext {
        files_dir: context.files_dir.clone(),
        workspace_files_dir: context.workspace_files_dir.clone(),
        agent_id: context.agent_id.clone(),
        session_key_json: None,
    };
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if !crate::platform_capabilities::is_platform_tool(tool_name) {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let bridge = bridge.clone();
        let tool_context = tool_context.clone();
        let tool_name = tool_name.to_string();
        Some(Box::pin(async move {
            let output = request_host_tool_execution_with_context(
                bridge,
                &tool_name,
                params,
                Duration::from_secs(600),
                Some(&tool_context),
            )
            .await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (
        crate::platform_capabilities::platform_tool_descriptors(),
        Some(handler),
    )
}

pub(super) fn media_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let files_dir = context.files_dir.clone();
    let workspace_files_dir = context.workspace_files_dir.clone();
    let llm_config = context.llm_config.clone();
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if !crate::media_tools::is_media_tool(tool_name) {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let files_dir = files_dir.clone();
        let workspace_files_dir = workspace_files_dir.clone();
        let llm_config = llm_config.clone();
        let tool_name = tool_name.to_string();
        Some(Box::pin(async move {
            let (output, events) = crate::media_tools::execute(
                &files_dir,
                &workspace_files_dir,
                &llm_config,
                &tool_name,
                params,
            )
            .await?;
            Ok(InternalToolResult { output, events })
        }))
    });
    (
        crate::media_tools::descriptors(&context.llm_config),
        Some(handler),
    )
}

async fn ensure_http_request_allowed(
    params: &serde_json::Value,
    approval_bridge: Option<ToolRequestBridge>,
) -> Result<(), String> {
    if !crate::http_tool::requires_explicit_approval(params) {
        return Ok(());
    }
    let Some(bridge) = approval_bridge else {
        return Err(
            "mutating HTTP requests require explicit approval and no approval bridge is registered"
                .to_string(),
        );
    };
    let response = request_host_tool_execution(
        bridge,
        APPROVAL_TOOL_NAME,
        serde_json::json!({
            "tool_name": "http",
            "description": "Approve mutating HTTP request",
            "parameters": params.to_string(),
            "allow_always": false
        }),
        Duration::from_secs(600),
    )
    .await?;
    parse_approval_response(&response)
}
