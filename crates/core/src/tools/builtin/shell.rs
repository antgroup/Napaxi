//! Shell tool descriptor + dispatch + per-platform execution.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::tool_loop::{InternalToolHandler, InternalToolResult, current_tool_call_cancel};
use crate::tool_registry::{ToolDescriptor, ToolRequestBridge};
use crate::types::ShellApprovalMode;

use super::BuiltinToolContext;
use super::shell_policy::ensure_shell_command_allowed;

pub(super) fn shell_handler(
    context: &BuiltinToolContext,
    fallback: Option<InternalToolHandler>,
) -> (Vec<ToolDescriptor>, Option<InternalToolHandler>) {
    let files_dir = context.files_dir.clone();
    let workspace_files_dir = context.workspace_files_dir.clone();
    let platform = context.platform.clone();
    let native_library_dir = context.native_library_dir.clone();
    let approval_bridge = context.approval_bridge.clone();
    let approval_mode = context.llm_config.shell_security.approval_mode;
    let handler: InternalToolHandler = Arc::new(move |tool_name, params, _progress| {
        if tool_name != "shell" {
            return fallback
                .as_ref()
                .and_then(|fallback| fallback(tool_name, params, None));
        }
        let files_dir = files_dir.clone();
        let workspace_files_dir = workspace_files_dir.clone();
        let platform = platform.clone();
        let native_library_dir = native_library_dir.clone();
        let approval_bridge = approval_bridge.clone();
        Some(Box::pin(async move {
            let cancel = current_tool_call_cancel();
            let output = execute_shell_tool(
                &files_dir,
                &workspace_files_dir,
                &platform,
                native_library_dir.as_deref(),
                params,
                approval_mode,
                approval_bridge,
                cancel,
            )
            .await?;
            Ok(InternalToolResult {
                output,
                events: Vec::new(),
            })
        }))
    });
    (vec![shell_tool_descriptor()], Some(handler))
}

pub fn shell_tool_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "shell".to_string(),
        description: "Execute a shell command in the mobile Linux environment. Use /workspace for persistent files and /skills for installed skill files. Default workdir is /workspace. Commands must finish; do not start long-running local servers or dev servers in the foreground shell.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "Shell command to execute, for example `ls -la /workspace`."
                },
                "workdir": {
                    "type": "string",
                    "description": "Working directory. Defaults to /workspace."
                },
                "timeout": {
                    "type": "integer",
                    "description": "Timeout in seconds. Defaults to 120.",
                    "minimum": 1,
                    "maximum": 600
                }
            },
            "required": ["command"]
        }),
        effect: crate::tool_registry::ToolEffect::Execute,
    }
}

async fn execute_shell_tool(
    files_dir: &str,
    workspace_files_dir: &str,
    platform: &str,
    native_library_dir: Option<&str>,
    params: serde_json::Value,
    approval_mode: ShellApprovalMode,
    approval_bridge: Option<ToolRequestBridge>,
    cancel: Option<Arc<AtomicBool>>,
) -> Result<String, String> {
    let command = params
        .get("command")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "shell command is required".to_string())?
        .to_string();
    ensure_shell_command_allowed(&command, approval_mode, approval_bridge).await?;
    if cancel
        .as_ref()
        .map(|flag| flag.load(Ordering::Relaxed))
        .unwrap_or(false)
    {
        return Err("Shell command cancelled before execution".to_string());
    }
    let workdir = params
        .get("workdir")
        .and_then(serde_json::Value::as_str)
        .map(str::to_string);
    let timeout = params
        .get("timeout")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(120)
        .clamp(1, 600);

    match platform {
        "android" => {
            let native_library_dir = native_library_dir
                .ok_or_else(|| "missing native_library_dir for Android shell".to_string())?
                .to_string();
            let files_dir = files_dir.to_string();
            let workspace_files_dir = workspace_files_dir.to_string();
            let cancel_for_blocking = cancel.clone();
            tokio::task::spawn_blocking(move || {
                crate::android_linux_env::execute_shell_in_workspace(
                    &files_dir,
                    &native_library_dir,
                    &workspace_files_dir,
                    &command,
                    workdir.as_deref(),
                    timeout,
                    cancel_for_blocking.as_deref(),
                )
            })
            .await
            .map_err(|e| format!("shell join error: {e}"))?
            .map_err(|e| e.to_string())
        }
        "ios" => {
            let files_dir = files_dir.to_string();
            let workspace_files_dir = workspace_files_dir.to_string();
            let cancel_for_blocking = cancel.clone();
            tokio::task::spawn_blocking(move || {
                execute_ios_shell(
                    &files_dir,
                    &workspace_files_dir,
                    &command,
                    workdir.as_deref(),
                    timeout,
                    cancel_for_blocking.as_deref(),
                )
            })
            .await
            .map_err(|e| format!("shell join error: {e}"))?
        }
        _ => Err(format!("shell is not available on platform '{platform}'")),
    }
}

#[cfg(target_os = "ios")]
fn execute_ios_shell(
    files_dir: &str,
    workspace_files_dir: &str,
    command: &str,
    workdir: Option<&str>,
    timeout: u64,
    cancel: Option<&AtomicBool>,
) -> Result<String, String> {
    if cancel
        .map(|flag| flag.load(Ordering::Relaxed))
        .unwrap_or(false)
    {
        return Err("Shell command cancelled before execution".to_string());
    }
    let result = crate::ios_ish_env::execute_in_workspace(
        files_dir,
        workspace_files_dir,
        command,
        workdir,
        (timeout * 1000) as i32,
    );
    let text = if result.stderr.trim().is_empty() {
        result.stdout
    } else if result.stdout.trim().is_empty() {
        result.stderr
    } else {
        format!("{}\n\n--- stderr ---\n{}", result.stdout, result.stderr)
    };
    if result.exit_code == 0 && result.error.is_none() {
        Ok(text)
    } else {
        Err(result.error.unwrap_or(text))
    }
}

#[cfg(not(target_os = "ios"))]
fn execute_ios_shell(
    _files_dir: &str,
    _workspace_files_dir: &str,
    _command: &str,
    _workdir: Option<&str>,
    _timeout: u64,
    _cancel: Option<&AtomicBool>,
) -> Result<String, String> {
    Err("iOS shell is only available on iOS".to_string())
}
