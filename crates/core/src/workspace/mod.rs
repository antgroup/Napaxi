//! File-backed workspace helpers for the standalone mobile SDK runtime.
//!
//! Public surface is preserved through re-exports below. Implementation is
//! split into:
//!
//! - [`paths`]: file name constants, account/agent scoping, path normalization
//! - [`types`]: DTOs returned over the workspace API
//! - [`meta`]: time, preview, and error JSON helpers shared across submodules
//! - [`files`]: read/write/append/delete/list and the `_handle`/`_checked` variants
//! - [`prompt`]: system prompt assembly from memory files
//! - [`journal`]: turn append, listing, and read with legacy daily fallback
//! - [`search`]: term-frequency search across memory and journal
//! - [`profile`]: profile JSON storage and derived prompt-document sync
//! - [`reseed`]: seeding and migration from legacy memory layouts
//! - [`recall`]: indexed recall over memory and journal (libsql-backed)

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod files;
mod journal;
mod meta;
mod paths;
mod profile;
mod prompt;
pub mod recall;
mod reseed;
mod search;
mod types;

#[cfg(test)]
mod tests;

pub use files::{
    append_workspace_file, append_workspace_file_checked, append_workspace_file_handle,
    delete_workspace_file, delete_workspace_file_handle, list_workspace_entries,
    list_workspace_files, list_workspace_files_handle, read_workspace_file,
    read_workspace_file_content, read_workspace_file_handle, write_workspace_file,
    write_workspace_file_checked, write_workspace_file_handle,
};
pub use journal::{
    append_journal_note, append_journal_turn, list_journal_days, list_journal_days_handle,
    read_journal_day, read_journal_day_handle,
};
pub use paths::{
    default_scoped_files_dir, looks_like_filesystem_path, normalize_workspace_memory_path,
    scoped_files_dir,
};
pub(crate) use profile::is_profile_populated;
pub use profile::{sync_profile_documents, write_profile_json};
pub(crate) use prompt::{WorkspacePromptSplit, workspace_prompt_split_with_language};
pub use prompt::{system_prompt, system_prompt_for_context, system_prompt_handle};
pub use recall::MemoryRecallSession;
pub use reseed::{reseed_workspace, reseed_workspace_handle};
pub use search::{search_memory, search_memory_handle, search_memory_results};
pub use types::{JournalDay, JournalTurnRecord, MemorySearchResult, WorkspaceEntry, WorkspaceFile};

use meta::{error_json, invalid_handle_json};

// Internal re-exports so the `recall` submodule can keep its `super::SYM` paths
// after the file split, without us editing its body.
pub(in crate::workspace) use journal::{
    journal_record_search_text, journal_records, legacy_daily_contents,
};
pub(in crate::workspace) use meta::modified_rfc3339;
pub(in crate::workspace) use paths::{
    ASSISTANT_DIRECTIVES, HEARTBEAT, MEMORY, PROFILE, PROJECT, USER,
};
pub(in crate::workspace) use search::{
    is_hybrid_match, modified_workspace_path, search_memory_results_fallback, search_terms, snippet,
};

pub async fn recall_sessions(
    files_dir: &str,
    config: &crate::types::PlatformLlmConfig,
    current_thread_id: Option<&str>,
    query: &str,
    limit: usize,
) -> Result<Vec<MemoryRecallSession>, String> {
    recall::recall_sessions(files_dir, config, current_thread_id, query, limit).await
}

pub async fn recall_sessions_handle(
    handle: i64,
    config_json: &str,
    account_id: &str,
    agent_id: &str,
    current_thread_id: &str,
    query: &str,
    limit: u32,
) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    let config = match serde_json::from_str::<crate::types::PlatformLlmConfig>(config_json) {
        Ok(config) => config,
        Err(error) => return error_json(&format!("Invalid config: {error}")),
    };
    match recall_sessions(
        &files_dir,
        &config,
        Some(current_thread_id).filter(|value| !value.trim().is_empty()),
        query,
        limit.clamp(1, 5) as usize,
    )
    .await
    {
        Ok(results) => {
            serde_json::to_string(&results).unwrap_or_else(|e| error_json(&e.to_string()))
        }
        Err(error) => error_json(&error),
    }
}

pub fn rebuild_recall_index_handle(handle: i64, account_id: &str, agent_id: &str) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    match recall::rebuild_index(&files_dir) {
        Ok(stats) => serde_json::to_string(&stats).unwrap_or_else(|e| error_json(&e.to_string())),
        Err(error) => error_json(&error),
    }
}

pub fn recall_index_stats_handle(handle: i64, account_id: &str, agent_id: &str) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    match recall::index_stats(&files_dir) {
        Ok(stats) => serde_json::to_string(&stats).unwrap_or_else(|e| error_json(&e.to_string())),
        Err(error) => error_json(&error),
    }
}
