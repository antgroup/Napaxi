//! Warm-prefix compaction path tests — the `compaction_model`-empty branch
//! of `run_compaction_with_retry`.
//!
//! These tests cover the routing invariant (warm taken when
//! `compaction_model` is empty, cold taken when set), the directive builder,
//! and the fallback chain when the warm LLM response misses the required
//! sections. They are scoped to `compaction.rs` so they can read private
//! items (`compaction_warm_directive`, `with_warm_path_probe`).

use super::compaction_warm::{
    WarmCompactionKind, build_warm_compaction_messages_test, compaction_warm_directive_test,
};
use super::*;
use crate::llm::{LlmTurn, with_scripted_turns};
use crate::session::SessionMessage;
use crate::types::PlatformLlmConfig;

/// Standard six-section summary content the scripted LLM turn returns when
/// the test wants the warm path to succeed.
fn six_section_summary() -> String {
    [
        "Decisions",
        "Open TODOs",
        "Constraints/Rules",
        "Pending user asks",
        "Exact identifiers",
        "Tool outcomes",
    ]
    .iter()
    .map(|heading| format!("{heading}:\n- detail"))
    .collect::<Vec<_>>()
    .join("\n")
}

fn message(id: &str, role: &str, content: &str) -> SessionMessage {
    SessionMessage {
        id: id.to_string(),
        role: role.to_string(),
        content: content.to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
        interrupted: false,
        turn_id: None,
    }
}

fn warm_config() -> PlatformLlmConfig {
    let mut config = PlatformLlmConfig::default();
    config.provider = "__test_noop__".to_string();
    config.api_key = "test".to_string();
    config.model = "test-model".to_string();
    config.context_engine.context_window_tokens = Some(220);
    config.context_engine.protect_head_messages = 1;
    config.context_engine.protect_tail_messages = 1;
    config.context_engine.compaction_strategy = "llm_summary".to_string();
    config
}

#[test]
fn warm_directive_embeds_six_section_heading_instruction() {
    let directive = compaction_warm_directive_test(None, None, None);
    // Reuses `compaction_system_prompt()` text so the heading instruction is
    // identical to the cold-path system prompt.
    assert!(directive.contains("Decisions, Open TODOs, Constraints/Rules, Pending user asks, Exact identifiers, Tool outcomes."));
    assert!(directive.contains("Write the durable summary now."));
}

#[test]
fn warm_directive_includes_focus_and_previous_summary() {
    let directive =
        compaction_warm_directive_test(Some("prior summary body"), None, Some("refactor X"));
    assert!(directive.contains("Focus:"));
    assert!(directive.contains("refactor X"));
    assert!(directive.contains("Previous summary:"));
    assert!(directive.contains("prior summary body"));
}

#[test]
fn warm_directive_folds_chunk_summaries_for_merge_path() {
    let chunk_summaries = vec![
        message("chunk_1", "assistant", "first chunk summary"),
        message("chunk_2", "assistant", "second chunk summary"),
    ];
    let directive = compaction_warm_directive_test(None, Some(&chunk_summaries), None);
    assert!(directive.contains("Messages to compact:"));
    assert!(directive.contains("first chunk summary"));
    assert!(directive.contains("second chunk summary"));
    assert!(directive.contains("<message id=\"chunk_1\" role=\"assistant\">"));
}

#[test]
fn warm_directive_omits_messages_section_for_chunk_path() {
    // Chunk path: messages flow as prefix; directive must NOT render them.
    let directive = compaction_warm_directive_test(None, None, None);
    assert!(!directive.contains("Messages to compact:"));
}

#[tokio::test]
async fn warm_path_taken_when_compaction_model_empty() {
    let config = warm_config();
    let mut settings = config.context_engine.clone();
    // Explicitly empty `compaction_model` -> warm path.
    settings.compaction_model = None;
    let history: Vec<SessionMessage> = (0..8)
        .map(|index| {
            message(
                &format!("m{index}"),
                if index % 2 == 0 { "user" } else { "assistant" },
                "needs real summarization payload ",
            )
        })
        .collect();
    let summary_text = six_section_summary();
    let history_for_closure = history.clone();
    let (warm_count, summary) = with_warm_path_probe(async {
        with_scripted_turns(
            vec![LlmTurn {
                content: summary_text.clone(),
                reasoning_content: None,
                tool_calls: Vec::new(),
                usage: None,
            }],
            run_compaction_with_retry(
                &config,
                &settings,
                Some("focus"),
                |focus_override| compaction_user_prompt(None, &history_for_closure, focus_override),
                WarmCompactionKind::ChunkPrefix {
                    messages: &history_for_closure,
                    previous_summary: None,
                },
            ),
        )
        .await
    })
    .await;
    assert_eq!(
        warm_count, 1,
        "warm path must be entered exactly once when compaction_model is empty"
    );
    let summary = summary.expect("warm path should succeed with a six-section scripted turn");
    assert!(summary.contains("Decisions"));
    assert!(summary.contains("Tool outcomes"));
}

#[tokio::test]
async fn cold_path_taken_when_compaction_model_set() {
    let mut config = warm_config();
    config.context_engine.compaction_model = Some("dedicated-compactor-model".to_string());
    let settings = config.context_engine.clone();
    let history: Vec<SessionMessage> = (0..4)
        .map(|index| {
            message(
                &format!("m{index}"),
                if index % 2 == 0 { "user" } else { "assistant" },
                "payload ",
            )
        })
        .collect();
    let summary_text = six_section_summary();
    let history_for_closure = history.clone();
    let (warm_count, summary) = with_warm_path_probe(async {
        with_scripted_turns(
            vec![LlmTurn {
                content: summary_text.clone(),
                reasoning_content: None,
                tool_calls: Vec::new(),
                usage: None,
            }],
            run_compaction_with_retry(
                &config,
                &settings,
                Some("focus"),
                |focus_override| compaction_user_prompt(None, &history_for_closure, focus_override),
                WarmCompactionKind::ChunkPrefix {
                    messages: &history_for_closure,
                    previous_summary: None,
                },
            ),
        )
        .await
    })
    .await;
    assert_eq!(
        warm_count, 0,
        "cold path must be taken when compaction_model is set"
    );
    let summary = summary.expect("cold path should succeed with a six-section scripted turn");
    assert!(summary.contains("Decisions"));
    assert!(summary.contains("Tool outcomes"));
}

#[tokio::test]
async fn warm_path_retries_when_first_attempt_misses_required_sections() {
    let config = warm_config();
    let settings = config.context_engine.clone();
    let history: Vec<SessionMessage> = (0..4)
        .map(|index| {
            message(
                &format!("m{index}"),
                if index % 2 == 0 { "user" } else { "assistant" },
                "payload ",
            )
        })
        .collect();
    // Turn 1: missing six sections (gets rejected by required-section check).
    // Turn 2: full six-section summary (accepted on retry).
    let bad_turn = LlmTurn {
        content: "free-form text without required headings".to_string(),
        reasoning_content: None,
        tool_calls: Vec::new(),
        usage: None,
    };
    let good_turn = LlmTurn {
        content: six_section_summary(),
        reasoning_content: None,
        tool_calls: Vec::new(),
        usage: None,
    };
    let history_for_closure = history.clone();
    let (warm_count, result) = with_warm_path_probe(async {
        with_scripted_turns(
            vec![bad_turn, good_turn],
            run_compaction_with_retry(
                &config,
                &settings,
                Some("focus"),
                |focus_override| compaction_user_prompt(None, &history_for_closure, focus_override),
                WarmCompactionKind::ChunkPrefix {
                    messages: &history_for_closure,
                    previous_summary: None,
                },
            ),
        )
        .await
    })
    .await;
    assert_eq!(
        warm_count, 1,
        "warm path entered once before the retry loop"
    );
    let summary = result.expect("retry with focus injection should recover the six sections");
    assert!(summary.contains("Decisions"));
    assert!(summary.contains("Tool outcomes"));
}

#[tokio::test]
async fn warm_path_returns_section_error_after_retry_exhausts() {
    let config = warm_config();
    let settings = config.context_engine.clone();
    let history: Vec<SessionMessage> = (0..4)
        .map(|index| {
            message(
                &format!("m{index}"),
                if index % 2 == 0 { "user" } else { "assistant" },
                "payload ",
            )
        })
        .collect();
    let bad1 = LlmTurn {
        content: "first bad attempt".to_string(),
        reasoning_content: None,
        tool_calls: Vec::new(),
        usage: None,
    };
    let bad2 = LlmTurn {
        content: "second bad attempt".to_string(),
        reasoning_content: None,
        tool_calls: Vec::new(),
        usage: None,
    };
    let history_for_closure = history.clone();
    let (warm_count, result) = with_warm_path_probe(async {
        with_scripted_turns(
            vec![bad1, bad2],
            run_compaction_with_retry(
                &config,
                &settings,
                Some("focus"),
                |focus_override| compaction_user_prompt(None, &history_for_closure, focus_override),
                WarmCompactionKind::ChunkPrefix {
                    messages: &history_for_closure,
                    previous_summary: None,
                },
            ),
        )
        .await
    })
    .await;
    assert_eq!(warm_count, 1);
    let err = result.expect_err(
        "both attempts miss sections; warm path must surface the cold-path section error",
    );
    assert_eq!(
        err,
        "Context compaction LLM did not return the required summary sections"
    );
}

#[tokio::test]
async fn warm_path_returns_empty_summary_error() {
    let config = warm_config();
    let settings = config.context_engine.clone();
    let history: Vec<SessionMessage> = (0..4)
        .map(|index| {
            message(
                &format!("m{index}"),
                if index % 2 == 0 { "user" } else { "assistant" },
                "payload ",
            )
        })
        .collect();
    let history_for_closure = history.clone();
    let (warm_count, result) = with_warm_path_probe(async {
        // No scripted turns queued -> __test_noop__ returns empty String
        // -> warm path's empty-summary guard fires.
        run_compaction_with_retry(
            &config,
            &settings,
            Some("focus"),
            |focus_override| compaction_user_prompt(None, &history_for_closure, focus_override),
            WarmCompactionKind::ChunkPrefix {
                messages: &history_for_closure,
                previous_summary: None,
            },
        )
        .await
    })
    .await;
    assert_eq!(warm_count, 1);
    let err = result.expect_err("empty summary must surface the empty-summary error");
    assert_eq!(err, "Context compaction LLM returned an empty summary");
}

#[test]
fn build_warm_compaction_messages_appends_directive_when_prefix_ends_non_user() {
    let prefix = vec![
        message("u1", "user", "hello"),
        message("a1", "assistant", "hi"),
    ];
    let out = build_warm_compaction_messages_test(&prefix, "directive text");
    assert_eq!(out.len(), 3);
    assert_eq!(out[2].role, "user");
    assert_eq!(out[2].content, "directive text");
}

#[test]
fn build_warm_compaction_messages_merges_directive_into_trailing_user() {
    let prefix = vec![
        message("u1", "user", "hello"),
        message("a1", "assistant", "hi"),
        message("u2", "user", "question"),
    ];
    let out = build_warm_compaction_messages_test(&prefix, "directive text");
    assert_eq!(out.len(), 3, "trailing user message must not be duplicated");
    assert!(out[2].content.contains("question"));
    assert!(out[2].content.contains("directive text"));
    assert!(out[2].content.contains("---"));
}

#[test]
fn build_warm_compaction_messages_with_empty_prefix_sends_directive_alone() {
    let out = build_warm_compaction_messages_test(&[], "directive text");
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].role, "user");
    assert_eq!(out[0].content, "directive text");
}
