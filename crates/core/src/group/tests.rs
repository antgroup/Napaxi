//! Integration tests covering CRUD, messages, coordinator helpers, tool
//! dispatch, and engine-handle wrappers.

use std::sync::Arc;

use super::coordinator::{
    append_system_prompt, build_coordinator_prompt, build_coordinator_prompt_with_language,
    extract_response, group_members_text, session_key, wrap_events,
};
use super::crud::{
    create_group, delete_group, get_group, list_groups, rename_group, set_group_custom_prompt,
    update_group_members,
};
use super::export::{export_group_state, import_group_state};
use super::handles::{
    clear_group_history_handle, create_group_handle, delete_group_handle,
    export_group_state_handle, get_group_handle, get_group_messages_handle,
    import_group_state_handle, list_groups_handle, rename_group_handle, send_to_group_agent_handle,
    send_to_group_handle, set_group_custom_prompt_handle, update_group_members_handle,
};
use super::messages::{
    add_agent_message, add_user_message, clear_group_history, get_group_messages, is_group_member,
};
use super::tools::{execute_group_tool, group_internal_tool_handler, group_tool_descriptors};

fn engine_handle(files_dir: &str) -> i64 {
    let config_json = serde_json::json!({
        "provider": "openai",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

// Engine whose LLM provider is the offline `__test_noop__` seam: a group turn
// runs end-to-end (admission, tool loop, finalize) without any network, the
// model returning an empty response. Lets delegate.rs be driven deterministically.
fn noop_engine_arc(files_dir: &str) -> std::sync::Arc<crate::runtime::Engine> {
    let config_json = serde_json::json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "capability_profile": { "platform": "test" },
        "native_library_dir": null
    })
    .to_string();
    let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();
    // SAFETY: handle was just created in this test and is not consumed elsewhere.
    unsafe { crate::runtime::handle_to_arc(handle) }.unwrap()
}

#[test]
fn manages_group_state() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let group_id = create_group(&files_dir, "demo", r#"["agent-a"]"#);
    assert!(!group_id.is_empty());
    assert!(list_groups(&files_dir).contains("demo"));
    assert!(is_group_member(&files_dir, &group_id, "agent-a"));
    assert!(add_user_message(&files_dir, &group_id, "hello"));
    assert!(add_agent_message(&files_dir, &group_id, "napaxi", "hi"));
    assert!(get_group_messages(&files_dir, &group_id).contains("hello"));
    assert!(rename_group(&files_dir, &group_id, "renamed"));
    assert!(get_group(&files_dir, &group_id).contains("renamed"));
    assert!(clear_group_history(&files_dir, &group_id));
    assert_eq!(get_group_messages(&files_dir, &group_id), "[]");
    let exported = export_group_state(&files_dir);
    assert!(delete_group(&files_dir, &group_id));
    assert!(import_group_state(&files_dir, &exported));
    assert!(get_group(&files_dir, &group_id).contains("renamed"));
}

#[tokio::test]
async fn handle_wrappers_delegate_to_group_state() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);

    assert_eq!(create_group_handle(0, "missing", r#"["agent-a"]"#), "");
    assert_eq!(list_groups_handle(0), "[]");
    assert_eq!(get_group_handle(0, "missing"), "null");
    assert_eq!(get_group_messages_handle(0, "missing"), "[]");
    assert_eq!(export_group_state_handle(0), "{}");
    assert!(!delete_group_handle(0, "missing"));
    assert!(!rename_group_handle(0, "missing", "next"));
    assert!(!update_group_members_handle(0, "missing", "[]"));
    assert!(!set_group_custom_prompt_handle(
        0,
        "missing",
        Some("prompt".to_string())
    ));
    assert!(!clear_group_history_handle(0, "missing"));
    assert!(!import_group_state_handle(0, "{}"));
    assert!(
        send_to_group_handle(0, "missing", "{}", "hello", 1)
            .await
            .contains("error")
    );
    assert!(
        send_to_group_agent_handle(0, "missing", "agent-a", "{}", "", "hello", 1)
            .await
            .contains("error")
    );

    let group_id = create_group_handle(handle, "demo", r#"["agent-a"]"#);
    assert!(!group_id.is_empty());
    assert!(list_groups_handle(handle).contains("demo"));
    assert!(get_group_handle(handle, &group_id).contains("agent-a"));
    assert!(rename_group_handle(handle, &group_id, "renamed"));
    assert!(update_group_members_handle(
        handle,
        &group_id,
        r#"["agent-a","agent-b"]"#
    ));
    assert!(set_group_custom_prompt_handle(
        handle,
        &group_id,
        Some("custom prompt".to_string())
    ));
    assert!(get_group_handle(handle, &group_id).contains("custom prompt"));
    assert!(add_user_message(&files_dir, &group_id, "hello"));
    assert!(get_group_messages_handle(handle, &group_id).contains("hello"));
    assert!(clear_group_history_handle(handle, &group_id));
    assert_eq!(get_group_messages_handle(handle, &group_id), "[]");
    let exported = export_group_state_handle(handle);
    assert!(delete_group_handle(handle, &group_id));
    assert!(import_group_state_handle(handle, &exported));
    assert!(get_group_handle(handle, &group_id).contains("renamed"));

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn builds_group_runtime_helpers() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let group_id = create_group(&files_dir, "demo", r#"["agent-a"]"#);
    assert!(group_members_text(&files_dir, &group_id).contains("agent-a"));
    assert!(build_coordinator_prompt(&files_dir, &group_id).is_some());
    let zh_prompt = build_coordinator_prompt_with_language(&files_dir, &group_id, "zh").unwrap();
    assert!(zh_prompt.contains("你是 Agent 群聊的协调者"));
    assert!(zh_prompt.contains("群组成员"));
    assert_eq!(group_tool_descriptors().len(), 2);

    let config = serde_json::json!({
        "provider": "openai",
        "api_key": "k",
        "model": "m",
        "system_prompt": "base",
        "max_tokens": 10
    })
    .to_string();
    let with_prompt = append_system_prompt(&config, "group prompt");
    assert!(with_prompt.contains("base\\n\\ngroup prompt"));

    let events = wrap_events(
        serde_json::json!({"type":"start"}),
        r#"[{"type":"response","content":"done"}]"#,
        serde_json::json!({"type":"end"}),
    );
    assert_eq!(extract_response(&events).as_deref(), Some("done"));
    assert!(session_key(&files_dir, &group_id, "agent-a").contains(&group_id));
}

#[tokio::test]
async fn executes_group_tools_with_delegate_callback() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let group_id = create_group(&files_dir, "demo", r#"["agent-a"]"#);

    let listed = execute_group_tool(
        &files_dir,
        &group_id,
        "napaxi",
        "{}",
        "list_group_members",
        serde_json::json!({}),
        |_| async { unreachable!("list_group_members should not delegate") },
    )
    .await
    .unwrap();
    assert!(listed.output.contains("agent-a"));

    let expected_group_id = group_id.clone();
    let sent = execute_group_tool(
        &files_dir,
        &group_id,
        "napaxi",
        "{}",
        "send_to_group_member",
        serde_json::json!({"member_id":"agent-a","task":"help"}),
        |request| async move {
            assert_eq!(request.member_id, "agent-a");
            assert_eq!(request.task, "help");
            let session: serde_json::Value =
                serde_json::from_str(&request.session_key_json).unwrap();
            assert_eq!(
                session
                    .get("account_id")
                    .and_then(serde_json::Value::as_str),
                Some(expected_group_id.as_str())
            );
            Ok(r#"[{"type":"response","content":"member answer"}]"#.to_string())
        },
    )
    .await
    .unwrap();
    assert_eq!(sent.output, "member answer");
    assert_eq!(sent.events.len(), 2);
    assert!(get_group_messages(&files_dir, &group_id).contains("member answer"));
}

#[tokio::test]
async fn core_group_internal_handler_lists_members() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let group_id = create_group(&files_dir, "demo", r#"["agent-a"]"#);
    let config_json = serde_json::json!({
        "provider": "openai",
        "api_key": "k",
        "base_url": null,
        "model": "m",
        "system_prompt": "base",
        "max_tokens": 10
    })
    .to_string();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null
    })
    .to_string();
    let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();
    // SAFETY: `handle` was just created in this test and not yet consumed, satisfying `handle_to_arc`'s contract.
    let engine = unsafe { crate::runtime::handle_to_arc(handle) }.unwrap();

    let handler = group_internal_tool_handler(
        tmp.path().to_string_lossy().to_string(),
        group_id,
        config_json,
        Arc::clone(&engine),
        1,
        None,
    );
    let result = handler("list_group_members", serde_json::json!({}), None)
        .expect("group tool future")
        .await
        .unwrap();
    assert!(result.output.contains("agent-a"));
    assert!(result.events.is_empty());

    drop(handler);
    drop(engine);
    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[tokio::test]
async fn send_to_group_returns_error_when_group_missing() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let engine = noop_engine_arc(&files_dir);

    let result = super::delegate::send_to_group(engine, "no-such-group", "{}", "hello", 1).await;
    assert_eq!(result.unwrap_err(), "group not found");
}

#[tokio::test]
async fn send_to_group_runs_a_turn_for_an_existing_group() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let group_id = create_group(&files_dir, "demo", r#"["agent-a"]"#);
    let engine = noop_engine_arc(&files_dir);

    // The noop provider returns an empty response, so the coordinator turn
    // completes Ok with no model content. The user message must be recorded.
    let events = super::delegate::send_to_group(engine, &group_id, "{}", "hello team", 1)
        .await
        .expect("group turn should succeed");
    let _ = events; // may be empty (no model output) — the point is it ran Ok.
    assert!(get_group_messages(&files_dir, &group_id).contains("hello team"));
}

#[tokio::test]
async fn send_to_group_agent_rejects_non_member() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let group_id = create_group(&files_dir, "demo", r#"["agent-a"]"#);
    let engine = noop_engine_arc(&files_dir);

    let result = super::delegate::send_to_group_agent(
        engine,
        &group_id,
        "agent-not-in-group",
        "{}",
        "",
        "do it",
        1,
    )
    .await;
    assert_eq!(result.unwrap_err(), "agent is not a member of the group");
}

#[tokio::test]
async fn send_to_group_agent_runs_a_turn_for_a_member() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let group_id = create_group(&files_dir, "demo", r#"["agent-a"]"#);
    let engine = noop_engine_arc(&files_dir);

    let events = super::delegate::send_to_group_agent(
        engine,
        &group_id,
        "agent-a",
        "{}",
        "",
        "summarize",
        1,
    )
    .await
    .expect("member turn should succeed");
    let _ = events;
}
