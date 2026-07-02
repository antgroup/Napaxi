//! Napaxi-owned mobile runtime orchestration helpers.
//!
//! Public surface preserved through pub use below. Split into:
//!
//! - [`engine`]: Engine struct + config/agent registry state
//! - [`session_runtime`]: long-lived session runtime state for active turns
//! - [`handle`]: FFI-friendly engine handle creation / lifetime / conversion
//! - [`capability_api`]: capability status + config update handle wrappers
//! - [`agents`]: agent registry handle wrappers
//! - [`sessions`]: session keys, scoped workspace dirs, cancellation, injection
//! - [`tool_context`]: session tool context assembly + dispatcher registry
//! - [`messaging`]: send / stream session handle wrappers

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod agents;
mod capability_api;
mod engine;
mod handle;
mod messaging;
mod session_runtime;
mod sessions;
mod tool_context;

#[cfg(test)]
mod tests;

pub const DEFAULT_AGENT_ID: &str = "napaxi";
pub const DEFAULT_ACCOUNT_ID: &str = "default";

// Engine struct + utilities.
pub use engine::{Engine, normalize_agent_id};

// Handle lifetime + creation.
pub use handle::{
    create_engine_handle, dispose_engine_handle, files_dir_from_handle, handle_consume,
    handle_to_arc, invalid_handle_json, platform_from_handle,
};

// Capability + config handle wrappers.
pub use capability_api::{
    capability_status_json_handle, get_config_handle, get_config_handle_typed,
    update_config_handle, update_config_handle_typed,
};

// Agent registry handle wrappers.
pub use agents::{
    delete_agent_handle, delete_agent_handle_typed, get_or_create_agent_handle, list_agents_handle,
};

// Session keys, scoped workspace dirs, cancellation, injection.
pub use sessions::{
    cancel_session_handle, cancel_session_handle_typed, default_session, inject_message_handle,
    retract_injected_message_handle, retract_injected_message_handle_typed,
    scoped_workspace_files_dir, scoped_workspace_files_dir_from_handle, session_account_id,
};
#[cfg(test)]
pub use sessions::{cancel_session_key, clear_session_cancellation, is_session_cancelled};

// Tool context + dispatcher.
pub use tool_context::{
    SessionToolContext, available_tool_infos_json, available_tool_infos_json_handle,
    prepare_session_tool_context, set_tool_request_dispatcher, tool_request_dispatcher,
    update_custom_tools_handle, update_custom_tools_handle_typed,
};
pub(crate) use tool_context::{
    prepare_session_tool_context_with_config_and_thread_for_core,
    prepare_session_tool_context_with_config_for_core,
};

// Messaging (send + stream).
pub use messaging::{
    SessionTurnInput, run_session_turn, send_message_json_handle, send_to_session_events_handle,
    send_to_session_json_handle, stream_message_handle, stream_session_turn,
    stream_to_session_handle, stream_to_session_with_display_handle,
};
