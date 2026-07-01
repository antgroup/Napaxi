//! Host and platform tool API.
//!
//! Two layers (mirrors `api::engine`):
//!
//! - **Legacy JSON layer**: `*_descriptors_json` / `is_*_tool` /
//!   `answer_human_request` keep their pre-typed shapes for the FRB bridge.
//! - **Typed layer**: descriptors come back as `Vec<ToolDescriptor>`
//!   directly (no JSON round-trip); `answer_human_request_typed` returns a
//!   `CoreResult<()>` with a stable `ToolError::NotFound` for unknown
//!   request ids instead of collapsing into `false`.

use crate::error::{CoreResult, ToolError};
pub use crate::tool_registry::{ToolDescriptor, ToolRequestDispatcher, resolve_tool_execution};
use serde::Deserialize;
use serde_json::json;

/// Inject a host response for a pending human-in-the-loop request; returns
/// whether a matching pending request was found.
pub fn answer_human_request(request_id: &str, response: &str) -> bool {
    crate::human_loop::answer_human_request(request_id, response)
}

/// Typed counterpart: `Err(ToolError::NotFound)` when the request id is not
/// pending (either never registered or already answered), `Ok(())` on
/// successful injection.
pub fn answer_human_request_typed(request_id: &str, response: &str) -> CoreResult<()> {
    if crate::human_loop::answer_human_request(request_id, response) {
        Ok(())
    } else {
        Err(ToolError::NotFound(format!("human_request {request_id}")).into())
    }
}

/// Platform (host-provided) tool descriptors as a JSON array.
pub fn platform_tool_descriptors_json() -> String {
    crate::platform_capabilities::platform_tool_descriptors_json()
}

/// Typed counterpart: returns the descriptors directly without a JSON
/// round-trip. Adapter code that does not need to forward the JSON to Dart
/// should prefer this.
pub fn platform_tool_descriptors() -> Vec<ToolDescriptor> {
    crate::platform_capabilities::platform_tool_descriptors()
}

/// Whether `name` is a registered platform tool.
pub fn is_platform_tool(name: &str) -> bool {
    crate::platform_capabilities::is_platform_tool(name)
}

/// Built-in browser tool descriptors as a JSON array.
pub fn browser_tool_descriptors_json() -> String {
    crate::browser_tools::browser_tool_descriptors_json()
}

/// Typed counterpart: returns the descriptors directly without a JSON
/// round-trip.
pub fn browser_tool_descriptors() -> Vec<ToolDescriptor> {
    crate::browser_tools::browser_tool_descriptors()
}

/// Whether `name` is a built-in browser tool.
pub fn is_browser_tool(name: &str) -> bool {
    crate::browser_tools::is_browser_tool(name)
}

/// Broker call: list the tools an agent engine exposes (JSON in, JSON out).
pub async fn tool_broker_list_tools_json_handle(handle: i64, request_json: &str) -> String {
    crate::agent_engine::list_tools_json_handle(handle, request_json).await
}

/// Broker call: invoke a tool on an agent engine (JSON in, JSON out).
pub async fn tool_broker_call_tool_json_handle(handle: i64, request_json: &str) -> String {
    crate::agent_engine::call_tool_json_handle(handle, request_json).await
}

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
#[derive(Debug, Deserialize)]
struct LinuxProgramRequest {
    files_dir: String,
    native_library_dir: String,
    workspace_dir: String,
    argv: Vec<String>,
    workdir: Option<String>,
    timeout: Option<u64>,
}

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
#[derive(Debug, Deserialize)]
struct LinuxPtyOpenRequest {
    files_dir: String,
    native_library_dir: String,
    workspace_dir: String,
    argv: Vec<String>,
    workdir: Option<String>,
    cols: Option<u16>,
    rows: Option<u16>,
}

/// Execute a native Linux program request encoded as JSON, returning JSON.
pub fn execute_linux_program_json(request_json: &str) -> String {
    let started_at = std::time::Instant::now();
    let request: LinuxProgramRequest = match serde_json::from_str(request_json) {
        Ok(request) => request,
        Err(error) => {
            return json!({
                "success": false,
                "providerAvailable": false,
                "exitCode": -1,
                "stdout": "",
                "stderr": "",
                "durationMs": started_at.elapsed().as_millis() as u64,
                "error": format!("invalid Linux program request: {error}"),
            })
            .to_string();
        }
    };
    execute_linux_program_request(request, started_at)
}

/// Open an Android Linux PTY session from a JSON request, returning JSON.
pub fn open_linux_pty_session_json(request_json: &str) -> String {
    let request: LinuxPtyOpenRequest = match serde_json::from_str(request_json) {
        Ok(request) => request,
        Err(error) => {
            return json!({
                "success": false,
                "sessionId": null,
                "error": format!("invalid Linux PTY open request: {error}"),
            })
            .to_string();
        }
    };
    open_linux_pty_session_request(request)
}

/// Write UTF-8 input to an Android Linux PTY session, returning JSON status.
pub fn write_linux_pty_session_json(session_id: u64, data: &str) -> String {
    pty_command_result(write_linux_pty_session(session_id, data))
}

/// Resize an Android Linux PTY session, returning JSON status.
pub fn resize_linux_pty_session_json(session_id: u64, cols: u16, rows: u16) -> String {
    pty_command_result(resize_linux_pty_session(session_id, cols, rows))
}

/// Close an Android Linux PTY session, returning JSON status.
pub fn close_linux_pty_session_json(session_id: u64) -> String {
    pty_command_result(close_linux_pty_session(session_id))
}

/// Drain queued Android Linux PTY events for a session, returning JSON.
pub fn drain_linux_pty_events_json(session_id: u64) -> String {
    drain_linux_pty_events(session_id)
}

#[cfg(target_os = "android")]
fn execute_linux_program_request(
    request: LinuxProgramRequest,
    started_at: std::time::Instant,
) -> String {
    match crate::android_linux_env::execute_program_in_workspace_dir(
        &request.files_dir,
        &request.native_library_dir,
        &request.workspace_dir,
        &request.argv,
        request.workdir.as_deref(),
        request.timeout.unwrap_or(120),
        None,
    ) {
        Ok(output) => json!({
            "success": output.exit_code == 0,
            "providerAvailable": true,
            "exitCode": output.exit_code,
            "stdout": output.stdout.trim(),
            "stderr": output.stderr.trim(),
            "durationMs": started_at.elapsed().as_millis() as u64,
        })
        .to_string(),
        Err(error) => json!({
            "success": false,
            "providerAvailable": false,
            "exitCode": -1,
            "stdout": "",
            "stderr": "",
            "durationMs": started_at.elapsed().as_millis() as u64,
            "error": error.to_string(),
        })
        .to_string(),
    }
}

#[cfg(target_os = "android")]
fn open_linux_pty_session_request(request: LinuxPtyOpenRequest) -> String {
    match crate::android_linux_env::pty::open_pty_session(
        &request.files_dir,
        &request.native_library_dir,
        &request.workspace_dir,
        &request.argv,
        request.workdir.as_deref(),
        request.cols.unwrap_or(80),
        request.rows.unwrap_or(24),
    ) {
        Ok(session_id) => json!({
            "success": true,
            "providerAvailable": true,
            "sessionId": session_id,
        })
        .to_string(),
        Err(error) => json!({
            "success": false,
            "providerAvailable": false,
            "sessionId": null,
            "error": error.to_string(),
        })
        .to_string(),
    }
}

#[cfg(target_os = "android")]
fn write_linux_pty_session(session_id: u64, data: &str) -> anyhow::Result<()> {
    crate::android_linux_env::pty::write_pty_session(session_id, data)
}

#[cfg(target_os = "android")]
fn resize_linux_pty_session(session_id: u64, cols: u16, rows: u16) -> anyhow::Result<()> {
    crate::android_linux_env::pty::resize_pty_session(session_id, cols, rows)
}

#[cfg(target_os = "android")]
fn close_linux_pty_session(session_id: u64) -> anyhow::Result<()> {
    crate::android_linux_env::pty::close_pty_session(session_id)
}

#[cfg(target_os = "android")]
fn drain_linux_pty_events(session_id: u64) -> String {
    match crate::android_linux_env::pty::drain_pty_events(session_id) {
        Ok(events) => json!({
            "success": true,
            "events": events.into_iter().map(|event| json!({
                "sessionId": event.session_id,
                "kind": match event.kind {
                    crate::android_linux_env::pty::PtyEventKind::Output => "SessionOutput",
                    crate::android_linux_env::pty::PtyEventKind::Exit => "SessionExit",
                    crate::android_linux_env::pty::PtyEventKind::Closed => "SessionClosed",
                    crate::android_linux_env::pty::PtyEventKind::Log => "SessionLog",
                },
                "data": event.data,
                "exitCode": event.exit_code,
            })).collect::<Vec<_>>(),
        })
        .to_string(),
        Err(error) => json!({
            "success": false,
            "events": [],
            "error": error.to_string(),
        })
        .to_string(),
    }
}

#[cfg(not(target_os = "android"))]
fn execute_linux_program_request(
    _request: LinuxProgramRequest,
    started_at: std::time::Instant,
) -> String {
    json!({
        "success": false,
        "providerAvailable": false,
        "exitCode": -1,
        "stdout": "",
        "stderr": "",
        "durationMs": started_at.elapsed().as_millis() as u64,
        "error": "Linux program execution is only available on Android",
    })
    .to_string()
}

#[cfg(not(target_os = "android"))]
fn open_linux_pty_session_request(_request: LinuxPtyOpenRequest) -> String {
    json!({
        "success": false,
        "providerAvailable": false,
        "sessionId": null,
        "error": "Linux PTY sessions are only available on Android",
    })
    .to_string()
}

#[cfg(not(target_os = "android"))]
fn write_linux_pty_session(_session_id: u64, _data: &str) -> anyhow::Result<()> {
    anyhow::bail!("Linux PTY sessions are only available on Android")
}

#[cfg(not(target_os = "android"))]
fn resize_linux_pty_session(_session_id: u64, _cols: u16, _rows: u16) -> anyhow::Result<()> {
    anyhow::bail!("Linux PTY sessions are only available on Android")
}

#[cfg(not(target_os = "android"))]
fn close_linux_pty_session(_session_id: u64) -> anyhow::Result<()> {
    anyhow::bail!("Linux PTY sessions are only available on Android")
}

#[cfg(not(target_os = "android"))]
fn drain_linux_pty_events(_session_id: u64) -> String {
    json!({
        "success": false,
        "events": [],
        "error": "Linux PTY sessions are only available on Android",
    })
    .to_string()
}

fn pty_command_result(result: anyhow::Result<()>) -> String {
    match result {
        Ok(()) => json!({"success": true}).to_string(),
        Err(error) => json!({
            "success": false,
            "error": error.to_string(),
        })
        .to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn answer_human_request_typed_reports_not_found() {
        let err = answer_human_request_typed("missing-id", "hi").unwrap_err();
        assert_eq!(err.code(), "tool_not_found");
    }

    #[test]
    fn answer_human_request_legacy_returns_false_for_missing() {
        assert!(!answer_human_request("missing-id", "hi"));
    }

    #[test]
    fn descriptors_typed_match_json_count() {
        let typed = platform_tool_descriptors();
        let json = platform_tool_descriptors_json();
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        assert_eq!(typed.len(), parsed.len());
    }

    #[test]
    fn browser_descriptors_typed_match_json_count() {
        let typed = browser_tool_descriptors();
        let json = browser_tool_descriptors_json();
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        assert_eq!(typed.len(), parsed.len());
    }

    #[test]
    fn platform_tool_descriptors_json_is_valid_json_array() {
        let json = platform_tool_descriptors_json();
        assert!(json.starts_with('['), "should be JSON array: {json}");
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        for desc in &parsed {
            assert!(desc["name"].is_string());
        }
    }

    #[test]
    fn browser_tool_descriptors_json_is_valid_json_array() {
        let json = browser_tool_descriptors_json();
        assert!(json.starts_with('['));
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        for desc in &parsed {
            assert!(desc["name"].is_string());
        }
    }

    #[test]
    fn is_platform_tool_and_is_browser_tool_are_disjoint() {
        let platform = platform_tool_descriptors();
        let browser = browser_tool_descriptors();
        for t in &platform {
            assert!(is_platform_tool(&t.name));
            assert!(
                !is_browser_tool(&t.name),
                "{} should not be a browser tool",
                t.name
            );
        }
        for t in &browser {
            assert!(is_browser_tool(&t.name));
            assert!(
                !is_platform_tool(&t.name),
                "{} should not be a platform tool",
                t.name
            );
        }
        assert!(!is_platform_tool("nonexistent_tool"));
        assert!(!is_browser_tool("nonexistent_tool"));
    }

    #[tokio::test]
    async fn answer_human_request_typed_succeeds_for_pending_request() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy().to_string();
        let session_key_json =
            crate::session::create_session(&files_dir, "agent-a", "app", "user-a", None);
        let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
        let files_dir_for_task = files_dir.clone();
        let session_key_for_task = session_key_json.clone();

        let task = tokio::spawn(async move {
            crate::human_loop::execute_ask_human(
                &files_dir_for_task,
                &session_key_for_task,
                serde_json::json!({"question": "Proceed?", "options": ["yes"]}),
                |event| {
                    let _ = sender.send(event);
                },
            )
            .await
        });

        // execute_ask_human emits AskingHuman as its first event.
        let request_id = match receiver.recv().await.unwrap() {
            crate::types::ChatEvent::AskingHuman { request_id, .. } => request_id,
            other => panic!("expected AskingHuman, got {other:?}"),
        };

        // The typed wrapper returns Ok(()) when the request is answered.
        answer_human_request_typed(&request_id, "yes").expect("answer should succeed");
        let _ = task.await.unwrap();
    }

    #[tokio::test]
    async fn tool_broker_handles_do_not_panic_for_invalid_handle() {
        let list = tool_broker_list_tools_json_handle(0, "{}").await;
        assert!(!list.is_empty(), "list tools: {list}");
        let call = tool_broker_call_tool_json_handle(0, "{}").await;
        assert!(!call.is_empty(), "call tool: {call}");
    }
}
