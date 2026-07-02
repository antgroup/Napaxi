//! Adapter-neutral API for agent app action packages.

/// Register an agent app action package from its JSON definition.
pub fn register_agent_app_package(handle: i64, package_json: &str) -> String {
    crate::agents::agent_app::register_package_handle(handle, package_json)
}

/// List all registered agent app action packages as a JSON array.
pub fn list_agent_app_packages(handle: i64) -> String {
    crate::agents::agent_app::list_packages_json_handle(handle)
}

/// Fetch a single agent app action package by agent id as JSON.
pub fn get_agent_app_package(handle: i64, agent_id: &str) -> String {
    crate::agents::agent_app::get_package_json_handle(handle, agent_id)
}

/// Delete an agent app action package by agent id; returns whether it existed.
pub fn delete_agent_app_package(handle: i64, agent_id: &str) -> bool {
    crate::agents::agent_app::delete_package_handle(handle, agent_id)
}

/// Submit the result of an executed agent app action back to the engine.
pub fn submit_agent_app_action_result(handle: i64, result_json: &str) -> String {
    crate::agents::agent_app::submit_result_handle(handle, result_json)
}

/// List pending action proposals awaiting host approval for an agent.
pub fn list_agent_app_action_proposals(handle: i64, agent_id: &str) -> String {
    crate::agents::agent_app::list_proposals_json_handle(handle, agent_id)
}

/// Fetch a single action proposal by request id as JSON.
pub fn get_agent_app_action_proposal(handle: i64, request_id: &str) -> String {
    crate::agents::agent_app::get_proposal_json_handle(handle, request_id)
}

/// Accept an agent app trigger, starting the associated action flow.
pub fn accept_agent_app_trigger(handle: i64, trigger_json: &str) -> String {
    crate::agents::agent_app::accept_trigger_handle(handle, trigger_json)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn is_error_json(json: &str) -> bool {
        let v: serde_json::Value =
            serde_json::from_str(json).expect("is_error_json: not valid JSON");
        v.get("error").is_some()
    }

    #[test]
    fn invalid_handle_returns_safe_defaults_for_all_agent_app_api_methods() {
        let bad: i64 = 0;

        // Write operations return error JSON.
        assert!(is_error_json(&register_agent_app_package(bad, "{}")));
        assert!(is_error_json(&submit_agent_app_action_result(bad, "{}")));
        assert!(is_error_json(&accept_agent_app_trigger(bad, "{}")));

        // Read operations gracefully degrade: list → empty array, get → error
        // or null, delete → false. This is by design — callers show "no data"
        // rather than surfacing an engine error to the user.
        assert_eq!(list_agent_app_packages(bad), "[]");
        assert!(!delete_agent_app_package(bad, "any"));

        let get = get_agent_app_package(bad, "any");
        let get_val: serde_json::Value =
            serde_json::from_str(&get).expect("get_agent_app_package should return valid JSON");
        assert!(
            get_val.is_null() || get_val.get("error").is_some(),
            "get should be null or error object: {get_val}"
        );

        let proposals = list_agent_app_action_proposals(bad, "any");
        let proposals_val: serde_json::Value = serde_json::from_str(&proposals)
            .expect("list_agent_app_action_proposals should return valid JSON");
        assert!(
            proposals_val.as_array().is_some_and(|a| a.is_empty())
                || proposals_val.get("error").is_some(),
            "proposals should be empty array or error object: {proposals_val}"
        );

        let proposal = get_agent_app_action_proposal(bad, "any");
        let proposal_val: serde_json::Value = serde_json::from_str(&proposal)
            .expect("get_agent_app_action_proposal should return valid JSON");
        assert!(
            proposal_val.is_null() || proposal_val.get("error").is_some(),
            "proposal should be null or error object: {proposal_val}"
        );
    }

    #[test]
    fn valid_handle_round_trips_agent_app_package_crud() {
        let temp = tempfile::tempdir().unwrap();
        let config_json = serde_json::json!({
            "provider": "openai",
            "api_key": "test",
            "base_url": null,
            "model": "test-model",
            "system_prompt": "",
            "max_tokens": 128
        })
        .to_string();
        let context_json = serde_json::json!({
            "platform": "test",
            "files_dir": temp.path().to_str().unwrap(),
            "native_library_dir": null
        })
        .to_string();
        let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();

        // Register a package.
        let package = serde_json::json!({
            "provider_id": "test.provider",
            "agent_id": "test.agent",
            "display_name": "Test Agent",
            "description": "A test agent app package",
            "system_prompt": "You are a test agent.",
            "actions": [],
            "handoff": {"mode": "app_handoff"},
            "result": {"mode": "callback"}
        });
        let reg_result = register_agent_app_package(handle, &package.to_string());
        assert!(
            !is_error_json(&reg_result),
            "register should succeed: {reg_result}"
        );

        // List should contain it.
        let list = list_agent_app_packages(handle);
        assert!(
            list.contains("test.agent"),
            "list should include the package"
        );

        // Get by agent id.
        let get = get_agent_app_package(handle, "test.agent");
        assert!(
            get.contains("test.agent"),
            "get should return the package: {get}"
        );

        // Delete.
        assert!(delete_agent_app_package(handle, "test.agent"));
        let list_after = list_agent_app_packages(handle);
        assert!(
            !list_after.contains("test.agent"),
            "deleted package should not appear in list"
        );

        // Proposals list (empty is fine, just should not error).
        let proposals = list_agent_app_action_proposals(handle, "test.agent");
        assert!(!is_error_json(&proposals), "proposals list: {proposals}");

        // Get proposal for a nonexistent request id returns error.
        let proposal = get_agent_app_action_proposal(handle, "nonexistent");
        assert!(
            is_error_json(&proposal)
                || serde_json::from_str::<serde_json::Value>(&proposal)
                    .unwrap()
                    .is_null()
        );

        crate::runtime::dispose_engine_handle(handle);
    }
}
