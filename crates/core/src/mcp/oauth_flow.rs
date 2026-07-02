//! OAuth start and finish flows for MCP servers.

use super::headers::is_http_like_transport;
use super::helpers::{oauth_start_json, result_json};
use super::oauth::{
    build_oauth_authorization_url, canonical_resource_uri, discover_oauth_metadata,
    exchange_oauth_code, merge_oauth_options, parse_oauth_start_options, random_urlsafe,
    register_oauth_client,
};
use super::servers::activate_server;
use super::store::{default_user, load_state, save_state};
use super::types::McpOAuthPending;

pub async fn start_oauth(
    files_dir: &str,
    name: &str,
    user_id: &str,
    redirect_uri: &str,
    oauth_json: &str,
) -> String {
    let user_id = default_user(user_id);
    let options = match parse_oauth_start_options(oauth_json) {
        Ok(options) => options,
        Err(error) => return oauth_start_json(name, None, None, None, Some(error)),
    };
    let mut state = load_state(files_dir);
    let Some(index) = state
        .servers
        .iter()
        .position(|server| server.name == name && server.user_id == user_id)
    else {
        return oauth_start_json(
            name,
            None,
            None,
            None,
            Some("MCP server not found".to_string()),
        );
    };
    if !is_http_like_transport(&state.servers[index].transport) {
        return oauth_start_json(
            name,
            None,
            None,
            None,
            Some("MCP OAuth is only supported for HTTP/SSE transport".to_string()),
        );
    }

    let redirect_uri = if redirect_uri.trim().is_empty() {
        state.servers[index]
            .oauth
            .as_ref()
            .and_then(|oauth| oauth.redirect_uri.clone())
            .unwrap_or_else(|| "napaxi://oauth/mcp".to_string())
    } else {
        redirect_uri.trim().to_string()
    };
    let mut oauth = merge_oauth_options(state.servers[index].oauth.clone(), options);
    oauth.redirect_uri = Some(redirect_uri.clone());

    let metadata = if oauth.authorization_url.is_none()
        || oauth.token_url.is_none()
        || oauth.client_id.is_none()
    {
        match discover_oauth_metadata(&state.servers[index].url).await {
            Ok(metadata) => Some(metadata),
            Err(error) if oauth.authorization_url.is_some() && oauth.token_url.is_some() => {
                tracing::debug!(server = name, error = %error, "MCP OAuth discovery skipped after explicit endpoints");
                None
            }
            Err(error) => {
                return oauth_start_json(
                    name,
                    None,
                    None,
                    None,
                    Some(format!("OAuth discovery failed: {error}")),
                );
            }
        }
    } else {
        None
    };

    if oauth.authorization_url.is_none() {
        oauth.authorization_url = metadata
            .as_ref()
            .map(|metadata| metadata.authorization_endpoint.clone());
    }
    if oauth.token_url.is_none() {
        oauth.token_url = metadata
            .as_ref()
            .map(|metadata| metadata.token_endpoint.clone());
    }
    if oauth.scopes.is_empty()
        && let Some(metadata) = &metadata
    {
        oauth.scopes = if metadata.protected_scopes_supported.is_empty() {
            metadata.scopes_supported.clone()
        } else {
            metadata.protected_scopes_supported.clone()
        };
    }
    if oauth.resource.is_none()
        && let Some(resource) = metadata
            .as_ref()
            .and_then(|metadata| metadata.protected_resource.clone())
    {
        oauth.resource = Some(resource);
    }
    if oauth.client_id.is_none() {
        let Some(registration_endpoint) = metadata
            .as_ref()
            .and_then(|metadata| metadata.registration_endpoint.as_deref())
        else {
            return oauth_start_json(
                name,
                None,
                None,
                None,
                Some("OAuth client_id is required and the server did not advertise dynamic client registration".to_string()),
            );
        };
        match register_oauth_client(registration_endpoint, &redirect_uri).await {
            Ok(client) => {
                oauth.client_id = Some(client.client_id);
                oauth.client_secret = client.client_secret;
            }
            Err(error) => {
                return oauth_start_json(
                    name,
                    None,
                    None,
                    None,
                    Some(format!("OAuth dynamic client registration failed: {error}")),
                );
            }
        }
    }

    let Some(authorization_url) = oauth.authorization_url.clone() else {
        return oauth_start_json(
            name,
            None,
            None,
            None,
            Some("OAuth authorization URL is missing".to_string()),
        );
    };
    let Some(token_url) = oauth.token_url.clone() else {
        return oauth_start_json(
            name,
            None,
            None,
            None,
            Some("OAuth token URL is missing".to_string()),
        );
    };
    let Some(client_id) = oauth.client_id.clone() else {
        return oauth_start_json(
            name,
            None,
            None,
            None,
            Some("OAuth client_id is missing".to_string()),
        );
    };

    let state_value = random_urlsafe(24);
    let code_verifier = if oauth.use_pkce {
        Some(random_urlsafe(32))
    } else {
        None
    };
    let resource = oauth
        .resource
        .clone()
        .or_else(|| Some(canonical_resource_uri(&state.servers[index].url)));
    let auth_url = build_oauth_authorization_url(
        &authorization_url,
        &client_id,
        &redirect_uri,
        &oauth.scopes,
        code_verifier.as_deref(),
        &oauth.extra_params,
        &state_value,
        resource.as_deref(),
    );

    state.servers[index].oauth = Some(oauth.clone());
    state.servers[index].oauth_pending = Some(McpOAuthPending {
        state: state_value.clone(),
        code_verifier,
        redirect_uri: redirect_uri.clone(),
        authorization_url: authorization_url.clone(),
        token_url,
        client_id,
        client_secret: oauth.client_secret.clone(),
        scopes: oauth.scopes.clone(),
        resource,
        created_at: chrono::Utc::now().to_rfc3339(),
    });
    state.servers[index].activation_error = None;
    if !save_state(files_dir, &state) {
        return oauth_start_json(
            name,
            None,
            None,
            None,
            Some("Failed to save MCP OAuth state".to_string()),
        );
    }
    oauth_start_json(
        name,
        Some(auth_url),
        Some(state_value),
        Some(redirect_uri),
        None,
    )
}

pub async fn finish_oauth(
    files_dir: &str,
    name: &str,
    user_id: &str,
    code: &str,
    state_value: &str,
) -> String {
    let user_id = default_user(user_id);
    if code.trim().is_empty() {
        return result_json(name, &[], "OAuth authorization code is required");
    }
    let state = load_state(files_dir);
    let Some(server) = state
        .servers
        .iter()
        .find(|server| server.name == name && server.user_id == user_id)
    else {
        return result_json(name, &[], "MCP server not found");
    };
    let Some(pending) = server.oauth_pending.clone() else {
        return result_json(name, &[], "No pending OAuth flow for MCP server");
    };
    if pending.state != state_value.trim() {
        return result_json(name, &[], "OAuth state mismatch");
    }

    let token = match exchange_oauth_code(&pending, code.trim()).await {
        Ok(token) => token,
        Err(error) => {
            return result_json(name, &[], &format!("OAuth token exchange failed: {error}"));
        }
    };
    let mut state = load_state(files_dir);
    let Some(index) = state
        .servers
        .iter()
        .position(|server| server.name == name && server.user_id == user_id)
    else {
        return result_json(name, &[], "MCP server not found after OAuth exchange");
    };
    state.servers[index].oauth_tokens = Some(token);
    state.servers[index].oauth_pending = None;
    state.servers[index].activation_error = None;
    if !save_state(files_dir, &state) {
        return result_json(name, &[], "Failed to save MCP OAuth token");
    }
    activate_server(files_dir, name, &user_id).await
}
