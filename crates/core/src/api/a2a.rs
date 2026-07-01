//! Mobile A2A deep-link API.

/// Local-pairing wire-shape contract (invite codec field names, QR prefix,
/// pairing message kinds, task-status classification). Adapters bind these
/// instead of hand-copying string literals — see the module docs.
pub use crate::a2a::local_pairing_contract;
pub use crate::a2a::{
    accept_deep_link_handle, accept_peer_invite_handle, build_result_link_handle,
    create_peer_invite_handle, create_task_message_handle, create_task_progress_message_handle,
    create_task_result_message_handle, delete_peer_handle, get_a2a_agent_card_handle,
    get_task_handle, list_delivery_records_handle, list_peer_messages_handle,
    list_peer_sessions_handle, list_peers_handle, list_tasks_handle, open_peer_session_handle,
    record_delivery_status_handle, record_peer_message_handle, record_result_envelope_handle,
    run_task_handle,
};
