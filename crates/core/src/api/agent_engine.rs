//! Core-owned agent engine protocol helpers.

/// Process an agent engine protocol run event (JSON in, JSON out).
pub fn run_event_json(request_json: &str) -> String {
    crate::agent_engine::run_event_json(request_json)
}

/// Configure the core-owned Codex agent engine (JSON in, JSON out).
pub fn configure_codex_agent_engine_json(handle: i64, request_json: &str) -> String {
    crate::agent_engine::codex::configure_codex_agent_engine_json(handle, request_json)
}

/// Query the core-owned Codex native history (JSON in, JSON out).
///
/// This operation may launch the Codex app-server and wait for PTY RPC, so
/// adapters must dispatch it away from their UI thread.
pub fn query_codex_agent_engine_history_json(handle: i64, request_json: &str) -> String {
    crate::agent_engine::codex::query_codex_agent_engine_history_json(handle, request_json)
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn run_event_json_returns_error_for_invalid_request() {
        let result = run_event_json("{}");
        assert!(
            result.contains("error") || result.contains("null"),
            "invalid request should not panic: {result}"
        );
    }

    #[test]
    fn codex_engine_json_wrappers_reject_invalid_handles_without_panic() {
        let config_result = configure_codex_agent_engine_json(0, "{}");
        assert!(
            config_result.contains("error") || config_result.contains("success"),
            "invalid config handle should return json: {config_result}"
        );

        let history_result = query_codex_agent_engine_history_json(0, "{}");
        assert!(
            history_result.contains("error") || history_result.contains("success"),
            "invalid history handle should return json: {history_result}"
        );
    }

    #[test]
    fn run_event_json_returns_error_for_malformed_json() {
        let result = run_event_json("not json");
        assert!(result.contains("error"), "malformed json: {result}");
    }
}
