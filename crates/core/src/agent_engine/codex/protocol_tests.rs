use super::*;

fn test_turn_request(message: &str, attachments_json: &str) -> AgentEngineTurnRequest {
    AgentEngineTurnRequest {
        engine_id: crate::agent_engine::CODEX_ENGINE_ID.to_string(),
        engine_profile_id: String::new(),
        engine_config: json!({}),
        run_id: "run-1".to_string(),
        files_dir: "/files".to_string(),
        workspace_files_dir: "/workspace".to_string(),
        account_id: "acct".to_string(),
        agent_id: "agent".to_string(),
        session_key_json: r#"{"thread_id":"thread"}"#.to_string(),
        message: message.to_string(),
        attachments_json: attachments_json.to_string(),
        config_json: r#"{"system_prompt":"Host prompt."}"#.to_string(),
    }
}

#[test]
fn initialize_request_opts_into_experimental_api_for_dynamic_tools() {
    let mut client = JsonRpcClient::new();
    let (id, line) = initialize_request(&mut client);
    let payload: Value = serde_json::from_str(&line).unwrap();

    assert_eq!(id, 1);
    assert!(payload.get("jsonrpc").is_none());
    assert_eq!(payload["method"], "initialize");
    assert_eq!(payload["params"]["capabilities"]["experimentalApi"], true);
}

#[test]
fn thread_start_request_includes_napaxi_developer_instructions() {
    let mut client = JsonRpcClient::new();
    let request = test_turn_request("hello", "[]");
    let (_, line) = thread_start_request(&mut client, Some(&request), &[]);
    let payload: Value = serde_json::from_str(&line).unwrap();

    assert!(payload.get("jsonrpc").is_none());
    assert_eq!(payload["method"], "thread/start");
    assert_eq!(payload["params"]["cwd"], "/workspace");
    let instructions = payload["params"]["developerInstructions"].as_str().unwrap();
    assert!(instructions.contains("Napaxi SDK runtime instructions"));
    assert!(instructions.contains("Host prompt."));
}

#[test]
fn thread_start_request_includes_dynamic_tools() {
    let mut client = JsonRpcClient::new();
    let request = test_turn_request("hello", "[]");
    let descriptor = ToolDescriptor {
        name: "open_url".to_string(),
        description: "Open a URL on the device".to_string(),
        parameters: json!({
            "type": "object",
            "properties": {"url": {"type": "string"}},
            "required": ["url"]
        }),
        effect: crate::tool_registry::ToolEffect::External,
    };

    let (_, line) = thread_start_request(&mut client, Some(&request), &[descriptor]);
    let payload: Value = serde_json::from_str(&line).unwrap();

    assert_eq!(payload["method"], "thread/start");
    assert_eq!(payload["params"]["dynamicTools"][0]["type"], "namespace");
    assert_eq!(payload["params"]["dynamicTools"][0]["name"], "napaxi");
    assert_eq!(
        payload["params"]["dynamicTools"][0]["tools"][0]["name"],
        "open_url"
    );
    assert_eq!(
        payload["params"]["dynamicTools"][0]["tools"][0]["inputSchema"]["required"][0],
        "url"
    );
}

#[test]
fn dynamic_tools_fingerprint_tracks_visible_tool_contract_changes() {
    let base = ToolDescriptor {
        name: "custom_echo".to_string(),
        description: "Echo".to_string(),
        parameters: json!({"type": "object"}),
        effect: crate::tool_registry::ToolEffect::Read,
    };
    let mut renamed = base.clone();
    renamed.name = "custom_other".to_string();
    let hidden = ToolDescriptor {
        name: crate::skills::SKILL_LOAD_TOOL_NAME.to_string(),
        description: "Hidden skill loader".to_string(),
        parameters: json!({"type": "object"}),
        effect: crate::tool_registry::ToolEffect::Read,
    };

    assert_eq!(
        dynamic_tools_fingerprint(&[base.clone(), hidden.clone()]),
        dynamic_tools_fingerprint(&[hidden, base.clone()])
    );
    assert_ne!(
        dynamic_tools_fingerprint(&[base]),
        dynamic_tools_fingerprint(&[renamed])
    );
}

#[test]
fn thread_resume_request_omits_dynamic_tools() {
    let mut client = JsonRpcClient::new();
    let state = CodexSessionState {
        native_thread_id: Some("codex-thread".to_string()),
        config_fingerprint: String::new(),
        dynamic_tools_fingerprint: String::new(),
    };
    let descriptor = ToolDescriptor {
        name: "open_url".to_string(),
        description: "Open a URL on the device".to_string(),
        parameters: json!({"type": "object"}),
        effect: crate::tool_registry::ToolEffect::External,
    };

    let (_, line, is_resume) = thread_open_request(&mut client, &state, None, &[descriptor]);
    let payload: Value = serde_json::from_str(&line).unwrap();

    assert!(is_resume);
    assert_eq!(payload["method"], "thread/resume");
    assert!(payload["params"].get("dynamicTools").is_none());
}

#[test]
fn thread_resume_request_includes_napaxi_developer_instructions() {
    let mut client = JsonRpcClient::new();
    let state = CodexSessionState {
        native_thread_id: Some("codex-thread".to_string()),
        config_fingerprint: String::new(),
        dynamic_tools_fingerprint: String::new(),
    };
    let request = test_turn_request("hello", "[]");
    let (_, line, is_resume) = thread_open_request(&mut client, &state, Some(&request), &[]);
    let payload: Value = serde_json::from_str(&line).unwrap();

    assert!(is_resume);
    assert_eq!(payload["method"], "thread/resume");
    assert_eq!(payload["params"]["threadId"], "codex-thread");
    assert!(
        payload["params"]["developerInstructions"]
            .as_str()
            .unwrap()
            .contains("Host prompt.")
    );
}

#[test]
fn turn_start_request_adds_workspace_image_as_local_image() {
    let mut client = JsonRpcClient::new();
    let state = CodexSessionState {
        native_thread_id: Some("codex-thread".to_string()),
        config_fingerprint: String::new(),
        dynamic_tools_fingerprint: String::new(),
    };
    let request = test_turn_request(
        "describe this",
        r#"[{"kind":"image","mime_type":"image/png","filename":"photo.png","sandbox_path":"/workspace/attachments/thread/photo.png"}]"#,
    );

    let line = turn_start_request(&mut client, &request, &state);
    let payload: Value = serde_json::from_str(&line).unwrap();
    let input = payload["params"]["input"].as_array().unwrap();

    assert_eq!(input[0]["type"], "text");
    assert!(
        input[0]["text"]
            .as_str()
            .unwrap()
            .contains("sandbox_path=/workspace/attachments/thread/photo.png")
    );
    assert_eq!(
        input[1],
        json!({
            "type": "localImage",
            "path": "/workspace/attachments/thread/photo.png",
        })
    );
}

#[test]
fn turn_start_request_does_not_send_host_path_as_local_image() {
    let mut client = JsonRpcClient::new();
    let state = CodexSessionState::default();
    let request = test_turn_request(
        "describe this",
        r#"[{"kind":"image","mime_type":"image/png","filename":"photo.png","path":"/host/photo.png"}]"#,
    );

    let line = turn_start_request(&mut client, &request, &state);
    let payload: Value = serde_json::from_str(&line).unwrap();
    let input = payload["params"]["input"].as_array().unwrap();

    assert_eq!(input.len(), 1);
    assert!(
        !input[0]["text"]
            .as_str()
            .unwrap()
            .contains("/host/photo.png")
    );
}

#[test]
fn turn_start_request_preserves_explicit_skill_with_attachments() {
    let mut client = JsonRpcClient::new();
    let state = CodexSessionState::default();
    let request = test_turn_request(
        "build the apk",
        r#"[{"kind":"document","mime_type":"text/plain","filename":"notes.txt","sandbox_path":"/workspace/attachments/thread/notes.txt"}]"#,
    );

    let line = turn_start_request(&mut client, &request, &state);
    let payload: Value = serde_json::from_str(&line).unwrap();
    let input = payload["params"]["input"].as_array().unwrap();

    assert_eq!(input[0]["type"], "text");
    assert!(
        input[0]["text"]
            .as_str()
            .unwrap()
            .starts_with("$android-apk-build\n")
    );
    assert!(input[0]["text"].as_str().unwrap().contains("notes.txt"));
    assert_eq!(input[1]["type"], "skill");
    assert_eq!(input[1]["name"], "android-apk-build");
}
#[test]
fn parses_dynamic_tool_call_request_and_response() {
    let message = json!({
        "jsonrpc": "2.0",
        "id": "rpc-1",
        "method": "item/tool/call",
        "params": {
            "arguments": {"url": "https://example.com"},
            "callId": "call-1",
            "namespace": "napaxi",
            "tool": "open_url",
            "threadId": "thread-1",
            "turnId": "turn-1"
        }
    });

    assert_eq!(server_request_id(&message), Some(json!("rpc-1")));
    let params = dynamic_tool_call_params(&message).unwrap().unwrap();
    assert_eq!(params.call_id, "call-1");
    assert_eq!(params.namespace.as_deref(), Some("napaxi"));
    assert_eq!(params.tool, "open_url");
    assert_eq!(params.arguments["url"], "https://example.com");

    let response: Value =
        serde_json::from_str(&dynamic_tool_call_response(json!("rpc-1"), true, "opened")).unwrap();
    assert!(response.get("jsonrpc").is_none());
    assert_eq!(response["id"], "rpc-1");
    assert_eq!(response["result"]["success"], true);
    assert_eq!(response["result"]["contentItems"][0]["type"], "inputText");
    assert_eq!(response["result"]["contentItems"][0]["text"], "opened");
}

#[test]
fn auto_responds_to_approval_requests_without_granting_access() {
    let command_response: Value = serde_json::from_str(
        &app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "approval-1",
                "method": "item/commandExecution/requestApproval",
                "params": {
                    "itemId": "item-1",
                    "startedAtMs": 1,
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "command": "cat /etc/passwd"
                }
            }),
            json!("approval-1"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(command_response["id"], "approval-1");
    assert_eq!(command_response["result"]["decision"], "decline");

    let file_response: Value = serde_json::from_str(
        &app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "approval-2",
                "method": "item/fileChange/requestApproval",
                "params": {
                    "itemId": "item-2",
                    "startedAtMs": 1,
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "grantRoot": "/host"
                }
            }),
            json!("approval-2"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(file_response["result"]["decision"], "decline");

    let permissions_response: Value = serde_json::from_str(
        &app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "approval-3",
                "method": "item/permissions/requestApproval",
                "params": {
                    "cwd": "/workspace",
                    "itemId": "item-3",
                    "permissions": {},
                    "startedAtMs": 1,
                    "threadId": "thread-1",
                    "turnId": "turn-1"
                }
            }),
            json!("approval-3"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(permissions_response["result"]["permissions"], json!({}));
    assert_eq!(permissions_response["result"]["scope"], "turn");
    assert_eq!(permissions_response["result"]["strictAutoReview"], false);
}

#[test]
fn auto_response_defers_user_input_and_dynamic_tool_calls() {
    assert!(
        app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "human-1",
                "method": "item/tool/requestUserInput",
                "params": {"questions": []}
            }),
            json!("human-1"),
        )
        .is_none()
    );
    assert!(
        app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "tool-1",
                "method": "item/tool/call",
                "params": {}
            }),
            json!("tool-1"),
        )
        .is_none()
    );
}

#[test]
fn auto_responds_to_misc_server_requests_or_errors() {
    let time_response: Value = serde_json::from_str(
        &app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "time-1",
                "method": "currentTime/read",
                "params": {}
            }),
            json!("time-1"),
        )
        .unwrap(),
    )
    .unwrap();
    assert!(time_response["result"]["currentTimeAt"].as_i64().unwrap() > 0);

    let elicitation_response: Value = serde_json::from_str(
        &app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "mcp-1",
                "method": "mcpServer/elicitation/request",
                "params": {}
            }),
            json!("mcp-1"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(elicitation_response["result"]["action"], "cancel");

    let unsupported_response: Value = serde_json::from_str(
        &app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "unsupported-1",
                "method": "account/chatgptAuthTokens/refresh",
                "params": {}
            }),
            json!("unsupported-1"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(unsupported_response["error"]["code"], -32000);

    let unknown_response: Value = serde_json::from_str(
        &app_server_request_auto_response(
            &json!({
                "jsonrpc": "2.0",
                "id": "unknown-1",
                "method": "unknown/request",
                "params": {}
            }),
            json!("unknown-1"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(unknown_response["error"]["code"], -32601);
}
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

#[test]
fn echoed_client_requests_are_not_treated_as_server_requests() {
    let echoed_initialize = json!({
        "id": 1,
        "method": "initialize",
        "params": {"capabilities": {"experimentalApi": true}}
    });
    let server_tool_request = json!({
        "id": "tool-rpc",
        "method": "item/tool/call",
        "params": {
            "arguments": {},
            "callId": "call-1",
            "namespace": "napaxi",
            "tool": "android_integration_ping",
            "threadId": "thread-1",
            "turnId": "turn-1"
        }
    });

    assert_eq!(server_request_id(&echoed_initialize), None);
    assert_eq!(
        server_request_id(&server_tool_request),
        Some(json!("tool-rpc"))
    );
}
