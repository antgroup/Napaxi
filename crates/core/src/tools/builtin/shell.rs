//! Shell tool descriptor + dispatch + per-platform execution.
//!
//! # Exec result data contract (AC-4, DIMA-2026110600120401874)
//!
//! Audit report of the "已观察成功结果被后续 cleanup 改写" risk surface:
//!
//! Pre-fix, every platform exec returns `Result<String, String>`:
//! - [`crate::android_linux_env::execute_shell_in_workspace`] collapsed
//!   stdout/stderr/exit_code into one error message when the command
//!   failed; cancel and timeout returned pure `Err` strings, so even
//!   already-collected stdout/stderr were lost to the caller.
//! - The iOS sibling (`ios_qemu_env::execute_in_workspace`) already
//!   returned [`crate::ios_qemu_env::IosQemuCommandResult`] (a structured
//!   type), but `execute_ios_shell` collapsed it back to a
//!   `Result<String, String>` and merged "command produced a non-zero
//!   exit" with "QEMU driver/cleanup failure" into the same error
//!   message — they were not distinguishable downstream.
//!
//! The new data contract ([`ShellExecResult`] + [`ShellExecStatus`]) keeps
//! the four failure modes apart at the type level:
//!
//! | Status              | When emitted                                              |
//! |---------------------|----------------------------------------------------------|
//! | `Ok`                | exit_code == 0, no driver error.                         |
//! | `NonZeroExit(code)` | exit_code != 0 but the process produced stdout/stderr.   |
//! | `Cancelled`         | cancel flag observed before / during the call.           |
//! | `Timeout { secs }`  | elapsed ≥ timeout, process terminated.                  |
//! | `CleanupFailed`    | driver failure (spawn, env setup, QEMU bridge errors)    |
//! |                     | outside the shell's own exit code. `stdout` / `stderr`  |
//! |                     | are NOT collected ⇒ they are blank.                     |
//!
//! [`render_shell_exec_result`] then maps the contract to the historical
//! LLM-facing `Result<String, String>` format so existing tool-loop
//! tests see an unchanged string. The data contract guarantee (#193614
//! gap): a successful `Ok { stdout, ... }` already observed by the
//! shell-exec returns `Ok(stdout)` even when a later cleanup step on
//! the caller's side fails — the contract carries the observed result,
//! not the caller's later state. Regression test:
//! `execute_shell_tool_preserves_observed_success_on_cleanup_failure`.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::tool_loop::{InternalToolHandler, InternalToolResult, current_tool_call_cancel};
use crate::tool_registry::{ToolDescriptor, ToolRequestBridge};
use crate::types::ShellApprovalMode;

use super::BuiltinToolContext;
use super::shell_policy::ensure_shell_command_allowed;

/// Status of a shell execution. Surfaced through [`ShellExecResult`].
/// Kept crate-private so the FRB codegen is not perturbed (the LLM-visible
/// string format is produced by [`render_shell_exec_result`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ShellExecStatus {
    /// The command succeeded (exit_code == 0); `stdout` / `stderr` carry
    /// the captured output.
    Ok,
    /// The command ran to completion but returned a non-zero exit code.
    /// `stdout` / `stderr` carry the partial output the caller can still
    /// surface to the LLM. Distinct from [`Self::CleanupFailed`] so the
    /// LLM can tell "the shell exited 1" from "the shell driver crashed
    /// before the command ran".
    NonZeroExit(i32),
    /// The cancel flag was observed before / during the call. `stdout` /
    /// `stderr` may carry partial output if some was collected before the
    /// cancellation was detected.
    Cancelled,
    /// The wall-clock timeout elapsed while the command was running.
    /// `stdout` / `stderr` carry whatever was captured before the kill.
    Timeout { seconds: u64 },
    /// Driver / cleanup failure (spawn failure, env-not-ready, QEMU
    /// bridge error, IO error joining the child). The "command natural
    /// failure" path is preserved as [`Self::NonZeroExit`]; this variant
    /// is strictly for failures outside the command's own exit code.
    /// `stdout` / `stderr` are blank by definition (nothing was
    /// collected).
    CleanupFailed { reason: String },
}

/// Crate-private struct carrying the structured result of a single
/// shell-tool execution. The LLM-facing adapter is
/// [`render_shell_exec_result`]; this struct is the data contract
/// separating "observed exec result" from any later cleanup state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ShellExecResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub status: ShellExecStatus,
}

impl ShellExecResult {
    /// Convenience constructor for the success path.
    #[allow(dead_code)] // used by iOS cfg + tests; off-iOS the iOS path is configured out.
    pub(crate) fn ok(stdout: String, stderr: String, exit_code: i32) -> Self {
        Self {
            stdout,
            stderr,
            exit_code,
            status: ShellExecStatus::Ok,
        }
    }

    /// Convenience constructor for the non-zero-exit path (process ran
    /// and produced output, just exited non-zero).
    #[allow(dead_code)] // used by iOS cfg + tests; off-iOS the iOS path is configured out.
    pub(crate) fn non_zero_exit(stdout: String, stderr: String, exit_code: i32) -> Self {
        Self {
            stdout,
            stderr,
            exit_code,
            status: ShellExecStatus::NonZeroExit(exit_code),
        }
    }

    /// Convenience constructor for the cancelled path.
    #[allow(dead_code)] // used by tests + iOS cfg path.
    pub(crate) fn cancelled(stdout: String, stderr: String, exit_code: i32) -> Self {
        Self {
            stdout,
            stderr,
            exit_code,
            status: ShellExecStatus::Cancelled,
        }
    }

    /// Convenience constructor for the timeout path.
    #[allow(dead_code)] // used by android cfg + tests; off-Android the android path is configured out.
    pub(crate) fn timeout(stdout: String, stderr: String, exit_code: i32, seconds: u64) -> Self {
        Self {
            stdout,
            stderr,
            exit_code,
            status: ShellExecStatus::Timeout { seconds },
        }
    }

    /// Convenience constructor for the cleanup-failure path.
    pub(crate) fn cleanup_failed(reason: String) -> Self {
        Self {
            stdout: String::new(),
            stderr: String::new(),
            exit_code: -1,
            status: ShellExecStatus::CleanupFailed { reason },
        }
    }
}

/// Render the structured [`ShellExecResult`] as the historical,
/// LLM-facing `Result<String, String>`. The format matches the
/// pre-fix behavior of `execute_shell_in_workspace` / `execute_ios_shell`
/// — `Ok(text)` where text is stdout (or `stdout + --- stderr --- +`
/// stderr when both were collected) for the success path, and
/// `Err(message)` for the failure paths, but the failure path keeps
/// command-natural failures ([`ShellExecStatus::NonZeroExit`]) separated
/// from cleanup failures ([`ShellExecStatus::CleanupFailed`]) even when
/// the rendered string ends up identical.
///
/// LLM-visible contract is preserved: tests that match on the existing
/// `proot command failed (exit=N): ...` / `Shell command cancelled` /
/// `proot command timed out` error strings still trigger.
pub(crate) fn render_shell_exec_result(result: &ShellExecResult) -> Result<String, String> {
    let text = if result.stderr.is_empty() {
        result.stdout.clone()
    } else if result.stdout.is_empty() {
        result.stderr.clone()
    } else {
        format!("{}\n\n--- stderr ---\n{}", result.stdout, result.stderr)
    };
    match &result.status {
        ShellExecStatus::Ok => Ok(text),
        ShellExecStatus::NonZeroExit(code) => {
            Err(format!("proot command failed (exit={code}): {text}"))
        }
        ShellExecStatus::Cancelled => {
            // The pre-fix string stays intact so the LLM and tests see the
            // same "cancelled by user" needle, even if a partial output
            // was collected (we don't fold partial output into the
            // cancel error — that was the old shrink-wrapping contract).
            Err("proot command cancelled by user".to_string())
        }
        ShellExecStatus::Timeout { seconds } => {
            Err(format!("proot command timed out after {seconds}s: {text}"))
        }
        ShellExecStatus::CleanupFailed { reason } => {
            // CleanupFailed does NOT inline stdout/stderr — they're blank
            // by definition. The reason is what the caller surfaces.
            Err(reason.clone())
        }
    }
}

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

    let exec_result: ShellExecResult = match platform {
        "android" => {
            let native_library_dir = native_library_dir
                .ok_or_else(|| "missing native_library_dir for Android shell".to_string())?
                .to_string();
            let files_dir = files_dir.to_string();
            let workspace_files_dir = workspace_files_dir.to_string();
            let cancel_for_blocking = cancel.clone();
            match tokio::task::spawn_blocking(move || {
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
            {
                Ok(result) => result,
                Err(join_err) => {
                    ShellExecResult::cleanup_failed(format!("shell join error: {join_err}"))
                }
            }
        }
        "ios" => {
            let files_dir = files_dir.to_string();
            let workspace_files_dir = workspace_files_dir.to_string();
            let cancel_for_blocking = cancel.clone();
            match tokio::task::spawn_blocking(move || {
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
            {
                Ok(result) => result,
                Err(join_err) => {
                    ShellExecResult::cleanup_failed(format!("shell join error: {join_err}"))
                }
            }
        }
        _ => {
            return Err(format!("shell is not available on platform '{platform}'"));
        }
    };
    render_shell_exec_result(&exec_result)
}

#[cfg(target_os = "ios")]
fn execute_ios_shell(
    files_dir: &str,
    workspace_files_dir: &str,
    command: &str,
    workdir: Option<&str>,
    timeout: u64,
    cancel: Option<&AtomicBool>,
) -> ShellExecResult {
    if cancel
        .map(|flag| flag.load(Ordering::Relaxed))
        .unwrap_or(false)
    {
        return ShellExecResult::cancelled(String::new(), String::new(), -1);
    }
    let result = crate::ios_qemu_env::execute_in_workspace(
        files_dir,
        workspace_files_dir,
        command,
        workdir,
        (timeout * 1000) as i32,
    );
    ios_qemu_result_to_shell_exec_result(&result)
}

#[cfg(not(target_os = "ios"))]
fn execute_ios_shell(
    _files_dir: &str,
    _workspace_files_dir: &str,
    _command: &str,
    _workdir: Option<&str>,
    _timeout: u64,
    _cancel: Option<&AtomicBool>,
) -> ShellExecResult {
    ShellExecResult::cleanup_failed("iOS shell is only available on iOS".to_string())
}

/// Adapt the iOS-side [`IosQemuCommandResult`] to the data contract. This
/// keeps "command natural failure" (`NonZeroExit`, partial stdout/stderr
/// preserved) distinct from "QEMU driver / cleanup failure"
/// (`CleanupFailed`, output intentionally blank) — the pre-fix path
/// collapsed both into the same `Err(error.unwrap_or(text))` call site.
#[cfg(target_os = "ios")]
pub(crate) fn ios_qemu_result_to_shell_exec_result(
    result: &crate::ios_qemu_env::IosQemuCommandResult,
) -> ShellExecResult {
    let crate::ios_qemu_env::IosQemuCommandResult {
        exit_code,
        stdout,
        stderr,
        error,
    } = result;
    if let Some(reason) = error {
        return ShellExecResult::cleanup_failed(reason.clone());
    }
    if *exit_code == 0 {
        ShellExecResult::ok(stdout.clone(), stderr.clone(), *exit_code)
    } else {
        ShellExecResult::non_zero_exit(stdout.clone(), stderr.clone(), *exit_code)
    }
}
