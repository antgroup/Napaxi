//! File-backed mobile group state for the standalone SDK runtime.
//!
//! Public surface preserved through pub use below. Implementation split into:
//!
//! - [`types`]: DTOs (Group, GroupMessage, GroupInfo, ...)
//! - [`state`]: persistence (load/save) and shared mutation helpers
//! - [`crud`]: create/delete/list/get/rename/update/custom prompt
//! - [`messages`]: append/list messages, history clearing, membership check
//! - [`coordinator`]: prompt assembly, system prompt overlay, session keys, event helpers
//! - [`tools`]: tool descriptors and internal tool handler/dispatch
//! - [`delegate`]: send_to_group and send_to_group_agent
//! - [`export`]: import/export group state
//! - [`handles`]: engine-handle wrappers used by the bridge

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod coordinator;
mod crud;
mod delegate;
mod export;
mod handles;
mod messages;
mod state;
mod tools;
mod types;

#[cfg(test)]
mod tests;

pub use coordinator::{
    append_system_prompt, build_coordinator_prompt, extract_response, group_members_text,
    session_key, wrap_events,
};
pub use crud::{
    create_group, delete_group, get_group, get_group_value, list_groups, rename_group,
    set_group_custom_prompt, update_group_members,
};
pub use delegate::{send_to_group, send_to_group_agent};
pub use export::{export_group_state, import_group_state};
pub use handles::{
    clear_group_history_handle, create_group_handle, delete_group_handle,
    export_group_state_handle, get_group_handle, get_group_messages_handle,
    import_group_state_handle, list_groups_handle, rename_group_handle, send_to_group_agent_handle,
    send_to_group_handle, set_group_custom_prompt_handle, update_group_members_handle,
};
pub use messages::{
    add_agent_message, add_delegation_message, add_user_message, clear_group_history,
    get_group_messages, is_group_member,
};
pub use tools::{execute_group_tool, group_internal_tool_handler, group_tool_descriptors};
pub use types::{
    Group, GroupInfo, GroupMemberTask, GroupMessage, GroupMessageType, GroupSessionState,
    GroupState, GroupToolExecution,
};
