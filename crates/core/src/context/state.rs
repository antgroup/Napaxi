//! Persisted per-thread context state and snapshot records.
//!
//! These types are owned by the context engine and live under
//! `<files_dir>/napaxi/context/<thread_id>.json`. The records here are
//! pure data + load/save helpers — compaction logic lives in
//! [`super::compaction`], budget math lives in [`super::budget`], and
//! status rendering lives in [`super::mod`].

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

const CONTEXT_DIR: &str = "napaxi/context";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(super) struct ContextState {
    pub(super) thread_id: String,
    pub(super) engine: String,
    #[serde(default)]
    pub(super) summary: Option<ContextSummaryRecord>,
    #[serde(default)]
    pub(super) compaction_count: usize,
    #[serde(default)]
    pub(super) last_compacted_at: Option<String>,
    #[serde(default)]
    pub(super) last_prompt_snapshot: Option<LastPromptSnapshot>,
    #[serde(default)]
    pub(super) preflight_snapshot: Option<PreflightSnapshot>,
    #[serde(default)]
    pub(super) last_tool_compaction: Option<ToolCompactionSnapshot>,
    #[serde(default)]
    pub(super) provider_context_metadata: Option<ProviderContextMetadataSnapshot>,
    #[serde(default)]
    pub(super) last_overflow_recovery: Option<OverflowRecoverySnapshot>,
    #[serde(default)]
    pub(super) last_memory_flush: Option<MemoryFlushSnapshot>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ContextSummaryRecord {
    pub(super) content: String,
    pub(super) compacted_through_message_id: String,
    pub(super) source_message_count: usize,
    pub(super) tokens_before: usize,
    pub(super) tokens_after: usize,
    pub(super) created_at: String,
    #[serde(default = "default_compaction_strategy")]
    pub(super) strategy: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) duration_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) focus: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) adaptive_chunk_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) oversized_message_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) protected_tail_tokens: Option<usize>,
}

fn default_compaction_strategy() -> String {
    "local_summary".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct LastPromptSnapshot {
    #[serde(default)]
    pub(super) provider: String,
    #[serde(default)]
    pub(super) model: String,
    #[serde(default)]
    pub(super) config_fingerprint: String,
    pub(super) prompt_tokens: usize,
    #[serde(default)]
    pub(super) input_tokens: usize,
    #[serde(default)]
    pub(super) output_tokens: usize,
    #[serde(default)]
    pub(super) cache_read_tokens: usize,
    #[serde(default)]
    pub(super) cache_write_tokens: usize,
    #[serde(default)]
    pub(super) reasoning_tokens: usize,
    #[serde(default)]
    pub(super) total_tokens: Option<usize>,
    pub(super) updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct PreflightSnapshot {
    #[serde(default)]
    pub(super) provider: String,
    #[serde(default)]
    pub(super) model: String,
    #[serde(default)]
    pub(super) config_fingerprint: String,
    pub(super) estimated_tokens: usize,
    pub(super) context_window_tokens: usize,
    pub(super) response_reserve_tokens: usize,
    pub(super) context_window_source: String,
    #[serde(default)]
    pub(super) native_context_window_tokens: usize,
    #[serde(default)]
    pub(super) native_context_window_source: String,
    #[serde(default)]
    pub(super) effective_context_window_tokens: usize,
    #[serde(default)]
    pub(super) effective_context_window_source: String,
    #[serde(default)]
    pub(super) response_reserve_source: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) provider_metadata_fetched_at: Option<String>,
    #[serde(default)]
    pub(super) provider_metadata_stale: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) provider_metadata_error: Option<String>,
    pub(super) breakdown: ContextTokenBreakdown,
    pub(super) context_budget_status: ContextBudgetStatus,
    pub(super) updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(super) struct ContextTokenBreakdown {
    pub(super) system_prompt_tokens: usize,
    pub(super) summary_tokens: usize,
    pub(super) history_tokens: usize,
    pub(super) tool_descriptor_tokens: usize,
    pub(super) tool_result_tokens: usize,
    pub(super) tool_call_tokens: usize,
    pub(super) attachment_tokens: usize,
    pub(super) image_tokens: usize,
    pub(super) response_reserve_tokens: usize,
    pub(super) total_tokens: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ContextBudgetStatus {
    pub(super) source: String,
    pub(super) provider: String,
    pub(super) model: String,
    pub(super) route: String,
    pub(super) should_compact: bool,
    pub(super) estimated_prompt_tokens: usize,
    pub(super) context_token_budget: usize,
    #[serde(default)]
    pub(super) native_context_window_tokens: usize,
    #[serde(default)]
    pub(super) native_context_window_source: String,
    #[serde(default)]
    pub(super) effective_context_window_tokens: usize,
    #[serde(default)]
    pub(super) effective_context_window_source: String,
    #[serde(default)]
    pub(super) response_reserve_source: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) provider_metadata_fetched_at: Option<String>,
    #[serde(default)]
    pub(super) provider_metadata_stale: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) provider_metadata_error: Option<String>,
    pub(super) prompt_budget_before_reserve: usize,
    pub(super) reserve_tokens: usize,
    pub(super) effective_reserve_tokens: usize,
    pub(super) remaining_prompt_budget_tokens: isize,
    pub(super) overflow_tokens: usize,
    pub(super) tool_result_reducible_chars: usize,
    #[serde(default)]
    pub(super) tool_result_reducible_tokens: usize,
    #[serde(default)]
    pub(super) context_guard_status: String,
    #[serde(default)]
    pub(super) context_guard_reason: String,
    pub(super) message_count: usize,
    pub(super) unwindowed_message_count: usize,
    pub(super) updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ToolCompactionSnapshot {
    pub(super) compacted_messages: usize,
    pub(super) original_chars: usize,
    pub(super) compacted_chars: usize,
    pub(super) pruned_chars: usize,
    pub(super) estimated_pruned_tokens: usize,
    pub(super) updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ProviderContextMetadataSnapshot {
    pub(super) provider: String,
    pub(super) model: String,
    pub(super) native_context_window_tokens: usize,
    #[serde(default)]
    pub(super) output_token_limit: Option<usize>,
    pub(super) fetched_at: String,
    #[serde(default)]
    pub(super) stale: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct OverflowRecoverySnapshot {
    pub(super) provider: String,
    pub(super) model: String,
    pub(super) attempted_at: String,
    pub(super) succeeded: bool,
    pub(super) retry_count: usize,
    pub(super) reason: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct MemoryFlushSnapshot {
    pub(super) attempted_at: String,
    pub(super) enabled: bool,
    pub(super) succeeded: bool,
    pub(super) reason: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) error: Option<String>,
}

pub(super) fn load_state(files_dir: &str, thread_id: &str) -> Option<ContextState> {
    let content = fs::read_to_string(state_path(files_dir, thread_id)).ok()?;
    serde_json::from_str(&content).ok()
}

pub(super) fn save_state(files_dir: &str, state: &ContextState) -> Result<(), String> {
    let path = state_path(files_dir, &state.thread_id);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let content = serde_json::to_string_pretty(state).map_err(|error| error.to_string())?;
    crate::storage::atomic_write_text_sync(&path, &content)
}

pub(crate) fn delete_context_state(files_dir: &str, thread_id: &str) -> bool {
    let path = state_path(files_dir, thread_id);
    if path.exists() {
        fs::remove_file(path).is_ok()
    } else {
        true
    }
}

fn state_path(files_dir: &str, thread_id: &str) -> PathBuf {
    Path::new(files_dir)
        .join(CONTEXT_DIR)
        .join(format!("{thread_id}.json"))
}
