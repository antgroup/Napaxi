//! Session run ledger API.

/// List session runs from the ledger as JSON, filtered and paginated.
pub fn list_session_runs_handle(handle: i64, filter_json: &str, limit: i64, offset: i64) -> String {
    crate::runtime::files_dir_from_handle(handle)
        .map(|files_dir| {
            crate::agent_runtime::runs::list_session_runs_handle(
                &files_dir,
                filter_json,
                limit,
                offset,
            )
        })
        .unwrap_or_else(crate::runtime::invalid_handle_json)
}

/// Fetch a single session run by id as JSON.
pub fn get_session_run_handle(handle: i64, run_id: &str) -> String {
    crate::runtime::files_dir_from_handle(handle)
        .map(|files_dir| crate::agent_runtime::runs::get_session_run_handle(&files_dir, run_id))
        .unwrap_or_else(crate::runtime::invalid_handle_json)
}

/// List currently active (in-progress) session runs as JSON.
pub fn get_active_session_runs_handle(handle: i64) -> String {
    crate::runtime::files_dir_from_handle(handle)
        .map(|files_dir| crate::agent_runtime::runs::active_session_runs_handle(&files_dir))
        .unwrap_or_else(crate::runtime::invalid_handle_json)
}

#[cfg(test)]
mod tests {
    use super::*;

    const INVALID_HANDLE_ERROR: &str = r#"{"error":"invalid engine handle"}"#;

    #[test]
    fn invalid_handle_returns_error_for_all_session_runs_methods() {
        let bad: i64 = 0;
        assert_eq!(
            list_session_runs_handle(bad, "{}", 10, 0),
            INVALID_HANDLE_ERROR
        );
        assert_eq!(get_session_run_handle(bad, "any"), INVALID_HANDLE_ERROR);
        assert_eq!(get_active_session_runs_handle(bad), INVALID_HANDLE_ERROR);
    }

    #[test]
    fn valid_handle_returns_json_arrays_for_empty_ledger() {
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

        // Empty ledger: list and active should return JSON arrays (possibly
        // empty), not error objects.
        let list = list_session_runs_handle(handle, "{}", 10, 0);
        assert!(
            list.starts_with('['),
            "list should return a JSON array, got: {list}"
        );

        let active = get_active_session_runs_handle(handle);
        assert!(
            active.starts_with('['),
            "active should return a JSON array, got: {active}"
        );

        // Get a nonexistent run: may return null or an error; just confirm it
        // doesn't panic and doesn't return invalid JSON.
        let get = get_session_run_handle(handle, "nonexistent-run-id");
        assert!(
            get == "null" || get.starts_with('{'),
            "get should return null or a JSON object, got: {get}"
        );

        crate::runtime::dispose_engine_handle(handle);
    }
}
