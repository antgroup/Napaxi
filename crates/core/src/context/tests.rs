//! Behavioral coverage for the context engine: compaction triggers,
//! status output, preflight snapshots, display source selection, and
//! tool-result pruning bookkeeping.

use chrono::Utc;

use crate::llm::LlmUsage;
use crate::session::SessionMessage;
use crate::tool_registry::ToolDescriptor;
use crate::types::{ChatEvent, PlatformLlmConfig};

use super::budget::{build_context_budget_status, context_window_details, response_reserve_info};
use super::compaction::{ToolMessageCompactionStats, compact_tool_messages};
use super::state::{
    ContextBudgetStatus, ContextState, ContextTokenBreakdown, LastPromptSnapshot,
    PreflightSnapshot, ToolCompactionSnapshot,
};
use super::{
    PreCompactionMemoryFlush, build_context, build_context_for_turn_with_event_sink,
    context_status, context_status_for_config, display_context_delta, display_context_usage,
    record_last_prompt_snapshot, record_preflight_snapshot,
    record_tool_compaction_snapshot_for_session,
};

fn message(id: usize, role: &str, content: &str) -> SessionMessage {
    SessionMessage {
        id: format!("m{id}"),
        role: role.to_string(),
        content: content.to_string(),
        created_at: Utc::now().to_rfc3339(),
        interrupted: false,
        turn_id: None,
    }
}

fn tool_trace(call_count: usize, result_chars: usize) -> String {
    let calls: Vec<_> = (0..call_count)
        .map(|index| {
            serde_json::json!({
                "call_id": format!("call_{index}"),
                "name": "browser_snapshot",
                "arguments": {"mode": "inspect"},
                "result": "z".repeat(result_chars),
            })
        })
        .collect();
    serde_json::json!({ "calls": calls }).to_string()
}

fn use_local_summary(config: &mut PlatformLlmConfig) {
    config.context_engine.compaction_strategy = "local_summary".to_string();
}

fn test_preflight_snapshot(
    estimated_tokens: usize,
    prompt_tokens: usize,
    updated_at: &str,
) -> PreflightSnapshot {
    PreflightSnapshot {
        provider: "openai_compatible".to_string(),
        model: "test-model".to_string(),
        config_fingerprint: String::new(),
        estimated_tokens,
        context_window_tokens: 128_000,
        response_reserve_tokens: estimated_tokens.saturating_sub(prompt_tokens),
        context_window_source: "config".to_string(),
        native_context_window_tokens: 128_000,
        native_context_window_source: "config".to_string(),
        effective_context_window_tokens: 128_000,
        effective_context_window_source: "config".to_string(),
        response_reserve_source: "config".to_string(),
        provider_metadata_fetched_at: None,
        provider_metadata_stale: false,
        provider_metadata_error: None,
        breakdown: ContextTokenBreakdown {
            total_tokens: estimated_tokens,
            response_reserve_tokens: estimated_tokens.saturating_sub(prompt_tokens),
            ..ContextTokenBreakdown::default()
        },
        context_budget_status: ContextBudgetStatus {
            source: "pre-prompt-estimate".to_string(),
            provider: "openai_compatible".to_string(),
            model: "test-model".to_string(),
            route: "fits".to_string(),
            should_compact: false,
            estimated_prompt_tokens: prompt_tokens,
            context_token_budget: 128_000,
            native_context_window_tokens: 128_000,
            native_context_window_source: "config".to_string(),
            effective_context_window_tokens: 128_000,
            effective_context_window_source: "config".to_string(),
            response_reserve_source: "config".to_string(),
            provider_metadata_fetched_at: None,
            provider_metadata_stale: false,
            provider_metadata_error: None,
            prompt_budget_before_reserve: 120_000,
            reserve_tokens: estimated_tokens.saturating_sub(prompt_tokens),
            effective_reserve_tokens: estimated_tokens.saturating_sub(prompt_tokens),
            remaining_prompt_budget_tokens: 120_000isize - prompt_tokens as isize,
            overflow_tokens: 0,
            tool_result_reducible_chars: 0,
            tool_result_reducible_tokens: 0,
            context_guard_status: "ok".to_string(),
            context_guard_reason: String::new(),
            message_count: 1,
            unwindowed_message_count: 1,
            updated_at: updated_at.to_string(),
        },
        updated_at: updated_at.to_string(),
    }
}

#[tokio::test]
async fn compacts_middle_and_keeps_head_tail() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(220);
    config.context_engine.protect_head_messages = 2;
    config.context_engine.protect_tail_messages = 2;
    use_local_summary(&mut config);
    let history: Vec<_> = (0..12)
        .map(|index| {
            message(
                index,
                if index % 2 == 0 { "user" } else { "assistant" },
                &"x".repeat(160),
            )
        })
        .collect();

    let output = build_context(
        files_dir, "thread", &config, "prompt", &history, false, None,
    )
    .await
    .unwrap();

    assert!(output.summary.is_some());
    assert_eq!(output.history.first().unwrap().id, "m0");
    assert_eq!(output.history[1].id, "m1");
    assert_eq!(output.history[2].id, "m10");
    assert_eq!(output.history[3].id, "m11");
    assert!(matches!(
        output.events.first(),
        Some(ChatEvent::ContextCompacting { .. })
    ));
}

#[test]
fn status_reports_empty_state() {
    let dir = tempfile::tempdir().unwrap();
    let value: serde_json::Value =
        serde_json::from_str(&context_status(dir.path().to_str().unwrap(), "thread")).unwrap();
    assert_eq!(value["summary_present"], false);
    assert_eq!(value["compaction_count"], 0);
}

#[test]
fn tool_message_compaction_replaces_large_old_tool_output() {
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(400);
    config.context_engine.target_ratio = 0.45;
    let mut messages = vec![
        serde_json::json!({"role":"user","content":"hello"}),
        serde_json::json!({"role":"tool","tool_call_id":"call_1","content":"z".repeat(4000)}),
        serde_json::json!({"role":"user","content":"continue"}),
    ];
    let stats = compact_tool_messages(&mut messages, &config, 0);

    let content = messages[1]["content"].as_str().unwrap();
    assert!(content.contains("tool result compacted"));
    assert_eq!(stats.compacted_messages, 1);
    assert!(stats.pruned_chars > 0);
}

#[test]
fn preflight_snapshot_counts_prompt_history_tools_attachments_and_reserve() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.provider = "openai-compatible".to_string();
    config.model = "gpt-4o".to_string();
    config.system_prompt = "dynamic prompt ".repeat(100);
    config.context_engine.context_window_tokens = Some(128_000);
    config.context_engine.response_reserve_tokens = Some(2_048);
    let raw_history = vec![
        serde_json::json!({
            "role":"user",
            "content":[
                {"type":"text","text":"hello\n<attachments>\n<attachment type=\"document\">notes</attachment>\n</attachments>"},
                {"type":"image_url","image_url":{"url":"data:image/png;base64,abc"}}
            ]
        }),
        serde_json::json!({"role":"assistant","tool_calls":[{"type":"function","function":{"name":"search","arguments":"{}"}}]}),
        serde_json::json!({"role":"tool","content":"tool output ".repeat(600)}),
    ];
    let descriptors = vec![ToolDescriptor {
        name: "search".to_string(),
        description: "Search a corpus".repeat(80),
        parameters: serde_json::json!({
            "type": "object",
            "properties": { "query": { "type": "string" } }
        }),
        effect: crate::tool_registry::ToolEffect::Read,
    }];

    record_preflight_snapshot(files_dir, "thread", &config, &raw_history, &descriptors);
    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();

    assert_eq!(value["display_source"], "preflight");
    assert_eq!(value["current_window_tokens"], value["display_used_tokens"]);
    assert_eq!(
        value["display_used_tokens"],
        value["context_budget_status"]["estimated_prompt_tokens"]
    );
    assert!(value["transcript_estimated_tokens"].as_u64().unwrap() > 0);
    assert_eq!(
        value["context_display_label"].as_str(),
        Some("current_window")
    );
    assert_eq!(value["context_window_source"], "config");
    assert_eq!(value["native_context_window_tokens"], 128_000);
    assert_eq!(value["effective_context_window_tokens"], 128_000);
    assert_eq!(value["effective_context_window_source"], "config");
    assert_eq!(value["response_reserve_source"], "config");
    assert_eq!(value["context_guard_status"], "ok");
    assert_eq!(value["context_route"], "fits");
    assert!(value["preflight_estimated_tokens"].as_u64().unwrap() > 0);
    assert!(
        value["breakdown"]["tool_descriptor_tokens"]
            .as_u64()
            .unwrap()
            > 0
    );
    assert!(value["breakdown"]["tool_result_tokens"].as_u64().unwrap() > 0);
    assert!(value["breakdown"]["tool_call_tokens"].as_u64().unwrap() > 0);
    assert!(value["breakdown"]["attachment_tokens"].as_u64().unwrap() > 0);
    assert_eq!(value["breakdown"]["image_tokens"].as_u64(), Some(2_000));
    assert_eq!(
        value["context_budget_status"]["route"].as_str(),
        Some("fits")
    );
}

#[test]
fn budget_status_routes_fit_truncate_and_compact_paths() {
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(10_000);
    config.context_engine.response_reserve_tokens = Some(1_000);
    let settings = super::normalized_config(&config.context_engine);

    let fits = build_context_budget_status(
        "thread", &config, &settings, 1_000, 1_000, 10_000, 0, 4, "now",
    );
    assert_eq!(fits.route, "fits");
    assert!(!fits.should_compact);

    let truncate = build_context_budget_status(
        "thread", &config, &settings, 9_500, 1_000, 10_000, 20_000, 4, "now",
    );
    assert_eq!(truncate.route, "prune_tools");
    assert!(!truncate.should_compact);

    let compact_then_truncate = build_context_budget_status(
        "thread", &config, &settings, 9_500, 1_000, 10_000, 100, 4, "now",
    );
    assert_eq!(compact_then_truncate.route, "compact_then_prune");
    assert!(compact_then_truncate.should_compact);

    let compact_only = build_context_budget_status(
        "thread", &config, &settings, 9_500, 1_000, 10_000, 0, 4, "now",
    );
    assert_eq!(compact_only.route, "compact");
    assert!(compact_only.should_compact);

    let blocked =
        build_context_budget_status("thread", &config, &settings, 100, 100, 3_000, 0, 4, "now");
    assert_eq!(blocked.route, "reject_too_large");
    assert_eq!(blocked.context_guard_status, "blocked");
}

#[tokio::test]
async fn build_context_rejects_low_remaining_budget_without_compactable_middle() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(20_000);
    config.context_engine.response_reserve_tokens = Some(4_000);
    config.context_engine.compaction_strategy = "local_summary".to_string();

    let error = build_context(
        files_dir,
        "thread",
        &config,
        &"large prompt ".repeat(4_000),
        &[],
        false,
        None,
    )
    .await
    .unwrap_err();

    assert!(error.contains("Context budget is too low to send safely"));
}

#[test]
fn context_window_resolution_reports_native_effective_and_sources() {
    let mut config = PlatformLlmConfig::default();
    config.provider = "gemini".to_string();
    config.model = "gemini-2.5-pro".to_string();
    config.context_engine.context_window_tokens = Some(200_000);
    let settings = super::normalized_config(&config.context_engine);

    let window = context_window_details(&config, &settings);

    assert_eq!(window.native_tokens, 1_000_000);
    assert_eq!(window.native_source, "model_rule");
    assert_eq!(window.effective_tokens, 200_000);
    assert_eq!(window.effective_source, "config");
}

#[test]
fn context_window_resolution_prefers_provider_metadata_before_model_rule() {
    let mut config = PlatformLlmConfig::default();
    config.model = "unknown-model".to_string();
    config.context_engine.provider_context_window_tokens = Some(512_000);
    let settings = super::normalized_config(&config.context_engine);

    let window = context_window_details(&config, &settings);

    assert_eq!(window.native_tokens, 512_000);
    assert_eq!(window.native_source, "provider");
    assert_eq!(window.effective_tokens, 512_000);
    assert_eq!(window.effective_source, "provider");
}

#[test]
fn context_window_resolution_treats_bare_model_ids_conservatively() {
    let mut bare = PlatformLlmConfig::default();
    bare.model = "gemini-2.5-pro".to_string();
    let bare_settings = super::normalized_config(&bare.context_engine);
    let bare_window = context_window_details(&bare, &bare_settings);
    assert_eq!(bare_window.native_tokens, 128_000);
    assert_eq!(bare_window.native_source, "default");

    let mut qualified = PlatformLlmConfig::default();
    qualified.model = "gemini/gemini-2.5-pro".to_string();
    let qualified_settings = super::normalized_config(&qualified.context_engine);
    let qualified_window = context_window_details(&qualified, &qualified_settings);
    assert_eq!(qualified_window.native_tokens, 1_000_000);
    assert_eq!(qualified_window.native_source, "model_rule");
}

#[test]
fn context_window_resolution_recognizes_long_context_models() {
    let mut gpt41 = PlatformLlmConfig::default();
    gpt41.provider = "openai".to_string();
    gpt41.model = "gpt-4.1".to_string();
    let gpt41_settings = super::normalized_config(&gpt41.context_engine);
    let gpt41_window = context_window_details(&gpt41, &gpt41_settings);
    assert_eq!(gpt41_window.native_tokens, 1_000_000);
    assert_eq!(gpt41_window.native_source, "model_rule");

    let mut kimi = PlatformLlmConfig::default();
    kimi.provider = "moonshot".to_string();
    kimi.model = "kimi-k2.7-code".to_string();
    let kimi_settings = super::normalized_config(&kimi.context_engine);
    let kimi_window = context_window_details(&kimi, &kimi_settings);
    assert_eq!(kimi_window.native_tokens, 256_000);
    assert_eq!(kimi_window.native_source, "model_rule");
}

#[test]
fn response_reserve_resolution_reports_source() {
    let mut config = PlatformLlmConfig::default();
    config.max_tokens = 12_000;
    let settings = super::normalized_config(&config.context_engine);
    let reserve = response_reserve_info(&config, &settings);
    assert_eq!(reserve.tokens, 8_192);
    assert_eq!(reserve.source, "model_output_limit");

    config.context_engine.response_reserve_tokens = Some(1_234);
    let settings = super::normalized_config(&config.context_engine);
    let reserve = response_reserve_info(&config, &settings);
    assert_eq!(reserve.tokens, 1_234);
    assert_eq!(reserve.source, "config");
}

#[test]
fn display_uses_newer_preflight_when_provider_snapshot_is_stale() {
    let state = ContextState {
        thread_id: "thread".to_string(),
        engine: "compressor".to_string(),
        last_prompt_snapshot: Some(LastPromptSnapshot {
            provider: "openai_compatible".to_string(),
            model: "test-model".to_string(),
            config_fingerprint: String::new(),
            prompt_tokens: 10_000,
            input_tokens: 10_000,
            output_tokens: 0,
            cache_read_tokens: 0,
            cache_write_tokens: 0,
            reasoning_tokens: 0,
            total_tokens: Some(10_000),
            updated_at: "2026-06-01T00:00:00Z".to_string(),
        }),
        preflight_snapshot: Some(test_preflight_snapshot(
            16_000,
            14_000,
            "2026-06-01T00:01:00Z",
        )),
        ..ContextState::default()
    };

    let mut config = PlatformLlmConfig::default();
    config.provider = "openai_compatible".to_string();
    config.model = "test-model".to_string();
    let settings = super::normalized_config(&config.context_engine);
    let display = display_context_usage(&state, &config, &settings, 1_000);

    assert_eq!(display.source, "preflight");
    assert_eq!(display.used_tokens, 14_000);
    assert_eq!(display.updated_at, Some("2026-06-01T00:01:00Z"));
    assert!(display.fresh);
}

#[test]
fn preflight_display_accounts_for_later_tool_pruning() {
    let state = ContextState {
        thread_id: "thread".to_string(),
        engine: "compressor".to_string(),
        preflight_snapshot: Some(test_preflight_snapshot(
            16_000,
            14_000,
            "2026-06-01T00:01:00Z",
        )),
        last_tool_compaction: Some(ToolCompactionSnapshot {
            compacted_messages: 1,
            original_chars: 8_000,
            compacted_chars: 2_000,
            pruned_chars: 6_000,
            estimated_pruned_tokens: 3_000,
            updated_at: "2026-06-01T00:02:00Z".to_string(),
        }),
        ..ContextState::default()
    };

    let mut config = PlatformLlmConfig::default();
    config.provider = "openai_compatible".to_string();
    config.model = "test-model".to_string();
    let settings = super::normalized_config(&config.context_engine);
    let display = display_context_usage(&state, &config, &settings, 1_000);
    let (delta, reason) = display_context_delta(&state, &display);

    assert_eq!(display.source, "preflight");
    assert_eq!(display.used_tokens, 11_000);
    assert_eq!(display.updated_at, Some("2026-06-01T00:02:00Z"));
    assert_eq!(delta, -3_000);
    assert_eq!(reason, "tool_result_pruned");
}

#[tokio::test]
async fn status_uses_compacted_estimate_after_manual_compaction() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(128_000);
    config.context_engine.response_reserve_tokens = Some(0);
    config.context_engine.protect_head_messages = 1;
    config.context_engine.protect_tail_messages = 1;
    use_local_summary(&mut config);
    let raw_history = vec![serde_json::json!({"role":"user","content":"x".repeat(120_000)})];
    record_preflight_snapshot(files_dir, "thread", &config, &raw_history, &[]);
    let preflight_value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();
    let preflight_tokens = preflight_value["display_used_tokens"].as_u64().unwrap();

    let history: Vec<_> = (0..10)
        .map(|index| {
            message(
                index,
                if index % 2 == 0 { "user" } else { "assistant" },
                &"manual compaction context ".repeat(120),
            )
        })
        .collect();
    let output = build_context(
        files_dir,
        "thread",
        &config,
        &config.system_prompt,
        &history,
        true,
        Some("manual compact"),
    )
    .await
    .unwrap();
    assert!(output.summary.is_some());

    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();

    assert_eq!(value["display_source"].as_str(), Some("legacy"));
    assert_eq!(value["fresh"].as_bool(), Some(true));
    assert_eq!(value["preflight_estimated_tokens"], serde_json::Value::Null);
    assert!(value["display_used_tokens"].as_u64().unwrap() < preflight_tokens);
    assert_eq!(
        value["last_context_delta_reason"].as_str(),
        Some("compacted")
    );
    assert_eq!(value["compaction_strategy"].as_str(), Some("local_summary"));
    assert!(value["last_compaction_duration_ms"].as_u64().is_some());
}

#[tokio::test]
async fn status_uses_model_context_estimate_for_huge_recent_tool_trace() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let thread_id = "11111111-1111-1111-1111-111111111111";
    let session_key_json =
        crate::session::create_session(files_dir, "agent", "app", "account", Some(thread_id));
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(128_000);
    config.context_engine.response_reserve_tokens = Some(0);
    config.context_engine.protect_head_messages = 1;
    config.context_engine.protect_tail_messages = 9;
    config.context_engine.target_ratio = 0.45;
    use_local_summary(&mut config);

    assert!(crate::session::append_message(
        files_dir,
        &session_key_json,
        "user",
        "head"
    ));
    for index in 0..8 {
        assert!(crate::session::append_message(
            files_dir,
            &session_key_json,
            if index % 2 == 0 { "assistant" } else { "user" },
            &"middle context ".repeat(4_000),
        ));
    }
    for _ in 0..8 {
        assert!(crate::session::append_message(
            files_dir,
            &session_key_json,
            "tool_calls",
            &tool_trace(1, 100_000),
        ));
    }
    assert!(crate::session::append_message(
        files_dir,
        &session_key_json,
        "assistant",
        "tail response"
    ));

    let history = crate::session::llm_context_history_all(files_dir, thread_id);
    let output = build_context(
        files_dir,
        thread_id,
        &config,
        &config.system_prompt,
        &history,
        true,
        Some("manual compact"),
    )
    .await
    .unwrap();
    assert!(output.summary.is_some());

    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        thread_id,
        Some(&config),
    ))
    .unwrap();

    let current_window = value["current_window_tokens"].as_u64().unwrap();
    let transcript = value["transcript_estimated_tokens"].as_u64().unwrap();
    assert!(current_window < 128_000, "{value}");
    assert!(transcript > current_window.saturating_mul(3), "{value}");
    assert!(value["tool_result_pruned_tokens"].as_u64().unwrap() > 0);
    assert_eq!(value["display_used_tokens"].as_u64(), Some(current_window));
    assert_eq!(value["display_source"].as_str(), Some("legacy"));
    assert_eq!(
        value["last_context_delta_reason"].as_str(),
        Some("compacted")
    );
    assert_eq!(value["compaction_strategy"].as_str(), Some("local_summary"));
}

#[tokio::test]
async fn llm_summary_compaction_falls_back_to_local_summary() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(220);
    config.context_engine.protect_head_messages = 1;
    config.context_engine.protect_tail_messages = 1;
    config.context_engine.compaction_strategy = "llm_summary".to_string();
    let history: Vec<_> = (0..8)
        .map(|index| {
            message(
                index,
                if index % 2 == 0 { "user" } else { "assistant" },
                &"needs real summarization ".repeat(40),
            )
        })
        .collect();

    let output = build_context(
        files_dir,
        "thread",
        &config,
        &config.system_prompt,
        &history,
        true,
        Some("manual compact"),
    )
    .await
    .unwrap();

    let summary = output.summary.unwrap();
    assert!(summary.contains("## Conversation Context Summary"));
    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();
    assert_eq!(value["summary_present"], true);
    assert_eq!(value["compaction_count"].as_u64(), Some(1));
    assert_eq!(
        value["compaction_strategy"].as_str(),
        Some("local_summary_fallback")
    );
}

#[tokio::test]
async fn pre_compaction_memory_flush_records_skipped_status_without_llm_config() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(220);
    config.context_engine.protect_head_messages = 1;
    config.context_engine.protect_tail_messages = 1;
    config.context_engine.compaction_strategy = "local_summary".to_string();
    config.context_engine.pre_compaction_memory_flush = true;
    let history: Vec<_> = (0..8)
        .map(|index| {
            message(
                index,
                if index % 2 == 0 { "user" } else { "assistant" },
                &"memory flush context ".repeat(40),
            )
        })
        .collect();

    let output = build_context_for_turn_with_event_sink(
        files_dir,
        "thread",
        &config,
        &config.system_prompt,
        &history,
        false,
        None,
        Some(PreCompactionMemoryFlush {
            review_files_dir: files_dir,
            agent_id: "napaxi",
        }),
        |_| false,
    )
    .await
    .unwrap();

    assert!(output.summary.is_some());
    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();
    assert_eq!(value["pre_compaction_memory_flush_enabled"], true);
    assert_eq!(
        value["pre_compaction_memory_flush_status"].as_str(),
        Some("skipped_missing_llm_config")
    );
}

#[test]
fn status_prefers_provider_usage_over_preflight_and_legacy() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.system_prompt = "legacy prompt ".repeat(100);
    config.context_engine.context_window_tokens = Some(128_000);
    let raw_history = vec![serde_json::json!({"role":"user","content":"x".repeat(1000)})];
    record_preflight_snapshot(files_dir, "thread", &config, &raw_history, &[]);
    record_last_prompt_snapshot(
        files_dir,
        "thread",
        &config,
        Some(&LlmUsage {
            input_tokens: Some(10_000),
            output_tokens: Some(200),
            cache_read_tokens: Some(2_000),
            cache_write_tokens: Some(500),
            reasoning_tokens: None,
            total_tokens: Some(12_700),
        }),
    );

    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();

    assert_eq!(value["display_source"], "provider");
    assert_eq!(value["display_used_tokens"].as_u64(), Some(12_500));
    assert_eq!(value["current_window_tokens"].as_u64(), Some(12_500));
    assert_eq!(
        value["last_context_delta_reason"].as_str(),
        Some("provider_replaced_preflight")
    );
    assert_eq!(value["estimated_tokens"].as_u64(), Some(12_500));
    assert_eq!(value["last_prompt_tokens"].as_u64(), Some(12_500));
    assert_eq!(value["cache_read_tokens"].as_u64(), Some(2_000));
    assert_eq!(value["cache_write_tokens"].as_u64(), Some(500));
}

#[test]
fn status_marks_snapshots_stale_after_model_switch() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.provider = "openai_compatible".to_string();
    config.model = "model-a".to_string();
    config.context_engine.context_window_tokens = Some(128_000);
    let raw_history = vec![serde_json::json!({"role":"user","content":"hello"})];
    record_preflight_snapshot(files_dir, "thread", &config, &raw_history, &[]);
    record_last_prompt_snapshot(
        files_dir,
        "thread",
        &config,
        Some(&LlmUsage {
            input_tokens: Some(10_000),
            output_tokens: None,
            cache_read_tokens: None,
            cache_write_tokens: None,
            reasoning_tokens: None,
            total_tokens: Some(10_000),
        }),
    );

    config.model = "model-b".to_string();
    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();

    assert_ne!(value["display_source"].as_str(), Some("provider"));
    assert_ne!(value["display_source"].as_str(), Some("preflight"));
    assert_eq!(value["fresh"].as_bool(), Some(false));
}

#[test]
fn status_reports_tool_result_pruning_snapshot() {
    let dir = tempfile::tempdir().unwrap();
    let files_dir = dir.path().to_str().unwrap();
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(400);
    config.context_engine.target_ratio = 0.45;
    let session_key_json = serde_json::json!({
        "channel_type": "app",
        "account_id": "test",
        "thread_id": "thread"
    })
    .to_string();
    record_tool_compaction_snapshot_for_session(
        files_dir,
        &session_key_json,
        &config,
        ToolMessageCompactionStats {
            compacted_messages: 1,
            original_chars: 2_000,
            compacted_chars: 400,
            pruned_chars: 1_600,
            estimated_pruned_tokens: 800,
        },
    );

    let value: serde_json::Value = serde_json::from_str(&context_status_for_config(
        files_dir,
        "thread",
        Some(&config),
    ))
    .unwrap();

    assert_eq!(value["tool_result_pruned_tokens"].as_u64(), Some(800));
    assert_eq!(value["tool_result_pruned_chars"].as_u64(), Some(1_600));
    assert_eq!(
        value["last_context_delta_reason"].as_str(),
        Some("tool_result_pruned")
    );
    assert_eq!(value["last_context_delta_tokens"].as_i64(), Some(-800));
}
