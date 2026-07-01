//! Tool registry integration tests covering rate limiter, redaction, schema
//! validation, dispatcher routing, and host execution flows.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use super::pending::resolve_tool_execution;
use super::prepare::prepare_tool_arguments;
use super::rate_limit::ToolRateLimiter;
use super::redact::{
    MAX_TOOL_OUTPUT_SIZE, REDACTED, redact_tool_arguments_json, sanitize_tool_output,
};
use super::registry::ToolRegistry;
use super::types::{ToolDescriptor, ToolEffect, ToolExecutionContext, ToolRateLimit};

#[tokio::test]
async fn registers_and_lists_custom_tools() {
    let registry = ToolRegistry::new();
    let count = registry
        .replace_custom_tools(
            r#"[{"name":"image_analyze","description":"Analyze an image","parameters":{"type":"object"}}]"#,
        )
        .await
        .unwrap();
    assert_eq!(count, 1);
    assert_eq!(registry.list_tools().await[0].name, "image_analyze");
}

#[tokio::test]
async fn dispatches_and_resolves_custom_tool() {
    let registry = ToolRegistry::new();
    registry.set_dispatcher(Arc::new(|request_id, tool_name, params_json, context| {
        assert_eq!(tool_name, "lookup");
        assert_eq!(params_json, r#"{"q":"napaxi"}"#);
        assert!(context.is_none());
        resolve_tool_execution(request_id, r#"{"ok":true}"#.to_string(), false);
    }));
    registry
        .replace_custom_tools(
            r#"[{"name":"lookup","description":"Lookup data","parameters":{"type":"object"}}]"#,
        )
        .await
        .unwrap();

    let result = registry
        .execute_custom_tool("lookup", serde_json::json!({"q":"napaxi"}))
        .await
        .unwrap();
    assert_eq!(result, r#"{"ok":true}"#);
}

#[tokio::test]
async fn dispatches_custom_tool_with_execution_context() {
    let registry = ToolRegistry::new();
    registry.set_dispatcher(Arc::new(|request_id, tool_name, params_json, context| {
        assert_eq!(tool_name, "take_photo");
        assert_eq!(params_json, r#"{}"#);
        let context = context.expect("execution context");
        assert_eq!(context.files_dir, "/app/files");
        assert_eq!(context.workspace_files_dir, "/app/files/scoped");
        assert_eq!(context.agent_id, "napaxi");
        resolve_tool_execution(request_id, "done".to_string(), false);
    }));
    registry
        .replace_custom_tools(
            r#"[{"name":"take_photo","description":"Take a photo","parameters":{"type":"object"}}]"#,
        )
        .await
        .unwrap();

    let context = ToolExecutionContext {
        files_dir: "/app/files".to_string(),
        workspace_files_dir: "/app/files/scoped".to_string(),
        agent_id: "napaxi".to_string(),
        session_key_json: None,
    };
    let result = registry
        .execute_custom_tool_with_context("take_photo", serde_json::json!({}), Some(&context))
        .await
        .unwrap();
    assert_eq!(result, "done");
}

#[tokio::test]
async fn pending_responses_are_scoped_by_registry() {
    let registry_a = Arc::new(ToolRegistry::new());
    let registry_b = Arc::new(ToolRegistry::new());
    let request_ids = Arc::new(Mutex::new(HashMap::<String, u64>::new()));

    registry_a.set_dispatcher({
        let request_ids = Arc::clone(&request_ids);
        Arc::new(move |request_id, _, _, _| {
            request_ids
                .lock()
                .unwrap()
                .insert("a".to_string(), request_id);
        })
    });
    registry_b.set_dispatcher({
        let request_ids = Arc::clone(&request_ids);
        Arc::new(move |request_id, _, _, _| {
            request_ids
                .lock()
                .unwrap()
                .insert("b".to_string(), request_id);
        })
    });
    registry_a
        .replace_custom_tools(
            r#"[{"name":"lookup","description":"Lookup data","parameters":{"type":"object"}}]"#,
        )
        .await
        .unwrap();
    registry_b
        .replace_custom_tools(
            r#"[{"name":"lookup","description":"Lookup data","parameters":{"type":"object"}}]"#,
        )
        .await
        .unwrap();

    let task_a = {
        let registry = Arc::clone(&registry_a);
        tokio::spawn(async move {
            registry
                .execute_custom_tool("lookup", serde_json::json!({}))
                .await
        })
    };
    let task_b = {
        let registry = Arc::clone(&registry_b);
        tokio::spawn(async move {
            registry
                .execute_custom_tool("lookup", serde_json::json!({}))
                .await
        })
    };

    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if request_ids.lock().unwrap().len() == 2 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("both tool requests dispatched");

    assert_eq!(registry_a.pending_request_count(), 1);
    assert_eq!(registry_b.pending_request_count(), 1);
    let request_id_a = request_ids.lock().unwrap()["a"];
    let request_id_b = request_ids.lock().unwrap()["b"];

    assert!(resolve_tool_execution(
        request_id_a,
        "done-a".to_string(),
        false
    ));
    assert_eq!(task_a.await.unwrap().unwrap(), "done-a");
    assert_eq!(registry_a.pending_request_count(), 0);
    assert_eq!(registry_b.pending_request_count(), 1);

    assert!(resolve_tool_execution(
        request_id_b,
        "done-b".to_string(),
        false
    ));
    assert_eq!(task_b.await.unwrap().unwrap(), "done-b");
    assert_eq!(registry_b.pending_request_count(), 0);
}

#[tokio::test]
async fn dispatches_custom_tool_errors_as_errors() {
    let registry = ToolRegistry::new();
    registry.set_dispatcher(Arc::new(|request_id, _, _, _| {
        resolve_tool_execution(request_id, "host failed".to_string(), true);
    }));
    registry
        .replace_custom_tools(
            r#"[{"name":"lookup","description":"Lookup data","parameters":{"type":"object"}}]"#,
        )
        .await
        .unwrap();

    let error = registry
        .execute_custom_tool("lookup", serde_json::json!({}))
        .await
        .unwrap_err();
    assert_eq!(error, "host failed");
}

#[test]
fn prepares_tool_arguments_with_required_type_enum_and_extra_checks() {
    let descriptor = ToolDescriptor {
        name: "search".to_string(),
        description: "Search".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer"},
                "mode": {"type": "string", "enum": ["fast", "deep"]},
                "dry_run": {"type": "boolean"}
            },
            "required": ["query", "mode"],
            "additionalProperties": false
        }),
        effect: ToolEffect::Read,
    };

    let prepared = prepare_tool_arguments(
        &descriptor,
        serde_json::json!({
            "query": "napaxi",
            "limit": "3",
            "mode": "fast",
            "dry_run": "true"
        }),
    )
    .unwrap();

    assert_eq!(prepared["limit"], 3);
    assert_eq!(prepared["dry_run"], true);
    assert!(prepare_tool_arguments(&descriptor, serde_json::json!({"query": "napaxi"})).is_err());
    assert!(
        prepare_tool_arguments(
            &descriptor,
            serde_json::json!({"query": "napaxi", "mode": "slow"})
        )
        .is_err()
    );
    assert!(
        prepare_tool_arguments(
            &descriptor,
            serde_json::json!({"query": "napaxi", "mode": "fast", "extra": true})
        )
        .is_err()
    );
}

#[test]
fn prepares_shell_arguments_with_cmd_alias() {
    let descriptor = ToolDescriptor {
        name: "shell".to_string(),
        description: "Run shell command".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "command": {"type": "string"},
                "timeout": {"type": "integer"}
            },
            "required": ["command"],
            "additionalProperties": false
        }),
        effect: ToolEffect::Execute,
    };

    let prepared = prepare_tool_arguments(
        &descriptor,
        serde_json::json!({
            "cmd": "ls -la /workspace",
            "timeout": "3"
        }),
    )
    .unwrap();

    assert_eq!(prepared["command"], "ls -la /workspace");
    assert_eq!(prepared["timeout"], 3);
    assert!(prepared.get("cmd").is_none());
}

#[tokio::test]
async fn dispatches_custom_tool_with_schema_prepared_params() {
    let registry = ToolRegistry::new();
    registry.set_dispatcher(Arc::new(|request_id, tool_name, params_json, _| {
        assert_eq!(tool_name, "lookup");
        assert_eq!(params_json, r#"{"limit":2,"q":"napaxi"}"#);
        resolve_tool_execution(request_id, "done".to_string(), false);
    }));
    registry
        .replace_custom_tools(
            r#"[{
                "name":"lookup",
                "description":"Lookup data",
                "parameters":{
                    "type":"object",
                    "properties":{
                        "q":{"type":"string"},
                        "limit":{"type":"integer"}
                    },
                    "required":["q"],
                    "additionalProperties":false
                }
            }]"#,
        )
        .await
        .unwrap();

    let result = registry
        .execute_custom_tool("lookup", serde_json::json!({"q":"napaxi","limit":"2"}))
        .await
        .unwrap();
    assert_eq!(result, "done");
    assert!(
        registry
            .execute_custom_tool("lookup", serde_json::json!({"limit":"2"}))
            .await
            .is_err()
    );
}

#[test]
fn redacts_sensitive_json_arguments_and_outputs() {
    let args = redact_tool_arguments_json(
        r#"{"query":"ok","apiKey":"secret","nested":{"Authorization":"Bearer abc"}}"#,
    );
    assert!(args.contains(r#""query":"ok""#));
    assert!(!args.contains("secret"));
    assert!(!args.contains("Bearer abc"));
    assert!(args.contains(REDACTED));

    let output = sanitize_tool_output(
        r#"{"headers":{"x-api-key":"k-123","content-type":"text/plain"},"token":"abc"}"#,
    );
    assert!(output.contains("content-type"));
    assert!(!output.contains("k-123"));
    assert!(!output.contains("\"abc\""));
    assert!(output.contains(REDACTED));
}

#[test]
fn redacts_plain_text_secrets_and_truncates_utf8_safely() {
    let output = sanitize_tool_output("Authorization: Bearer abcdef\npassword=hunter2\nok");
    assert!(output.contains("Authorization: Bearer [REDACTED]"));
    assert!(output.contains("password= [REDACTED]"));
    assert!(!output.contains("hunter2"));
    assert!(!output.contains("abcdef"));

    let long = "猫".repeat(MAX_TOOL_OUTPUT_SIZE);
    let truncated = sanitize_tool_output(&long);
    assert!(truncated.contains("[truncated"));
    assert!(truncated.is_char_boundary(truncated.len()));
}

#[test]
fn rate_limiter_allows_windowed_calls_and_blocks_excess() {
    let limiter = ToolRateLimiter::default();
    let limit = ToolRateLimit {
        max_calls: 2,
        window: Duration::from_secs(60),
    };
    let start = Instant::now();

    assert!(limiter.check_at("shell", limit, start).is_ok());
    assert!(
        limiter
            .check_at("shell", limit, start + Duration::from_secs(1))
            .is_ok()
    );
    let err = limiter
        .check_at("shell", limit, start + Duration::from_secs(2))
        .unwrap_err();
    assert!(err.contains("rate limit exceeded"));

    assert!(
        limiter
            .check_at("shell", limit, start + Duration::from_secs(61))
            .is_ok()
    );
}
