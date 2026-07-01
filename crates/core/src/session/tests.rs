use super::*;
use crate::types::PlatformLlmConfig;
use chrono::Utc;
use serde_json::Value;

fn temp_files_dir(name: &str) -> String {
    let millis = Utc::now().timestamp_millis();
    std::env::temp_dir()
        .join(format!("napaxi_mobile_session_{name}_{millis}"))
        .display()
        .to_string()
}

fn config() -> PlatformLlmConfig {
    PlatformLlmConfig {
        provider: "openai".to_string(),
        api_key: "test".to_string(),
        base_url: None,
        model: "test-model".to_string(),
        system_prompt: String::new(),
        max_tokens: 1000,
        max_tool_iterations: 0,
        extra_headers: None,
        allowed_models: None,
        image_model: None,
        image_analysis_model: None,
        capability_configs: None,
        scene_prompt_config: None,
        ..PlatformLlmConfig::default()
    }
}

fn engine_handle(files_dir: &str) -> i64 {
    let config_json = serde_json::to_string(&config()).unwrap();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null,
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

#[test]
fn session_crud_and_history_work() {
    let files_dir = temp_files_dir("crud");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(append_message(&files_dir, &key_json, "user", "hello"));
    assert!(append_message(&files_dir, &key_json, "assistant", "hi"));

    let sessions = list_sessions(&files_dir, "agent-a", "user-a");
    assert!(sessions.contains(&key.thread_id));
    assert!(sessions.contains("\"message_count\":2"));

    let history = get_history(&files_dir, &key.thread_id);
    assert!(history.contains("\"role\":\"user\""));
    assert!(history.contains("\"content\":\"hi\""));
    assert_eq!(llm_history(&files_dir, &key.thread_id, 10).len(), 2);

    assert!(clear_session(&files_dir, &key_json));
    assert_eq!(get_history(&files_dir, &key.thread_id), "[]");
    assert!(delete_session(&files_dir, &key_json));
}

#[test]
fn llm_history_keeps_trailing_user_message_for_current_turn() {
    let files_dir = temp_files_dir("trailing-user");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(append_message(
        &files_dir,
        &key_json,
        "user",
        "开发个贪食蛇"
    ));

    let history = llm_history(&files_dir, &key.thread_id, 10);
    assert_eq!(history.len(), 1);
    assert_eq!(history[0].role, "user");
    assert_eq!(history[0].content, "开发个贪食蛇");
}

#[test]
fn delete_session_if_empty_removes_ghost_but_keeps_used() {
    let files_dir = temp_files_dir("empty-hygiene");

    let ghost_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let ghost: SessionKey = serde_json::from_str(&ghost_json).unwrap();

    let used_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    assert!(append_message(&files_dir, &used_json, "user", "hello"));

    // Ghost session is removed; used session is kept.
    assert!(delete_session_if_empty(&files_dir, &ghost_json));
    assert!(!delete_session_if_empty(&files_dir, &used_json));

    let sessions = list_sessions(&files_dir, "agent-a", "user-a");
    assert!(!sessions.contains(&ghost.thread_id));

    // A second call on the now-missing ghost is a no-op.
    assert!(!delete_session_if_empty(&files_dir, &ghost_json));
}

#[test]
fn prune_empty_sessions_clears_only_ghosts() {
    let files_dir = temp_files_dir("prune-empty");

    create_session(&files_dir, "agent-a", "app", "user-a", None);
    create_session(&files_dir, "agent-a", "app", "user-a", None);
    let used_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    assert!(append_message(&files_dir, &used_json, "user", "hi"));

    assert_eq!(prune_empty_sessions(&files_dir, "agent-a", "user-a"), 2);

    let sessions = list_sessions(&files_dir, "agent-a", "user-a");
    assert!(sessions.contains("\"message_count\":1"));
    assert_eq!(prune_empty_sessions(&files_dir, "agent-a", "user-a"), 0);
}

#[test]
fn empty_agent_id_uses_runtime_default_scope() {
    let files_dir = temp_files_dir("default-agent");
    let key_json = create_session(&files_dir, "", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(append_message(&files_dir, &key_json, "user", "hello"));
    assert!(
        list_sessions(&files_dir, crate::runtime::DEFAULT_AGENT_ID, "user-a")
            .contains(&key.thread_id)
    );
    assert_eq!(list_sessions(&files_dir, "default", "user-a"), "[]");
}

#[test]
fn previous_default_agent_sessions_are_visible_in_runtime_default_scope() {
    let files_dir = temp_files_dir("previous-default-agent");
    let key_json = create_session(&files_dir, "default", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(append_message(
        &files_dir,
        &key_json,
        "user",
        "previous hello"
    ));
    assert!(
        list_sessions(&files_dir, crate::runtime::DEFAULT_AGENT_ID, "user-a")
            .contains(&key.thread_id)
    );
    assert!(get_history(&files_dir, &key.thread_id).contains("previous hello"));
}

#[test]
fn handle_wrappers_delegate_to_session_storage() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let handle = engine_handle(files_dir);

    assert_eq!(
        create_session_handle(0, "agent-a", "app", "user-a", None),
        super::store::INVALID_HANDLE_JSON
    );
    assert_eq!(list_sessions_handle(0, "agent-a", "user-a"), "[]");

    let key_json = create_session_handle(handle, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();
    assert!(inject_user_message_handle(handle, &key_json, "hello", "[]"));

    let sessions = list_sessions_handle(handle, "agent-a", "user-a");
    assert!(sessions.contains(&key.thread_id));
    assert!(get_history_handle(handle, &key.thread_id).contains("\"content\":\"hello\""));
    assert!(get_history_page_handle(handle, &key.thread_id, None, 20).contains("hello"));

    assert!(clear_session_handle(handle, &key_json));
    assert_eq!(get_history_handle(handle, &key.thread_id), "[]");
    assert!(delete_session_handle(handle, &key_json));
    assert!(!delete_session_handle(0, &key_json));

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn trace_messages_are_persisted_for_ui_and_replayed_for_llm_context() {
    let files_dir = temp_files_dir("trace");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(append_message(&files_dir, &key_json, "user", "list files"));
    assert!(append_trace_messages(
        &files_dir,
        &key_json,
        "I should inspect the workspace.",
        &[serde_json::json!({
            "call_id": "call_1",
            "name": "shell",
            "arguments": "{\"command\":\"ls\"}",
            "result": "README.md"
        })]
    ));
    assert!(append_message(
        &files_dir,
        &key_json,
        "assistant",
        "README.md"
    ));

    let history: Value = serde_json::from_str(&get_history(&files_dir, &key.thread_id)).unwrap();
    let roles: Vec<_> = history
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|item| item.get("role").and_then(Value::as_str))
        .collect();
    assert_eq!(roles, vec!["user", "reasoning", "tool_calls", "assistant"]);
    assert_eq!(llm_history(&files_dir, &key.thread_id, 10).len(), 2);
    let context_history = llm_context_history_all(&files_dir, &key.thread_id);
    let context_roles: Vec<_> = context_history
        .iter()
        .map(|message| message.role.as_str())
        .collect();
    assert_eq!(context_roles, vec!["user", "tool_calls", "assistant"]);
    let raw = crate::llm::openai_messages_from_mobile_history(&context_history);
    assert_eq!(raw[0]["role"].as_str(), Some("user"));
    assert_eq!(raw[1]["role"].as_str(), Some("assistant"));
    assert_eq!(raw[1]["tool_calls"][0]["id"].as_str(), Some("call_1"));
    assert_eq!(
        raw[1]["tool_calls"][0]["function"]["name"].as_str(),
        Some("shell")
    );
    assert_eq!(raw[2]["role"].as_str(), Some("tool"));
    assert_eq!(raw[2]["tool_call_id"].as_str(), Some("call_1"));
    assert_eq!(raw[2]["content"].as_str(), Some("README.md"));
    assert_eq!(raw[3]["role"].as_str(), Some("assistant"));
}

#[test]
fn llm_context_replay_skips_hidden_tools_and_repairs_invalid_trace() {
    let history = vec![SessionMessage {
        id: "m1".to_string(),
        role: "tool_calls".to_string(),
        content: serde_json::json!({
            "calls": [
                {
                    "call_id": "hidden",
                    "name": crate::skills::SKILL_LOAD_TOOL_NAME,
                    "arguments": "{}",
                    "result": "private implementation"
                },
                {
                    "call_id": "call_1",
                    "name": "web_search",
                    "arguments": "{\"q\":\"napaxi\"}",
                    "result": "result one"
                },
                {
                    "call_id": "call_1",
                    "name": "web_search",
                    "arguments": "{\"q\":\"duplicate\"}",
                    "result": "duplicate result"
                },
                {
                    "call_id": "call_2",
                    "name": "read_file",
                    "arguments": "{\"path\":\"README.md\"}"
                },
                {
                    "call_id": "delegation:agent",
                    "name": "delegate · agent",
                    "arguments": "please inspect",
                    "result": "delegated answer"
                }
            ]
        })
        .to_string(),
        created_at: Utc::now().to_rfc3339(),
        interrupted: false,
        turn_id: None,
    }];

    let raw = crate::llm::openai_messages_from_mobile_history(&history);

    assert_eq!(raw.len(), 4);
    assert_eq!(raw[0]["role"].as_str(), Some("assistant"));
    let tool_calls = raw[0]["tool_calls"].as_array().unwrap();
    assert_eq!(tool_calls.len(), 2);
    assert_eq!(tool_calls[0]["id"].as_str(), Some("call_1"));
    assert_eq!(tool_calls[1]["id"].as_str(), Some("call_2"));
    assert_eq!(raw[1]["role"].as_str(), Some("tool"));
    assert_eq!(raw[1]["content"].as_str(), Some("result one"));
    assert_eq!(raw[2]["role"].as_str(), Some("tool"));
    assert!(
        raw[2]["content"]
            .as_str()
            .unwrap()
            .contains("missing from persisted transcript")
    );
    assert_eq!(raw[3]["role"].as_str(), Some("assistant"));
    assert!(
        raw[3]["content"]
            .as_str()
            .unwrap()
            .contains("Prior tool observation")
    );
    let raw_text = serde_json::to_string(&raw).unwrap();
    assert!(!raw_text.contains("private implementation"));
    assert!(!raw_text.contains("duplicate result"));
}

#[test]
fn replace_turn_segment_overwrites_only_trailing_same_turn() {
    let files_dir = temp_files_dir("turn_replace");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(append_message(&files_dir, &key_json, "user", "do work"));
    assert!(replace_turn_segment(
        &files_dir,
        &key_json,
        "turn-a",
        &[SessionAppendMessage {
            role: "reasoning".to_string(),
            content: "partial".to_string(),
            interrupted: true,
            turn_id: None,
        }],
    ));
    assert!(replace_turn_segment(
        &files_dir,
        &key_json,
        "turn-a",
        &[
            SessionAppendMessage {
                role: "reasoning".to_string(),
                content: "final reasoning".to_string(),
                interrupted: false,
                turn_id: None,
            },
            SessionAppendMessage {
                role: "assistant".to_string(),
                content: "done".to_string(),
                interrupted: false,
                turn_id: None,
            },
        ],
    ));

    let history: Value = serde_json::from_str(&get_history(&files_dir, &key.thread_id)).unwrap();
    let items = history.as_array().unwrap();
    let roles: Vec<_> = items
        .iter()
        .filter_map(|item| item.get("role").and_then(Value::as_str))
        .collect();
    assert_eq!(roles, vec!["user", "reasoning", "assistant"]);
    assert_eq!(items[1]["content"].as_str(), Some("final reasoning"));
    assert!(items[1].get("interrupted").is_none());
}

#[test]
fn interrupted_tool_calls_message_projects_per_call_interrupted_flag() {
    let files_dir = temp_files_dir("tool_calls_interrupt");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(append_messages(
        &files_dir,
        &key_json,
        &[SessionAppendMessage {
            role: "tool_calls".to_string(),
            content: serde_json::json!({
                "calls": [
                    { "call_id": "c1", "name": "shell", "arguments": "{}", "result": "ok" },
                    { "call_id": "c2", "name": "shell", "arguments": "{}" }
                ]
            })
            .to_string(),
            interrupted: true,
            turn_id: Some("turn-x".to_string()),
        }],
    ));

    let history: Value = serde_json::from_str(&get_history(&files_dir, &key.thread_id)).unwrap();
    let item = &history.as_array().unwrap()[0];
    let payload: Value = serde_json::from_str(item["content"].as_str().unwrap()).unwrap();
    let calls = payload["calls"].as_array().unwrap();
    assert_eq!(calls[0]["call_id"], "c1");
    assert!(calls[0].get("interrupted").is_none());
    assert_eq!(calls[1]["call_id"], "c2");
    assert_eq!(calls[1]["interrupted"], Value::Bool(true));
}

#[test]
fn history_page_compacts_large_tool_results() {
    let files_dir = temp_files_dir("history_page_compact_tool_results");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();
    let large_result = "x".repeat(2000);

    assert!(append_messages(
        &files_dir,
        &key_json,
        &[
            SessionAppendMessage {
                role: "tool_calls".to_string(),
                content: serde_json::json!({
                    "calls": [
                        {
                            "call_id": "c1",
                            "name": "browser_snapshot",
                            "arguments": "{}",
                            "result": large_result,
                        }
                    ]
                })
                .to_string(),
                interrupted: false,
                turn_id: Some("turn-x".to_string()),
            },
            SessionAppendMessage {
                role: "assistant".to_string(),
                content: "done".to_string(),
                interrupted: false,
                turn_id: Some("turn-x".to_string()),
            },
        ],
    ));

    let history: Value = serde_json::from_str(&get_history(&files_dir, &key.thread_id)).unwrap();
    let full_payload: Value =
        serde_json::from_str(history[0]["content"].as_str().unwrap()).unwrap();
    assert_eq!(
        full_payload["calls"][0]["result"].as_str().unwrap().len(),
        2000
    );

    let page: Value =
        serde_json::from_str(&get_history_page(&files_dir, &key.thread_id, None, 10)).unwrap();
    let item = &page["messages"].as_array().unwrap()[0];
    let payload: Value = serde_json::from_str(item["content"].as_str().unwrap()).unwrap();
    let call = &payload["calls"][0];
    assert_eq!(call["call_id"], "c1");
    assert_eq!(call["result_truncated"], Value::Bool(true));
    assert_eq!(call["result_chars"], serde_json::json!(2000));
    assert!(call["result"].as_str().unwrap().len() < 2000);
}

#[test]
fn inject_user_message_persists_message_and_attachments() {
    let files_dir = temp_files_dir("inject");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();

    assert!(inject_user_message(&files_dir, &key_json, "first", "[]"));
    assert!(inject_user_message(
        &files_dir,
        &key_json,
        "second",
        r#"[{"name":"notes.txt","path":"/workspace/notes.txt"}]"#
    ));

    let history: Value = serde_json::from_str(&get_history(&files_dir, &key.thread_id)).unwrap();
    let messages = history.as_array().unwrap();
    assert_eq!(messages.len(), 2);
    assert!(messages[0].get("attachments").is_none());
    assert_eq!(
        messages[1]["attachments"][0]["filename"].as_str(),
        Some("notes.txt")
    );
    assert_eq!(
        messages[1]["attachments"][0]["sandbox_path"].as_str(),
        Some("/workspace/notes.txt")
    );
}

#[test]
fn history_page_uses_before_cursor() {
    let files_dir = temp_files_dir("page");
    let key_json = create_session(&files_dir, "agent-a", "app", "user-a", None);
    let key: SessionKey = serde_json::from_str(&key_json).unwrap();
    for idx in 0..5 {
        assert!(append_message(
            &files_dir,
            &key_json,
            "user",
            &format!("message-{idx}")
        ));
    }

    let page: Value =
        serde_json::from_str(&get_history_page(&files_dir, &key.thread_id, None, 2)).unwrap();
    assert_eq!(page["has_more"], true);
    assert_eq!(page["messages"].as_array().unwrap().len(), 2);

    let before = page["next_before"].as_str().unwrap();
    let older: Value = serde_json::from_str(&get_history_page(
        &files_dir,
        &key.thread_id,
        Some(before),
        2,
    ))
    .unwrap();
    assert_eq!(older["messages"].as_array().unwrap().len(), 2);
}
