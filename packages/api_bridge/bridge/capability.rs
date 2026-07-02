#[flutter_rust_bridge::frb(sync)]
pub fn list_capability_definitions_json() -> String {
    napaxi_core::api::capability::list_capability_definitions_json()
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_capability_status_json(
    handle: i64,
    profile_json: String,
    selection_json: String,
) -> String {
    napaxi_core::api::capability::list_capability_status_json_handle(
        handle,
        &profile_json,
        &selection_json,
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_scenario_packs_json(handle: i64) -> String {
    napaxi_core::api::capability::list_scenario_packs_json_handle(handle)
}

#[flutter_rust_bridge::frb(sync)]
pub fn install_scenario_pack_json(handle: i64, pack_json: String) -> String {
    napaxi_core::api::capability::install_scenario_pack_json_handle(handle, &pack_json)
}

#[flutter_rust_bridge::frb(sync)]
pub fn remove_scenario_pack_json(handle: i64, scenario_id: String) -> String {
    napaxi_core::api::capability::remove_scenario_pack_json_handle(handle, &scenario_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_scenario_status_json(
    handle: i64,
    profile_json: String,
    selection_json: String,
) -> String {
    napaxi_core::api::capability::list_scenario_status_json_handle(
        handle,
        &profile_json,
        &selection_json,
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn resolve_scenario_json(
    handle: i64,
    profile_json: String,
    selection_json: String,
    scenario_id: String,
) -> String {
    napaxi_core::api::capability::resolve_scenario_json_handle(
        handle,
        &profile_json,
        &selection_json,
        &scenario_id,
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn provider_capability_id(provider: String) -> String {
    napaxi_core::api::capability::provider_capability_id(&provider)
}

#[flutter_rust_bridge::frb(sync)]
pub fn agent_engine_capability_id(engine_id: String) -> String {
    napaxi_core::api::capability::agent_engine_capability_id(&engine_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn tool_capability_id(tool_name: String) -> String {
    napaxi_core::api::capability::tool_capability_id(&tool_name)
}
