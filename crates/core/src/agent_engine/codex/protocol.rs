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

pub(crate) fn initialize_request(client: &mut JsonRpcClient) -> (u64, String) {
    client.request(
        "initialize",
        json!({
            "clientInfo": {
                "name": "napaxi-core",
                "title": "Napaxi",
                "version": "1.0.0"
            },
            "capabilities": {"experimentalApi": true}
        }),
    )
}

pub(crate) fn initialized_notification(client: &JsonRpcClient) -> String {
    client.notification("initialized", None)
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
                "cwd": "/workspace",
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
            "cwd": "/workspace",
            "approvalPolicy": "never",
            "sandbox": "danger-full-access",
        }),
    )
}

pub(crate) fn thread_list_request(client: &mut JsonRpcClient, cwd: Option<&str>) -> (u64, String) {
    let mut params = json!({
        "limit": 50,
        "sortDirection": "desc",
        "sortKey": "updated_at",
        "sourceKinds": [
            "cli",
            "vscode",
            "exec",
            "appServer",
            "subAgent",
            "subAgentReview",
            "subAgentCompact",
            "subAgentThreadSpawn",
            "subAgentOther",
            "unknown"
        ]
    });
    if let Some(cwd) = cwd {
        params["cwd"] = Value::String(cwd.to_string());
    }
    client.request("thread/list", params)
}

pub(crate) fn thread_history_resume_request(
    client: &mut JsonRpcClient,
    thread_id: &str,
) -> (u64, String) {
    client.request(
        "thread/resume",
        json!({
            "threadId": thread_id,
            "approvalPolicy": "never",
            "sandbox": "danger-full-access",
        }),
    )
}

pub(crate) fn thread_read_request(client: &mut JsonRpcClient, thread_id: &str) -> (u64, String) {
    client.request(
        "thread/read",
        json!({"threadId": thread_id, "includeTurns": true}),
    )
}

pub(crate) fn thread_delete_request(client: &mut JsonRpcClient, thread_id: &str) -> (u64, String) {
    client.request("thread/delete", json!({"threadId": thread_id}))
}

pub(crate) fn skills_extra_roots_set_request(client: &mut JsonRpcClient) -> (u64, String) {
    client.request(
        "skills/extraRoots/set",
        json!({
            "extraRoots": ["/skills"],
        }),
    )
}

pub(crate) fn skills_list_request(client: &mut JsonRpcClient, force_reload: bool) -> (u64, String) {
    client.request(
        "skills/list",
        json!({
            "forceReload": force_reload,
        }),
    )
}

pub(crate) fn skill_roots_then_turn_lines(
    client: &mut JsonRpcClient,
    request: &AgentEngineTurnRequest,
    state: &CodexSessionState,
) -> Vec<String> {
    let (_, skills_root_line) = skills_extra_roots_set_request(client);
    let (_, skills_list_line) = skills_list_request(client, true);
    vec![
        skills_root_line,
        skills_list_line,
        turn_start_request(client, request, state),
    ]
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
    let input = codex_turn_input_items(&request.message);
    let (_, line) = client.request(
        "turn/start",
        json!({
            "threadId": thread_id,
            "input": input,
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

fn codex_turn_input_items(message: &str) -> Vec<Value> {
    let skills = explicit_codex_skills(message);
    if skills.is_empty() {
        return vec![json!({"type": "text", "text": message})];
    }
    let mut text = message.to_string();
    for skill in &skills {
        if !has_skill_mention(&text, skill) {
            text = format!("${skill}\n{text}");
        }
    }
    let mut input = vec![json!({"type": "text", "text": text})];
    for skill in skills {
        input.push(json!({
            "type": "skill",
            "name": skill,
            "path": format!("/skills/{skill}/SKILL.md"),
        }));
    }
    input
}

fn explicit_codex_skills(message: &str) -> Vec<&'static str> {
    if should_use_android_apk_build(message) {
        vec!["android-apk-build"]
    } else {
        Vec::new()
    }
}

fn should_use_android_apk_build(message: &str) -> bool {
    let lower = message.to_lowercase();
    has_skill_mention(&lower, "android-apk-build")
        || ((lower.contains("apk") || lower.contains("android"))
            && (lower.contains("build")
                || lower.contains("package")
                || lower.contains("sign")
                || lower.contains("install")
                || lower.contains("构建")
                || lower.contains("打包")
                || lower.contains("签名")
                || lower.contains("安装")))
}

fn has_skill_mention(text: &str, skill: &str) -> bool {
    text.contains(&format!("${skill}")) || text.contains(&format!("/{skill}"))
}

pub(crate) fn response_id(message: &Value) -> Option<u64> {
    if message.get("method").is_some() {
        return None;
    }
    message.get("id").and_then(Value::as_u64)
}

pub(crate) fn response_error(message: &Value) -> Option<String> {
    let error = message.get("error").filter(|value| !value.is_null())?;
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
    while let Some((line_end, drain_end)) = next_line_boundary(buffer) {
        let line: String = buffer.drain(..drain_end).collect();
        let line = &line[..line_end];
        let trimmed = strip_ansi(line.trim());
        if trimmed.starts_with('{')
            && let Ok(value) = serde_json::from_str::<Value>(&trimmed)
        {
            parsed.push(value);
        }
    }
    parsed
}

fn next_line_boundary(buffer: &str) -> Option<(usize, usize)> {
    for (idx, ch) in buffer.char_indices() {
        match ch {
            '\n' => return Some((idx, idx + ch.len_utf8())),
            '\r' => {
                let next = idx + ch.len_utf8();
                let drain_end = if buffer[next..].starts_with('\n') {
                    next + '\n'.len_utf8()
                } else {
                    next
                };
                return Some((idx, drain_end));
            }
            _ => {}
        }
    }
    None
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

    #[test]
    fn parses_json_lines_with_cr_and_crlf_delimiters() {
        let mut buf = String::new();
        let out = parse_json_lines(
            &mut buf,
            "{\"jsonrpc\":\"2.0\",\"id\":1}\r{\"jsonrpc\":\"2.0\",\"id\":2}\r\n",
        );
        assert_eq!(out.len(), 2);
        assert_eq!(out[0]["id"], 1);
        assert_eq!(out[1]["id"], 2);
        assert!(buf.is_empty());
    }

    #[test]
    fn parses_json_lines_split_across_chunks() {
        let mut buf = String::new();
        assert!(parse_json_lines(&mut buf, "{\"jsonrpc\":").is_empty());
        let out = parse_json_lines(&mut buf, "\"2.0\",\"id\":3}\r");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["id"], 3);
        assert!(buf.is_empty());
    }

    #[test]
    fn extracts_thread_id_from_thread_started_notification() {
        let message = json!({
            "jsonrpc": "2.0",
            "method": "thread/started",
            "params": {"thread": {"id": "thread-1"}}
        });
        assert_eq!(extract_thread_id(&message).as_deref(), Some("thread-1"));
    }

    #[test]
    fn ignores_null_json_rpc_error_fields() {
        assert!(response_error(&json!({"id": 1, "result": {}, "error": null})).is_none());
        assert_eq!(
            response_error(&json!({"id": 1, "error": {"message": "not initialized"}})).as_deref(),
            Some("not initialized")
        );
    }

    #[test]
    fn history_requests_match_codex_app_server_contract() {
        let mut client = JsonRpcClient::new();
        let (_, list) = thread_list_request(&mut client, Some("/workspace"));
        let (_, read) = thread_read_request(&mut client, "thread-1");
        let (_, delete) = thread_delete_request(&mut client, "thread-1");
        let list: Value = serde_json::from_str(&list).unwrap();
        let read: Value = serde_json::from_str(&read).unwrap();
        let delete: Value = serde_json::from_str(&delete).unwrap();
        assert_eq!(list["method"], "thread/list");
        assert_eq!(list["params"]["cwd"], "/workspace");
        assert_eq!(read["method"], "thread/read");
        assert_eq!(read["params"]["includeTurns"], true);
        assert_eq!(delete["method"], "thread/delete");
        assert_eq!(delete["params"]["threadId"], "thread-1");
    }
}
