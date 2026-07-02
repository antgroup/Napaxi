//! Engine-handle wrappers over MCP server APIs.

use super::helpers::invalid_handle_json;
use super::oauth_flow::{finish_oauth, start_oauth};
use super::servers::{activate_server, add_server, deactivate_server, list_servers, remove_server};
use super::tools::list_tools;

pub async fn add_server_handle(
    handle: i64,
    name: &str,
    url: &str,
    headers_json: &str,
    user_id: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    add_server(&files_dir, name, url, headers_json, user_id).await
}

pub async fn start_oauth_handle(
    handle: i64,
    name: &str,
    user_id: &str,
    redirect_uri: &str,
    oauth_json: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    start_oauth(&files_dir, name, user_id, redirect_uri, oauth_json).await
}

pub async fn finish_oauth_handle(
    handle: i64,
    name: &str,
    user_id: &str,
    code: &str,
    state: &str,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    finish_oauth(&files_dir, name, user_id, code, state).await
}

pub fn remove_server_handle(handle: i64, name: &str, user_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    remove_server(&files_dir, name, user_id)
}

pub fn list_servers_handle(handle: i64, user_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_servers(&files_dir, user_id)
}

pub async fn activate_server_handle(handle: i64, name: &str, user_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    activate_server(&files_dir, name, user_id).await
}

pub fn deactivate_server_handle(handle: i64, name: &str, user_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    deactivate_server(&files_dir, name, user_id)
}

pub fn list_tools_handle(handle: i64, server_name: &str, user_id: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return "[]".to_string();
    };
    list_tools(&files_dir, server_name, user_id)
}
