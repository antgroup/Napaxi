use serde_json::{Value, json};

use super::state::CodexSessionState;
use crate::agent_engine::AgentEngineTurnRequest;

pub(crate) struct JsonRpcClient {
    next_id: u64,
}

impl JsonRpcClient {
    pub(crate) fn new() -> Self {
        Self { next_id: 1 }
    }

    pub(crate) fn request(&mut self, method: &str, params: Value) -> (u64, String) {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        (
            id,
            json!({"jsonrpc":"2.0","id":id,"method":method,"params":params}).to_string(),
        )
    }

    pub(crate) fn notification(&self, method: &str, params: Option<Value>) -> String {
        let mut payload = json!({"jsonrpc":"2.0","method":method});
        if let Some(params) = params {
            payload["params"] = params;
        }
        payload.to_string()
    }
}

pub(crate) fn startup_requests(client: &mut JsonRpcClient) -> Vec<String> {
    let (_, initialize) = client.request(
        "initialize",
        json!({
            "clientInfo": {
                "name": "napaxi-core",
                "title": "Napaxi",
                "version": "1.0.0"
            },
            "capabilities": {"experimentalApi": true}
        }),
    );
    vec![initialize, client.notification("initialized", None)]
}

pub(crate) fn thread_open_request(
    client: &mut JsonRpcClient,
    state: &CodexSessionState,
) -> (u64, String, bool) {
    if let Some(thread_id) = &state.native_thread_id {
        let (id, line) = client.request(
            "thread/resume",
            json!({
                "threadId": thread_id,
                "approvalPolicy": "never",
                "sandbox": "danger-full-access",
            }),
        );
        (id, line, true)
    } else {
        let (id, line) = client.request(
            "thread/start",
            json!({
                "cwd": "/workspace/codex",
                "approvalPolicy": "never",
                "sandbox": "danger-full-access",
            }),
        );
        (id, line, false)
    }
}

pub(crate) fn thread_start_request(client: &mut JsonRpcClient) -> (u64, String) {
    client.request(
        "thread/start",
        json!({
            "cwd": "/workspace/codex",
            "approvalPolicy": "never",
            "sandbox": "danger-full-access",
        }),
    )
}

pub(crate) fn turn_start_request(
    client: &mut JsonRpcClient,
    request: &AgentEngineTurnRequest,
    state: &CodexSessionState,
) -> String {
    let thread_id = state.native_thread_id.as_deref().unwrap_or_default();
    let effort = request
        .engine_config
        .get("reasoning_effort")
        .or_else(|| request.engine_config.get("effort"))
        .and_then(Value::as_str)
        .unwrap_or("medium");
    let (_, line) = client.request(
        "turn/start",
        json!({
            "threadId": thread_id,
            "input": [{"type": "text", "text": request.message}],
            "approvalPolicy": "never",
            "sandboxPolicy": {"type": "dangerFullAccess"},
            "effort": effort,
            "metadata": {
                "napaxi_run_id": request.run_id,
                "account_id": request.account_id,
                "agent_id": request.agent_id,
                "session_key_json": request.session_key_json,
            }
        }),
    );
    line
}

pub(crate) fn response_id(message: &Value) -> Option<u64> {
    if message.get("method").is_some() {
        return None;
    }
    message.get("id").and_then(Value::as_u64)
}

pub(crate) fn response_error(message: &Value) -> Option<String> {
    let error = message.get("error")?;
    Some(
        error
            .get("message")
            .and_then(Value::as_str)
            .map(str::to_string)
            .unwrap_or_else(|| error.to_string()),
    )
}

pub(crate) fn extract_thread_id(message: &Value) -> Option<String> {
    message
        .pointer("/result/thread/id")
        .or_else(|| message.pointer("/result/thread_id"))
        .or_else(|| message.pointer("/result/threadId"))
        .or_else(|| message.pointer("/params/thread/id"))
        .or_else(|| message.pointer("/params/thread_id"))
        .or_else(|| message.pointer("/params/threadId"))
        .and_then(Value::as_str)
        .map(str::to_string)
}

pub(crate) fn parse_json_lines(buffer: &mut String, chunk: &str) -> Vec<Value> {
    buffer.push_str(chunk);
    let mut parsed = Vec::new();
    while let Some(pos) = buffer.find('\n') {
        let line: String = buffer.drain(..=pos).collect();
        let trimmed = strip_ansi(line.trim());
        if trimmed.starts_with('{') {
            if let Ok(value) = serde_json::from_str::<Value>(&trimmed) {
                parsed.push(value);
            }
        }
    }
    parsed
}

fn strip_ansi(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\u{1b}' && chars.peek() == Some(&'[') {
            let _ = chars.next();
            for c in chars.by_ref() {
                if c.is_ascii_alphabetic() {
                    break;
                }
            }
        } else {
            out.push(ch);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_json_lines_and_filters_noise() {
        let mut buf = String::new();
        let out = parse_json_lines(&mut buf, "noise\n{\"jsonrpc\":\"2.0\"}\n");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["jsonrpc"], "2.0");
    }
}
