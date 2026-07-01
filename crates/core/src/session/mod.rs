//! File-backed session metadata and history helpers for the standalone mobile SDK runtime.
//!
//! Split across submodules:
//! - [`types`]: stable wire types (`SessionKey`, `SessionMessage`, `SessionAppendMessage`).
//! - [`store`]: on-disk persistence + path/string/time helpers.
//! - [`lifecycle`]: create / list / delete / clear.
//! - [`mutation`]: append, replace turn segment, interrupt flags, inject, remove.
//! - [`history`]: read-only UI history, paginated windows, LLM context history.

mod history;
mod lifecycle;
mod mutation;
mod store;
mod types;

#[cfg(test)]
mod tests;

pub use types::{SessionAppendMessage, SessionKey, SessionMessage};

pub use lifecycle::{
    clear_session, clear_session_handle, create_session, create_session_handle, delete_session,
    delete_session_handle, delete_session_if_empty, delete_session_if_empty_handle, list_sessions,
    list_sessions_handle, prune_empty_sessions, prune_empty_sessions_handle,
};

#[allow(unused_imports)]
pub use mutation::{
    append_message, append_messages, append_trace_messages, inject_user_message,
    inject_user_message_handle, mark_asking_human_interrupted, remove_latest_user_message,
    replace_turn_segment,
};

#[allow(unused_imports)]
pub use history::{
    get_history, get_history_handle, get_history_page, get_history_page_handle, llm_history,
};

#[allow(unused_imports)]
pub(crate) use history::{llm_context_history_all, llm_history_all};
