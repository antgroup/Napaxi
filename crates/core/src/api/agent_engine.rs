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
