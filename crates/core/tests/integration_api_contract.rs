//! Integration tests verifying the public API contract of `napaxi_core::api`.
//!
//! These tests exercise the adapter-facing API boundary as SDK integrators would
//! use it, confirming that the typed API layer, error wire format, and engine
//! lifecycle behave correctly end-to-end without relying on internal details.

mod error_wire_format {
    /// Verify that `CoreError::to_wire_json()` always produces the documented
    /// wire envelope shape `{ "error": { "code": "...", "message": "..." } }`.
    #[test]
    fn core_error_to_wire_json_produces_envelope() {
        let error = napaxi_core::error::CoreError::InvalidInput("test detail".to_string());
        let json_str = error.to_wire_json();
        let value: serde_json::Value =
            serde_json::from_str(&json_str).expect("wire JSON must be valid");

        let envelope = value.get("error").expect("must have 'error' key");
        let code = envelope.get("code").and_then(|v| v.as_str());
        let message = envelope.get("message").and_then(|v| v.as_str());

        assert!(code.is_some(), "wire envelope must contain error.code");
        assert!(
            message.is_some(),
            "wire envelope must contain error.message"
        );
    }

    /// Spot-check that well-known domain errors produce their documented stable
    /// error codes.  The full mapping is in `docs/api-contract.md`; this test
    /// covers a representative sample to catch accidental code renames.
    #[test]
    fn core_error_codes_are_stable() {
        let cases: Vec<(napaxi_core::error::CoreError, &str)> = vec![
            (
                napaxi_core::error::CoreError::InvalidInput("x".to_string()),
                "invalid_input",
            ),
            (
                napaxi_core::error::CoreError::InvalidHandle(0),
                "invalid_handle",
            ),
            (napaxi_core::error::CoreError::Cancelled, "cancelled"),
        ];

        for (error, expected_code) in cases {
            let json_str = error.to_wire_json();
            let value: serde_json::Value =
                serde_json::from_str(&json_str).expect("wire JSON must be valid");
            let actual_code = value["error"]["code"].as_str().unwrap_or("<missing>");
            assert_eq!(
                actual_code, expected_code,
                "CoreError::{:?} should produce code {expected_code}, got {actual_code}",
                error
            );
        }
    }

    /// Verify that the fallback envelope is produced even when the error
    /// message contains characters that might break JSON serialisation.
    #[test]
    fn core_error_wire_json_handles_special_characters() {
        let error = napaxi_core::error::CoreError::InvalidInput(
            "Contains \"quotes\" and \n newlines \t tabs".to_string(),
        );
        let json_str = error.to_wire_json();
        let _: serde_json::Value =
            serde_json::from_str(&json_str).expect("wire JSON with special chars must be valid");
    }
}

mod engine_lifecycle {
    /// Build a minimal valid LLM config JSON for testing.
    fn test_config_json(_workspace_path: &str) -> String {
        serde_json::json!({
            "provider": "openai",
            "api_key": "test-key",
            "model": "test-model",
            "system_prompt": "Test prompt.",
            "max_tokens": 4096
        })
        .to_string()
    }

    /// Build a minimal valid platform context JSON for testing.
    fn test_platform_context_json(files_dir: &str) -> String {
        serde_json::json!({
            "files_dir": files_dir
        })
        .to_string()
    }

    /// Verify that creating an engine with a valid config and then disposing
    /// it does not panic or produce an error.
    #[test]
    fn create_and_dispose_engine_succeeds() {
        let dir = tempfile::tempdir().expect("temp dir");
        let workspace = dir.path().to_string_lossy().to_string();
        let config = test_config_json(&workspace);
        let context = test_platform_context_json(&workspace);

        let handle = napaxi_core::api::engine::create_engine_handle(&config, &context)
            .expect("create_engine_handle should succeed with valid config");
        assert!(
            handle != 0,
            "create_engine_handle returned zero (invalid handle)"
        );

        // Dispose should not panic.
        napaxi_core::api::engine::dispose_engine_handle(handle);
    }

    /// Creating an engine with invalid config should return an error.
    #[test]
    fn create_engine_with_invalid_config_returns_error() {
        let dir = tempfile::tempdir().expect("temp dir");
        let workspace = dir.path().to_string_lossy().to_string();
        let context = test_platform_context_json(&workspace);

        let result = napaxi_core::api::engine::create_engine_handle("not-json", &context);
        assert!(
            result.is_err(),
            "create_engine_handle should fail with invalid JSON config"
        );
    }

    /// Operations on an invalid handle should return a well-formed error.
    #[test]
    fn get_config_on_invalid_handle_returns_error() {
        let result = napaxi_core::api::engine::get_config_handle_typed(0);
        assert!(result.is_err(), "get_config on handle 0 should be Err");
        let err = result.unwrap_err();
        assert_eq!(err.code(), "invalid_handle");
    }
}
