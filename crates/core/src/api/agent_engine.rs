//! Core-owned agent engine protocol helpers.

/// Process an agent engine protocol run event (JSON in, JSON out).
pub fn run_event_json(request_json: &str) -> String {
    crate::agent_engine::run_event_json(request_json)
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
    fn run_event_json_returns_error_for_malformed_json() {
        let result = run_event_json("not json");
        assert!(result.contains("error"), "malformed json: {result}");
    }
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
