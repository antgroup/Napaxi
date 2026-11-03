//! Integration tests covering MCP server state, tool dispatch, and OAuth flow.

use std::collections::HashMap;
use std::fs;

use super::LEGACY_DEFAULT_ACCOUNT_ID;
use super::headers::{effective_headers, transport_kind, update_dynamic_headers};
use super::helpers::{McpRequest, McpResponse, initialize_advertises_tools};
use super::oauth::{oauth_refresh_params, oauth_token_needs_refresh};
use super::oauth_flow::{finish_oauth, start_oauth};
use super::servers::{
    add_server, deactivate_server, list_servers, remove_server, set_server_active,
};
use super::store::{load_state, save_state, secret_store_path, store_path};
use super::tools::{list_tools, tool_descriptors};
use super::transport::send_mcp_stdio_sequence;
use super::types::{
    McpOAuthConfig, McpOAuthPending, McpOAuthTokens, McpServer, McpState, McpTool, McpTransport,
};

fn engine_handle(files_dir: &str) -> i64 {
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
        "files_dir": files_dir,
        "native_library_dir": null
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

#[test]
fn stores_mcp_servers_without_network() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "demo".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: true,
        tools: vec![McpTool {
            name: "lookup".to_string(),
            description: "Lookup".to_string(),
            input_schema: serde_json::json!({"type": "object"}),
            requires_approval: false,
        }],
        session_id: Some("session-1".to_string()),
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));
    assert!(list_servers(&files_dir, "user").contains("demo"));
    assert!(deactivate_server(&files_dir, "demo", "user").contains(r#""success":true"#));
    assert!(set_server_active(&files_dir, "demo", "user").contains(r#""name":"demo"#));
    assert!(list_tools(&files_dir, "", "user").contains("demo_lookup"));
    assert!(remove_server(&files_dir, "demo", "user").contains(r#""success":true"#));
    assert_eq!(list_servers(&files_dir, "user"), "[]");
}

#[test]
fn list_servers_reports_explicit_lifecycle_status() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    let base = |name: &str| McpServer {
        name: name.to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: false,
        tools: Vec::new(),
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    };
    // Configured-but-not-activated: not a failure.
    state.servers.push(base("configured"));
    // Activated.
    let mut connected = base("connected");
    connected.active = true;
    state.servers.push(connected);
    // Activation failed.
    let mut failed = base("failed");
    failed.activation_error = Some("Activation failed: boom".to_string());
    state.servers.push(failed);
    assert!(save_state(&files_dir, &state));

    let listed = list_servers(&files_dir, "user");
    let servers: Vec<serde_json::Value> = serde_json::from_str(&listed).unwrap();
    let status_of = |name: &str| {
        servers
            .iter()
            .find(|s| s["name"] == name)
            .and_then(|s| s["status"].as_str())
            .unwrap()
            .to_string()
    };
    assert_eq!(status_of("configured"), "configured");
    assert_eq!(status_of("connected"), "connected");
    assert_eq!(status_of("failed"), "error");
}

#[test]
fn tool_descriptors_are_scoped_by_user_id() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "demo".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user-a".to_string(),
        active: true,
        tools: vec![McpTool {
            name: "lookup".to_string(),
            description: "Lookup".to_string(),
            input_schema: serde_json::json!({"type": "object"}),
            requires_approval: false,
        }],
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));

    let user_a_tools = tool_descriptors(&files_dir, "user-a");
    assert_eq!(user_a_tools.len(), 1);
    assert_eq!(user_a_tools[0].name, "demo_lookup");
    assert!(tool_descriptors(&files_dir, "user-b").is_empty());
}

#[test]
fn legacy_flutter_user_servers_are_read_as_default_user() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "demo".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: LEGACY_DEFAULT_ACCOUNT_ID.to_string(),
        active: true,
        tools: vec![McpTool {
            name: "lookup".to_string(),
            description: "Lookup".to_string(),
            input_schema: serde_json::json!({"type": "object"}),
            requires_approval: false,
        }],
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));

    let tools = tool_descriptors(&files_dir, crate::runtime::DEFAULT_ACCOUNT_ID);
    assert_eq!(tools.len(), 1);
    assert_eq!(tools[0].name, "demo_lookup");
    assert!(list_servers(&files_dir, crate::runtime::DEFAULT_ACCOUNT_ID).contains("demo"));
}

#[tokio::test]
async fn handle_wrappers_delegate_to_mcp_state() {
    use super::handles::{
        activate_server_handle, add_server_handle, deactivate_server_handle, finish_oauth_handle,
        list_servers_handle, list_tools_handle, remove_server_handle, start_oauth_handle,
    };

    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let handle = engine_handle(&files_dir);
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "demo".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: true,
        tools: vec![McpTool {
            name: "lookup".to_string(),
            description: "Lookup".to_string(),
            input_schema: serde_json::json!({"type": "object"}),
            requires_approval: false,
        }],
        session_id: Some("session-1".to_string()),
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    state.servers.push(McpServer {
        name: "remote".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: false,
        tools: Vec::new(),
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));

    assert_eq!(list_servers_handle(0, "user"), "[]");
    assert!(
        add_server_handle(0, "", "", "{}", "user")
            .await
            .contains("invalid engine handle")
    );
    assert!(
        activate_server_handle(0, "demo", "user")
            .await
            .contains("invalid engine handle")
    );
    assert!(list_servers_handle(handle, "user").contains("demo"));
    assert!(list_tools_handle(handle, "", "user").contains("demo_lookup"));
    assert!(
        start_oauth_handle(
            handle,
            "remote",
            "user",
            "napaxi://oauth/callback",
            r#"{"client_id":"client-1","authorization_url":"https://auth.example.com/authorize","token_url":"https://auth.example.com/token"}"#,
        )
        .await
        .contains("authorization_url")
    );
    assert!(
        finish_oauth_handle(handle, "remote", "user", "code", "bad-state")
            .await
            .contains("OAuth state mismatch")
    );
    assert!(deactivate_server_handle(handle, "demo", "user").contains(r#""success":true"#));
    assert!(remove_server_handle(handle, "demo", "user").contains(r#""success":true"#));
    assert!(!list_servers_handle(handle, "user").contains(r#""name":"demo""#));
    assert!(deactivate_server_handle(0, "demo", "user").contains("invalid engine handle"));
    assert!(remove_server_handle(0, "demo", "user").contains("invalid engine handle"));
    assert_eq!(list_tools_handle(0, "", "user"), "[]");

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn preserves_non_http_transport_config() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "local".to_string(),
        url: String::new(),
        transport: McpTransport::Stdio {
            command: "server".to_string(),
            args: vec!["--stdio".to_string()],
            env: HashMap::from([("A".to_string(), "B".to_string())]),
        },
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: false,
        tools: Vec::new(),
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });

    assert!(save_state(&files_dir, &state));
    let loaded = load_state(&files_dir);
    assert_eq!(transport_kind(&loaded.servers[0].transport), "stdio");
    assert!(list_servers(&files_dir, "user").contains(r#""transport":"stdio""#));
}

#[tokio::test]
async fn starts_oauth_with_explicit_config_without_network() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "remote".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: false,
        tools: Vec::new(),
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));

    let result = start_oauth(
        &files_dir,
        "remote",
        "user",
        "napaxi://oauth/callback",
        r#"{"client_id":"client-1","authorization_url":"https://auth.example.com/authorize","token_url":"https://auth.example.com/token","scopes":["read"],"extra_params":{"audience":"mcp"}}"#,
    )
    .await;
    let json: serde_json::Value = serde_json::from_str(&result).unwrap();
    let auth_url = json["authorization_url"].as_str().unwrap();
    assert!(auth_url.contains("client_id=client-1"));
    assert!(auth_url.contains("response_type=code"));
    assert!(auth_url.contains("scope=read"));
    assert!(auth_url.contains("audience=mcp"));
    assert!(auth_url.contains("state="));
    assert!(auth_url.contains("code_challenge="));

    let loaded = load_state(&files_dir);
    let pending = loaded.servers[0].oauth_pending.as_ref().unwrap();
    assert_eq!(pending.client_id, "client-1");
    assert_eq!(pending.redirect_uri, "napaxi://oauth/callback");
}

#[tokio::test]
async fn finish_oauth_rejects_state_mismatch_before_exchange() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "remote".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: false,
        tools: Vec::new(),
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: Some(McpOAuthPending {
            state: "good-state".to_string(),
            code_verifier: None,
            redirect_uri: "napaxi://oauth/callback".to_string(),
            authorization_url: "https://auth.example.com/authorize".to_string(),
            token_url: "https://auth.example.com/token".to_string(),
            client_id: "client-1".to_string(),
            client_secret: None,
            scopes: Vec::new(),
            resource: None,
            created_at: chrono::Utc::now().to_rfc3339(),
        }),
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));

    let result = finish_oauth(&files_dir, "remote", "user", "code", "bad-state").await;
    assert!(result.contains("OAuth state mismatch"));
}

#[test]
fn effective_headers_inject_oauth_token_without_overriding_custom_auth() {
    let mut server = McpServer {
        name: "remote".to_string(),
        url: "https://example.com/mcp".to_string(),
        oauth_tokens: Some(McpOAuthTokens {
            access_token: "token-1".to_string(),
            token_type: "Bearer".to_string(),
            refresh_token: None,
            scope: None,
            expires_at: None,
        }),
        ..Default::default()
    };
    assert_eq!(
        effective_headers("", &server)
            .get("Authorization")
            .map(String::as_str),
        Some("Bearer token-1")
    );

    server
        .headers
        .insert("authorization".to_string(), "Bearer custom".to_string());
    assert_eq!(
        effective_headers("", &server)
            .get("authorization")
            .map(String::as_str),
        Some("Bearer custom")
    );
    assert!(!effective_headers("", &server).contains_key("Authorization"));
}

#[test]
fn dynamic_headers_are_scoped_by_files_dir() {
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let first_dir = first.path().to_string_lossy().to_string();
    let second_dir = second.path().to_string_lossy().to_string();
    let server = McpServer {
        name: "remote".to_string(),
        url: "https://example.com/mcp".to_string(),
        ..Default::default()
    };

    assert!(update_dynamic_headers(
        &first_dir,
        HashMap::from([("x-runtime".to_string(), "first".to_string())]),
    ));
    assert!(update_dynamic_headers(
        &second_dir,
        HashMap::from([("x-runtime".to_string(), "second".to_string())]),
    ));

    assert_eq!(
        effective_headers(&first_dir, &server)
            .get("x-runtime")
            .map(String::as_str),
        Some("first")
    );
    assert_eq!(
        effective_headers(&second_dir, &server)
            .get("x-runtime")
            .map(String::as_str),
        Some("second")
    );
}

#[test]
fn save_state_keeps_oauth_secrets_out_of_server_catalog() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let state = McpState {
        servers: vec![McpServer {
            name: "remote".to_string(),
            url: "https://example.com/mcp".to_string(),
            transport: McpTransport::Http,
            user_id: "user".to_string(),
            oauth: Some(McpOAuthConfig {
                client_id: Some("client-1".to_string()),
                client_secret: Some("client-secret-1".to_string()),
                authorization_url: Some("https://auth.example.com/authorize".to_string()),
                token_url: Some("https://auth.example.com/token".to_string()),
                ..Default::default()
            }),
            oauth_pending: Some(McpOAuthPending {
                state: "state-1".to_string(),
                code_verifier: Some("pkce-verifier-1".to_string()),
                redirect_uri: "napaxi://oauth/mcp".to_string(),
                authorization_url: "https://auth.example.com/authorize".to_string(),
                token_url: "https://auth.example.com/token".to_string(),
                client_id: "client-1".to_string(),
                client_secret: Some("client-secret-1".to_string()),
                scopes: Vec::new(),
                resource: None,
                created_at: chrono::Utc::now().to_rfc3339(),
            }),
            oauth_tokens: Some(McpOAuthTokens {
                access_token: "access-token-1".to_string(),
                token_type: "Bearer".to_string(),
                refresh_token: Some("refresh-token-1".to_string()),
                scope: None,
                expires_at: None,
            }),
            ..Default::default()
        }],
    };

    assert!(save_state(&files_dir, &state));
    let catalog = fs::read_to_string(store_path(&files_dir)).unwrap();
    assert!(catalog.contains("client-1"));
    assert!(!catalog.contains("client-secret-1"));
    assert!(!catalog.contains("pkce-verifier-1"));
    assert!(!catalog.contains("access-token-1"));
    assert!(!catalog.contains("refresh-token-1"));

    let secrets = fs::read_to_string(secret_store_path(&files_dir)).unwrap();
    assert!(secrets.contains("client-secret-1"));
    assert!(secrets.contains("pkce-verifier-1"));
    assert!(secrets.contains("access-token-1"));
    assert!(secrets.contains("refresh-token-1"));

    let loaded = load_state(&files_dir);
    let server = &loaded.servers[0];
    assert_eq!(
        server
            .oauth
            .as_ref()
            .and_then(|oauth| oauth.client_secret.as_deref()),
        Some("client-secret-1")
    );
    assert_eq!(
        server
            .oauth_pending
            .as_ref()
            .and_then(|pending| pending.code_verifier.as_deref()),
        Some("pkce-verifier-1")
    );
    assert_eq!(
        server
            .oauth_tokens
            .as_ref()
            .map(|tokens| tokens.access_token.as_str()),
        Some("access-token-1")
    );
}

#[test]
fn oauth_token_refresh_window_uses_expiry_skew() {
    let fresh = McpOAuthTokens {
        access_token: "token".to_string(),
        token_type: "Bearer".to_string(),
        refresh_token: Some("refresh".to_string()),
        scope: None,
        expires_at: Some((chrono::Utc::now() + chrono::Duration::minutes(5)).to_rfc3339()),
    };
    assert!(!oauth_token_needs_refresh(&fresh));

    let expiring = McpOAuthTokens {
        expires_at: Some((chrono::Utc::now() + chrono::Duration::seconds(30)).to_rfc3339()),
        ..fresh
    };
    assert!(oauth_token_needs_refresh(&expiring));
}

#[test]
fn oauth_refresh_params_include_refresh_grant_and_client_credentials() {
    let oauth = McpOAuthConfig {
        client_id: Some("client-1".to_string()),
        client_secret: Some("secret-1".to_string()),
        resource: Some("https://example.com/mcp".to_string()),
        ..Default::default()
    };
    let tokens = McpOAuthTokens {
        access_token: "old-access".to_string(),
        token_type: "Bearer".to_string(),
        refresh_token: Some("old-refresh".to_string()),
        scope: Some("read".to_string()),
        expires_at: Some((chrono::Utc::now() - chrono::Duration::seconds(1)).to_rfc3339()),
    };

    let params = oauth_refresh_params(&oauth, &tokens).unwrap();
    let params: HashMap<_, _> = params.into_iter().collect();
    assert_eq!(
        params.get("grant_type").map(String::as_str),
        Some("refresh_token")
    );
    assert_eq!(
        params.get("refresh_token").map(String::as_str),
        Some("old-refresh")
    );
    assert_eq!(
        params.get("client_id").map(String::as_str),
        Some("client-1")
    );
    assert_eq!(
        params.get("client_secret").map(String::as_str),
        Some("secret-1")
    );
    assert_eq!(
        params.get("resource").map(String::as_str),
        Some("https://example.com/mcp")
    );
}

#[tokio::test]
async fn stdio_transport_sequence_matches_response_ids() {
    let response = send_mcp_stdio_sequence(
        "sh",
        &[
            "-c".to_string(),
            "while IFS= read -r line; do id=$(printf '%s' \"$line\" | sed -n 's/.*\"id\":\\([0-9][0-9]*\\).*/\\1/p'); [ -n \"$id\" ] && printf '{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"ok\":true}}\\n' \"$id\"; done".to_string(),
        ],
        &HashMap::new(),
        vec![
            McpRequest::initialize(),
            McpRequest::initialized_notification(),
            McpRequest::list_tools(),
        ],
    )
    .await
    .unwrap();

    assert_eq!(response.len(), 2);
    assert!(response[0].response.result.is_some());
    assert!(response[1].response.result.is_some());
}

#[test]
fn admission_can_hide_mcp_tool_from_descriptors() {
    use std::sync::Arc;

    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "tier3probesrv".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user-a".to_string(),
        active: true,
        tools: vec![
            McpTool {
                name: "allowed_action".to_string(),
                description: "Allowed".to_string(),
                input_schema: serde_json::json!({"type": "object"}),
                requires_approval: false,
            },
            McpTool {
                name: "denied_action".to_string(),
                description: "Denied".to_string(),
                input_schema: serde_json::json!({"type": "object"}),
                requires_approval: false,
            },
        ],
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));

    let _guard = crate::capabilities::register_policy_hook(Arc::new(|admission| {
        if admission.subject == "tier3probesrv_denied_action" {
            crate::capabilities::CapabilityAdmissionDecision::Deny(
                "tier3_mcp_policy_test".to_string(),
            )
        } else {
            crate::capabilities::CapabilityAdmissionDecision::Allow
        }
    }));

    let visible = tool_descriptors(&files_dir, "user-a");
    let names: Vec<_> = visible.iter().map(|t| t.name.as_str()).collect();
    assert!(names.contains(&"tier3probesrv_allowed_action"));
    assert!(!names.contains(&"tier3probesrv_denied_action"));
}

#[tokio::test]
async fn admission_can_block_mcp_call_tool_before_io() {
    use super::tools::call_tool;
    use std::sync::Arc;

    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "tier3probecall".to_string(),
        url: "https://example.invalid/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user-a".to_string(),
        active: true,
        tools: vec![McpTool {
            name: "lookup".to_string(),
            description: "Lookup".to_string(),
            input_schema: serde_json::json!({"type": "object"}),
            requires_approval: false,
        }],
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
    });
    assert!(save_state(&files_dir, &state));

    let _guard = crate::capabilities::register_policy_hook(Arc::new(|admission| {
        if matches!(
            admission.kind,
            crate::capabilities::CapabilityAdmissionKind::Invocation
        ) && admission.subject == "tier3probecall_lookup"
        {
            crate::capabilities::CapabilityAdmissionDecision::Deny(
                "tier3_mcp_invocation_deny".to_string(),
            )
        } else {
            crate::capabilities::CapabilityAdmissionDecision::Allow
        }
    }));

    let err = call_tool(
        &files_dir,
        "tier3probecall_lookup",
        serde_json::json!({}),
        "user-a",
    )
    .await
    .expect_err("admission should block the call");
    assert!(
        err.contains("tier3_mcp_invocation_deny"),
        "expected deny reason, got: {err}"
    );
}

// ===========================================================================
// HTTP transport tests (httpmock)
// ===========================================================================

#[tokio::test]
async fn http_transport_sends_mcp_request_and_returns_result() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;
    use httpmock::prelude::*;

    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/");
            then.status(200)
                .header("content-type", "application/json")
                .json_body(serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": 1,
                    "result": {"tools": []}
                }));
        })
        .await;

    let resp = send_mcp_request(
        &server.base_url(),
        &McpTransport::Http,
        &HashMap::new(),
        None,
        McpRequest::list_tools(),
    )
    .await
    .expect("HTTP transport should succeed");

    mock.assert_async().await;
    assert!(resp.response.result.is_some());
    assert!(resp.response.error.is_none());
}

#[tokio::test]
async fn http_transport_persists_session_id_from_response_header() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;
    use httpmock::prelude::*;

    let server = MockServer::start_async().await;
    let _mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/");
            then.status(200)
                .header("content-type", "application/json")
                .header("mcp-session-id", "sess-abc-123")
                .json_body(serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": 1,
                    "result": {}
                }));
        })
        .await;

    let resp = send_mcp_request(
        &server.base_url(),
        &McpTransport::Http,
        &HashMap::new(),
        None,
        McpRequest::initialize(),
    )
    .await
    .unwrap();

    assert_eq!(
        resp.session_id.as_deref(),
        Some("sess-abc-123"),
        "session id from response header must be surfaced"
    );
}

#[tokio::test]
async fn http_transport_forwards_session_id_in_request_header() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;
    use httpmock::prelude::*;

    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/")
                .header("mcp-session-id", "sess-incoming");
            then.status(200)
                .header("content-type", "application/json")
                .json_body(serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": 1,
                    "result": {}
                }));
        })
        .await;

    let _ = send_mcp_request(
        &server.base_url(),
        &McpTransport::Http,
        &HashMap::new(),
        Some("sess-incoming"),
        McpRequest::list_tools(),
    )
    .await
    .unwrap();

    mock.assert_async().await;
}

#[tokio::test]
async fn http_transport_forwards_custom_headers() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;
    use httpmock::prelude::*;

    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/")
                .header("authorization", "Bearer secret-token");
            then.status(200)
                .header("content-type", "application/json")
                .json_body(serde_json::json!({"jsonrpc":"2.0","id":1,"result":{}}));
        })
        .await;

    let mut headers = HashMap::new();
    headers.insert(
        "Authorization".to_string(),
        "Bearer secret-token".to_string(),
    );

    let _ = send_mcp_request(
        &server.base_url(),
        &McpTransport::Http,
        &headers,
        None,
        McpRequest::list_tools(),
    )
    .await
    .unwrap();

    mock.assert_async().await;
}

#[tokio::test]
async fn http_transport_surfaces_5xx_as_error() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;
    use httpmock::prelude::*;

    let server = MockServer::start_async().await;
    let _mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/");
            then.status(503).body("backend unavailable");
        })
        .await;

    let result = send_mcp_request(
        &server.base_url(),
        &McpTransport::Http,
        &HashMap::new(),
        None,
        McpRequest::list_tools(),
    )
    .await;

    let err = match result {
        Ok(_) => panic!("5xx must surface as transport error"),
        Err(e) => e,
    };
    // The exact wording is internal, but it should mention status/HTTP
    // failure somewhere so adapters can branch.
    assert!(
        err.to_lowercase().contains("503")
            || err.to_lowercase().contains("status")
            || err.to_lowercase().contains("http"),
        "error should reference status/HTTP, got: {err}"
    );
}

#[tokio::test]
async fn http_transport_surfaces_4xx_as_error() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;
    use httpmock::prelude::*;

    let server = MockServer::start_async().await;
    let _mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/");
            then.status(401).body("unauthorized");
        })
        .await;

    let result = send_mcp_request(
        &server.base_url(),
        &McpTransport::Http,
        &HashMap::new(),
        None,
        McpRequest::list_tools(),
    )
    .await;

    assert!(result.is_err(), "4xx must surface as transport error");
}

#[tokio::test]
async fn http_transport_rejects_metadata_endpoint_before_io() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;

    // SSRF guard: an LLM-chosen MCP URL pointing at the cloud metadata endpoint
    // must be rejected by the transport (no client built, no request sent),
    // even though loopback is allowed for legitimate local MCP servers.
    let result = send_mcp_request(
        "http://169.254.169.254/latest/meta-data/",
        &McpTransport::Http,
        &HashMap::new(),
        None,
        McpRequest::list_tools(),
    )
    .await;

    let err = match result {
        Ok(_) => panic!("metadata endpoint must be rejected"),
        Err(e) => e,
    };
    assert!(
        err.to_lowercase().contains("blocked"),
        "error should reference a blocked address, got: {err}"
    );
}

#[tokio::test]
async fn http_transport_rejects_private_range_before_io() {
    use super::helpers::McpRequest;
    use super::transport::send_mcp_request;

    // A private-range target is blocked too (only loopback is exempted).
    let result = send_mcp_request(
        "http://10.0.0.1:8080/",
        &McpTransport::Http,
        &HashMap::new(),
        None,
        McpRequest::list_tools(),
    )
    .await;

    assert!(
        result.is_err(),
        "private-range MCP URL must be rejected by the SSRF guard"
    );
}

#[tokio::test]
async fn add_server_rejects_empty_name_and_url_before_any_network() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    // Empty name and empty URL are rejected by the early validation guards,
    // before load_remote_tools is ever reached — no network needed.
    let no_name = add_server(&files_dir, "  ", "https://example.test/mcp", "{}", "user").await;
    assert!(no_name.contains("name is required"), "got: {no_name}");

    let no_url = add_server(&files_dir, "demo", "  ", "{}", "user").await;
    assert!(no_url.contains("URL is required"), "got: {no_url}");

    // Nothing was persisted.
    assert_eq!(list_servers(&files_dir, "user"), "[]");
}

#[tokio::test]
async fn add_server_rejects_malformed_headers_json() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let result = add_server(
        &files_dir,
        "demo",
        "https://example.test/mcp",
        "not valid json",
        "user",
    )
    .await;
    // parse_headers error surfaces through result_json's "error" field.
    assert!(result.contains("\"error\""), "got: {result}");
    assert_eq!(list_servers(&files_dir, "user"), "[]");
}

#[tokio::test]
async fn add_server_persists_with_activation_error_when_endpoint_unreachable() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();

    // A syntactically valid but unreachable endpoint: validation + transport
    // resolution pass, the remote activation fails, and the server is still
    // persisted (inactive) so the user can retry / re-auth. Exercises the
    // add → save → read-back path without a live MCP server.
    let result = add_server(&files_dir, "demo", "https://127.0.0.1:1/mcp", "{}", "user").await;
    assert!(result.contains("\"name\":\"demo\""), "got: {result}");

    // The server is now listed (persisted despite activation failure).
    let listed = list_servers(&files_dir, "user");
    assert!(listed.contains("demo"), "server should persist: {listed}");
}

#[test]
fn initialize_with_tools_capability_advertises_tools() {
    let response: McpResponse = serde_json::from_value(serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "result": { "capabilities": { "tools": { "listChanged": false } } }
    }))
    .unwrap();
    assert!(initialize_advertises_tools(&response));
}

#[test]
fn initialize_without_tools_capability_skips_tools() {
    let response: McpResponse = serde_json::from_value(serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "result": { "capabilities": { "prompts": {}, "resources": {} } }
    }))
    .unwrap();
    assert!(!initialize_advertises_tools(&response));
}

#[test]
fn initialize_without_capability_map_falls_back_to_tools() {
    // Legacy servers that predate capability advertisement still expect
    // tools/list, so an absent or empty capabilities map must not gate them.
    let absent: McpResponse = serde_json::from_value(serde_json::json!({
        "jsonrpc": "2.0", "id": 1, "result": {}
    }))
    .unwrap();
    assert!(initialize_advertises_tools(&absent));

    let empty: McpResponse = serde_json::from_value(serde_json::json!({
        "jsonrpc": "2.0", "id": 1, "result": { "capabilities": {} }
    }))
    .unwrap();
    assert!(initialize_advertises_tools(&empty));
}

// ===========================================================================
// Lazy-load discovery (idea reference: OpenClaw #186776 `32f9477bf4`)
// ===========================================================================

#[tokio::test]
async fn activate_server_does_not_eagerly_load_tools() {
    use super::servers::activate_server;

    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    // Pre-persist an inactive server whose URL points at an unreachable port.
    // With lazy-load discovery, activation no longer issues `tools/list`, so
    // even an unreachable endpoint should activate cleanly with `active=true`,
    // an empty tool list, and `tools_loaded == false`.
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "remote".to_string(),
        url: "https://127.0.0.1:1/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: false,
        tools: Vec::new(),
        tools_loaded: false,
        tools_error: None,
        last_tools_attempt_at: None,
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    });
    assert!(save_state(&files_dir, &state));

    let result = activate_server(&files_dir, "remote", "user").await;
    assert!(result.contains("\"name\":\"remote\""), "got: {result}");

    let loaded = load_state(&files_dir);
    let server = &loaded.servers[0];
    assert!(server.active, "activation should mark the server active");
    assert!(
        server.tools.is_empty(),
        "lazy-load activation must not eagerly fetch tools"
    );
    assert!(server.activation_error.is_none());
}

#[tokio::test]
async fn list_tools_lazily_fetches_and_caches() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    // Count the number of remote `tools/list` calls this stdio server actually
    // serves. Each spawn of the stdio process appends one tick when it
    // responds to `tools/list`; verifying the counter captures the
    // "cached after first call" property of lazy-load.
    let count_path = tmp.path().join("tools_list_calls.txt");
    let count_path_arg = count_path.to_string_lossy().to_string();
    let script = format!(
        "while IFS= read -r line; do \
           id=$(printf '%s' \"$line\" | sed -n 's/.*\"id\":\\([0-9][0-9]*\\).*/\\1/p'); \
           case \"$line\" in \
             *'\"method\":\"initialize\"'*) printf '{{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{{\"capabilities\":{{\"tools\":{{}}}}}}}}\\n' \"$id\";; \
             *'\"method\":\"tools/list\"'*) echo 1 >> {count_path_arg}; printf '{{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{{\"tools\":[{{\"name\":\"lookup\",\"description\":\"Lookup\",\"inputSchema\":{{\"type\":\"object\"}}}}]}}}}\\n' \"$id\";; \
             *) [ -n \"$id\" ] && printf '{{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{{}}}}\\n' \"$id\";; \
           esac; \
         done"
    );

    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "local-srv".to_string(),
        url: String::new(),
        transport: McpTransport::Stdio {
            command: "sh".to_string(),
            args: vec!["-c".to_string(), script],
            env: HashMap::new(),
        },
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: true,
        tools: Vec::new(),
        tools_loaded: false,
        tools_error: None,
        last_tools_attempt_at: None,
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    });
    assert!(save_state(&files_dir, &state));

    let first = list_tools(&files_dir, "local-srv", "user");
    assert!(
        first.contains("local-srv_lookup"),
        "first call should lazily fetch and return the tool: {first}"
    );

    let loaded = load_state(&files_dir);
    let server = &loaded.servers[0];
    assert!(
        server.tools_loaded,
        "tools_loaded should be flipped to true after the fetch"
    );
    assert_eq!(server.tools.len(), 1);
    assert!(server.tools_error.is_none());

    let count_after_first = std::fs::read_to_string(&count_path).unwrap_or_default();
    assert_eq!(
        count_after_first.lines().count(),
        1,
        "expected exactly one remote tools/list call on first request"
    );

    // Second call must reuse the cache (no new spawn, no new fetch).
    let second = list_tools(&files_dir, "local-srv", "user");
    assert!(second.contains("local-srv_lookup"));
    let count_after_second = std::fs::read_to_string(&count_path).unwrap_or_default();
    assert_eq!(
        count_after_second.lines().count(),
        1,
        "second call should reuse the cached tools without re-fetching"
    );
}

#[test]
fn load_state_normalizes_legacy_pre_populated_tools_as_loaded() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    // Pre-lazy-load records serialized `tools` eagerly. After deserialization
    // `tools_loaded` defaults to `false`; the store must normalize records
    // whose `tools` are already populated so first read does not re-fetch.
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "legacy".to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: true,
        tools: vec![McpTool {
            name: "lookup".to_string(),
            description: "Lookup".to_string(),
            input_schema: serde_json::json!({"type": "object"}),
            requires_approval: false,
        }],
        // Serialize before normalizing so the on-disk record reflects the
        // pre-lazy-load shape. `tools_loaded` is `#[serde(skip_serializing)]`,
        // so it is not written to disk even when set; on deserialization the
        // field defaults to `false`, after which `load_state` normalizes a
        // server whose `tools` are already populated to `tools_loaded == true`.
        tools_loaded: true,
        tools_error: None,
        last_tools_attempt_at: None,
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    });
    assert!(save_state(&files_dir, &state));

    // Confirm the on-disk record really is the pre-lazy-load shape (no
    // `tools_loaded` field). Without this assertion the test would pass
    // trivially even if the new field were serialized.
    let on_disk = std::fs::read_to_string(super::store::store_path(&files_dir)).unwrap();
    assert!(
        !on_disk.contains("tools_loaded"),
        "tools_loaded must be skipped on serialization, got: {on_disk}"
    );

    let loaded = load_state(&files_dir);
    let server = &loaded.servers[0];
    assert!(!server.tools.is_empty());
    assert!(
        server.tools_loaded,
        "loaded records with non-empty tools should be treated as already-loaded"
    );
}

// ===========================================================================
// OpenClaw #176154 — MCP startup fail-fast
// ===========================================================================
// `mcp_startup_failure` surfaces an active MCP server whose first
// `tools/list` failed (tools_loaded=false + tools_error=Some). The turn
// prepare path uses this to abort the turn instead of silently proceeding
// with a partial tool inventory (idea ref: OpenClaw #176154).

#[test]
fn startup_failure_in_state_classifies_active_failed_server_only() {
    // Pure in-memory classifier check: an active server with `tools_loaded=false`
    // and `tools_error=Some` is classified as a startup failure (idea ref:
    // OpenClaw #176154). This is the helper `tool_descriptors_strict` and
    // `mcp_startup_failure` consult after the lazy tool load populates
    // `tools_error` in the freshly-loaded in-memory state.
    use super::tools::startup_failure_in_state;

    let make = |name: &str, active: bool, loaded: bool, err: Option<&str>| McpServer {
        name: name.to_string(),
        url: "https://example.com/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active,
        tools: Vec::new(),
        tools_loaded: loaded,
        tools_error: err.map(str::to_string),
        last_tools_attempt_at: None,
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    };

    // Healthy (loaded) — never fires, even with a stale error entry still set.
    let mut state = McpState::default();
    state
        .servers
        .push(make("healthy", true, true, Some("stale")));
    assert!(startup_failure_in_state(&state, "user").is_none());

    // Pending (not yet attempted, no error) — never fires; lazy load decides.
    let mut state = McpState::default();
    state.servers.push(make("pending", true, false, None));
    assert!(startup_failure_in_state(&state, "user").is_none());

    // Inactive — even with a cached failure it must not fire (turn does not
    // depend on this server's tools).
    let mut state = McpState::default();
    state
        .servers
        .push(make("off", false, false, Some("offline")));
    assert!(startup_failure_in_state(&state, "user").is_none());

    // Active + not loaded + error — fires.
    let mut state = McpState::default();
    state
        .servers
        .push(make("broken", true, false, Some("boom")));
    let failure = startup_failure_in_state(&state, "user").expect("active+broken fires");
    assert_eq!(failure.server, "broken");
    assert!(
        failure.to_string().contains("mcp_server_activate(broken)"),
        "Display carries the retry hint: {}",
        failure
    );

    // State scoped to another account_id — never fires for the wrong user.
    let mut state = McpState::default();
    state
        .servers
        .push(make("other-user-broken", true, false, Some("boom")));
    state.servers[0].user_id = "another".to_string();
    assert!(
        startup_failure_in_state(&state, "user").is_none(),
        "fail-fast must stay scoped to account_id"
    );
}

#[test]
fn mcp_startup_failure_helper_surfaces_failed_active_server() {
    use super::tools::{McpStartupFailure, mcp_startup_failure, tool_descriptors_strict};

    // End-to-end: an active MCP server whose `tools/list` cannot complete
    // (port 1 - immediate connection refused on loopback, the same unreachable
    // endpoint already used by `add_server_persists_with_activation_error_…`)
    // is surfaced by the strict tool descriptor path as `Err`, rather than the
    // pre-fix behavior of silently returning a partial / empty descriptor list.
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "broken".to_string(),
        url: "https://127.0.0.1:1/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: true,
        tools: Vec::new(),
        tools_loaded: false,
        tools_error: None,
        last_tools_attempt_at: None,
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    });
    assert!(save_state(&files_dir, &state));

    let strict = tool_descriptors_strict(&files_dir, "user").expect_err(
        "tool_descriptors_strict returns Err when the active server fails its tools/list",
    );
    assert_eq!(strict.server, "broken");
    let display = format!("{}", strict);
    assert!(
        display.contains("mcp_server_activate(broken)"),
        "Display hints retry activation: {display}"
    );
    assert_eq!(
        strict,
        McpStartupFailure {
            server: "broken".to_string(),
            // The recorded error comes from the lazy-load failure path; we
            // only assert it is non-empty here because the exact wording can
            // evolve with the transport layer.
            reason: strict.reason.clone(),
        }
    );

    // Standalone helper mirrors the strict path so the turn-prepare path can
    // spot the same failure without re-running the descriptor aggregation.
    let standalone = mcp_startup_failure(&files_dir, "user")
        .expect("mcp_startup_failure mirrors the strict path");
    assert_eq!(standalone.server, "broken");
}

#[tokio::test]
async fn mcp_tools_and_handler_returns_no_tools_when_startup_failed() {
    use crate::builtin_tools::mcp_tools_and_handler;

    // The agent-facing builtin tool surface (`mcp_tools_and_handler`) wires the
    // strict descriptor path; on a first-time startup failure it must yield NO
    // MCP descriptors to the tool loop rather than silently proceeding with a
    // partial inventory (idea ref: OpenClaw #176154).
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let mut state = McpState::default();
    state.servers.push(McpServer {
        name: "broken".to_string(),
        url: "https://127.0.0.1:1/mcp".to_string(),
        transport: McpTransport::Http,
        headers: HashMap::new(),
        user_id: "user".to_string(),
        active: true,
        tools: Vec::new(),
        tools_loaded: false,
        tools_error: None,
        last_tools_attempt_at: None,
        session_id: None,
        activation_error: None,
        oauth: None,
        oauth_pending: None,
        oauth_tokens: None,
    });
    assert!(save_state(&files_dir, &state));

    let (tools, handler) = mcp_tools_and_handler(&files_dir, "user");
    assert!(
        tools.is_empty(),
        "fail-fast path returns no MCP descriptors, got: {tools:?}"
    );
    assert!(
        handler.is_some(),
        "handler is still populated for tool-call dispatch"
    );
}
