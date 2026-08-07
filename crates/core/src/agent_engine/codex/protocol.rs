use serde::Deserialize;
use serde_json::{Value, json};

use super::state::CodexSessionState;
use crate::agent_engine::AgentEngineTurnRequest;
use crate::tool_registry::ToolDescriptor;

// Codex app-server speaks a JSON-line RPC protocol that is JSON-RPC-like,
// but the wire objects intentionally omit a top-level `jsonrpc` field.
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
            json!({"id":id,"method":method,"params":params}).to_string(),
        )
    }

    pub(crate) fn notification(&self, method: &str, params: Option<Value>) -> String {
        let mut payload = json!({"method":method});
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
    request: Option<&AgentEngineTurnRequest>,
    dynamic_tools: &[ToolDescriptor],
) -> (u64, String, bool) {
    if let Some(thread_id) = &state.native_thread_id {
        let (id, line) = client.request(
            "thread/resume",
            thread_open_params(Some(thread_id), request, dynamic_tools),
        );
        (id, line, true)
    } else {
        let (id, line) = client.request(
            "thread/start",
            thread_open_params(None, request, dynamic_tools),
        );
        (id, line, false)
    }
}

pub(crate) fn thread_start_request(
    client: &mut JsonRpcClient,
    request: Option<&AgentEngineTurnRequest>,
    dynamic_tools: &[ToolDescriptor],
) -> (u64, String) {
    client.request(
        "thread/start",
        thread_open_params(None, request, dynamic_tools),
    )
}

fn thread_open_params(
    thread_id: Option<&str>,
    request: Option<&AgentEngineTurnRequest>,
    dynamic_tools: &[ToolDescriptor],
) -> Value {
    let mut params = json!({
        "cwd": "/workspace",
        "approvalPolicy": "never",
        "sandbox": "danger-full-access",
    });
    if let Some(thread_id) = thread_id {
        params["threadId"] = Value::String(thread_id.to_string());
    }
    if let Some(instructions) = request.and_then(codex_developer_instructions) {
        params["developerInstructions"] = Value::String(instructions);
    }
    if thread_id.is_none()
        && let Some(dynamic_tools) = codex_dynamic_tools(dynamic_tools)
    {
        params["dynamicTools"] = dynamic_tools;
    }
    params
}

pub(crate) fn dynamic_tools_fingerprint(descriptors: &[ToolDescriptor]) -> String {
    let mut visible = descriptors
        .iter()
        .filter(|descriptor| !crate::skills::is_hidden_skill_tool(&descriptor.name))
        .cloned()
        .collect::<Vec<_>>();
    visible.sort_by(|left, right| left.name.cmp(&right.name));
    let raw = serde_json::to_vec(&visible).unwrap_or_default();
    crate::crypto::sha256_base64_no_pad(&raw)
}

fn codex_dynamic_tools(descriptors: &[ToolDescriptor]) -> Option<Value> {
    let tools = descriptors
        .iter()
        .filter(|descriptor| !crate::skills::is_hidden_skill_tool(&descriptor.name))
        .map(|descriptor| {
            json!({
                "type": "function",
                "name": descriptor.name,
                "description": descriptor.description,
                "inputSchema": descriptor.parameters,
            })
        })
        .collect::<Vec<_>>();
    if tools.is_empty() {
        return None;
    }
    Some(json!([
        {
            "type": "namespace",
            "name": "napaxi",
            "description": "Napaxi SDK runtime and device tools admitted by the current capability profile. Use these for host/device actions that are outside Codex's built-in workspace tools.",
            "tools": tools,
        }
    ]))
}

fn codex_developer_instructions(request: &AgentEngineTurnRequest) -> Option<String> {
    serde_json::from_str::<Value>(&request.config_json)
        .ok()
        .and_then(|value| {
            value
                .get("system_prompt")
                .or_else(|| value.get("systemPrompt"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|value| {
                    format!(
                        "Napaxi SDK runtime instructions. These instructions are supplied by napaxi_core for adapter parity and should be treated as developer guidance, not as user-provided content.\n\n{value}"
                    )
                })
        })
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
    let input = codex_turn_input_items(&request.message, &request.attachments_json);
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

fn codex_turn_input_items(message: &str, attachments_json: &str) -> Vec<Value> {
    let attachments = parse_codex_attachments(attachments_json);
    let skills = explicit_codex_skills(message);
    let mut text = message.to_string();
    for skill in &skills {
        if !has_skill_mention(&text, skill) {
            text = format!("${skill}\n{text}");
        }
    }
    if !attachments.is_empty() {
        text.push_str("\n\n<attachments>\n");
        for attachment in &attachments {
            text.push_str("- ");
            if let Some(filename) = &attachment.filename {
                text.push_str(filename);
            } else {
                text.push_str("attachment");
            }
            text.push_str(&format!(" ({})", attachment.kind));
            if let Some(mime_type) = &attachment.mime_type {
                text.push_str(&format!(", mime_type={mime_type}"));
            }
            if let Some(path) = &attachment.sandbox_path {
                text.push_str(&format!(", sandbox_path={path}"));
            }
            text.push('\n');
        }
        text.push_str("</attachments>");
    }

    let mut input = vec![json!({"type": "text", "text": text})];
    for attachment in &attachments {
        if attachment.kind == "image"
            && let Some(path) = &attachment.sandbox_path
        {
            input.push(json!({
                "type": "localImage",
                "path": path,
            }));
        }
    }
    for skill in skills {
        input.push(json!({
            "type": "skill",
            "name": skill,
            "path": format!("/skills/{skill}/SKILL.md"),
        }));
    }
    input
}

#[derive(Debug, Clone)]
struct CodexAttachmentInput {
    kind: String,
    mime_type: Option<String>,
    filename: Option<String>,
    sandbox_path: Option<String>,
}

fn parse_codex_attachments(attachments_json: &str) -> Vec<CodexAttachmentInput> {
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(attachments_json) else {
        return Vec::new();
    };
    items
        .into_iter()
        .map(|item| {
            let kind = string_field(&item, "kind").unwrap_or_else(|| {
                let mime_type = string_field(&item, "mime_type")
                    .or_else(|| string_field(&item, "mimeType"))
                    .unwrap_or_default();
                if mime_type.starts_with("image/") {
                    "image".to_string()
                } else if mime_type.starts_with("audio/") {
                    "audio".to_string()
                } else {
                    "document".to_string()
                }
            });
            let sandbox_path = string_field(&item, "sandbox_path")
                .or_else(|| string_field(&item, "storage_key"))
                .or_else(|| string_field(&item, "storageKey"))
                .or_else(|| string_field(&item, "path").filter(|path| is_codex_sandbox_path(path)))
                .filter(|path| is_codex_sandbox_path(path));
            CodexAttachmentInput {
                kind,
                mime_type: string_field(&item, "mime_type")
                    .or_else(|| string_field(&item, "mimeType")),
                filename: string_field(&item, "filename").or_else(|| string_field(&item, "name")),
                sandbox_path,
            }
        })
        .collect()
}

fn string_field(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
}

fn is_codex_sandbox_path(path: &str) -> bool {
    path == "/workspace" || path.starts_with("/workspace/")
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
    if has_skill_mention(&lower, "android-apk-build") {
        return true;
    }

    let android_or_apk = lower.contains("apk")
        || lower.contains("android")
        || lower.contains("安卓")
        || lower.contains("安装包");
    let build_or_package = contains_any(
        &lower,
        &[
            "build", "make", "create", "generate", "develop", "package", "sign", "install",
            "compile", "构建", "打包", "签名", "安装", "编译", "生成", "创建", "开发", "做", "写",
        ],
    );
    if android_or_apk && build_or_package {
        return true;
    }

    // In the phone-hosted Napaxi experience, users often say just “写一个 app”
    // or “做个应用” and expect an installable Android APK. Inject the APK build
    // skill for app-creation phrasing unless the prompt clearly asks for an app
    // surface that needs a separate unsupported toolchain such as iOS, Flutter,
    // or React Native. Web/HTML wrappers are allowed because the fixed Java
    // template can host local assets in an Android WebView.
    let app_surface = lower.contains("app")
        || lower.contains("应用")
        || lower.contains("小工具")
        || lower.contains("安装到手机")
        || lower.contains("手机上安装")
        || lower.contains("能安装");
    let create_app = contains_any(
        &lower,
        &[
            "写", "做", "开发", "创建", "生成", "make", "create", "build", "develop",
        ],
    );
    let unsupported_toolchain_surface = contains_any(
        &lower,
        &[
            "browser extension",
            "浏览器插件",
            "ios app",
            "iphone",
            "swift",
            "flutter",
            "react native",
        ],
    );

    app_surface && create_app && !unsupported_toolchain_surface
}

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

fn has_skill_mention(text: &str, skill: &str) -> bool {
    text.contains(&format!("${skill}")) || text.contains(&format!("/{skill}"))
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DynamicToolCallParams {
    #[serde(default)]
    pub(crate) arguments: Value,
    pub(crate) call_id: String,
    #[serde(default)]
    pub(crate) namespace: Option<String>,
    pub(crate) tool: String,
    pub(crate) thread_id: String,
    pub(crate) turn_id: String,
}

pub(crate) fn server_request_id(message: &Value) -> Option<Value> {
    let method = message.get("method")?.as_str()?;
    if is_client_request_method(method) {
        return None;
    }
    message.get("id").cloned()
}

fn is_client_request_method(method: &str) -> bool {
    matches!(
        method,
        "initialize"
            | "initialized"
            | "thread/start"
            | "thread/resume"
            | "thread/delete"
            | "turn/start"
            | "skills/extraRoots/set"
            | "skills/list"
    )
}

pub(crate) fn dynamic_tool_call_params(
    message: &Value,
) -> Result<Option<DynamicToolCallParams>, String> {
    if message.get("method").and_then(Value::as_str) != Some("item/tool/call") {
        return Ok(None);
    }
    let params = message
        .get("params")
        .cloned()
        .ok_or_else(|| "missing item/tool/call params".to_string())?;
    serde_json::from_value(params)
        .map(Some)
        .map_err(|error| format!("invalid item/tool/call params: {error}"))
}

pub(crate) fn dynamic_tool_call_response(id: Value, success: bool, output: &str) -> String {
    json!({
        "id": id,
        "result": {
            "success": success,
            "contentItems": [
                {"type": "inputText", "text": output}
            ]
        }
    })
    .to_string()
}

pub(crate) fn app_server_request_auto_response(message: &Value, id: Value) -> Option<String> {
    let method = message.get("method").and_then(Value::as_str)?;
    match method {
        // Handled by the dynamic tool bridge before this fallback.
        "item/tool/call" => None,
        // Deliberately deferred until the host supplies an answer through
        // answer_human_request.
        "item/tool/requestUserInput" => None,
        // Keep the mobile runtime policy gate authoritative: Codex is opened
        // with approvalPolicy=never, so approval requests should be unusual.
        // If they still arrive, answer deterministically instead of leaving the
        // JSON-RPC request pending forever.
        "item/commandExecution/requestApproval" => {
            Some(json_rpc_result(id, json!({"decision": "decline"})))
        }
        "item/fileChange/requestApproval" => {
            Some(json_rpc_result(id, json!({"decision": "decline"})))
        }
        "item/permissions/requestApproval" => Some(json_rpc_result(
            id,
            json!({
                "permissions": {},
                "scope": "turn",
                "strictAutoReview": false
            }),
        )),
        "mcpServer/elicitation/request" => Some(json_rpc_result(
            id,
            json!({"action": "cancel", "content": Value::Null}),
        )),
        "currentTime/read" => Some(json_rpc_result(
            id,
            json!({"currentTimeAt": unix_time_seconds()}),
        )),
        // These requests require upstream account/device attestation providers
        // that Napaxi does not expose through the Codex app-server bridge.
        // Return structured RPC errors rather than hanging the turn.
        "account/chatgptAuthTokens/refresh" | "attestation/generate" => Some(json_rpc_error(
            id,
            -32000,
            &format!("Napaxi Codex app-server bridge does not support {method}"),
        )),
        _ => Some(json_rpc_error(
            id,
            -32601,
            &format!("unsupported Codex app-server request: {method}"),
        )),
    }
}

fn json_rpc_result(id: Value, result: Value) -> String {
    json!({
        "id": id,
        "result": result,
    })
    .to_string()
}

fn json_rpc_error(id: Value, code: i64, message: &str) -> String {
    json!({
        "id": id,
        "error": {
            "code": code,
            "message": message,
        },
    })
    .to_string()
}

fn unix_time_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
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
#[path = "protocol_tests.rs"]
mod tests;
