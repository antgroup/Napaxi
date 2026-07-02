//! FRB workspace bridge functions. Split out of `bridge/mod.rs`;
//! path `bridge::workspace::*` is unchanged for codegen.

pub fn read_workspace_file(
    handle: i64,
    account_id: String,
    agent_id: String,
    path: String,
) -> String {
    napaxi_core::api::workspace::read_workspace_file_handle(handle, &account_id, &agent_id, &path)
}
pub fn write_workspace_file(
    handle: i64,
    account_id: String,
    agent_id: String,
    path: String,
    content: String,
) -> bool {
    napaxi_core::api::workspace::write_workspace_file_handle(
        handle,
        &account_id,
        &agent_id,
        &path,
        &content,
    )
}
pub fn append_workspace_file(
    handle: i64,
    account_id: String,
    agent_id: String,
    path: String,
    content: String,
) -> bool {
    napaxi_core::api::workspace::append_workspace_file_handle(
        handle,
        &account_id,
        &agent_id,
        &path,
        &content,
    )
}
pub fn delete_workspace_file(
    handle: i64,
    account_id: String,
    agent_id: String,
    path: String,
) -> bool {
    napaxi_core::api::workspace::delete_workspace_file_handle(handle, &account_id, &agent_id, &path)
}
pub fn list_workspace_files(
    handle: i64,
    account_id: String,
    agent_id: String,
    directory: String,
) -> String {
    napaxi_core::api::workspace::list_workspace_files_handle(
        handle,
        &account_id,
        &agent_id,
        &directory,
    )
}
pub fn get_system_prompt(handle: i64, account_id: String, agent_id: String) -> String {
    napaxi_core::api::workspace::system_prompt_handle(handle, &account_id, &agent_id)
}
pub fn reseed_workspace(handle: i64, account_id: String, agent_id: String) -> String {
    napaxi_core::api::workspace::reseed_workspace_handle(handle, &account_id, &agent_id)
}
pub fn search_memory(
    handle: i64,
    account_id: String,
    agent_id: String,
    query: String,
    limit: u32,
) -> String {
    napaxi_core::api::workspace::search_memory_handle(handle, &account_id, &agent_id, &query, limit)
}
pub async fn recall_sessions(
    handle: i64,
    config_json: String,
    account_id: String,
    agent_id: String,
    current_thread_id: String,
    query: String,
    limit: u32,
) -> String {
    napaxi_core::api::workspace::recall_sessions_handle(
        handle,
        &config_json,
        &account_id,
        &agent_id,
        &current_thread_id,
        &query,
        limit,
    )
    .await
}
pub fn rebuild_recall_index(handle: i64, account_id: String, agent_id: String) -> String {
    napaxi_core::api::workspace::rebuild_recall_index_handle(handle, &account_id, &agent_id)
}
pub fn recall_index_stats(handle: i64, account_id: String, agent_id: String) -> String {
    napaxi_core::api::workspace::recall_index_stats_handle(handle, &account_id, &agent_id)
}
pub fn list_journal_days(handle: i64, account_id: String, agent_id: String) -> String {
    napaxi_core::api::workspace::list_journal_days_handle(handle, &account_id, &agent_id)
}
pub fn read_journal_day(handle: i64, account_id: String, agent_id: String, date: String) -> String {
    napaxi_core::api::workspace::read_journal_day_handle(handle, &account_id, &agent_id, &date)
}
