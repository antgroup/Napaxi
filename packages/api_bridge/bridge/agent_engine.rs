#[flutter_rust_bridge::frb(sync)]
pub fn configure_codex_agent_engine_json(handle: i64, request_json: String) -> String {
    napaxi_core::api::agent_engine::configure_codex_agent_engine_json(handle, &request_json)
}
