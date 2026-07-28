#[flutter_rust_bridge::frb(sync)]
pub fn configure_codex_agent_engine_json(handle: i64, request_json: String) -> String {
    napaxi_core::api::agent_engine::configure_codex_agent_engine_json(handle, &request_json)
}

/// Intentionally asynchronous at the FRB boundary: native history RPC may
/// wait for a Codex app-server process and must never block the Flutter UI.
pub fn query_codex_agent_engine_history_json(handle: i64, request_json: String) -> String {
    napaxi_core::api::agent_engine::query_codex_agent_engine_history_json(handle, &request_json)
}
