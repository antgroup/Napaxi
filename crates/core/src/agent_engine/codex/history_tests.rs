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

#[test]
fn maps_codex_tool_history_with_alternate_id_and_output_fields() {
    let message = map_history_item(&json!({
        "callId": "call-2",
        "type": "commandExecution",
        "command": "echo hi",
        "stdout": "hi\n",
        "status": "completed"
    }))
    .unwrap();
    assert_eq!(message["role"], "tool_calls");
    assert_eq!(message["id"], "call-2");
    let content: Value = serde_json::from_str(message["content"].as_str().unwrap()).unwrap();
    let call = &content["calls"][0];
    assert_eq!(call["name"], "shell");
    assert_eq!(call["call_id"], "call-2");
    assert_eq!(call["result"], "hi\n");
}

#[test]
fn maps_codex_reasoning_history_string_and_object_content() {
    let string_message = map_history_item(&json!({
        "id": "r2",
        "type": "reasoning",
        "summary": "first thought"
    }))
    .unwrap();
    assert_eq!(string_message["role"], "reasoning");
    assert_eq!(string_message["content"], "first thought");

    let object_message = map_history_item(&json!({
        "id": "r3",
        "type": "reasoning",
        "content": [{"type": "text", "text": "second thought"}]
    }))
    .unwrap();
    assert_eq!(object_message["role"], "reasoning");
    assert_eq!(object_message["content"], "second thought");
}

#[test]
fn maps_persisted_response_items_to_messages_reasoning_and_shell_trace() {
    let items = vec![
        json!({
            "type": "response_item",
            "payload": {
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": "请运行 printf"}]
            }
        }),
        json!({
            "type": "response_item",
            "payload": {
                "id": "rs-1",
                "type": "reasoning",
                "content": [{"type": "reasoning_text", "text": "Need to run a shell command."}]
            }
        }),
        json!({
            "type": "response_item",
            "payload": {
                "id": "fc-1",
                "type": "function_call",
                "name": "exec_command",
                "call_id": "call-fc-1",
                "arguments": "{\"cmd\":\"printf 'hello\\nworld\\n'\"}"
            }
        }),
        json!({
            "type": "response_item",
            "payload": {
                "type": "function_call_output",
                "call_id": "call-fc-1",
                "output": "Output:\nhello\nworld\n"
            }
        }),
        json!({
            "type": "response_item",
            "payload": {
                "id": "msg-1",
                "type": "message",
                "role": "assistant",
                "content": [{"type": "output_text", "text": "完成"}]
            }
        }),
    ];
    let messages = map_history_items(&items);
    assert_eq!(messages.len(), 4);
    assert_eq!(messages[0]["role"], "user");
    assert_eq!(messages[1]["role"], "reasoning");
    assert_eq!(messages[2]["role"], "tool_calls");
    let content: Value = serde_json::from_str(messages[2]["content"].as_str().unwrap()).unwrap();
    let call = &content["calls"][0];
    assert_eq!(call["name"], "shell");
    assert_eq!(call["call_id"], "call-fc-1");
    assert!(call["arguments"].as_str().unwrap().contains("printf"));
    assert!(call["result"].as_str().unwrap().contains("hello"));
    assert_eq!(messages[3]["role"], "assistant");
    assert_eq!(messages[3]["content"], "完成");
}

#[test]
fn maps_persisted_custom_apply_patch_to_history_write_file_schema() {
    let items = vec![
        json!({
            "type": "response_item",
            "payload": {
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": "用 apply_patch 写文件"}]
            }
        }),
        json!({
            "type": "response_item",
            "payload": {
                "id": "ctc-1",
                "type": "custom_tool_call",
                "status": "completed",
                "call_id": "call-apply-1",
                "name": "apply_patch",
                "input": "*** Begin Patch\n*** Add File: tmp_codex_render_test.txt\n+hello codex\n+second line\n*** End Patch\n"
            }
        }),
        json!({
            "type": "response_item",
            "payload": {
                "type": "custom_tool_call_output",
                "call_id": "call-apply-1",
                "output": "Exit code: 0\nWall time: 0 seconds\nOutput:\nSuccess. Updated the following files:\nA tmp_codex_render_test.txt\n"
            }
        }),
        json!({
            "type": "response_item",
            "payload": {
                "id": "msg-1",
                "type": "message",
                "role": "assistant",
                "content": [{"type": "output_text", "text": "完成"}]
            }
        }),
    ];
    let messages = map_history_items(&items);
    assert_eq!(messages.len(), 3);
    assert_eq!(messages[1]["role"], "tool_calls");
    let content: Value = serde_json::from_str(messages[1]["content"].as_str().unwrap()).unwrap();
    let call = &content["calls"][0];
    assert_eq!(call["name"], "apply_patch");
    assert_eq!(call["call_id"], "call-apply-1");
    assert!(call["arguments"].as_str().unwrap().contains("*** Add File"));
    let result: Value = serde_json::from_str(call["result"].as_str().unwrap()).unwrap();
    assert_eq!(result["status"], "ok");
    assert_eq!(result["files"][0]["path"], "tmp_codex_render_test.txt");
    assert_eq!(result["files"][0]["action"], "added");
    assert_eq!(result["files"][0]["added_lines"], 2);
    assert_eq!(result["files"][0]["removed_lines"], 0);
    assert!(result["output"].as_str().unwrap().contains("Success"));
    assert_eq!(messages[2]["role"], "assistant");
}

#[test]
fn maps_codex_file_changes_to_history_apply_patch_schema() {
    let message = map_history_item(&json!({
        "id": "file-1",
        "type": "fileChange",
        "status": "completed",
        "changes": [{
            "path": "lib/main.dart",
            "action": "update",
            "additions": 2,
            "deletions": 1
        }]
    }))
    .unwrap();
    assert_eq!(message["role"], "tool_calls");
    let content: Value = serde_json::from_str(message["content"].as_str().unwrap()).unwrap();
    let call = &content["calls"][0];
    assert_eq!(call["name"], "apply_patch");
    assert!(
        call["arguments"]
            .as_str()
            .unwrap()
            .contains("lib/main.dart")
    );
    let result: Value = serde_json::from_str(call["result"].as_str().unwrap()).unwrap();
    assert_eq!(result["status"], "ok");
    assert_eq!(result["files"][0]["path"], "lib/main.dart");
    assert_eq!(result["files"][0]["added_lines"], 2);
    assert_eq!(result["files"][0]["removed_lines"], 1);
}
