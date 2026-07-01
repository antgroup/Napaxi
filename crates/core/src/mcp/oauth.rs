use std::collections::HashMap;
use std::net::IpAddr;

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::{
    McpOAuthConfig, McpOAuthPending, McpOAuthStartOptions, McpOAuthTokens, McpServer,
    default_token_type, sanitize_error_body,
};

#[derive(Debug, Clone, Deserialize)]
pub(super) struct AuthorizationServerMetadata {
    pub(super) issuer: String,
    pub(super) authorization_endpoint: String,
    pub(super) token_endpoint: String,
    #[serde(default)]
    pub(super) registration_endpoint: Option<String>,
    #[serde(default)]
    pub(super) scopes_supported: Vec<String>,
    #[serde(skip)]
    pub(super) protected_resource: Option<String>,
    #[serde(skip)]
    pub(super) protected_scopes_supported: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct ClientRegistrationResponse {
    pub(super) client_id: String,
    #[serde(default)]
    pub(super) client_secret: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct ProtectedResourceMetadata {
    resource: Option<String>,
    #[serde(default)]
    authorization_servers: Vec<String>,
    #[serde(default)]
    scopes_supported: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ClientRegistrationRequest {
    client_name: String,
    redirect_uris: Vec<String>,
    grant_types: Vec<String>,
    response_types: Vec<String>,
    token_endpoint_auth_method: String,
}

#[derive(Debug, Deserialize)]
struct OAuthTokenResponse {
    access_token: String,
    #[serde(default = "default_token_type")]
    token_type: String,
    #[serde(default)]
    expires_in: Option<u64>,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    scope: Option<String>,
}

pub(super) fn parse_oauth_start_options(oauth_json: &str) -> Result<McpOAuthStartOptions, String> {
    if oauth_json.trim().is_empty() || oauth_json.trim() == "{}" {
        return Ok(McpOAuthStartOptions::default());
    }
    serde_json::from_str(oauth_json).map_err(|e| format!("Invalid OAuth JSON: {e}"))
}

pub(super) fn merge_oauth_options(
    existing: Option<McpOAuthConfig>,
    options: McpOAuthStartOptions,
) -> McpOAuthConfig {
    let is_new_config = existing.is_none();
    let mut oauth = existing.unwrap_or_default();
    if is_new_config {
        oauth.use_pkce = true;
    }
    if options.client_id.is_some() {
        oauth.client_id = options.client_id;
    }
    if options.client_secret.is_some() {
        oauth.client_secret = options.client_secret;
    }
    if options.authorization_url.is_some() {
        oauth.authorization_url = options.authorization_url;
    }
    if options.token_url.is_some() {
        oauth.token_url = options.token_url;
    }
    if !options.scopes.is_empty() {
        oauth.scopes = options.scopes;
    }
    if let Some(use_pkce) = options.use_pkce {
        oauth.use_pkce = use_pkce;
    }
    if !options.extra_params.is_empty() {
        oauth.extra_params = options.extra_params;
    }
    if options.resource.is_some() {
        oauth.resource = options.resource;
    }
    oauth
}

pub(super) fn random_urlsafe(bytes_len: usize) -> String {
    let mut bytes = vec![0u8; bytes_len];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

fn pkce_challenge(verifier: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(verifier.as_bytes());
    URL_SAFE_NO_PAD.encode(hasher.finalize())
}

pub(super) fn build_oauth_authorization_url(
    base_url: &str,
    client_id: &str,
    redirect_uri: &str,
    scopes: &[String],
    code_verifier: Option<&str>,
    extra_params: &HashMap<String, String>,
    state: &str,
    resource: Option<&str>,
) -> String {
    let mut params = vec![
        ("client_id".to_string(), client_id.to_string()),
        ("response_type".to_string(), "code".to_string()),
        ("redirect_uri".to_string(), redirect_uri.to_string()),
        ("state".to_string(), state.to_string()),
    ];
    if !scopes.is_empty() {
        params.push(("scope".to_string(), scopes.join(" ")));
    }
    if let Some(verifier) = code_verifier {
        params.push(("code_challenge".to_string(), pkce_challenge(verifier)));
        params.push(("code_challenge_method".to_string(), "S256".to_string()));
    }
    for (key, value) in extra_params {
        if key != "state" {
            params.push((key.clone(), value.clone()));
        }
    }
    if let Some(resource) = resource
        && !resource.trim().is_empty()
    {
        params.push(("resource".to_string(), resource.to_string()));
    }

    let query = params
        .into_iter()
        .map(|(key, value)| {
            format!(
                "{}={}",
                urlencoding::encode(&key),
                urlencoding::encode(&value)
            )
        })
        .collect::<Vec<_>>()
        .join("&");
    if base_url.contains('?') {
        format!("{base_url}&{query}")
    } else {
        format!("{base_url}?{query}")
    }
}

pub(super) fn canonical_resource_uri(server_url: &str) -> String {
    match reqwest::Url::parse(server_url) {
        Ok(mut parsed) => {
            parsed.set_fragment(None);
            parsed.to_string().trim_end_matches('/').to_string()
        }
        Err(_) => server_url.trim_end_matches('/').to_string(),
    }
}

fn build_well_known_uri(base_url: &str, suffix: &str) -> Result<String, String> {
    let parsed = reqwest::Url::parse(base_url).map_err(|e| format!("Invalid URL: {e}"))?;
    let origin = parsed.origin().ascii_serialization();
    let path = parsed.path().trim_end_matches('/');
    Ok(format!("{origin}/.well-known/{suffix}{path}"))
}

fn is_localhost_url(url: &str) -> bool {
    reqwest::Url::parse(url)
        .ok()
        .and_then(|parsed| parsed.host_str().map(str::to_string))
        .is_some_and(|host| matches!(host.as_str(), "localhost" | "127.0.0.1" | "::1"))
}

fn is_dangerous_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_broadcast()
                || v4.is_unspecified()
                || (v4.octets()[0] == 169 && v4.octets()[1] == 254)
                || (v4.octets()[0] == 100 && (v4.octets()[1] & 0xC0) == 64)
        }
        IpAddr::V6(v6) => {
            let segs = v6.segments();
            v6.is_loopback()
                || v6.is_unspecified()
                || (segs[0] & 0xffc0) == 0xfe80
                || (segs[0] & 0xffc0) == 0xfec0
                || (segs[0] & 0xfe00) == 0xfc00
                || (segs[0] == 0x2001 && segs[1] == 0x0db8)
                || v6
                    .to_ipv4_mapped()
                    .is_some_and(|v4| is_dangerous_ip(IpAddr::V4(v4)))
        }
    }
}

async fn validate_oauth_url_safe(url: &str) -> Result<(), String> {
    let parsed = reqwest::Url::parse(url).map_err(|e| format!("Invalid URL: {e}"))?;
    let scheme = parsed.scheme();
    if scheme != "https" && scheme != "http" {
        return Err(format!("Unsupported scheme: {scheme}"));
    }
    if scheme == "http" {
        if is_localhost_url(url) {
            return Ok(());
        }
        return Err("HTTP OAuth endpoints are only allowed for localhost".to_string());
    }
    let host = parsed
        .host_str()
        .ok_or_else(|| "URL has no host".to_string())?;
    if let Ok(ip) = host.parse::<IpAddr>()
        && is_dangerous_ip(ip)
    {
        return Err(format!("URL points to a restricted IP address: {host}"));
    }
    if host.parse::<IpAddr>().is_err() {
        let addr = format!("{}:{}", host, parsed.port_or_known_default().unwrap_or(443));
        let addrs = tokio::net::lookup_host(&addr)
            .await
            .map_err(|e| format!("DNS resolution failed for '{host}': {e}"))?;
        for socket_addr in addrs {
            if is_dangerous_ip(socket_addr.ip()) {
                return Err(format!(
                    "URL hostname '{host}' resolves to restricted IP address: {}",
                    socket_addr.ip()
                ));
            }
        }
    }
    Ok(())
}

pub(super) async fn discover_oauth_metadata(
    server_url: &str,
) -> Result<AuthorizationServerMetadata, String> {
    if let Ok(metadata) = discover_oauth_via_401(server_url).await {
        return Ok(metadata);
    }
    if let Ok(resource) = discover_protected_resource(server_url).await
        && let Ok(metadata) = discover_from_resource_metadata(&resource).await
    {
        return Ok(metadata);
    }
    discover_authorization_server(server_url).await
}

async fn discover_oauth_via_401(server_url: &str) -> Result<AuthorizationServerMetadata, String> {
    validate_oauth_url_safe(server_url).await?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| format!("Failed to create OAuth HTTP client: {e}"))?;
    let response = client
        .post(server_url)
        .header("Content-Type", "application/json")
        .body("{}")
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = response.status().as_u16();
    if status != 401 && status != 400 {
        return Err(format!(
            "Expected OAuth challenge, got {}",
            response.status()
        ));
    }
    let www_authenticate = response
        .headers()
        .get("WWW-Authenticate")
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| format!("No WWW-Authenticate header in {status} response"))?;
    let resource_metadata_url = parse_resource_metadata_url(www_authenticate)
        .ok_or_else(|| "No resource_metadata URL in WWW-Authenticate header".to_string())?;
    let resource = fetch_protected_resource_metadata(&resource_metadata_url).await?;
    discover_from_resource_metadata(&resource).await
}

fn parse_resource_metadata_url(www_authenticate: &str) -> Option<String> {
    for part in www_authenticate.split(',') {
        let part = part.trim();
        if let Some(rest) = part.strip_prefix("resource_metadata=\"") {
            return rest.strip_suffix('"').map(str::to_string);
        }
        if let Some(rest) = part.strip_prefix("resource_metadata=") {
            return Some(rest.trim_matches('"').to_string());
        }
    }
    for part in www_authenticate.split_whitespace() {
        if let Some(rest) = part.strip_prefix("resource_metadata=\"") {
            return rest
                .trim_end_matches(',')
                .strip_suffix('"')
                .map(str::to_string);
        }
        if let Some(rest) = part.strip_prefix("resource_metadata=") {
            return Some(rest.trim_matches('"').trim_end_matches(',').to_string());
        }
    }
    None
}

async fn discover_protected_resource(
    server_url: &str,
) -> Result<ProtectedResourceMetadata, String> {
    let url = build_well_known_uri(server_url, "oauth-protected-resource")?;
    fetch_protected_resource_metadata(&url).await
}

async fn fetch_protected_resource_metadata(url: &str) -> Result<ProtectedResourceMetadata, String> {
    validate_oauth_url_safe(url).await?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| format!("Failed to create OAuth HTTP client: {e}"))?;
    let response = client.get(url).send().await.map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    response
        .json()
        .await
        .map_err(|e| format!("Invalid protected resource metadata: {e}"))
}

async fn discover_from_resource_metadata(
    resource: &ProtectedResourceMetadata,
) -> Result<AuthorizationServerMetadata, String> {
    let auth_server = resource
        .authorization_servers
        .first()
        .ok_or_else(|| "No authorization servers listed".to_string())?;
    let mut metadata = discover_authorization_server(auth_server).await?;
    metadata.protected_resource = resource.resource.clone();
    metadata.protected_scopes_supported = resource.scopes_supported.clone();
    Ok(metadata)
}

async fn discover_authorization_server(
    auth_server_url: &str,
) -> Result<AuthorizationServerMetadata, String> {
    let url = build_well_known_uri(auth_server_url, "oauth-authorization-server")?;
    validate_oauth_url_safe(&url).await?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| format!("Failed to create OAuth HTTP client: {e}"))?;
    let response = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    let metadata: AuthorizationServerMetadata = response
        .json()
        .await
        .map_err(|e| format!("Invalid authorization server metadata: {e}"))?;
    if metadata.issuer.trim().is_empty() {
        return Err("Authorization server metadata is missing issuer".to_string());
    }
    Ok(metadata)
}

pub(super) async fn register_oauth_client(
    registration_endpoint: &str,
    redirect_uri: &str,
) -> Result<ClientRegistrationResponse, String> {
    validate_oauth_url_safe(registration_endpoint).await?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(|e| format!("Failed to create OAuth HTTP client: {e}"))?;
    let request = ClientRegistrationRequest {
        client_name: "Napaxi Mobile".to_string(),
        redirect_uris: vec![redirect_uri.to_string()],
        grant_types: vec![
            "authorization_code".to_string(),
            "refresh_token".to_string(),
        ],
        response_types: vec!["code".to_string()],
        token_endpoint_auth_method: "none".to_string(),
    };
    let response = client
        .post(registration_endpoint)
        .json(&request)
        .send()
        .await
        .map_err(|e| format!("DCR request failed: {e}"))?;
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("HTTP {status} - {}", sanitize_error_body(&body)));
    }
    response
        .json()
        .await
        .map_err(|e| format!("Invalid DCR response: {e}"))
}

pub(super) async fn exchange_oauth_code(
    pending: &McpOAuthPending,
    code: &str,
) -> Result<McpOAuthTokens, String> {
    validate_oauth_url_safe(&pending.token_url).await?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| format!("Failed to create OAuth HTTP client: {e}"))?;
    let mut params = vec![
        ("grant_type", "authorization_code".to_string()),
        ("code", code.to_string()),
        ("redirect_uri", pending.redirect_uri.clone()),
        ("client_id", pending.client_id.clone()),
    ];
    if let Some(client_secret) = &pending.client_secret {
        params.push(("client_secret", client_secret.clone()));
    }
    if let Some(code_verifier) = &pending.code_verifier {
        params.push(("code_verifier", code_verifier.clone()));
    }
    if let Some(resource) = &pending.resource {
        params.push(("resource", resource.clone()));
    }
    let response = client
        .post(&pending.token_url)
        .form(&params)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("HTTP {status} - {}", sanitize_error_body(&body)));
    }
    let token: OAuthTokenResponse = response
        .json()
        .await
        .map_err(|e| format!("Invalid token response: {e}"))?;
    Ok(oauth_tokens_from_response(token, None, None))
}

fn oauth_tokens_from_response(
    token: OAuthTokenResponse,
    fallback_refresh_token: Option<String>,
    fallback_scope: Option<String>,
) -> McpOAuthTokens {
    let expires_at = token
        .expires_in
        .map(|secs| chrono::Utc::now() + chrono::Duration::seconds(secs as i64))
        .map(|time| time.to_rfc3339());
    McpOAuthTokens {
        access_token: token.access_token,
        token_type: token.token_type,
        refresh_token: token.refresh_token.or(fallback_refresh_token),
        scope: token.scope.or(fallback_scope),
        expires_at,
    }
}

pub(super) fn oauth_token_needs_refresh(tokens: &McpOAuthTokens) -> bool {
    let Some(expires_at) = tokens.expires_at.as_deref() else {
        return false;
    };
    let Ok(expires_at) = chrono::DateTime::parse_from_rfc3339(expires_at) else {
        return true;
    };
    let refresh_at = expires_at.with_timezone(&chrono::Utc) - chrono::Duration::seconds(60);
    chrono::Utc::now() >= refresh_at
}

async fn refresh_oauth_tokens(
    oauth: &McpOAuthConfig,
    tokens: &McpOAuthTokens,
) -> Result<McpOAuthTokens, String> {
    let token_url = oauth
        .token_url
        .as_deref()
        .filter(|url| !url.trim().is_empty())
        .ok_or_else(|| "OAuth token URL is missing".to_string())?;
    let params = oauth_refresh_params(oauth, tokens)?;
    validate_oauth_url_safe(token_url).await?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| format!("Failed to create OAuth HTTP client: {e}"))?;
    let response = client
        .post(token_url)
        .form(&params)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("HTTP {status} - {}", sanitize_error_body(&body)));
    }
    let token: OAuthTokenResponse = response
        .json()
        .await
        .map_err(|e| format!("Invalid token refresh response: {e}"))?;
    Ok(oauth_tokens_from_response(
        token,
        tokens.refresh_token.clone(),
        tokens.scope.clone(),
    ))
}

pub(super) fn oauth_refresh_params(
    oauth: &McpOAuthConfig,
    tokens: &McpOAuthTokens,
) -> Result<Vec<(&'static str, String)>, String> {
    let client_id = oauth
        .client_id
        .as_deref()
        .filter(|client_id| !client_id.trim().is_empty())
        .ok_or_else(|| "OAuth client_id is missing".to_string())?;
    let refresh_token = tokens
        .refresh_token
        .as_deref()
        .filter(|refresh_token| !refresh_token.trim().is_empty())
        .ok_or_else(|| {
            "OAuth access token is expired and no refresh_token is available".to_string()
        })?;
    let mut params = vec![
        ("grant_type", "refresh_token".to_string()),
        ("refresh_token", refresh_token.to_string()),
        ("client_id", client_id.to_string()),
    ];
    if let Some(client_secret) = oauth
        .client_secret
        .as_deref()
        .filter(|client_secret| !client_secret.trim().is_empty())
    {
        params.push(("client_secret", client_secret.to_string()));
    }
    if let Some(resource) = oauth
        .resource
        .as_deref()
        .filter(|resource| !resource.trim().is_empty())
    {
        params.push(("resource", resource.to_string()));
    }
    Ok(params)
}

pub(super) async fn refresh_server_oauth_if_needed(server: &mut McpServer) -> Result<bool, String> {
    let Some(tokens) = server.oauth_tokens.clone() else {
        return Ok(false);
    };
    if !oauth_token_needs_refresh(&tokens) {
        return Ok(false);
    }
    let oauth = server
        .oauth
        .as_ref()
        .ok_or_else(|| "OAuth config is missing".to_string())?;
    let refreshed = refresh_oauth_tokens(oauth, &tokens).await?;
    server.oauth_tokens = Some(refreshed);
    server.activation_error = None;
    Ok(true)
}
