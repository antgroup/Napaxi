//! Core-owned Codex app-server agent engine.
//!
//! The public engine id is `napaxi.agent_engine.codex`; Android runs it inside
//! the Napaxi Linux sandbox PTY and iOS runs it through the vendored QEMU PTY
//! backend. Other platforms keep the same API surface and return an explicit
//! unsupported error.

#[cfg(any(target_os = "android", target_os = "ios", test))]
mod config;
mod configure;
#[cfg(any(target_os = "android", target_os = "ios", test))]
mod dynamic_tools;
#[cfg_attr(not(any(target_os = "android", target_os = "ios")), allow(dead_code))]
mod env;
#[cfg_attr(not(any(target_os = "android", target_os = "ios")), allow(dead_code))]
mod events;
mod history;
mod process;
#[cfg_attr(not(any(target_os = "android", target_os = "ios")), allow(dead_code))]
mod protocol;
#[cfg_attr(not(any(target_os = "android", target_os = "ios")), allow(dead_code))]
mod state;

pub(crate) use configure::configure_codex_agent_engine_json;
#[cfg(test)]
pub(crate) use events::map_app_server_message;
pub(crate) use process::answer_human_request;
pub(crate) use process::run_codex_turn;
pub(crate) use state::register_android_native_library_dir;

pub(crate) fn query_codex_agent_engine_history_json(handle: i64, request_json: &str) -> String {
    history::handle_request_json(handle, request_json)
}

pub const CODEX_ENGINE_ID: &str = "codex";
pub const CODEX_ENGINE_CAPABILITY_ID: &str = "napaxi.agent_engine.codex";

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::types::ChatEvent;

    #[test]
    fn maps_assistant_delta_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "assistant_delta", "delta": "hello"}
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::ResponseDelta { content }) if content == "hello")
        );
    }

    #[test]
    fn maps_reasoning_delta_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "reasoning_delta", "delta": "thinking"}
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::ReasoningDelta { content }) if content == "thinking")
        );
    }

    #[test]
    fn maps_command_output_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {
                "type": "command_output_delta",
                "call_id": "c1",
                "stream": "stdout",
                "delta": "out"
            }
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::ToolOutputChunk { call_id, content, stream }) if call_id == "c1" && content == "out" && stream == "stdout")
        );
    }

    #[test]
    fn maps_turn_completed_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "turn_completed"}
        }));
        assert!(outcome.completed);
        assert!(!outcome.failed);
    }

    #[test]
    fn maps_turn_completed_with_null_error_as_success() {
        let outcome = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "turn/completed",
            "params": {
                "turn": {
                    "status": "completed",
                    "error": null
                }
            }
        }));
        assert!(outcome.completed);
        assert!(!outcome.failed);
        assert!(outcome.event.is_none());
    }

    #[test]
    fn maps_failed_turn_completed_as_error() {
        let outcome = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "turn/completed",
            "params": {
                "turn": {
                    "status": "failed",
                    "error": {"message": "stream disconnected before completion"}
                }
            }
        }));
        assert!(outcome.completed);
        assert!(outcome.failed);
        assert!(
            matches!(outcome.event, Some(ChatEvent::Error { message }) if message == "stream disconnected before completion")
        );
    }

    #[test]
    fn maps_turn_error_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "turn_error", "message": "boom"}
        }));
        assert!(outcome.completed);
        assert!(outcome.failed);
        assert!(matches!(outcome.event, Some(ChatEvent::Error { message }) if message == "boom"));
    }

    #[test]
    fn maps_final_app_server_error_and_surfaces_retry_notice() {
        let retry = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "error",
            "params": {
                "error": {
                    "message": "Reconnecting... 2/5",
                    "additionalDetails": "stream disconnected before completion"
                },
                "willRetry": true
            }
        }));
        assert!(matches!(
            retry.event,
            Some(ChatEvent::StreamReset { reason })
                if reason.contains("Reconnecting... 2/5")
                    && reason.contains("stream disconnected before completion")
        ));
        assert!(!retry.completed);

        let final_error = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "error",
            "params": {
                "error": {"message": "stream disconnected before completion"},
                "willRetry": false
            }
        }));
        assert!(final_error.completed);
        assert!(final_error.failed);
        assert!(
            matches!(final_error.event, Some(ChatEvent::Error { message }) if message == "stream disconnected before completion")
        );
    }

    #[test]
    fn maps_user_input_request_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {
                "type": "user_input_request",
                "request_id": "h1",
                "question": "Continue?",
                "options": ["yes", "no"]
            }
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::AskingHuman { request_id, question, options, .. }) if request_id == "h1" && question == "Continue?" && options.len() == 2)
        );
        assert!(!outcome.completed);
        assert!(!outcome.failed);
    }
    #[test]
    fn maps_real_app_server_notifications() {
        let assistant = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/agentMessage/delta",
            "params": {"itemId": "i1", "delta": "hello"}
        }));
        assert!(
            matches!(assistant.event, Some(ChatEvent::ResponseDelta { content }) if content == "hello")
        );

        let reasoning = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/reasoning/textDelta",
            "params": {"itemId": "r1", "delta": "why"}
        }));
        assert!(
            matches!(reasoning.event, Some(ChatEvent::ReasoningDelta { content }) if content == "why")
        );

        let output = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/commandExecution/outputDelta",
            "params": {"itemId": "cmd1", "delta": "out"}
        }));
        assert!(
            matches!(output.event, Some(ChatEvent::ToolOutputChunk { call_id, content, stream }) if call_id == "cmd1" && content == "out" && stream == "stdout")
        );

        let done = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "turn/completed",
            "params": {}
        }));
        assert!(done.completed);
    }

    #[test]
    fn maps_real_user_input_request() {
        let outcome = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "id": 9,
            "method": "item/tool/requestUserInput",
            "params": {
                "questions": [{
                    "id": "approval",
                    "header": "Confirm",
                    "question": "Proceed?",
                    "options": [{"label": "yes"}, {"label": "no"}]
                }]
            }
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::AskingHuman { request_id, question, options, context }) if request_id.starts_with("codex:") && question == "Proceed?" && options == vec!["yes", "no"] && context.as_deref() == Some("Confirm"))
        );
        assert!(!outcome.completed);
    }

    #[test]
    fn maps_codex_command_items_to_existing_tool_trace_events() {
        let started = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/started",
            "params": {"item": {
                "id": "cmd1",
                "type": "commandExecution",
                "command": "pwd",
                "cwd": "/workspace"
            }}
        }));
        assert!(
            matches!(started.event, Some(ChatEvent::ToolCall { call_id, name, arguments }) if call_id == "cmd1" && name == "shell" && arguments.contains("pwd"))
        );

        let completed = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/completed",
            "params": {"item": {
                "id": "cmd1",
                "type": "commandExecution",
                "aggregatedOutput": "/workspace\n",
                "status": "completed",
                "exitCode": 0
            }}
        }));
        assert!(
            matches!(completed.event, Some(ChatEvent::ToolResult { call_id, name, output, is_error }) if call_id == "cmd1" && name == "shell" && output == "/workspace\n" && !is_error)
        );
    }

    #[test]
    fn maps_codex_dynamic_mcp_and_web_items_to_tool_events() {
        let dynamic_started = map_app_server_message(&json!({
            "method": "item/started",
            "params": {"item": {
                "id": "dyn1",
                "type": "dynamicToolCall",
                "namespace": "browser",
                "tool": "open",
                "arguments": {"url": "https://example.com"}
            }}
        }));
        assert!(
            matches!(dynamic_started.event, Some(ChatEvent::ToolCall { call_id, name, arguments }) if call_id == "dyn1" && name == "browser.open" && arguments.contains("example.com"))
        );

        let mcp_completed = map_app_server_message(&json!({
            "method": "item/completed",
            "params": {"item": {
                "id": "mcp1",
                "type": "mcpToolCall",
                "server": "filesystem",
                "tool": "read_file",
                "result": {"content": "hello"},
                "status": "completed"
            }}
        }));
        assert!(
            matches!(mcp_completed.event, Some(ChatEvent::ToolResult { call_id, name, output, is_error }) if call_id == "mcp1" && name == "filesystem.read_file" && output.contains("hello") && !is_error)
        );

        let web_started = map_app_server_message(&json!({
            "method": "item/started",
            "params": {"item": {
                "id": "web1",
                "type": "webSearch",
                "query": "napaxi codex"
            }}
        }));
        assert!(
            matches!(web_started.event, Some(ChatEvent::ToolCall { call_id, name, arguments }) if call_id == "web1" && name == "web_search" && arguments.contains("napaxi codex"))
        );
    }

    #[test]
    fn maps_codex_file_changes_to_apply_patch_for_existing_write_renderer() {
        let started = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/started",
            "params": {"item": {
                "id": "file1",
                "type": "fileChange",
                "changes": [{
                    "path": "lib/main.dart",
                    "action": "update",
                    "additions": 2,
                    "deletions": 1
                }]
            }}
        }));
        assert!(
            matches!(started.event, Some(ChatEvent::ToolCall { call_id, name, arguments }) if call_id == "file1" && name == "apply_patch" && arguments.contains("lib/main.dart"))
        );
        assert_eq!(started.extra_events.len(), 1);
        let ChatEvent::ToolOutputChunk {
            call_id,
            stream,
            content,
        } = &started.extra_events[0]
        else {
            panic!("expected apply_patch progress chunk");
        };
        assert_eq!(call_id, "file1");
        assert_eq!(stream, "patch");
        let progress: serde_json::Value = serde_json::from_str(content).unwrap();
        assert_eq!(progress["type"], "apply_patch_progress");
        assert_eq!(progress["path"], "lib/main.dart");
        assert_eq!(progress["added_lines"], 2);
        assert_eq!(progress["removed_lines"], 1);

        let completed = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/completed",
            "params": {"item": {
                "id": "file1",
                "type": "fileChange",
                "status": "completed",
                "changes": [{
                    "path": "lib/main.dart",
                    "action": "update",
                    "additions": 2,
                    "deletions": 1
                }]
            }}
        }));
        let Some(ChatEvent::ToolResult {
            call_id,
            name,
            output,
            is_error,
        }) = completed.event
        else {
            panic!("expected fileChange ToolResult");
        };
        assert_eq!(call_id, "file1");
        assert_eq!(name, "apply_patch");
        assert!(!is_error);
        let output: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(output["status"], "ok");
        assert_eq!(output["files"][0]["path"], "lib/main.dart");
        assert_eq!(output["files"][0]["added_lines"], 2);
        assert_eq!(output["files"][0]["removed_lines"], 1);
    }

    #[test]
    fn maps_realtime_file_change_add_diff_to_apply_patch_line_counts() {
        let started = map_app_server_message(&json!({
            "method": "item/started",
            "params": {"item": {
                "type": "fileChange",
                "id": "call_file_add",
                "changes": [{
                    "path": "/tmp/probe_apply_patch_demo.py",
                    "kind": {"type": "add"},
                    "diff": "one\ntwo\nthree\n"
                }],
                "status": "inProgress"
            }}
        }));
        assert!(
            matches!(started.event, Some(ChatEvent::ToolCall { call_id, name, .. }) if call_id == "call_file_add" && name == "apply_patch")
        );
        assert_eq!(started.extra_events.len(), 1);
        let ChatEvent::ToolOutputChunk { content, .. } = &started.extra_events[0] else {
            panic!("expected apply_patch progress chunk");
        };
        let progress: serde_json::Value = serde_json::from_str(content).unwrap();
        assert_eq!(progress["type"], "apply_patch_progress");
        assert_eq!(progress["path"], "/tmp/probe_apply_patch_demo.py");
        assert_eq!(progress["action"], "added");
        assert_eq!(progress["added_lines"], 3);
        assert_eq!(progress["removed_lines"], 0);

        let completed = map_app_server_message(&json!({
            "method": "item/completed",
            "params": {"item": {
                "type": "fileChange",
                "id": "call_file_add",
                "changes": [{
                    "path": "/tmp/probe_apply_patch_demo.py",
                    "kind": {"type": "add"},
                    "diff": "one\ntwo\nthree\n"
                }],
                "status": "completed"
            }}
        }));
        let Some(ChatEvent::ToolResult { output, .. }) = completed.event else {
            panic!("expected fileChange ToolResult");
        };
        let output: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(output["files"][0]["action"], "added");
        assert_eq!(output["files"][0]["added_lines"], 3);
    }

    #[test]
    fn maps_codex_custom_apply_patch_started_to_progress_lines() {
        let started = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/started",
            "params": {"item": {
                "id": "ctc-1",
                "type": "custom_tool_call",
                "call_id": "call-apply-1",
                "name": "apply_patch",
                "input": "*** Begin Patch\n*** Add File: tmp_codex_render_test.txt\n+hello codex\n+second line\n*** End Patch\n"
            }}
        }));
        assert!(
            matches!(started.event, Some(ChatEvent::ToolCall { call_id, name, arguments }) if call_id == "call-apply-1" && name == "apply_patch" && arguments.contains("*** Add File"))
        );
        assert_eq!(started.extra_events.len(), 1);
        let ChatEvent::ToolOutputChunk {
            call_id,
            stream,
            content,
        } = &started.extra_events[0]
        else {
            panic!("expected apply_patch progress chunk");
        };
        assert_eq!(call_id, "call-apply-1");
        assert_eq!(stream, "patch");
        let progress: serde_json::Value = serde_json::from_str(content).unwrap();
        assert_eq!(progress["type"], "apply_patch_progress");
        assert_eq!(progress["path"], "tmp_codex_render_test.txt");
        assert_eq!(progress["action"], "added");
        assert_eq!(progress["added_lines"], 2);
        assert_eq!(progress["removed_lines"], 0);
    }
    fn test_turn_request(message: &str) -> crate::agent_engine::AgentEngineTurnRequest {
        crate::agent_engine::AgentEngineTurnRequest {
            engine_id: CODEX_ENGINE_ID.to_string(),
            engine_profile_id: String::new(),
            engine_config: serde_json::json!({}),
            run_id: "run".to_string(),
            files_dir: "files".to_string(),
            workspace_files_dir: "workspace".to_string(),
            account_id: "acct".to_string(),
            agent_id: "agent".to_string(),
            session_key_json: "{}".to_string(),
            message: message.to_string(),
            attachments_json: String::new(),
            config_json: "{}".to_string(),
        }
    }

    #[test]
    fn builds_skills_extra_roots_payload_for_sandbox_skills() {
        let mut rpc = super::protocol::JsonRpcClient::new();
        let (_, line) = super::protocol::skills_extra_roots_set_request(&mut rpc);
        let payload: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(payload["method"], "skills/extraRoots/set");
        assert_eq!(
            payload["params"]["extraRoots"],
            serde_json::json!(["/skills"])
        );
    }

    #[test]
    fn turn_start_input_is_plain_text_without_explicit_skill() {
        let mut rpc = super::protocol::JsonRpcClient::new();
        let state = super::state::CodexSessionState {
            native_thread_id: Some("thread".to_string()),
            config_fingerprint: String::new(),
            dynamic_tools_fingerprint: String::new(),
        };
        let line =
            super::protocol::turn_start_request(&mut rpc, &test_turn_request("hello"), &state);
        let payload: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(payload["method"], "turn/start");
        assert_eq!(
            payload["params"]["input"],
            serde_json::json!([{"type":"text","text":"hello"}])
        );
    }

    #[test]
    fn turn_start_input_includes_android_apk_build_skill_item() {
        let mut rpc = super::protocol::JsonRpcClient::new();
        let state = super::state::CodexSessionState {
            native_thread_id: Some("thread".to_string()),
            config_fingerprint: String::new(),
            dynamic_tools_fingerprint: String::new(),
        };
        let line = super::protocol::turn_start_request(
            &mut rpc,
            &test_turn_request("帮我构建 APK"),
            &state,
        );
        let payload: serde_json::Value = serde_json::from_str(&line).unwrap();
        let input = payload["params"]["input"].as_array().unwrap();
        assert_eq!(input.len(), 2);
        assert_eq!(input[0]["type"], "text");
        assert!(
            input[0]["text"]
                .as_str()
                .unwrap()
                .starts_with("$android-apk-build\n")
        );
        assert_eq!(
            input[1],
            serde_json::json!({
                "type": "skill",
                "name": "android-apk-build",
                "path": "/skills/android-apk-build/SKILL.md"
            })
        );
    }

    #[test]
    fn turn_start_input_includes_android_apk_build_for_plain_app_creation() {
        let mut rpc = super::protocol::JsonRpcClient::new();
        let state = super::state::CodexSessionState {
            native_thread_id: Some("thread".to_string()),
            config_fingerprint: String::new(),
            dynamic_tools_fingerprint: String::new(),
        };
        let line = super::protocol::turn_start_request(
            &mut rpc,
            &test_turn_request("帮我写一个简单记账 app，可以安装到手机上"),
            &state,
        );
        let payload: serde_json::Value = serde_json::from_str(&line).unwrap();
        let input = payload["params"]["input"].as_array().unwrap();
        assert_eq!(input.len(), 2);
        assert_eq!(input[1]["name"], "android-apk-build");

        let terse_line =
            super::protocol::turn_start_request(&mut rpc, &test_turn_request("写app"), &state);
        let terse_payload: serde_json::Value = serde_json::from_str(&terse_line).unwrap();
        assert_eq!(
            terse_payload["params"]["input"].as_array().unwrap().len(),
            2
        );
    }

    #[test]
    fn turn_start_input_allows_web_wrappers_but_not_flutter_apps() {
        let mut rpc = super::protocol::JsonRpcClient::new();
        let state = super::state::CodexSessionState {
            native_thread_id: Some("thread".to_string()),
            config_fingerprint: String::new(),
            dynamic_tools_fingerprint: String::new(),
        };

        let web_line = super::protocol::turn_start_request(
            &mut rpc,
            &test_turn_request("帮我做一个 web app 的登录页"),
            &state,
        );
        let web_payload: serde_json::Value = serde_json::from_str(&web_line).unwrap();
        assert_eq!(web_payload["params"]["input"].as_array().unwrap().len(), 2);
        assert_eq!(
            web_payload["params"]["input"].as_array().unwrap()[1]["name"],
            "android-apk-build"
        );

        let flutter_line = super::protocol::turn_start_request(
            &mut rpc,
            &test_turn_request("创建一个 Flutter app 页面"),
            &state,
        );
        let flutter_payload: serde_json::Value = serde_json::from_str(&flutter_line).unwrap();
        assert_eq!(
            flutter_payload["params"]["input"].as_array().unwrap().len(),
            1
        );
    }
}
