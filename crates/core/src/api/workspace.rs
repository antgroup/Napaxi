//! Workspace API and scoped workspace path policy.

pub use crate::workspace::{
    append_workspace_file_handle, delete_workspace_file_handle, list_journal_days_handle,
    list_workspace_files_handle, read_journal_day_handle, read_workspace_file_handle,
    rebuild_recall_index_handle, recall_index_stats_handle, recall_sessions_handle,
    reseed_workspace_handle, search_memory_handle, system_prompt_handle,
    write_workspace_file_handle,
};
