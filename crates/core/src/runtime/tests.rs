//! Runtime integration tests covering engine handle, sessions, tools, turn IO.

use super::engine::Engine;
use super::messaging::{SessionTurnInput, run_session_turn, stream_session_turn};
use super::tool_context::prepare_session_tool_context_with_config;
use crate::turn::{
    ChatRuntimeInput, TurnHistoryRecorder, attachment_metadata_json,
    parse_scene_prompt_attachments, persist_attachment_files, persist_turn_history_segments,
    prepare_chat_config, prepare_turn as prepare_session_turn, raw_history_with_attachments,
};
use base64::Engine as _;
use std::collections::HashMap;

use crate::types::{
    AttachmentKind, ChatEvent, IncomingAttachment, PlatformLlmCapabilityConfig, PlatformLlmConfig,
};

fn config() -> PlatformLlmConfig {
    PlatformLlmConfig {
        provider: "openai".to_string(),
        api_key: "test".to_string(),
        base_url: None,
        model: "test-model".to_string(),
        system_prompt: "Host prompt.".to_string(),
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

#[test]
fn session_tool_context_uses_turn_config_capability_tools() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let engine = Engine::new(
        files_dir,
        Some("test".to_string()),
        None,
        config(),
        crate::capabilities::CapabilityProfile::default(),
        crate::capabilities::CapabilitySelection::default(),
        napaxi_skills::SkillReadinessContext::default(),
    );
    let mut turn_config = config();
    turn_config.capability_configs = Some(HashMap::from([(
        "imageAnalysis".to_string(),
        PlatformLlmCapabilityConfig {
            provider: "openai_compatible".to_string(),
            api_key: "vision-key".to_string(),
            base_url: Some("https://vision.example/v1".to_string()),
            model: "vision-model".to_string(),
            max_tokens: None,
            extra_headers: None,
            image_base64_url_format: None,
        },
    )]));

    let context =
        prepare_session_tool_context_with_config(&engine, "user-a", "agent-a", turn_config);

    assert!(
        context
            .extra_tools
            .iter()
            .any(|tool| tool.name == "image_analyze")
    );
}

#[test]
fn attachments_are_decoded_persisted_and_added_to_raw_history() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let data_base64 = base64::engine::general_purpose::STANDARD.encode(b"image-bytes");
    let attachments_json = serde_json::json!([{
        "kind": "image",
        "mime_type": "image/png",
        "filename": "../photo.png",
        "data_base64": data_base64,
    }])
    .to_string();
    let mut attachments = parse_scene_prompt_attachments(&attachments_json);

    assert_eq!(attachments[0].data, b"image-bytes");
    persist_attachment_files(files_dir, files_dir, "thread/a", &mut attachments);
    let sandbox_path = attachments[0].storage_key.as_deref().unwrap();
    assert!(sandbox_path.starts_with("/workspace/attachments/thread_a/"));
    assert!(
        crate::storage::sandbox_to_real(files_dir, sandbox_path)
            .map(|path| std::path::Path::new(&path).is_file())
            .unwrap_or(false)
    );

    let metadata = attachment_metadata_json(&attachments);
    assert!(metadata.contains(r#""sandbox_path":"/workspace/attachments/"#));

    let history = vec![crate::session::SessionMessage {
        id: String::new(),
        role: "user".to_string(),
        content: "what is this?".to_string(),
        created_at: String::new(),
        interrupted: false,
        turn_id: None,
    }];
    let raw = raw_history_with_attachments(&history, &attachments);
    let parts = raw[0]["content"].as_array().unwrap();
    assert_eq!(parts[0]["type"], "text");
    assert_eq!(parts[1]["type"], "image_url");
}

#[tokio::test]
async fn session_turn_keeps_current_user_message_when_bootstrap_is_present() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    crate::workspace::reseed_workspace(&files_dir);
    let session_key_json =
        crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

    let prepared = prepare_session_turn(
        &files_dir,
        &files_dir,
        &serde_json::to_string(&config()).unwrap(),
        "napaxi",
        &session_key_json,
        "开发个贪食蛇小游戏",
        None,
        "[]",
        None,
        &[],
        false,
    )
    .await
    .unwrap();

    assert!(
        prepared
            .config
            .system_prompt
            .contains("## First-Run Bootstrap")
    );
    let last = prepared.raw_history.last().unwrap();
    assert_eq!(last["role"].as_str(), Some("user"));
    assert_eq!(last["content"].as_str(), Some("开发个贪食蛇小游戏"));
}

#[tokio::test]
async fn session_turn_replays_prior_tool_results_into_raw_history() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json =
        crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

    assert!(crate::session::append_message(
        &files_dir,
        &session_key_json,
        "user",
        "inspect the readme"
    ));
    assert!(crate::session::append_trace_messages(
        &files_dir,
        &session_key_json,
        "",
        &[serde_json::json!({
            "call_id": "call_readme",
            "name": "read_file",
            "arguments": "{\"path\":\"README.md\"}",
            "result": "Napaxi README"
        })],
    ));
    assert!(crate::session::append_message(
        &files_dir,
        &session_key_json,
        "assistant",
        "I found the README."
    ));

    let prepared = prepare_session_turn(
        &files_dir,
        &files_dir,
        &serde_json::to_string(&config()).unwrap(),
        "napaxi",
        &session_key_json,
        "what did you find?",
        None,
        "[]",
        None,
        &[],
        false,
    )
    .await
    .unwrap();

    let roles: Vec<_> = prepared
        .raw_history
        .iter()
        .filter_map(|message| message.get("role").and_then(serde_json::Value::as_str))
        .collect();
    assert_eq!(
        roles,
        vec!["user", "assistant", "tool", "assistant", "user"]
    );
    assert_eq!(
        prepared.raw_history[1]["tool_calls"][0]["id"].as_str(),
        Some("call_readme")
    );
    assert_eq!(
        prepared.raw_history[2]["tool_call_id"].as_str(),
        Some("call_readme")
    );
    assert_eq!(
        prepared.raw_history[2]["content"].as_str(),
        Some("Napaxi README")
    );
}

#[tokio::test]
async fn chat_config_includes_workspace_host_time_and_shell_context() {
    let dir = tempfile::tempdir().unwrap();
    crate::workspace::write_workspace_file(
        dir.path().to_str().unwrap(),
        "IDENTITY.md",
        "# Identity\n\n- Name: Napaxi",
    );

    let prepared = prepare_chat_config(
        config(),
        ChatRuntimeInput {
            files_dir: dir.path().to_str().unwrap(),
            workspace_files_dir: dir.path().to_str().unwrap(),
            agent_id: "napaxi",
            thread_id: "thread",
            message: "who are you?",
            attachments: &[],
            has_shell_tool: true,
            has_browser_tool: false,
            is_group_context: false,
        },
    )
    .await;

    assert!(prepared.system_prompt.starts_with("## Response Language"));
    assert!(prepared.system_prompt.contains("## Identity"));
    assert!(prepared.system_prompt.contains("Name: Napaxi"));
    assert!(prepared.system_prompt.contains("Host prompt."));
    assert!(prepared.system_prompt.contains("## Response Language"));
    assert!(
        prepared
            .system_prompt
            .contains("visible reasoning, thinking, planning, or trace text")
    );
    assert!(prepared.system_prompt.contains("## Current Time"));
    assert!(prepared.system_prompt.contains("`shell` tool"));
}

#[tokio::test]
async fn chat_config_includes_enabled_scene_guidance() {
    let dir = tempfile::tempdir().unwrap();
    let mut config = config();
    config.scene_prompt_config = Some(crate::scene_prompt::ScenePromptConfig {
        enabled: true,
        host_policies: HashMap::from([(
            crate::scene_prompt::VIDEO_PROCESSING_SCENE_ID.to_string(),
            "Export mobile previewable MP4.".to_string(),
        )]),
    });
    let attachments = vec![IncomingAttachment {
        id: "clip".to_string(),
        kind: AttachmentKind::from_mime_type("video/mp4"),
        mime_type: "video/mp4".to_string(),
        filename: Some("clip.mp4".to_string()),
        size_bytes: None,
        source_url: None,
        storage_key: None,
        local_path: None,
        extracted_text: None,
        data: Vec::new(),
        duration_secs: None,
    }];

    let prepared = prepare_chat_config(
        config,
        ChatRuntimeInput {
            files_dir: dir.path().to_str().unwrap(),
            workspace_files_dir: dir.path().to_str().unwrap(),
            agent_id: "napaxi",
            thread_id: "thread",
            message: "剪辑这个视频",
            attachments: &attachments,
            has_shell_tool: false,
            has_browser_tool: false,
            is_group_context: false,
        },
    )
    .await;

    assert!(prepared.system_prompt.contains("<scene_guidance>"));
    assert!(prepared.system_prompt.contains("video_processing"));
    assert!(
        prepared
            .system_prompt
            .contains("Export mobile previewable MP4.")
    );
}

#[tokio::test]
async fn session_turn_reports_invalid_config_without_persisting_message() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json =
        crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

    let events = run_session_turn(
        SessionTurnInput {
            files_dir: files_dir.clone(),
            workspace_files_dir: files_dir.clone(),
            config_json: "not-json".to_string(),
            agent_id: "napaxi".to_string(),
            session_key_json: session_key_json.clone(),
            message: "hello".to_string(),
            display_message: None,
            attachments_json: "[]".to_string(),
            tools: None,
            max_iterations: 0,
            extra_tools: Vec::new(),
            internal_tool_handler: None,
            is_group_context: false,
            agent_engine: None,
        },
        || false,
    )
    .await;

    assert!(matches!(
        events.first(),
        Some(crate::types::ChatEvent::Error { .. })
    ));
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    assert_eq!(
        crate::session::get_history(&files_dir, &key.thread_id),
        "[]"
    );
}

#[tokio::test]
async fn stream_session_turn_reports_invalid_config_without_persisting_message() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json =
        crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let mut events = Vec::new();

    stream_session_turn(
        SessionTurnInput {
            files_dir: files_dir.clone(),
            workspace_files_dir: files_dir.clone(),
            config_json: "not-json".to_string(),
            agent_id: "napaxi".to_string(),
            session_key_json: session_key_json.clone(),
            message: "hello".to_string(),
            display_message: None,
            attachments_json: "[]".to_string(),
            tools: None,
            max_iterations: 0,
            extra_tools: Vec::new(),
            internal_tool_handler: None,
            is_group_context: false,
            agent_engine: None,
        },
        |event| events.push(event),
        || false,
    )
    .await;

    assert!(matches!(
        events.first(),
        Some(crate::types::ChatEvent::Error { .. })
    ));
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    assert_eq!(
        crate::session::get_history(&files_dir, &key.thread_id),
        "[]"
    );
}

#[test]
fn turn_history_persists_interleaved_reasoning_and_response_segments() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json =
        crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    assert!(crate::session::append_message(
        &files_dir,
        &session_key_json,
        "user",
        "hello",
    ));

    let mut recorder = TurnHistoryRecorder::default();
    recorder.record(&ChatEvent::ReasoningDelta {
        content: "First thought.".to_string(),
    });
    recorder.record(&ChatEvent::ResponseDelta {
        content: "First answer.".to_string(),
    });
    recorder.record(&ChatEvent::ReasoningDelta {
        content: "Second thought.".to_string(),
    });
    recorder.record(&ChatEvent::ResponseDelta {
        content: "Second answer.".to_string(),
    });
    recorder.record(&ChatEvent::Response {
        content: "First answer.Second answer.".to_string(),
    });
    persist_turn_history_segments(&files_dir, &session_key_json, &recorder, false);

    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let history: serde_json::Value =
        serde_json::from_str(&crate::session::get_history(&files_dir, &key.thread_id)).unwrap();
    let messages = history.as_array().unwrap();
    let roles: Vec<_> = messages
        .iter()
        .filter_map(|message| message.get("role").and_then(serde_json::Value::as_str))
        .collect();
    assert_eq!(
        roles,
        vec!["user", "reasoning", "assistant", "reasoning", "assistant"]
    );
    assert_eq!(messages[2]["content"].as_str(), Some("First answer."));
    assert_eq!(messages[4]["content"].as_str(), Some("Second answer."));
}

#[test]
fn turn_history_persists_tool_calls_with_current_segment() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json =
        crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    assert!(crate::session::append_message(
        &files_dir,
        &session_key_json,
        "user",
        "list files",
    ));

    let mut recorder = TurnHistoryRecorder::default();
    recorder.record(&ChatEvent::ReasoningDelta {
        content: "I should inspect the workspace.".to_string(),
    });
    recorder.record(&ChatEvent::ToolCall {
        call_id: "call-1".to_string(),
        name: "list_files".to_string(),
        arguments: r#"{"path":"/workspace"}"#.to_string(),
    });
    recorder.record(&ChatEvent::ToolResult {
        call_id: "call-1".to_string(),
        name: "list_files".to_string(),
        output: r#"{"files":["README.md"]}"#.to_string(),
        is_error: false,
    });
    recorder.record(&ChatEvent::ResponseDelta {
        content: "README.md is present.".to_string(),
    });
    persist_turn_history_segments(&files_dir, &session_key_json, &recorder, false);

    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let history: serde_json::Value =
        serde_json::from_str(&crate::session::get_history(&files_dir, &key.thread_id)).unwrap();
    let messages = history.as_array().unwrap();
    let roles: Vec<_> = messages
        .iter()
        .filter_map(|message| message.get("role").and_then(serde_json::Value::as_str))
        .collect();
    assert_eq!(roles, vec!["user", "reasoning", "tool_calls", "assistant"]);
    let tool_calls: serde_json::Value =
        serde_json::from_str(messages[2]["content"].as_str().unwrap()).unwrap();
    assert_eq!(tool_calls["calls"][0]["call_id"].as_str(), Some("call-1"));
    assert_eq!(
        tool_calls["calls"][0]["result"].as_str(),
        Some(r#"{"files":["README.md"]}"#)
    );
}

#[test]
fn session_runtime_helpers_parse_defaults_and_track_cancellation() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = super::default_session(&files_dir, "");
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();

    assert_eq!(key.account_id, super::DEFAULT_ACCOUNT_ID);
    assert_eq!(super::session_account_id(&session_key_json), "default");
    assert!(
        super::scoped_workspace_files_dir(&files_dir, "user-a", "agent-a")
            .ends_with("napaxi_scopes/accounts/user-a/agents/agent-a")
    );
    assert!(!super::is_session_cancelled(&session_key_json));
    assert!(super::cancel_session_key(&session_key_json));
    assert!(super::is_session_cancelled(&session_key_json));
    super::clear_session_cancellation(&session_key_json);
    assert!(!super::is_session_cancelled(&session_key_json));
    assert!(!super::cancel_session_key("not-json"));
    assert_eq!(super::session_account_id("not-json"), "default");
}

#[test]
fn cancellation_is_scoped_by_full_session_key() {
    let thread_id = uuid::Uuid::new_v4().to_string();
    let first = serde_json::json!({
        "channel_type": "app",
        "account_id": "user-a",
        "thread_id": thread_id,
    })
    .to_string();
    let second = serde_json::json!({
        "channel_type": "app",
        "account_id": "user-b",
        "thread_id": thread_id,
    })
    .to_string();

    assert!(super::cancel_session_key(&first));
    assert!(super::is_session_cancelled(&first));
    assert!(!super::is_session_cancelled(&second));
    super::clear_session_cancellation(&first);
    assert!(!super::is_session_cancelled(&first));
}

#[test]
fn engine_handles_do_not_share_cancellation_state() {
    let first_dir = tempfile::tempdir().unwrap();
    let second_dir = tempfile::tempdir().unwrap();
    let config_json = serde_json::to_string(&config()).unwrap();
    let first_context = serde_json::json!({
        "platform": "test",
        "files_dir": first_dir.path().to_str().unwrap(),
    })
    .to_string();
    let second_context = serde_json::json!({
        "platform": "test",
        "files_dir": second_dir.path().to_str().unwrap(),
    })
    .to_string();
    let first_handle = super::create_engine_handle(&config_json, &first_context).unwrap();
    let second_handle = super::create_engine_handle(&config_json, &second_context).unwrap();
    // SAFETY: `handle` was just created in this test and not yet consumed, satisfying `handle_to_arc`'s contract.
    let first_engine = unsafe { super::handle_to_arc(first_handle) }.unwrap();
    // SAFETY: `handle` was just created in this test and not yet consumed, satisfying `handle_to_arc`'s contract.
    let second_engine = unsafe { super::handle_to_arc(second_handle) }.unwrap();
    let session_key_json = serde_json::json!({
        "channel_type": "app",
        "account_id": "user-a",
        "thread_id": uuid::Uuid::new_v4().to_string(),
    })
    .to_string();

    assert!(super::cancel_session_handle(
        first_handle,
        &session_key_json
    ));

    assert!(first_engine.is_session_cancelled(&session_key_json));
    assert!(!second_engine.is_session_cancelled(&session_key_json));
}

#[test]
fn engine_handle_owns_config_tools_agents_and_workspace() {
    let dir = tempfile::tempdir().unwrap();
    let config_json = serde_json::to_string(&config()).unwrap();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": dir.path().to_str().unwrap(),
        "native_library_dir": null,
    })
    .to_string();

    let handle = super::create_engine_handle(&config_json, &context_json).unwrap();
    // SAFETY: `handle` was just created in this test and not yet consumed, satisfying `handle_to_arc`'s contract.
    let engine = unsafe { super::handle_to_arc(handle) }.unwrap();

    assert_eq!(engine.files_dir(), dir.path().to_str().unwrap());
    assert_eq!(engine.platform(), "test");
    assert!(engine.native_library_dir().is_none());
    assert!(engine.config_json().contains("test-model"));
    assert!(engine.ensure_agent("research"));
    assert!(engine.list_agents_json().contains("research"));
    assert!(super::get_or_create_agent_handle(handle, "planner").contains(r#""planner""#));
    assert!(super::list_agents_handle(handle).contains("planner"));
    assert!(!super::delete_agent_handle(handle, super::DEFAULT_AGENT_ID));
    assert!(super::delete_agent_handle(handle, "planner"));
    assert!(!super::list_agents_handle(handle).contains("planner"));
    assert!(dir.path().join("linux-env").join("workspace").is_dir());
    assert!(dir.path().join("memory").join("IDENTITY.md").is_file());
    let tool_context = super::prepare_session_tool_context(&engine, "user-a", "agent-a");
    assert!(
        tool_context
            .workspace_files_dir
            .ends_with("napaxi_scopes/accounts/user-a/agents/agent-a")
    );
    assert!(
        super::scoped_workspace_files_dir_from_handle(handle, "user-a", "agent-a")
            .unwrap()
            .ends_with("napaxi_scopes/accounts/user-a/agents/agent-a")
    );
    let session_key_json = super::default_session(dir.path().to_str().unwrap(), "agent-a");
    assert!(super::cancel_session_handle(handle, &session_key_json));
    super::clear_session_cancellation(&session_key_json);
    assert!(!super::cancel_session_handle(0, &session_key_json));
    assert!(
        tool_context
            .extra_tools
            .iter()
            .any(|tool| tool.name == "shell")
    );
    assert!(
        tool_context
            .extra_tools
            .iter()
            .any(|tool| tool.name == "memory_read")
    );
    assert!(tool_context.internal_tool_handler.is_some());
    let available_tools =
        tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(super::available_tool_infos_json(
                &engine, "user-a", "agent-a",
            ));
    assert!(available_tools.contains(r#""name":"shell""#));
    assert!(available_tools.contains(r#""name":"memory_read""#));
    assert!(available_tools.contains(r#""name":"mcp_server_add""#));
    assert!(available_tools.contains(r#""name":"mcp_tool_list""#));
    let available_tools_from_handle =
        tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(super::available_tool_infos_json_handle(
                handle, "user-a", "agent-a",
            ));
    assert!(available_tools_from_handle.contains(r#""name":"shell""#));
    assert!(available_tools_from_handle.contains(r#""name":"memory_read""#));
    assert!(available_tools_from_handle.contains(r#""name":"mcp_server_add""#));
    assert!(available_tools_from_handle.contains(r#""name":"mcp_tool_list""#));
    let send_error =
        tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(super::send_message_json_handle(
                handle, "not-json", "hello", "[]", 0,
            ));
    assert!(send_error.contains("Invalid config"));
    let invalid_handle_error =
        tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(super::send_to_session_json_handle(
                0,
                "not-json",
                "agent-a",
                &session_key_json,
                "hello",
                "[]",
                0,
            ));
    assert!(invalid_handle_error.contains("engine handle is not available"));
    let mut streamed = Vec::new();
    tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(super::stream_message_handle(
            handle,
            "not-json",
            "hello",
            "[]",
            0,
            |event| streamed.push(event),
        ));
    assert!(
        streamed
            .first()
            .is_some_and(|event| event.contains("Invalid config"))
    );

    let mut next_config = config();
    next_config.model = "next-model".to_string();
    assert!(super::update_config_handle(
        handle,
        &serde_json::to_string(&next_config).unwrap()
    ));
    assert!(super::get_config_handle(handle).contains("next-model"));

    drop(engine);
    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { super::handle_consume(handle) };
}

#[test]
fn failed_interjection_does_not_persist_user_message() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let config_json = serde_json::to_string(&config()).unwrap();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null,
    })
    .to_string();
    let handle = super::create_engine_handle(&config_json, &context_json).unwrap();
    let session_key_json =
        crate::session::create_session(files_dir, "napaxi", "app", "user-a", None);

    assert!(!super::inject_message_handle(
        handle,
        &config_json,
        "napaxi",
        &session_key_json,
        "late follow-up",
        "[]",
    ));

    let thread_id = crate::turn::session_thread_id(&session_key_json).unwrap();
    assert_eq!(crate::session::get_history(files_dir, &thread_id), "[]");
    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn delete_agent_handle_typed_surfaces_structured_errors() {
    let dir = tempfile::tempdir().unwrap();
    let config_json = serde_json::to_string(&config()).unwrap();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": dir.path().to_str().unwrap(),
        "native_library_dir": null,
    })
    .to_string();
    let handle = super::create_engine_handle(&config_json, &context_json).unwrap();

    let err = super::delete_agent_handle_typed(handle, super::DEFAULT_AGENT_ID).unwrap_err();
    assert_eq!(err.code(), "invalid_input");

    let err = super::delete_agent_handle_typed(0, "anything").unwrap_err();
    assert_eq!(err.code(), "invalid_handle");

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn update_config_handle_typed_classifies_failures() {
    let dir = tempfile::tempdir().unwrap();
    let config_json = serde_json::to_string(&config()).unwrap();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": dir.path().to_str().unwrap(),
        "native_library_dir": null,
    })
    .to_string();
    let handle = super::create_engine_handle(&config_json, &context_json).unwrap();

    let err = super::update_config_handle_typed(0, "{}").unwrap_err();
    assert_eq!(err.code(), "invalid_handle");

    let err = super::update_config_handle_typed(handle, "not-json").unwrap_err();
    assert_eq!(err.code(), "config");

    assert!(super::update_config_handle_typed(handle, &config_json).is_ok());

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn cancel_session_handle_typed_surfaces_invalid_handle() {
    let err = super::cancel_session_handle_typed(0, "{}").unwrap_err();
    assert_eq!(err.code(), "invalid_handle");
}

#[test]
fn retract_injected_message_handle_typed_surfaces_invalid_handle() {
    let err = super::retract_injected_message_handle_typed(0, "{}", "msg").unwrap_err();
    assert_eq!(err.code(), "invalid_handle");
}

#[tokio::test]
async fn update_custom_tools_handle_typed_reports_missing_dispatcher_or_handle() {
    let result = super::update_custom_tools_handle_typed(0, "[]").await;
    let err = result.unwrap_err();
    // Either no dispatcher registered (tool_execution) or invalid handle —
    // both are structured codes, not a silent false.
    assert!(
        err.code() == "tool_execution" || err.code() == "invalid_handle",
        "expected typed error, got {}",
        err.code()
    );
}

#[test]
fn create_engine_handle_surfaces_config_error_for_bad_json() {
    let err = super::create_engine_handle("not-json", "{}").unwrap_err();
    assert_eq!(err.code(), "config");
    assert!(err.to_string().contains("config"));
}

#[test]
fn create_engine_handle_surfaces_config_error_for_bad_platform_context() {
    let cfg = serde_json::to_string(&config()).unwrap();
    let err = super::create_engine_handle(&cfg, "not-json").unwrap_err();
    assert_eq!(err.code(), "config");
}
