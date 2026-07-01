use super::attachments::raw_history_with_attachments_for_config;
use super::orchestration::stream_turn_with_hooks;
use super::*;
use crate::types::PlatformLlmCapabilityConfig;
use std::collections::HashMap;

const SKILL: &str = r#"---
name: demo-skill
version: 1.0.0
description: Demo skill
activation:
  keywords: [demo]
---

Use this skill for demos.
"#;

#[derive(Debug, Clone, PartialEq, Eq)]
struct HookEvent {
    kind: &'static str,
    stage: TurnStage,
    mode: TurnMode,
    thread_id: Option<String>,
    agent_id: String,
    is_group_context: bool,
    message: Option<String>,
}

#[derive(Default)]
struct RecordingHooks {
    events: Vec<HookEvent>,
    prompt_summaries: Vec<PromptPlanSummary>,
    outcome_summaries: Vec<TurnOutcomeSummary>,
    context_events: Vec<ChatEvent>,
    deliver_context_events: bool,
}

impl RecordingHooks {
    fn push(
        &mut self,
        kind: &'static str,
        context: &TurnLifecycleContext,
        stage: TurnStage,
        message: Option<&str>,
    ) {
        self.events.push(HookEvent {
            kind,
            stage,
            mode: context.mode,
            thread_id: context.thread_id.clone(),
            agent_id: context.agent_id.clone(),
            is_group_context: context.is_group_context,
            message: message.map(str::to_string),
        });
    }

    fn pairs(&self) -> Vec<(&'static str, TurnStage)> {
        self.events
            .iter()
            .map(|event| (event.kind, event.stage))
            .collect()
    }

    fn completed_stages(&self) -> Vec<TurnStage> {
        self.events
            .iter()
            .filter(|event| event.kind == "completed")
            .map(|event| event.stage)
            .collect()
    }
}

impl TurnLifecycleHooks for RecordingHooks {
    fn stage_started(&mut self, context: &TurnLifecycleContext, stage: TurnStage) {
        self.push("started", context, stage, None);
    }

    fn stage_completed(&mut self, context: &TurnLifecycleContext, stage: TurnStage) {
        self.push("completed", context, stage, None);
    }

    fn stage_warning(&mut self, context: &TurnLifecycleContext, stage: TurnStage, message: &str) {
        self.push("warning", context, stage, Some(message));
    }

    fn stage_failed(&mut self, context: &TurnLifecycleContext, stage: TurnStage, message: &str) {
        self.push("failed", context, stage, Some(message));
    }

    fn prompt_prepared(&mut self, _context: &TurnLifecycleContext, summary: &PromptPlanSummary) {
        self.prompt_summaries.push(summary.clone());
    }

    fn context_event(&mut self, _context: &TurnLifecycleContext, event: &ChatEvent) -> bool {
        self.context_events.push(event.clone());
        self.deliver_context_events
    }

    fn turn_completed(&mut self, _context: &TurnLifecycleContext, summary: &TurnOutcomeSummary) {
        self.outcome_summaries.push(summary.clone());
    }
}

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

fn test_prompt_plan(content: &str) -> PromptPlan {
    PromptPlan {
        sections: vec![PromptSection {
            source: PromptSectionSource::HostSystem,
            visibility: PromptSectionVisibility::Private,
            priority: PromptPriority::High,
            content: content.to_string(),
        }],
        active_skills: Vec::new(),
        skill_catalog_names: Vec::new(),
        skill_catalog_hashes: std::collections::HashMap::new(),
        skill_snapshot_id: None,
    }
}

fn diagnostic_record(id: &str) -> TurnDiagnosticRecord {
    TurnDiagnosticRecord {
        id: id.to_string(),
        created_at: now_rfc3339(),
        completed_at: Some(now_rfc3339()),
        status: TurnDiagnosticStatus::Succeeded,
        mode: Some(TurnMode::Collected),
        agent_id: Some("napaxi".to_string()),
        thread_id: Some(format!("thread-{id}")),
        is_group_context: false,
        stages: Vec::new(),
        prompt: None,
        outcome: None,
        error: None,
    }
}

#[test]
fn image_analysis_tool_config_keeps_images_as_attachment_paths() {
    let history = vec![crate::session::SessionMessage {
        id: "1".to_string(),
        role: "user".to_string(),
        content: "what is this?".to_string(),
        created_at: now_rfc3339(),
        interrupted: false,
        turn_id: None,
    }];
    let attachments = vec![IncomingAttachment {
        id: "image".to_string(),
        kind: AttachmentKind::Image,
        mime_type: "image/png".to_string(),
        filename: Some("photo.png".to_string()),
        size_bytes: Some(4),
        source_url: None,
        storage_key: Some("/workspace/attachments/thread/photo.png".to_string()),
        local_path: None,
        extracted_text: None,
        data: vec![1, 2, 3, 4],
        duration_secs: None,
    }];
    let mut config = config();
    config.capability_configs = Some(HashMap::from([(
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

    let raw = raw_history_with_attachments_for_config(&history, &attachments, &config);
    let content = raw[0].get("content").unwrap().as_array().unwrap();

    assert_eq!(content.len(), 1);
    let text = content[0].get("text").unwrap().as_str().unwrap();
    assert!(text.contains("sandbox_path=\"/workspace/attachments/thread/photo.png\""));
    assert!(text.contains("Visual inspection requires an image analysis tool"));
}

#[test]
fn image_attachments_never_inline_visual_parts_for_main_chat() {
    let history = vec![crate::session::SessionMessage {
        id: "1".to_string(),
        role: "user".to_string(),
        content: "what is this?".to_string(),
        created_at: now_rfc3339(),
        interrupted: false,
        turn_id: None,
    }];
    let attachments = vec![IncomingAttachment {
        id: "image".to_string(),
        kind: AttachmentKind::Image,
        mime_type: "image/png".to_string(),
        filename: Some("photo.png".to_string()),
        size_bytes: Some(4),
        source_url: None,
        storage_key: Some("/workspace/attachments/thread/photo.png".to_string()),
        local_path: None,
        extracted_text: None,
        data: vec![1, 2, 3, 4],
        duration_secs: None,
    }];

    let raw = raw_history_with_attachments_for_config(&history, &attachments, &config());
    let content = raw[0].get("content").unwrap().as_array().unwrap();

    assert_eq!(content.len(), 1);
    assert_eq!(content[0].get("type").unwrap().as_str(), Some("text"));
    assert!(
        content[0]
            .get("text")
            .and_then(serde_json::Value::as_str)
            .unwrap()
            .contains("sandbox_path=\"/workspace/attachments/thread/photo.png\"")
    );
}

#[tokio::test]
async fn image_attachment_prompt_requires_image_analyze_tool_when_available() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let attachments = vec![IncomingAttachment {
        id: "image".to_string(),
        kind: AttachmentKind::Image,
        mime_type: "image/png".to_string(),
        filename: Some("photo.png".to_string()),
        size_bytes: Some(4),
        source_url: None,
        storage_key: Some("/workspace/photo.png".to_string()),
        local_path: None,
        extracted_text: None,
        data: vec![1, 2, 3, 4],
        duration_secs: None,
    }];
    let mut config = config();
    config.capability_configs = Some(HashMap::from([(
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

    let prompt = prepare_prompt_sections(
        &config,
        ChatRuntimeInput {
            files_dir,
            workspace_files_dir: files_dir,
            agent_id: "napaxi",
            thread_id: "thread",
            message: "what is this?",
            attachments: &attachments,
            has_shell_tool: false,
            has_browser_tool: false,
            is_group_context: false,
        },
    )
    .await;

    let media = prompt
        .sections
        .iter()
        .find(|section| section.source == PromptSectionSource::MediaTool)
        .unwrap();
    assert!(media.content.contains("call the `image_analyze` tool"));
    assert!(
        media
            .content
            .contains("Pass the `sandbox_path` exactly as shown")
    );
    assert!(media.content.contains("do not retry the same path"));
}

#[tokio::test]
async fn prompt_sections_keep_source_order_and_compile_to_existing_prompt_order() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    crate::workspace::write_workspace_file(files_dir, "IDENTITY.md", "# Identity\n\nNapa");
    let _ = crate::skills::install_skill(files_dir, "napaxi", SKILL).await;
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

    let prompt = prepare_prompt_sections(
        &config,
        ChatRuntimeInput {
            files_dir,
            workspace_files_dir: files_dir,
            agent_id: "napaxi",
            thread_id: "thread",
            message: "please use /demo-skill and 剪辑这个视频",
            attachments: &attachments,
            has_shell_tool: true,
            has_browser_tool: true,
            is_group_context: true,
        },
    )
    .await;

    let sources: Vec<_> = prompt
        .sections
        .iter()
        .map(|section| section.source)
        .collect();
    assert_eq!(
        sources,
        vec![
            PromptSectionSource::ResponseLanguage,
            PromptSectionSource::Workspace,
            PromptSectionSource::HostSystem,
            PromptSectionSource::SceneGuidance,
            PromptSectionSource::SkillCatalog,
            PromptSectionSource::ActiveSkill,
            PromptSectionSource::GroupContext,
            PromptSectionSource::BrowserTool,
            PromptSectionSource::ShellTool,
            PromptSectionSource::ApplyPatch,
            PromptSectionSource::CurrentTime,
        ]
    );
    assert_eq!(
        prompt.sections[1].visibility,
        PromptSectionVisibility::GroupSafe
    );
    assert_eq!(prompt.sections[0].priority, PromptPriority::Required);

    let compiled = compile_prompt_sections(config, &prompt);
    let response_language = compiled.system_prompt.find("## Response Language").unwrap();
    let workspace = compiled.system_prompt.find("## Identity").unwrap();
    let host = compiled.system_prompt.find("Host prompt.").unwrap();
    let scene = compiled.system_prompt.find("<scene_guidance>").unwrap();
    let skill = compiled.system_prompt.find("<skills>").unwrap();
    let group = compiled.system_prompt.find("## Group Context").unwrap();
    let browser = compiled.system_prompt.find("## Browser Tool").unwrap();
    let time = compiled.system_prompt.find("## Current Time").unwrap();
    let shell = compiled.system_prompt.find("## Linux Shell").unwrap();
    let apply_patch = compiled.system_prompt.find("## apply_patch").unwrap();
    assert!(compiled.system_prompt.contains("defaults to mobile mode"));
    assert!(compiled.system_prompt.contains("native client/app"));
    assert!(compiled.system_prompt.contains("interaction_source"));
    assert!(compiled.system_prompt.contains("viewport_map"));
    assert!(compiled.system_prompt.contains("image_analyze"));
    assert!(compiled.system_prompt.contains("last_action_effect"));
    // CurrentTime is intentionally last (after shell/apply_patch) to keep the
    // every-turn-changing timestamp out of the cacheable static prefix.
    assert!(
        response_language < workspace
            && workspace < host
            && host < scene
            && scene < skill
            && skill < group
            && group < browser
            && browser < shell
            && shell < apply_patch
            && apply_patch < time
    );
}

#[tokio::test]
async fn volatile_workspace_sinks_below_static_sections_and_keeps_stable_prefix() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    // Stable identity (rarely changes) vs volatile long-term memory (rewritten
    // often). In private (non-group) context both are present.
    crate::workspace::write_workspace_file(files_dir, "IDENTITY.md", "# Identity\n\nNapa");
    crate::workspace::write_workspace_file(files_dir, "MEMORY.md", "# Memory\n\nFirst memory note");

    let runtime_input = |message: &'static str| ChatRuntimeInput {
        files_dir,
        workspace_files_dir: files_dir,
        agent_id: "napaxi",
        thread_id: "thread",
        message,
        attachments: &[],
        has_shell_tool: true,
        has_browser_tool: false,
        is_group_context: false,
    };

    let prompt = prepare_prompt_sections(&config(), runtime_input("hello")).await;
    let compiled = compile_prompt_sections(config(), &prompt);
    let sys = &compiled.system_prompt;

    // Stable identity stays in the prefix; volatile memory sinks below the
    // static instruction sections and just above the per-turn time block.
    let identity = sys.find("## Identity").unwrap();
    let host = sys.find("Host prompt.").unwrap();
    let apply_patch = sys.find("## apply_patch").unwrap();
    let memory = sys.find("## Long-Term Memory").unwrap();
    let time = sys.find("## Current Time").unwrap();
    assert!(
        identity < host && host < apply_patch && apply_patch < memory && memory < time,
        "expected stable Identity in prefix and volatile Memory sunk below apply_patch, before time"
    );

    // The cacheable stable prefix (everything up to the volatile block) must be
    // byte-identical after a memory rewrite — only the tail changes.
    let prefix_before = &sys[..memory];
    crate::workspace::write_workspace_file(
        files_dir,
        "MEMORY.md",
        "# Memory\n\nFirst memory note\n\nA brand new memory appended this turn",
    );
    let prompt2 = prepare_prompt_sections(&config(), runtime_input("hello")).await;
    let compiled2 = compile_prompt_sections(config(), &prompt2);
    let sys2 = &compiled2.system_prompt;
    let memory2 = sys2.find("## Long-Term Memory").unwrap();
    assert_eq!(
        prefix_before,
        &sys2[..memory2],
        "stable prefix must be unchanged when only volatile memory is rewritten"
    );
    assert!(
        sys2.contains("A brand new memory appended this turn"),
        "rewritten volatile memory should appear in the new prompt"
    );
}

#[tokio::test]
async fn prompt_sections_use_sdk_language_preference() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = config();
    config.response_language = "zh".to_string();

    let prompt = prepare_prompt_sections(
        &config,
        ChatRuntimeInput {
            files_dir,
            workspace_files_dir: files_dir,
            agent_id: "napaxi",
            thread_id: "thread",
            message: "hello",
            attachments: &[],
            has_shell_tool: true,
            has_browser_tool: true,
            is_group_context: false,
        },
    )
    .await;

    let compiled = compile_prompt_sections(config, &prompt);
    assert!(compiled.system_prompt.contains("使用中文回答用户"));
    assert!(compiled.system_prompt.contains("## 响应语言"));
    assert!(compiled.system_prompt.contains("## Agent 指令"));
    assert!(compiled.system_prompt.contains("你是一个可以使用工具"));
    assert!(compiled.system_prompt.contains("## 浏览器工具"));
    assert!(compiled.system_prompt.contains("## 文件工具优先级"));
    assert!(compiled.system_prompt.contains("## 当前时间"));
    assert!(compiled.system_prompt.contains("## apply_patch — 文件编辑"));
    assert!(!compiled.system_prompt.contains("## Response Language"));
    assert!(
        !compiled
            .system_prompt
            .contains("Use the browser tools only for live web pages")
    );
    assert!(
        !compiled
            .system_prompt
            .contains("## apply_patch — file editing")
    );
}

#[tokio::test]
async fn current_time_prompt_includes_user_timezone_context() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = config();
    config.user_timezone = Some("Asia/Shanghai".to_string());

    let prompt = prepare_prompt_sections(
        &config,
        ChatRuntimeInput {
            files_dir,
            workspace_files_dir: files_dir,
            agent_id: "napaxi",
            thread_id: "thread",
            message: "明天上午九点提醒我",
            attachments: &[],
            has_shell_tool: false,
            has_browser_tool: false,
            is_group_context: false,
        },
    )
    .await;

    let time = prompt
        .sections
        .iter()
        .find(|section| section.source == PromptSectionSource::CurrentTime)
        .unwrap();
    assert!(time.content.contains("Current Time UTC:"));
    assert!(time.content.contains("User Timezone: Asia/Shanghai"));
    assert!(time.content.contains("Current Local Time:"));
    assert!(
        time.content
            .contains("Interpret relative dates and local-time requests")
    );
}

#[tokio::test]
async fn group_prompt_section_uses_existing_group_safe_workspace_prompt() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    crate::workspace::write_workspace_file(files_dir, "USER.md", "Shared user note");
    crate::workspace::write_workspace_file(files_dir, "PROFILE.md", "Private profile note");

    let prompt = prepare_prompt_sections(
        &config(),
        ChatRuntimeInput {
            files_dir,
            workspace_files_dir: files_dir,
            agent_id: "napaxi",
            thread_id: "thread",
            message: "hello",
            attachments: &[],
            has_shell_tool: false,
            has_browser_tool: false,
            is_group_context: true,
        },
    )
    .await;

    let workspace = prompt
        .sections
        .iter()
        .find(|section| section.source == PromptSectionSource::Workspace)
        .unwrap();
    assert_eq!(workspace.visibility, PromptSectionVisibility::GroupSafe);
    assert!(workspace.content.contains("Shared user note"));
    assert!(!workspace.content.contains("Private profile note"));
}

#[tokio::test]
async fn prepare_turn_hooks_record_same_stage_names_for_collected_and_streaming() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let config_json = serde_json::to_string(&config()).unwrap();

    for mode in [TurnMode::Collected, TurnMode::Streaming] {
        let session_key_json =
            crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
        let mut context = TurnLifecycleContext::new(mode, "napaxi", false);
        let mut hooks = RecordingHooks::default();
        prepare_turn_with_hooks(
            &files_dir,
            &files_dir,
            &config_json,
            "napaxi",
            &session_key_json,
            "hello",
            None,
            "[]",
            None,
            &[],
            false,
            &mut context,
            &mut hooks,
        )
        .await
        .unwrap();

        assert_eq!(
            hooks.completed_stages(),
            vec![
                TurnStage::ParseInput,
                TurnStage::PreparePrompt,
                TurnStage::PersistUserMessage,
                TurnStage::BuildHistory,
            ]
        );
        assert!(hooks.events.iter().all(|event| event.mode == mode));
        assert_eq!(hooks.prompt_summaries.len(), 1);
        assert!(hooks.prompt_summaries[0].compiled_char_count > 0);
        assert!(
            hooks
                .events
                .iter()
                .filter(|event| event.stage == TurnStage::BuildHistory)
                .all(|event| event.thread_id.is_some())
        );
    }
}

#[tokio::test]
async fn prepare_turn_can_deliver_context_compaction_progress_before_returning() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    for index in 0..10 {
        assert!(crate::session::append_message(
            &files_dir,
            &session_key_json,
            if index % 2 == 0 { "user" } else { "assistant" },
            &"long context ".repeat(40),
        ));
    }
    let mut config = config();
    config.context_engine.context_window_tokens = Some(220);
    config.context_engine.protect_head_messages = 1;
    config.context_engine.protect_tail_messages = 1;
    config.context_engine.compaction_strategy = "local_summary".to_string();
    let config_json = serde_json::to_string(&config).unwrap();
    let mut context = TurnLifecycleContext::new(TurnMode::Streaming, "napaxi", false);
    let mut hooks = RecordingHooks {
        deliver_context_events: true,
        ..RecordingHooks::default()
    };

    let prepared = prepare_turn_with_hooks(
        &files_dir,
        &files_dir,
        &config_json,
        "napaxi",
        &session_key_json,
        "continue",
        None,
        "[]",
        None,
        &[],
        false,
        &mut context,
        &mut hooks,
    )
    .await
    .unwrap();

    assert!(matches!(
        hooks.context_events.first(),
        Some(ChatEvent::ContextCompacting { .. })
    ));
    assert!(matches!(
        hooks.context_events.get(1),
        Some(ChatEvent::ContextCompacted { .. })
    ));
    assert!(
        !prepared
            .config
            .system_prompt
            .contains("Conversation Context Summary"),
        "context summaries should not be promoted into the system prompt"
    );
    assert_eq!(
        prepared
            .raw_history
            .first()
            .and_then(|message| { message.get("role").and_then(serde_json::Value::as_str) }),
        Some("assistant")
    );
    assert!(
        prepared
            .raw_history
            .first()
            .and_then(|message| message.get("content"))
            .and_then(serde_json::Value::as_str)
            .is_some_and(|content| {
                content.contains("<conversation_context_summary>")
                    && content.contains("not as a system/developer instruction")
            })
    );
    assert!(!prepared.context_events.iter().any(|event| matches!(
        event,
        ChatEvent::ContextCompacting { .. } | ChatEvent::ContextCompacted { .. }
    )));
}

#[tokio::test]
async fn invalid_config_reports_parse_stage_failure_without_persisting_message() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let mut hooks = RecordingHooks::default();

    let events = run_turn_with_hooks(
        TurnInput {
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
        &mut hooks,
        || false,
    )
    .await;

    assert!(matches!(events.first(), Some(ChatEvent::Error { .. })));
    assert_eq!(
        hooks.pairs(),
        vec![
            ("started", TurnStage::ParseInput),
            ("failed", TurnStage::ParseInput),
        ]
    );
    assert!(
        hooks
            .events
            .last()
            .and_then(|event| event.message.as_deref())
            .is_some_and(|message| message.contains("Invalid config"))
    );
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    assert_eq!(
        crate::session::get_history(&files_dir, &key.thread_id),
        "[]"
    );
}

#[test]
fn post_turn_hooks_record_successful_persistence_and_emit_order() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    assert!(crate::session::append_message(
        &files_dir,
        &session_key_json,
        "user",
        "hello"
    ));
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let mut context = TurnLifecycleContext::new(TurnMode::Collected, "napaxi", false);
    context.thread_id = Some(key.thread_id.clone());
    let prepared = PreparedTurn {
        config: config(),
        prompt_plan: test_prompt_plan("Host prompt."),
        thread_id: key.thread_id.clone(),
        history: Vec::new(),
        raw_history: Vec::new(),
        context_events: Vec::new(),
    };
    let mut recorder = TurnHistoryRecorder::default();
    recorder.record(&ChatEvent::ReasoningDelta {
        content: "thinking".to_string(),
    });
    let mut hooks = RecordingHooks::default();

    let outcome = finish_successful_turn(
        &files_dir,
        &files_dir,
        "napaxi",
        &session_key_json,
        "hello",
        prepared,
        "final answer".to_string(),
        0,
        &mut recorder,
        &context,
        &mut hooks,
    );

    assert!(outcome.emitted_events.iter().any(|event| {
        matches!(event, ChatEvent::Response { content } if content == "final answer")
    }));
    assert_eq!(
        hooks.completed_stages(),
        vec![
            TurnStage::PersistAssistantTrace,
            TurnStage::AppendJournal,
            TurnStage::QueueEvolution,
            TurnStage::EmitFinalEvents,
        ]
    );
    let history: serde_json::Value =
        serde_json::from_str(&crate::session::get_history(&files_dir, &key.thread_id)).unwrap();
    let roles: Vec<_> = history
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|message| message.get("role").and_then(serde_json::Value::as_str))
        .collect();
    assert!(roles.contains(&"reasoning"));
    assert!(roles.contains(&"assistant"));
}

#[test]
fn prompt_plan_summary_hashes_without_raw_content() {
    let secret = "Private profile note that must not be persisted";
    let plan = test_prompt_plan(secret);
    let summary = plan.summary();
    let serialized = serde_json::to_string(&summary).unwrap();

    assert_eq!(summary.sections.len(), 1);
    assert_eq!(summary.sections[0].char_count, secret.chars().count());
    assert_eq!(summary.sections[0].sha256, sha256_hex(secret));
    assert!(!serialized.contains(secret));
    assert!(serialized.contains(&sha256_hex(secret)));
}

#[test]
fn diagnostics_recorder_persists_success_record_with_prompt_summary() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    assert!(crate::session::append_message(
        &files_dir,
        &session_key_json,
        "user",
        "hello"
    ));
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let mut context = TurnLifecycleContext::new(TurnMode::Collected, "napaxi", false);
    context.thread_id = Some(key.thread_id.clone());
    let mut diagnostics = TurnDiagnosticsRecorder::new(&files_dir);
    let prompt_plan = test_prompt_plan("Secret prompt body");
    let prompt_summary = prompt_plan.summary();

    diagnostics.stage_started(&context, TurnStage::PreparePrompt);
    diagnostics.prompt_prepared(&context, &prompt_summary);
    diagnostics.stage_completed(&context, TurnStage::PreparePrompt);

    let prepared = PreparedTurn {
        config: config(),
        prompt_plan,
        thread_id: key.thread_id.clone(),
        history: Vec::new(),
        raw_history: Vec::new(),
        context_events: Vec::new(),
    };
    let mut history_recorder = TurnHistoryRecorder::default();
    let outcome = finish_successful_turn(
        &files_dir,
        &files_dir,
        "napaxi",
        &session_key_json,
        "hello",
        prepared,
        "final answer".to_string(),
        2,
        &mut history_recorder,
        &context,
        &mut diagnostics,
    );
    diagnostics.turn_completed(&context, &outcome.summary());
    diagnostics.persist();

    let records = list_turn_diagnostics(&files_dir, 10);
    assert_eq!(records.len(), 1);
    let record = &records[0];
    assert_eq!(record.status, TurnDiagnosticStatus::Succeeded);
    assert_eq!(record.mode, Some(TurnMode::Collected));
    assert_eq!(record.agent_id.as_deref(), Some("napaxi"));
    assert_eq!(record.thread_id.as_deref(), Some(key.thread_id.as_str()));
    assert_eq!(record.prompt.as_ref().unwrap(), &prompt_summary);
    assert_eq!(record.outcome.as_ref().unwrap().tool_call_count, 2);
    assert!(
        record
            .stages
            .iter()
            .any(|stage| stage.stage == TurnStage::PersistAssistantTrace)
    );
    let serialized = serde_json::to_string(record).unwrap();
    assert!(!serialized.contains("Secret prompt body"));
}

#[tokio::test]
async fn default_run_turn_invalid_config_persists_failed_diagnostic() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

    let events = run_turn(
        TurnInput {
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

    assert!(matches!(events.first(), Some(ChatEvent::Error { .. })));
    let records = list_turn_diagnostics(&files_dir, 10);
    assert_eq!(records.len(), 1);
    let record = &records[0];
    assert_eq!(record.status, TurnDiagnosticStatus::Failed);
    assert!(
        record
            .error
            .as_deref()
            .is_some_and(|error| error.contains("Invalid config"))
    );
    assert!(record.stages.iter().any(|stage| {
        stage.stage == TurnStage::ParseInput && stage.status == TurnDiagnosticStageStatus::Failed
    }));
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    assert_eq!(
        crate::session::get_history(&files_dir, &key.thread_id),
        "[]"
    );
}

#[test]
fn diagnostics_retention_keeps_latest_records() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();

    for index in 0..=TURN_DIAGNOSTICS_LIMIT {
        append_turn_diagnostic_record(&files_dir, diagnostic_record(&index.to_string())).unwrap();
    }

    let records = list_turn_diagnostics(&files_dir, TURN_DIAGNOSTICS_LIMIT + 10);
    assert_eq!(records.len(), TURN_DIAGNOSTICS_LIMIT);
    assert_eq!(records.first().unwrap().id, "1");
    assert_eq!(
        records.last().unwrap().id,
        TURN_DIAGNOSTICS_LIMIT.to_string()
    );
}

#[test]
fn diagnostics_persist_failure_is_best_effort() {
    let file = tempfile::NamedTempFile::new().unwrap();
    let files_dir = file.path().to_string_lossy().to_string();
    let mut context = TurnLifecycleContext::new(TurnMode::Collected, "napaxi", false);
    context.thread_id = Some("thread".to_string());
    let mut diagnostics = TurnDiagnosticsRecorder::new(&files_dir);

    diagnostics.stage_started(&context, TurnStage::ParseInput);
    diagnostics.stage_completed(&context, TurnStage::ParseInput);
    diagnostics.persist();
}

#[tokio::test]
async fn execute_tool_loop_failure_records_stage_failure_without_assistant_response() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let mut config = config();
    config.api_key.clear();
    let mut hooks = RecordingHooks::default();

    let events = run_turn_with_hooks(
        TurnInput {
            files_dir: files_dir.clone(),
            workspace_files_dir: files_dir.clone(),
            config_json: serde_json::to_string(&config).unwrap(),
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
        &mut hooks,
        || false,
    )
    .await;

    assert!(matches!(events.first(), Some(ChatEvent::Error { .. })));
    assert!(hooks.events.iter().any(|event| {
        event.kind == "failed"
            && event.stage == TurnStage::ExecuteToolLoop
            && event
                .message
                .as_deref()
                .is_some_and(|message| message.contains("LLM API key is required"))
    }));
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let history: serde_json::Value =
        serde_json::from_str(&crate::session::get_history(&files_dir, &key.thread_id)).unwrap();
    assert!(!history.as_array().unwrap().iter().any(|message| {
        message.get("role").and_then(serde_json::Value::as_str) == Some("assistant")
    }));
}

#[tokio::test]
async fn collected_turn_emits_activated_skills_before_model_events() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    crate::skills::install_skill(&files_dir, "napaxi", SKILL).await;
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let mut config = config();
    config.api_key.clear();
    let mut hooks = RecordingHooks::default();

    let events = run_turn_with_hooks(
        TurnInput {
            files_dir: files_dir.clone(),
            workspace_files_dir: files_dir.clone(),
            config_json: serde_json::to_string(&config).unwrap(),
            agent_id: "napaxi".to_string(),
            session_key_json,
            message: "please use /demo-skill".to_string(),
            display_message: None,
            attachments_json: "[]".to_string(),
            tools: None,
            max_iterations: 0,
            extra_tools: Vec::new(),
            internal_tool_handler: None,
            is_group_context: false,
            agent_engine: None,
        },
        &mut hooks,
        || false,
    )
    .await;

    assert!(matches!(
        events.first(),
        Some(ChatEvent::SkillActivated { agent_id, skills })
            if agent_id == "napaxi" && skills.len() == 1 && skills[0].name == "demo-skill"
    ));
    assert!(matches!(events.get(1), Some(ChatEvent::Error { .. })));
}

#[tokio::test]
async fn streaming_turn_emits_activated_skills_before_model_events() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    crate::skills::install_skill(&files_dir, "napaxi", SKILL).await;
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let mut config = config();
    config.api_key.clear();
    let mut hooks = RecordingHooks::default();
    let mut events = Vec::new();

    stream_turn_with_hooks(
        TurnInput {
            files_dir: files_dir.clone(),
            workspace_files_dir: files_dir.clone(),
            config_json: serde_json::to_string(&config).unwrap(),
            agent_id: "napaxi".to_string(),
            session_key_json,
            message: "please use /demo-skill".to_string(),
            display_message: None,
            attachments_json: "[]".to_string(),
            tools: None,
            max_iterations: 0,
            extra_tools: Vec::new(),
            internal_tool_handler: None,
            is_group_context: false,
            agent_engine: None,
        },
        &mut hooks,
        |event| events.push(event),
        || false,
    )
    .await;

    assert!(matches!(
        events.first(),
        Some(ChatEvent::SkillActivated { agent_id, skills })
            if agent_id == "napaxi" && skills.len() == 1 && skills[0].name == "demo-skill"
    ));
    assert!(matches!(events.get(1), Some(ChatEvent::Error { .. })));
}

fn assistant_messages(files_dir: &str, session_key_json: &str) -> Vec<serde_json::Value> {
    let key: crate::session::SessionKey = serde_json::from_str(session_key_json).unwrap();
    let history: serde_json::Value =
        serde_json::from_str(&crate::session::get_history(files_dir, &key.thread_id)).unwrap();
    history
        .as_array()
        .unwrap()
        .iter()
        .filter(|message| {
            matches!(
                message.get("role").and_then(serde_json::Value::as_str),
                Some("assistant") | Some("reasoning") | Some("tool_calls"),
            )
        })
        .cloned()
        .collect()
}

#[test]
fn finish_cancelled_turn_persists_partial_response_deltas() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let context = TurnLifecycleContext::new(TurnMode::Streaming, "napaxi", false);
    let mut hooks = RecordingHooks::default();
    let mut recorder = TurnHistoryRecorder::default();
    recorder.record(&ChatEvent::ResponseDelta {
        content: "Hello, ".to_string(),
    });
    recorder.record(&ChatEvent::ResponseDelta {
        content: "world".to_string(),
    });

    finish_cancelled_turn(
        &files_dir,
        &session_key_json,
        &mut recorder,
        true,
        &context,
        &mut hooks,
    );

    let messages = assistant_messages(&files_dir, &session_key_json);
    assert_eq!(messages.len(), 1);
    assert_eq!(
        messages[0].get("role").and_then(serde_json::Value::as_str),
        Some("assistant")
    );
    assert_eq!(
        messages[0]
            .get("content")
            .and_then(serde_json::Value::as_str),
        Some("Hello, world")
    );
    assert!(
        hooks
            .completed_stages()
            .contains(&TurnStage::PersistAssistantTrace)
    );
}

#[test]
fn stream_reset_discards_partial_content_before_reconnect() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let context = TurnLifecycleContext::new(TurnMode::Streaming, "napaxi", false);
    let mut hooks = RecordingHooks::default();
    let mut recorder = TurnHistoryRecorder::default();

    // First attempt streams a partial answer, then the connection drops.
    recorder.record(&ChatEvent::ReasoningDelta {
        content: "thinking about it".to_string(),
    });
    recorder.record(&ChatEvent::ResponseDelta {
        content: "Half of an ans".to_string(),
    });
    recorder.record(&ChatEvent::StreamReset {
        reason: "connection reset by peer".to_string(),
    });
    // Reconnected stream produces the real, complete answer.
    recorder.record(&ChatEvent::ResponseDelta {
        content: "Complete answer.".to_string(),
    });

    finish_cancelled_turn(
        &files_dir,
        &session_key_json,
        &mut recorder,
        true,
        &context,
        &mut hooks,
    );

    let messages = assistant_messages(&files_dir, &session_key_json);
    let assistant = messages
        .iter()
        .find(|message| {
            message.get("role").and_then(serde_json::Value::as_str) == Some("assistant")
        })
        .expect("assistant message persisted");
    assert_eq!(
        assistant.get("content").and_then(serde_json::Value::as_str),
        Some("Complete answer."),
        "partial pre-reset content must not survive the reconnect"
    );
}

#[test]
fn finish_cancelled_turn_persists_completed_tool_calls() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let context = TurnLifecycleContext::new(TurnMode::Streaming, "napaxi", false);
    let mut hooks = RecordingHooks::default();
    let mut recorder = TurnHistoryRecorder::default();
    recorder.record(&ChatEvent::ToolCall {
        call_id: "call-1".to_string(),
        name: "echo".to_string(),
        arguments: "{\"text\":\"hi\"}".to_string(),
    });
    recorder.record(&ChatEvent::ToolResult {
        call_id: "call-1".to_string(),
        name: "echo".to_string(),
        output: "hi".to_string(),
        is_error: false,
    });
    recorder.record(&ChatEvent::ResponseDelta {
        content: "partial".to_string(),
    });

    finish_cancelled_turn(
        &files_dir,
        &session_key_json,
        &mut recorder,
        true,
        &context,
        &mut hooks,
    );

    let messages = assistant_messages(&files_dir, &session_key_json);
    assert_eq!(messages.len(), 2);
    assert_eq!(
        messages[0].get("role").and_then(serde_json::Value::as_str),
        Some("tool_calls")
    );
    let tool_calls_content = messages[0]
        .get("content")
        .and_then(serde_json::Value::as_str)
        .unwrap();
    assert!(tool_calls_content.contains("\"call_id\":\"call-1\""));
    assert!(tool_calls_content.contains("\"result\":\"hi\""));
    assert_eq!(
        messages[1].get("role").and_then(serde_json::Value::as_str),
        Some("assistant")
    );
    assert_eq!(
        messages[1]
            .get("content")
            .and_then(serde_json::Value::as_str),
        Some("partial")
    );
}

#[test]
fn finish_cancelled_turn_writes_nothing_when_recorder_is_empty() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let context = TurnLifecycleContext::new(TurnMode::Streaming, "napaxi", false);
    let mut hooks = RecordingHooks::default();
    let mut recorder = TurnHistoryRecorder::default();

    finish_cancelled_turn(
        &files_dir,
        &session_key_json,
        &mut recorder,
        false,
        &context,
        &mut hooks,
    );

    assert!(assistant_messages(&files_dir, &session_key_json).is_empty());
}

#[test]
fn finish_cancelled_turn_writes_turn_aborted_marker_when_empty_and_enabled() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let context = TurnLifecycleContext::new(TurnMode::Streaming, "napaxi", false);
    let mut hooks = RecordingHooks::default();
    let mut recorder = TurnHistoryRecorder::default();

    // Empty recorder (assistant produced nothing) + marker enabled: a
    // turn_aborted boundary must be persisted so the model sees an explicit
    // break between the interrupted user turn and the next one.
    finish_cancelled_turn(
        &files_dir,
        &session_key_json,
        &mut recorder,
        true,
        &context,
        &mut hooks,
    );

    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();

    // The marker reaches the model-facing context history as a turn_aborted role.
    let context_history = crate::session::llm_context_history_all(&files_dir, &key.thread_id);
    let marker = context_history
        .iter()
        .find(|message| message.role == "turn_aborted")
        .expect("turn_aborted marker persisted into model-facing history");
    assert!(marker.content.contains("<turn_aborted>"));

    // It is hidden from the UI history projection.
    let ui_history: serde_json::Value =
        serde_json::from_str(&crate::session::get_history(&files_dir, &key.thread_id)).unwrap();
    assert!(
        ui_history.as_array().unwrap().iter().all(|message| message
            .get("role")
            .and_then(serde_json::Value::as_str)
            != Some("turn_aborted")),
        "turn_aborted marker must not surface in UI history"
    );
}

#[test]
fn cancelled_reasoning_only_turn_survives_get_history_reload() {
    // Regression: pausing during the reasoning phase used to write a
    // role="reasoning" tail message that get_history's trim_incomplete_tail
    // then stripped on reload. finish_cancelled_turn must flag persisted
    // messages as interrupted so the trim leaves them in place.
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let context = TurnLifecycleContext::new(TurnMode::Streaming, "napaxi", false);
    let mut hooks = RecordingHooks::default();
    let mut recorder = TurnHistoryRecorder::default();
    recorder.record(&ChatEvent::ReasoningDelta {
        content: "Thinking about it...".to_string(),
    });

    finish_cancelled_turn(
        &files_dir,
        &session_key_json,
        &mut recorder,
        true,
        &context,
        &mut hooks,
    );

    let messages = assistant_messages(&files_dir, &session_key_json);
    assert_eq!(messages.len(), 1);
    assert_eq!(
        messages[0].get("role").and_then(serde_json::Value::as_str),
        Some("reasoning")
    );
    assert_eq!(
        messages[0]
            .get("content")
            .and_then(serde_json::Value::as_str),
        Some("Thinking about it...")
    );
    assert_eq!(
        messages[0]
            .get("interrupted")
            .and_then(serde_json::Value::as_bool),
        Some(true)
    );

    // Regression (interrupt boundary): the `reasoning` role is stripped from the
    // model envelope by `llm_context_history_all`, so a reasoning-only interrupt
    // contributes nothing the model can see. A turn_aborted marker must be
    // written so the next request does not present two consecutive user turns.
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let context_history = crate::session::llm_context_history_all(&files_dir, &key.thread_id);
    assert!(
        context_history
            .iter()
            .any(|message| message.role == "turn_aborted"),
        "reasoning-only interrupt must still persist a turn_aborted boundary marker"
    );
}

#[test]
fn successful_turn_trailing_reasoning_is_still_trimmed_on_reload() {
    // Guardrail: the trim is still meaningful for non-interrupted turns.
    // A reasoning message written without the interrupted flag (e.g. left
    // over from a crash mid-stream) must still be removed from get_history.
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    crate::session::append_messages(
        &files_dir,
        &session_key_json,
        &[crate::session::SessionAppendMessage {
            role: "reasoning".to_string(),
            content: "Orphan reasoning".to_string(),
            interrupted: false,
            turn_id: None,
        }],
    );

    let history: serde_json::Value =
        serde_json::from_str(&crate::session::get_history(&files_dir, &key.thread_id)).unwrap();
    assert!(history.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn streaming_turn_cancel_does_not_emit_error_event() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);
    let mut config = config();
    config.api_key.clear();
    let mut hooks = RecordingHooks::default();
    let mut events = Vec::new();

    stream_turn_with_hooks(
        TurnInput {
            files_dir: files_dir.clone(),
            workspace_files_dir: files_dir.clone(),
            config_json: serde_json::to_string(&config).unwrap(),
            agent_id: "napaxi".to_string(),
            session_key_json,
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
        &mut hooks,
        |event| events.push(event),
        || true,
    )
    .await;

    assert!(
        !events
            .iter()
            .any(|event| matches!(event, ChatEvent::Error { .. })),
        "cancel path should not emit a ChatEvent::Error, got: {events:?}"
    );
    assert!(hooks.events.iter().any(|event| event.kind == "failed"
        && event.stage == TurnStage::ExecuteToolLoop
        && event.message.as_deref() == Some("Chat cancelled")));
}
