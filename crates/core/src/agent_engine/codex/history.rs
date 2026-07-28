#![cfg_attr(not(any(target_os = "android", test)), allow(dead_code))]

use serde::Deserialize;
use serde_json::{Map, Value, json};

const HISTORY_OPERATION_PREFIX: &str = "history_";
#[cfg(target_os = "android")]
const CODEX_WORKSPACE: &str = "/workspace";

#[cfg(target_os = "android")]
use std::time::{Duration, Instant};

#[cfg(target_os = "android")]
use super::config;
#[cfg(target_os = "android")]
use super::protocol::{
    JsonRpcClient, initialize_request, initialized_notification, parse_json_lines, response_error,
    response_id, thread_history_resume_request, thread_list_request, thread_read_request,
};
#[cfg(target_os = "android")]
use super::state::{bind_native_thread, current_config_fingerprint, native_library_dir_for};

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
#[derive(Debug, Default, Deserialize)]
struct CodexHistoryRequest {
    #[serde(default)]
    operation: String,
    #[serde(default)]
    thread_id: String,
    #[serde(default)]
    account_id: String,
    #[serde(default)]
    agent_id: String,
    #[serde(default)]
    session_key_json: String,
}

pub(crate) fn is_history_request(raw: &str) -> bool {
    serde_json::from_str::<Value>(raw)
        .ok()
        .and_then(|value| value.get("operation")?.as_str().map(str::to_string))
        .is_some_and(|operation| operation.starts_with(HISTORY_OPERATION_PREFIX))
}

pub(crate) fn handle_request_json(handle: i64, raw: &str) -> String {
    let request = match serde_json::from_str::<CodexHistoryRequest>(raw) {
        Ok(request) => request,
        Err(error) => {
            return history_error(
                false,
                "history_query_failed",
                format!("Invalid Codex history request: {error}"),
            );
        }
    };
    handle_request(handle, request)
}

#[cfg(not(target_os = "android"))]
fn handle_request(_handle: i64, _request: CodexHistoryRequest) -> String {
    history_error(
        false,
        "unsupported_platform",
        "napaxi.agent_engine.codex is unsupported on this platform",
    )
}

#[cfg(target_os = "android")]
fn handle_request(handle: i64, request: CodexHistoryRequest) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return history_error(false, "unsupported_platform", "invalid engine handle");
    };
    match request.operation.as_str() {
        "history_list_threads" => list_threads(handle, &files_dir, &request),
        "history_read_thread" => read_thread(handle, &files_dir, &request),
        "history_bind_thread" => bind_thread(&files_dir, &request),
        _ => history_error(
            true,
            "history_query_failed",
            format!("Unknown Codex history operation: {}", request.operation),
        ),
    }
}

#[cfg(target_os = "android")]
fn list_threads(handle: i64, files_dir: &str, request: &CodexHistoryRequest) -> String {
    let mut rpc = match HistoryRpc::open(handle, files_dir, request) {
        Ok(rpc) => rpc,
        Err(error) => return history_error(true, "history_query_failed", error.to_string()),
    };
    let mut data = match rpc.list(Some(CODEX_WORKSPACE)) {
        Ok(data) => data,
        Err(error) => return history_error(true, "history_query_failed", error.to_string()),
    };
    if data.is_empty() {
        data = match rpc.list(None) {
            Ok(data) => data,
            Err(error) => return history_error(true, "history_query_failed", error.to_string()),
        };
    }
    let threads = data
        .iter()
        .filter_map(map_thread_summary)
        .collect::<Vec<_>>();
    history_success(json!({"threads": threads}))
}

#[cfg(target_os = "android")]
fn read_thread(handle: i64, files_dir: &str, request: &CodexHistoryRequest) -> String {
    let thread_id = request.thread_id.trim();
    if thread_id.is_empty() {
        return history_error(true, "missing_native_thread", "Codex thread ID is required");
    }
    let mut rpc = match HistoryRpc::open(handle, files_dir, request) {
        Ok(rpc) => rpc,
        Err(error) => return history_error(true, "history_query_failed", error.to_string()),
    };
    let resume = rpc.resume(thread_id).ok();
    let mut items = extract_thread_items(resume.as_ref());
    if items.is_empty() {
        let read = match rpc.read(thread_id) {
            Ok(read) => read,
            Err(error) => return history_error(true, "history_query_failed", error.to_string()),
        };
        items = extract_thread_items(Some(&read));
    }
    let messages = items
        .iter()
        .filter_map(map_history_item)
        .collect::<Vec<_>>();
    history_success(json!({"nativeThreadId": thread_id, "messages": messages}))
}

#[cfg(target_os = "android")]
fn bind_thread(files_dir: &str, request: &CodexHistoryRequest) -> String {
    let thread_id = request.thread_id.trim();
    if thread_id.is_empty() || request.session_key_json.trim().is_empty() {
        return history_error(
            true,
            "missing_native_thread",
            "Codex thread ID and session key are required",
        );
    }
    let Some(fingerprint) = current_config_fingerprint(files_dir) else {
        return history_error(
            true,
            "missing_main_model",
            "Codex main model configuration must be synchronized before binding history",
        );
    };
    bind_native_thread(
        files_dir,
        normalized_account_id(&request.account_id),
        normalized_agent_id(&request.agent_id),
        &request.session_key_json,
        thread_id,
        &fingerprint,
    );
    history_success(json!({"nativeThreadId": thread_id}))
}

#[cfg(target_os = "android")]
struct HistoryRpc {
    pty: u64,
    rpc: JsonRpcClient,
    buffer: String,
}

#[cfg(target_os = "android")]
impl HistoryRpc {
    fn open(handle: i64, files_dir: &str, request: &CodexHistoryRequest) -> anyhow::Result<Self> {
        let config_dir = config::config_dir(files_dir);
        if !config_dir.join("config.toml").is_file() || !config_dir.join("auth.json").is_file() {
            anyhow::bail!("Codex sandbox configuration is missing");
        }
        let native_library_dir = native_library_dir_for(files_dir).ok_or_else(|| {
            anyhow::anyhow!("missing native_library_dir for Android Codex history")
        })?;
        let workspace_files_dir =
            crate::runtime::default_engine_workspace_files_dir_from_handle(handle)
                .unwrap_or_else(|| files_dir.to_string());
        let workspace_dir = crate::storage::FileBridge::new_with_workspace_files_dir(
            files_dir,
            &workspace_files_dir,
        )
        .workspace_dir()
        .display()
        .to_string();
        let argv = vec![
            "/bin/sh".to_string(),
            "-lc".to_string(),
            "mkdir -p /workspace /root/.codex && stty raw -echo -icanon -ixon -ixoff 2>/dev/null; export HOME=/root CODEX_HOME=/root/.codex PATH=\"/root/.local/bin:$PATH\"; exec codex app-server 2>&1".to_string(),
        ];
        let pty = crate::android_linux_env::pty::open_pty_session(
            files_dir,
            &native_library_dir,
            &workspace_dir,
            &argv,
            Some(CODEX_WORKSPACE),
            120,
            40,
        )?;
        let mut rpc = JsonRpcClient::new();
        let (initialize_id, initialize) = initialize_request(&mut rpc);
        let mut history_rpc = Self {
            pty,
            rpc,
            buffer: String::new(),
        };
        history_rpc.call(initialize_id, &initialize, Duration::from_secs(15))?;
        let initialized = initialized_notification(&history_rpc.rpc);
        crate::android_linux_env::pty::write_pty_session(pty, &(initialized + "\n"))?;
        Ok(history_rpc)
    }

    fn list(&mut self, cwd: Option<&str>) -> anyhow::Result<Vec<Value>> {
        let (id, line) = thread_list_request(&mut self.rpc, cwd);
        let result = self.call(id, &line, Duration::from_secs(10))?;
        Ok(result
            .get("data")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default())
    }

    fn resume(&mut self, thread_id: &str) -> anyhow::Result<Value> {
        let (id, line) = thread_history_resume_request(&mut self.rpc, thread_id);
        self.call(id, &line, Duration::from_secs(15))
    }

    fn read(&mut self, thread_id: &str) -> anyhow::Result<Value> {
        let (id, line) = thread_read_request(&mut self.rpc, thread_id);
        self.call(id, &line, Duration::from_secs(15))
    }

    fn call(&mut self, id: u64, line: &str, timeout: Duration) -> anyhow::Result<Value> {
        crate::android_linux_env::pty::write_pty_session(self.pty, &(line.to_string() + "\n"))?;
        let started = Instant::now();
        while started.elapsed() < timeout {
            for event in crate::android_linux_env::pty::drain_pty_events(self.pty)? {
                match event.kind {
                    crate::android_linux_env::pty::PtyEventKind::Output => {
                        for message in parse_json_lines(&mut self.buffer, &event.data) {
                            if response_id(&message) != Some(id) {
                                continue;
                            }
                            if let Some(error) = response_error(&message) {
                                anyhow::bail!(error);
                            }
                            return Ok(message.get("result").cloned().unwrap_or(Value::Null));
                        }
                    }
                    crate::android_linux_env::pty::PtyEventKind::Exit
                    | crate::android_linux_env::pty::PtyEventKind::Closed => {
                        anyhow::bail!("Codex app-server exited while reading history");
                    }
                    crate::android_linux_env::pty::PtyEventKind::Log => {}
                }
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        anyhow::bail!("Codex history request timed out")
    }
}

#[cfg(target_os = "android")]
impl Drop for HistoryRpc {
    fn drop(&mut self) {
        let _ = crate::android_linux_env::pty::close_pty_session_nonblocking(self.pty);
    }
}

#[cfg(target_os = "android")]
fn normalized_account_id(value: &str) -> &str {
    if value.trim().is_empty() {
        "default"
    } else {
        value
    }
}

#[cfg(target_os = "android")]
fn normalized_agent_id(value: &str) -> &str {
    if value.trim().is_empty() {
        "engine.codex"
    } else {
        value
    }
}

fn map_thread_summary(value: &Value) -> Option<Value> {
    let id = value.get("id")?.as_str()?.trim();
    if id.is_empty() {
        return None;
    }
    Some(json!({
        "id": id,
        "name": string_field(value, "name"),
        "preview": string_field(value, "preview"),
        "createdAt": timestamp_millis(value.get("createdAt")),
        "updatedAt": timestamp_millis(value.get("updatedAt")),
    }))
}

fn timestamp_millis(value: Option<&Value>) -> i64 {
    let raw = value.and_then(Value::as_f64).unwrap_or_default();
    if raw > 1_000_000_000_000.0 {
        raw as i64
    } else {
        (raw * 1000.0) as i64
    }
}

fn extract_thread_items(result: Option<&Value>) -> Vec<Value> {
    let Some(result) = result else {
        return Vec::new();
    };
    if let Some(turns) = result.pointer("/thread/turns").and_then(Value::as_array) {
        let items = turns
            .iter()
            .filter_map(|turn| turn.get("items").and_then(Value::as_array))
            .flatten()
            .filter(|item| item.get("type").is_some())
            .cloned()
            .collect::<Vec<_>>();
        if !items.is_empty() {
            return items;
        }
    }
    ["/thread/items", "/thread/content", "/items"]
        .iter()
        .find_map(|pointer| result.pointer(pointer).and_then(Value::as_array))
        .map(|items| {
            items
                .iter()
                .filter(|item| item.get("type").is_some())
                .cloned()
                .collect()
        })
        .unwrap_or_default()
}

fn map_history_item(item: &Value) -> Option<Value> {
    let kind = string_field(item, "type");
    let id = string_field(item, "id");
    let (role, content) = match kind.as_str() {
        "agentMessage" => ("assistant", string_field(item, "text")),
        "userMessage" => ("user", user_message_text(item)),
        "reasoning" => ("reasoning", reasoning_text(item)),
        "commandExecution" | "dynamicToolCall" | "mcpToolCall" | "fileChange" | "webSearch" => {
            ("tool_calls", tool_call_content(item, &kind, &id))
        }
        _ => {
            let content = item
                .get("text")
                .or_else(|| item.get("content"))
                .map(value_text)
                .unwrap_or_default();
            let role = if kind.to_ascii_lowercase().contains("user") {
                "user"
            } else {
                "assistant"
            };
            (role, content)
        }
    };
    if content.trim().is_empty() {
        return None;
    }
    let mut message = Map::from_iter([
        ("role".to_string(), Value::String(role.to_string())),
        ("content".to_string(), Value::String(content)),
    ]);
    if !id.is_empty() {
        message.insert("id".to_string(), Value::String(id));
    }
    Some(Value::Object(message))
}

fn user_message_text(item: &Value) -> String {
    if let Some(content) = item.get("content").and_then(Value::as_array) {
        return content
            .iter()
            .filter_map(|entry| {
                if let Some(text) = entry.as_str() {
                    return Some(text.to_string());
                }
                (entry.get("type").and_then(Value::as_str) == Some("text"))
                    .then(|| string_field(entry, "text"))
            })
            .filter(|text| !text.is_empty())
            .collect::<String>()
            .trim()
            .to_string();
    }
    item.get("text")
        .or_else(|| item.get("content"))
        .map(value_text)
        .unwrap_or_default()
}

fn reasoning_text(item: &Value) -> String {
    ["summary", "content"]
        .iter()
        .filter_map(|field| item.get(field).and_then(Value::as_array))
        .flatten()
        .map(value_text)
        .filter(|text| !text.trim().is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

fn tool_call_content(item: &Value, kind: &str, id: &str) -> String {
    let (name, arguments, output, failed, narrative) = match kind {
        "commandExecution" => {
            let arguments = json!({
                "cmd": string_field(item, "command"),
                "cwd": string_field(item, "cwd"),
            });
            let status = string_field(item, "status").to_ascii_lowercase();
            let failed = matches!(status.as_str(), "failed" | "rejected")
                || item
                    .get("exitCode")
                    .and_then(Value::as_i64)
                    .is_some_and(|code| code != 0);
            (
                "shell".to_string(),
                arguments.to_string(),
                string_field(item, "aggregatedOutput"),
                failed,
                "Ran command".to_string(),
            )
        }
        "dynamicToolCall" => {
            let namespace = string_field(item, "namespace");
            let tool = string_field(item, "tool");
            let name = if namespace.is_empty() {
                tool
            } else {
                format!("{namespace}.{tool}")
            };
            let status = string_field(item, "status").to_ascii_lowercase();
            let failed = matches!(status.as_str(), "failed" | "rejected")
                || item.get("success").and_then(Value::as_bool) == Some(false);
            let output = item
                .get("contentItems")
                .map(value_text)
                .unwrap_or_else(|| item.to_string());
            (
                name.clone(),
                item.get("arguments")
                    .cloned()
                    .unwrap_or(Value::Null)
                    .to_string(),
                output,
                failed,
                format!("Called {name}"),
            )
        }
        "mcpToolCall" => {
            let name = format!(
                "{}.{}",
                string_field(item, "server"),
                string_field(item, "tool")
            );
            let status = string_field(item, "status").to_ascii_lowercase();
            (
                name.clone(),
                item.get("arguments")
                    .cloned()
                    .unwrap_or_else(|| json!({}))
                    .to_string(),
                item.get("result")
                    .or_else(|| item.get("error"))
                    .map(value_text)
                    .unwrap_or_default(),
                matches!(status.as_str(), "failed" | "rejected"),
                format!("Called {name}"),
            )
        }
        "fileChange" => {
            let status = string_field(item, "status").to_ascii_lowercase();
            let failed = matches!(status.as_str(), "failed" | "rejected");
            (
                "fileChange".to_string(),
                json!({"changes": item.get("changes").cloned().unwrap_or(Value::Null)}).to_string(),
                String::new(),
                failed,
                if failed {
                    "File change failed"
                } else {
                    "File change"
                }
                .to_string(),
            )
        }
        _ => {
            let query = string_field(item, "query");
            (
                "web_search".to_string(),
                json!({"query": query}).to_string(),
                String::new(),
                false,
                if query.is_empty() {
                    "Searched the web".to_string()
                } else {
                    format!("Searched: {query}")
                },
            )
        }
    };
    let mut call = json!({"name": name, "call_id": id, "arguments": arguments});
    if !output.is_empty() {
        call["result"] = Value::String(output.clone());
        if failed {
            call["error"] = Value::String(output);
        }
    } else if failed {
        call["error"] = Value::String("Tool call failed".to_string());
    }
    json!({"narrative": narrative, "calls": [call]}).to_string()
}

fn string_field(value: &Value, key: &str) -> String {
    match value.get(key) {
        Some(Value::String(value)) => value.clone(),
        Some(Value::Null) | None => String::new(),
        Some(value) => value_text(value),
    }
}

fn value_text(value: &Value) -> String {
    value
        .as_str()
        .map(str::to_string)
        .unwrap_or_else(|| value.to_string())
}

#[cfg(target_os = "android")]
fn history_success(extra: Value) -> String {
    let mut result = json!({
        "success": true,
        "providerAvailable": true,
        "errorCode": null,
        "error": null,
        "threads": [],
        "messages": [],
        "nativeThreadId": "",
    });
    if let (Some(target), Some(extra)) = (result.as_object_mut(), extra.as_object()) {
        target.extend(extra.clone());
    }
    result.to_string()
}

fn history_error(
    provider_available: bool,
    error_code: impl Into<String>,
    error: impl Into<String>,
) -> String {
    json!({
        "success": false,
        "providerAvailable": provider_available,
        "errorCode": error_code.into(),
        "error": error.into(),
        "threads": [],
        "messages": [],
        "nativeThreadId": "",
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_current_codex_turn_items_and_maps_messages() {
        let result = json!({
            "thread": {"turns": [{"items": [
                {"id": "u1", "type": "userMessage", "content": [{"type": "text", "text": "hello"}]},
                {"id": "a1", "type": "agentMessage", "text": "world"},
                {"id": "r1", "type": "reasoning", "summary": ["thinking"]}
            ]}]}
        });
        let messages = extract_thread_items(Some(&result))
            .iter()
            .filter_map(map_history_item)
            .collect::<Vec<_>>();
        assert_eq!(messages.len(), 3);
        assert_eq!(messages[0]["role"], "user");
        assert_eq!(messages[0]["content"], "hello");
        assert_eq!(messages[1]["role"], "assistant");
        assert_eq!(messages[2]["role"], "reasoning");
    }

    #[test]
    fn maps_native_thread_summary_timestamps_to_milliseconds() {
        let summary = map_thread_summary(&json!({
            "id": "thread-1",
            "name": "Conversation",
            "preview": "hello",
            "createdAt": 1_700_000_000,
            "updatedAt": 1_700_000_001,
        }))
        .unwrap();
        assert_eq!(summary["id"], "thread-1");
        assert_eq!(summary["createdAt"], 1_700_000_000_000_i64);
    }

    #[test]
    fn maps_null_native_thread_name_to_empty_for_preview_fallback() {
        let summary = map_thread_summary(&json!({
            "id": "thread-1",
            "name": null,
            "preview": "first user message",
            "createdAt": 1_700_000_000,
            "updatedAt": 1_700_000_001,
        }))
        .unwrap();
        assert_eq!(summary["name"], "");
        assert_eq!(summary["preview"], "first user message");
    }

    #[test]
    fn maps_codex_tool_items_to_tool_call_history_schema() {
        let message = map_history_item(&json!({
            "id": "call-1",
            "type": "commandExecution",
            "command": "pwd",
            "aggregatedOutput": "/workspace",
            "status": "completed"
        }))
        .unwrap();
        assert_eq!(message["role"], "tool_calls");
        let content: Value = serde_json::from_str(message["content"].as_str().unwrap()).unwrap();
        assert_eq!(content["calls"][0]["name"], "shell");
    }
}
