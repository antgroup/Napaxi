//! Tool listing, descriptor enumeration, remote tool loading, and tool calls.

use std::collections::HashMap;
use std::time::Duration;

use chrono::Utc;

use super::headers::{effective_headers, is_http_like_transport};
use super::helpers::{CallToolResult, ListToolsResult, McpRequest, McpResponse};
use super::oauth::refresh_server_oauth_if_needed;
use super::store::{default_user, load_state, save_state};
use super::tool_descriptor::{prefixed_tool_name, remote_tool_name, tool_json};
use super::transport::{send_mcp_request, send_mcp_sse_sequence, send_mcp_transport_sequence};
use super::types::{McpServer, McpTool, McpTransport};

/// Minimum spacing between lazy-load retry attempts for a server whose
/// `tools/list` call failed. Prevents a failing MCP server from being
/// hammered on every `list_tools` / `tool_descriptors` call while still
/// letting it recover (e.g. after the server comes back online).
const TOOLS_RETRY_BACKOFF: Duration = Duration::from_secs(60);

pub fn list_tools(files_dir: &str, server_name: &str, user_id: &str) -> String {
    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    ensure_active_tools_loaded_blocking(files_dir, &mut state, &user_id, server_name);
    let tools: Vec<_> = state
        .servers
        .iter()
        .filter(|server| server.user_id == user_id && server.active)
        .filter(|server| server_name.trim().is_empty() || server.name == server_name)
        .flat_map(|server| server.tools.iter().map(|tool| tool_json(server, tool)))
        .collect();
    serde_json::to_string(&tools).unwrap_or_else(|_| "[]".to_string())
}

pub fn tool_descriptors(
    files_dir: &str,
    user_id: &str,
) -> Vec<crate::tool_registry::ToolDescriptor> {
    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    // Pass an empty server filter so every active server's tool list is
    // lazily fetched before we enumerate descriptors.
    ensure_active_tools_loaded_blocking(files_dir, &mut state, &user_id, "");
    state
        .servers
        .iter()
        .filter(|server| server.user_id == user_id && server.active)
        .flat_map(|server| {
            server
                .tools
                .iter()
                .map(|tool| crate::tool_registry::ToolDescriptor {
                    name: prefixed_tool_name(&server.name, &tool.name),
                    description: if tool.description.trim().is_empty() {
                        format!("MCP tool '{}' from server '{}'", tool.name, server.name)
                    } else {
                        format!("{} (MCP server: {})", tool.description, server.name)
                    },
                    parameters: tool.input_schema.clone(),
                    effect: crate::tool_registry::ToolEffect::External,
                })
        })
        // Run descriptor admission so policy hooks can hide MCP tools from
        // the agent's tool list. `admit_tool_descriptor` falls back to the
        // tool name as the capability id when no static mapping matches
        // (MCP tool names are `{server}_{name}`); policy hooks can branch
        // on either the subject prefix or the `napaxi.mcp.runtime`
        // capability id.
        .filter(|descriptor| crate::capabilities::admit_tool_descriptor(&descriptor.name).is_ok())
        .collect()
}

pub async fn call_tool(
    files_dir: &str,
    tool_name: &str,
    arguments: serde_json::Value,
    user_id: &str,
) -> Result<String, String> {
    // Invocation admission must pass before any network IO. Policy hooks can
    // deny by subject (the prefixed MCP tool name) or by capability id;
    // unresolved capability ids fall back to the subject name.
    crate::capabilities::admit_tool_invocation(tool_name)?;

    let user_id = default_user(user_id);
    let mut state = load_state(files_dir);
    // Resolve the owning server by name prefix first; the lazy-load then fills
    // in the tools list so the second pass of `remote_tool_name` below has the
    // concrete tool to call. The prefix-based resolution does not depend on
    // `server.tools` being populated.
    let Some(index) = state
        .servers
        .iter()
        .enumerate()
        .filter(|(_, server)| server.user_id == user_id && server.active)
        .find(|(_, server)| remote_tool_name(&server.name, tool_name).is_some())
        .map(|(index, _)| index)
    else {
        return Err(format!("MCP tool not found: {tool_name}"));
    };

    // Lazy-load the chosen server's tools on first invocation. Re-resolve the
    // remote tool name afterwards so the cached list gates the call.
    if !state.servers[index].tools_loaded {
        ensure_server_tools_loaded(files_dir, &mut state, index).await?;
    }

    let remote_tool = remote_tool_name(&state.servers[index].name, tool_name)
        .ok_or_else(|| format!("MCP tool not found: {tool_name}"))?;

    let result = if is_http_like_transport(&state.servers[index].transport) {
        let refreshed = refresh_server_oauth_if_needed(&mut state.servers[index])
            .await
            .map_err(|error| format!("MCP OAuth refresh failed: {error}"))?;
        if refreshed && !save_state(files_dir, &state) {
            return Err("Failed to save refreshed MCP OAuth token".to_string());
        }
        let http_result = if let McpTransport::Sse { sse_path } = &state.servers[index].transport {
            let responses = send_mcp_sse_sequence(
                &state.servers[index].url,
                sse_path,
                &effective_headers(files_dir, &state.servers[index]),
                vec![
                    McpRequest::initialize(),
                    McpRequest::initialized_notification(),
                    McpRequest::call_tool(&remote_tool, arguments),
                ],
            )
            .await?;
            responses
                .into_iter()
                .last()
                .ok_or_else(|| "No result in MCP tool response".to_string())?
        } else {
            send_mcp_request(
                &state.servers[index].url,
                &state.servers[index].transport,
                &effective_headers(files_dir, &state.servers[index]),
                state.servers[index].session_id.as_deref(),
                McpRequest::call_tool(&remote_tool, arguments),
            )
            .await?
        };
        if http_result.session_id != state.servers[index].session_id {
            state.servers[index].session_id = http_result.session_id.clone();
            let _ = save_state(files_dir, &state);
        }
        http_result.response
    } else {
        let responses = send_mcp_transport_sequence(
            &state.servers[index].transport,
            vec![
                McpRequest::initialize(),
                McpRequest::initialized_notification(),
                McpRequest::call_tool(&remote_tool, arguments),
            ],
        )
        .await?;
        responses
            .into_iter()
            .last()
            .map(|response| response.response)
            .ok_or_else(|| "No result in MCP tool response".to_string())?
    };

    let result: CallToolResult = result
        .result
        .ok_or_else(|| "No result in MCP tool response".to_string())
        .and_then(|value| {
            serde_json::from_value(value).map_err(|e| format!("Invalid MCP tool result: {e}"))
        })?;
    let content = result
        .content
        .iter()
        .map(|block| {
            block
                .text
                .clone()
                .unwrap_or_else(|| serde_json::to_string(block).unwrap_or_default())
        })
        .collect::<Vec<_>>()
        .join("\n");
    if result.is_error {
        Err(content)
    } else {
        Ok(content)
    }
}

pub(super) struct McpActivation {
    pub(super) tools: Vec<McpTool>,
    pub(super) session_id: Option<String>,
}

/// Lazily populate `tools` for every active server in `state` that has not
/// been loaded yet (`tools_loaded == false`), filtered by `user_id` and an
/// optional `server_name`. The fetch is dispatched on a dedicated OS thread
/// that runs its own short-lived current-thread Tokio runtime: the public
/// `list_tools` / `tool_descriptors` entry points are sync, but they are
/// routinely called from inside an outer Tokio runtime (the bridge runs the
/// agent turn on a worker thread). Building a runtime on the same thread and
/// calling `block_on` from within a runtime panics
/// ("Cannot start a runtime from within a runtime"), so the lazy fetch is
/// moved to a standalone thread that owns its own runtime and serializes the
/// per-server fetches. The thread persists results to disk via
/// [`save_state`]; the caller then re-reads state from disk so its in-memory
/// snapshot reflects what the thread produced.
fn ensure_active_tools_loaded_blocking(
    files_dir: &str,
    state: &mut super::types::McpState,
    user_id: &str,
    server_name: &str,
) {
    // Capture the identities (name + user_id) of the servers that still need
    // a remote `tools/list`. We move these owned strings into the worker
    // thread; the thread finds each server by identity inside a freshly
    // loaded on-disk state, so it does not borrow the caller's `state`.
    let needs_load: Vec<(String, String)> = state
        .servers
        .iter()
        .filter(|server| server.user_id == user_id && server.active)
        .filter(|server| !server.tools_loaded)
        .filter(|server| server_name.trim().is_empty() || server.name == server_name)
        .filter(|server| should_retry_lazy_load(server))
        .map(|server| (server.name.clone(), server.user_id.clone()))
        .collect();
    if needs_load.is_empty() {
        return;
    }

    let files_dir_owned = files_dir.to_string();
    let work = move || -> Vec<(String, String)> {
        // Build an isolated runtime on this dedicated thread. We do NOT use
        // `block_in_place` because that requires a multi-threaded runtime and
        // panics on a current-thread runtime (which is what `#[tokio::test]`
        // and several bridge call sites use). Owning the thread + runtime
        // keeps the lazy load off the caller's worker pool entirely.
        let runtime = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(runtime) => runtime,
            Err(error) => {
                tracing::warn!("failed to build lazy-load runtime: {}", error);
                // Mark each pending server with the runtime-build failure so
                // callers see a cached error instead of a silent no-op.
                let mut local = load_state(&files_dir_owned);
                for (name, user) in &needs_load {
                    if let Some(server) = local
                        .servers
                        .iter_mut()
                        .find(|s| &s.name == name && &s.user_id == user)
                    {
                        server.tools_error = Some(format!("failed to build runtime: {error}"));
                    }
                }
                let _ = save_state(&files_dir_owned, &local);
                return needs_load
                    .iter()
                    .map(|(n, u)| (n.clone(), u.clone()))
                    .collect();
            }
        };
        let failed: Vec<(String, String)> = runtime.block_on(async move {
            let mut failed = Vec::new();
            for (name, user) in &needs_load {
                // Re-load fresh state each iteration so concurrent
                // modifications (including our own previous iteration's
                // save_state) are reflected.
                let mut local = load_state(&files_dir_owned);
                let Some(index) = local
                    .servers
                    .iter()
                    .position(|s| &s.name == name && &s.user_id == user)
                else {
                    // Server vanished between scheduling and fetch; skip.
                    continue;
                };
                if let Err(error) =
                    ensure_server_tools_loaded(&files_dir_owned, &mut local, index).await
                {
                    tracing::warn!(
                        server = %name,
                        error = %error,
                        "MCP lazy tool load failed"
                    );
                    failed.push((name.clone(), user.clone()));
                }
            }
            failed
        });
        failed
    };

    let _ = std::thread::spawn(work)
        .join()
        .map_err(|panic| {
            tracing::warn!("lazy-load worker thread panicked: {:?}", panic);
        })
        .ok();

    // Re-read the on-disk state so the caller's in-memory snapshot reflects
    // whatever the worker thread persisted (loaded tools, cached errors,
    // back-off timestamps). Servers whose fetch failed keep their cached
    // `tools_error` from `record_lazy_load_failure`.
    *state = load_state(files_dir);
    // `load_state` already normalizes legacy tool records; preserve a final
    // save so the in-memory and on-disk views stay in sync (no-op if nothing
    // changed).
    let _ = save_state(files_dir, state);
}

/// Decide whether the lazy-load can be retried for `server` based on the
/// back-off window ([`TOOLS_RETRY_BACKOFF`]). A server that just failed its
/// `tools/list` call is not retried within the window — the cached
/// `tools_error` keeps adapters informed without re-hitting the network.
fn should_retry_lazy_load(server: &McpServer) -> bool {
    match &server.last_tools_attempt_at {
        None => true,
        Some(timestamp) => {
            let Ok(parsed) = chrono::DateTime::parse_from_rfc3339(timestamp) else {
                return true;
            };
            let elapsed = Utc::now().signed_duration_since(parsed.with_timezone(&Utc));
            elapsed.num_seconds() >= TOOLS_RETRY_BACKOFF.as_secs() as i64
        }
    }
}

/// Lazily fetch and cache the remote `tools/list` response for the server at
/// `index` in `state`. On success, records `tools_loaded = true` and clears
/// any cached `tools_error` / `last_tools_attempt_at`. On failure, records the
/// bounded error + attempt timestamp so the next call within the back-off
/// window does not retry; the server's existing tools (which may be empty or
/// slightly stale) are left untouched so adapters can still render whatever
/// they have.
async fn ensure_server_tools_loaded(
    files_dir: &str,
    state: &mut super::types::McpState,
    index: usize,
) -> Result<(), String> {
    if state.servers[index].tools_loaded {
        return Ok(());
    }
    if !should_retry_lazy_load(&state.servers[index]) {
        // Surface the previously cached error instead of retrying within the
        // back-off window; callers treat the empty tool list as best-effort.
        if let Some(error) = state.servers[index].tools_error.clone() {
            return Err(error);
        }
        return Err("MCP tool list not loaded yet".to_string());
    }

    refresh_server_oauth_if_needed(&mut state.servers[index])
        .await
        .map_err(|error| format!("MCP OAuth refresh failed: {error}"))?;

    let loaded = load_remote_tools(
        &state.servers[index].name,
        &state.servers[index].url,
        &state.servers[index].transport,
        &effective_headers(files_dir, &state.servers[index]),
        state.servers[index].session_id.as_deref(),
    )
    .await
    .map_err(|error| {
        // Record the failure so the back-off window suppresses retries.
        record_lazy_load_failure(
            files_dir,
            state,
            index,
            format!("Activation failed: {error}"),
        );
        format!("Activation failed: {error}")
    })?;

    // After the network round-trip, re-load state. Concurrent calls may have
    // rewritten state on disk; merge the fetched tools into the freshly
    // loaded version so we never lose another server's changes. The HSM
    // (header secrets / OAuth metadata) is preserved by `save_state` too.
    let mut fresh = load_state(files_dir);
    let server = &mut fresh
        .servers
        .iter_mut()
        .find(|s| s.name == state.servers[index].name && s.user_id == state.servers[index].user_id)
        .ok_or_else(|| "MCP server disappeared during lazy load".to_string())?;
    server.tools = loaded.tools;
    server.session_id = loaded.session_id;
    server.tools_loaded = true;
    server.tools_error = None;
    server.last_tools_attempt_at = Some(Utc::now().to_rfc3339());
    *state = fresh;
    if !save_state(files_dir, state) {
        return Err("Failed to save MCP servers".to_string());
    }
    Ok(())
}

/// Stash the lazy-load failure on `state` without retrying within the
/// back-off window. Used by `call_tool` so the next call inside the window
/// surfaces the same error rather than re-issuing the network request.
fn record_lazy_load_failure(
    files_dir: &str,
    state: &mut super::types::McpState,
    index: usize,
    error: String,
) {
    let server = &mut state.servers[index];
    server.tools_loaded = false;
    server.tools_error = Some(error);
    server.last_tools_attempt_at = Some(Utc::now().to_rfc3339());
    let _ = save_state(files_dir, state);
}

/// Inspect an [initialize, initialized, tools/list] response batch and decide
/// whether the server advertises the `tools` capability. The initialize
/// response is the first entry in the batch.
fn sequence_advertises_tools(responses: &[super::helpers::McpHttpResponse]) -> bool {
    match responses.first() {
        Some(initialized) => super::helpers::initialize_advertises_tools(&initialized.response),
        None => true,
    }
}

pub(super) async fn load_remote_tools(
    server_name: &str,
    url: &str,
    transport: &McpTransport,
    headers: &HashMap<String, String>,
    initial_session_id: Option<&str>,
) -> Result<McpActivation, String> {
    if let McpTransport::Sse { sse_path } = transport {
        let responses = send_mcp_sse_sequence(
            url,
            sse_path,
            headers,
            vec![
                McpRequest::initialize(),
                McpRequest::initialized_notification(),
                McpRequest::list_tools(),
            ],
        )
        .await?;
        if !sequence_advertises_tools(&responses) {
            return Ok(McpActivation {
                tools: Vec::new(),
                session_id: None,
            });
        }
        let listed = responses
            .into_iter()
            .last()
            .ok_or_else(|| "No result in MCP tools/list response".to_string())?;
        return tools_activation_from_response(server_name, listed.response, None);
    }

    if !matches!(transport, McpTransport::Http) {
        let responses = send_mcp_transport_sequence(
            transport,
            vec![
                McpRequest::initialize(),
                McpRequest::initialized_notification(),
                McpRequest::list_tools(),
            ],
        )
        .await?;
        if !sequence_advertises_tools(&responses) {
            return Ok(McpActivation {
                tools: Vec::new(),
                session_id: None,
            });
        }
        let listed = responses
            .into_iter()
            .last()
            .ok_or_else(|| "No result in MCP tools/list response".to_string())?;
        return tools_activation_from_response(server_name, listed.response, None);
    }

    let initialized = send_mcp_request(
        url,
        transport,
        headers,
        initial_session_id,
        McpRequest::initialize(),
    )
    .await?;
    let mut session_id = initialized.session_id;
    let advertises_tools = super::helpers::initialize_advertises_tools(&initialized.response);
    let _ = send_mcp_request(
        url,
        transport,
        headers,
        session_id.as_deref(),
        McpRequest::initialized_notification(),
    )
    .await;
    if !advertises_tools {
        return Ok(McpActivation {
            tools: Vec::new(),
            session_id,
        });
    }
    let listed = send_mcp_request(
        url,
        transport,
        headers,
        session_id.as_deref(),
        McpRequest::list_tools(),
    )
    .await?;
    if listed.session_id.is_some() {
        session_id = listed.session_id.clone();
    }
    tools_activation_from_response(server_name, listed.response, session_id)
}

fn tools_activation_from_response(
    server_name: &str,
    response: McpResponse,
    session_id: Option<String>,
) -> Result<McpActivation, String> {
    if let Some(error) = response.error {
        return Err(format!(
            "MCP error: {} (code {})",
            error.message, error.code
        ));
    }
    let result: ListToolsResult = response
        .result
        .ok_or_else(|| "No result in MCP tools/list response".to_string())
        .and_then(|value| {
            serde_json::from_value(value).map_err(|e| format!("Invalid MCP tools/list result: {e}"))
        })?;
    let tools = result
        .tools
        .into_iter()
        .map(|tool| McpTool {
            name: tool.name,
            description: tool.description,
            input_schema: tool.input_schema,
            requires_approval: tool
                .annotations
                .as_ref()
                .map(|annotations| annotations.destructive_hint)
                .unwrap_or(false),
        })
        .inspect(|tool| {
            tracing::debug!(server = server_name, tool = tool.name, "Loaded MCP tool");
        })
        .collect();
    Ok(McpActivation { tools, session_id })
}
