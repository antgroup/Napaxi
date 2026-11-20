use super::super::compaction_assembly::{
    OwnedSliceTranscript, collect_facts, plan_from_facts, render_chunk_prompt,
};
use super::*;
use chrono::Utc;

fn msg(id: &str, role: &str, content: &str) -> SessionMessage {
    SessionMessage {
        id: id.to_string(),
        role: role.to_string(),
        content: content.to_string(),
        created_at: Utc::now().to_rfc3339(),
        interrupted: false,
        turn_id: None,
    }
}

fn cfg(window: usize) -> (PlatformLlmConfig, ContextEngineConfig) {
    let mut config = PlatformLlmConfig::default();
    config.context_engine.context_window_tokens = Some(window);
    let settings = config.context_engine.clone();
    (config, settings)
}

fn legacy_per_chunk_prompts(
    messages: &[SessionMessage],
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    focus: Option<&str>,
) -> Vec<String> {
    let max_chunk = adaptive_chunk_token_budget(config, settings);
    let (sanitized, _) = sanitize_oversized_messages(messages, max_chunk, config, settings);
    let chunks = chunk_messages_by_tokens(&sanitized, max_chunk);
    chunks
        .iter()
        .map(|chunk| compaction_user_prompt(None, chunk, focus))
        .collect()
}

fn new_per_chunk_prompts(
    messages: &[SessionMessage],
    config: &PlatformLlmConfig,
    settings: &ContextEngineConfig,
    focus: Option<&str>,
) -> Vec<String> {
    let transcript = OwnedSliceTranscript::new(messages);
    let facts = collect_facts(&transcript);
    let plan = plan_from_facts(&facts, config, settings);
    plan.chunks
        .iter()
        .map(|chunk| render_chunk_prompt(&plan, chunk, &transcript, &facts, None, focus))
        .collect()
}

#[test]
fn single_chunk_non_oversized_byte_equal_with_legacy() {
    let messages = vec![
        msg("u1", "user", "Help me ship the build today"),
        msg("a1", "assistant", "Ack: starting CI now."),
        msg("u2", "user", "Did the test pass?"),
    ];
    let (config, settings) = cfg(8_000);
    let legacy = legacy_per_chunk_prompts(&messages, &config, &settings, Some("ship focus"));
    let new = new_per_chunk_prompts(&messages, &config, &settings, Some("ship focus"));
    assert_eq!(
        legacy.len(),
        1,
        "legacy single-chunk expected, got {}: {legacy:?}",
        legacy.len()
    );
    assert_eq!(
        new.len(),
        1,
        "new single-chunk expected, got {}: {new:?}",
        new.len()
    );
    assert_eq!(new[0], legacy[0], "single-chunk prompt drifted from legacy");
}

#[test]
fn multi_chunk_non_oversized_byte_equal_per_chunk() {
    // Each message carries ~6k chars (~1.5k tokens) — adaptive budget is
    // ~floor 1024 for an 8_000 window, so 3 such rows span multiple chunks
    // in both the legacy path (over sanitized == original here) and the
    // new payload-free plan.
    let messages = vec![
        msg("u1", "user", &"needs real summarization ".repeat(250)),
        msg(
            "a1",
            "assistant",
            &"assistant continuation body ".repeat(250),
        ),
        msg("u2", "user", &"next user turn body ".repeat(250)),
    ];
    let (config, settings) = cfg(8_000);
    let legacy = legacy_per_chunk_prompts(&messages, &config, &settings, None);
    let new = new_per_chunk_prompts(&messages, &config, &settings, None);
    assert!(
        legacy.len() >= 2,
        "legacy must produce multiple chunks, got {}: {legacy:?}",
        legacy.len()
    );
    assert_eq!(
        new.len(),
        legacy.len(),
        "chunk count drift: new={} legacy={}",
        new.len(),
        legacy.len()
    );
    for (i, (legacy_prompt, new_prompt)) in legacy.iter().zip(new.iter()).enumerate() {
        assert_eq!(
            new_prompt, legacy_prompt,
            "chunk {i} prompt drifted from legacy"
        );
    }
}

#[test]
fn single_oversized_row_placeholder_byte_equal_with_legacy() {
    // 80k-char row → oversized against an 8_000 window. Both legacy and new
    // produce a single chunk whose sole row carries the placeholder text.
    let messages = vec![msg("u1", "user", &"O".repeat(80_000))];
    let (config, settings) = cfg(8_000);
    let legacy = legacy_per_chunk_prompts(&messages, &config, &settings, None);
    let new = new_per_chunk_prompts(&messages, &config, &settings, None);
    assert_eq!(legacy.len(), 1, "legacy single-chunk expected: {legacy:?}");
    assert_eq!(new.len(), 1, "new single-chunk expected: {new:?}");
    assert_eq!(
        new[0], legacy[0],
        "oversized placeholder prompt drifted from legacy"
    );
    assert!(
        new[0].contains("[oversized message omitted during context compaction:"),
        "oversized placeholder missing in: {0}",
        new[0]
    );
}

#[test]
fn tool_calls_chunk_non_oversized_byte_equal_with_legacy() {
    let tool_content = serde_json::json!({
        "calls": [
            {"name": "browser_snapshot", "result": "page snapshot ok"},
            {"name": "shell_exec", "result": "exit 0"},
        ]
    })
    .to_string();
    let messages = vec![
        msg("t1", "tool_calls", &tool_content),
        msg("u1", "user", "next ask"),
    ];
    let (config, settings) = cfg(8_000);
    let legacy = legacy_per_chunk_prompts(&messages, &config, &settings, Some("tools focus"));
    let new = new_per_chunk_prompts(&messages, &config, &settings, Some("tools focus"));
    assert_eq!(legacy.len(), 1, "legacy single-chunk expected: {legacy:?}");
    assert_eq!(new.len(), 1, "new single-chunk expected: {new:?}");
    assert_eq!(new[0], legacy[0], "tool_calls prompt drifted from legacy");
}
