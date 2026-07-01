use std::collections::{HashMap, HashSet};

use reqwest::header::{COOKIE, SET_COOKIE};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use crate::net::UrlPolicy;

use super::{
    McpHttpResponse, McpRequest, McpResponse, McpTransport, safe_truncate, sanitize_error_body,
};

/// Environment variable names that must never be forwarded to MCP stdio child
/// processes. These can hijack the child's loader, shell startup, or config
/// resolution to execute attacker-controlled code.
const DANGEROUS_STDIO_ENV_KEYS: &[&str] = &[
    "ANSIBLE_CONFIG",
    "BASH_ENV",
    "CDPATH",
    "DYLD_FALLBACK_FRAMEWORK_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH",
    "DYLD_FRAMEWORK_PATH",
    "DYLD_INSERT_LIBRARIES",
    "DYLD_LIBRARY_PATH",
    "DYLD_VERSIONED_FRAMEWORK_PATH",
    "DYLD_VERSIONED_LIBRARY_PATH",
    "ENV",
    "GCONV_PATH",
    "GIT_ASKPASS",
    "HOSTALIASES",
    "JAVA_TOOL_OPTIONS",
    "LD_AUDIT",
    "LD_LIBRARY_PATH",
    "LD_PRELOAD",
    "NODE_OPTIONS",
    "PERL5OPT",
    "PERLLIB",
    "PYTHONHOME",
    "PYTHONPATH",
    "PYTHONSTARTUP",
    "RES_OPTIONS",
    "RUBYLIB",
    "RUBYOPT",
    "SSH_ASKPASS",
    "TF_CLI_CONFIG_FILE",
    "_JAVA_OPTIONS",
];

fn filter_dangerous_env(env: &HashMap<String, String>) -> HashMap<String, String> {
    let blocked: HashSet<&str> = DANGEROUS_STDIO_ENV_KEYS.iter().copied().collect();
    env.iter()
        .filter(|(key, _)| !blocked.contains(key.to_ascii_uppercase().as_str()))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect()
}

/// Validates an outbound MCP URL against the SSRF guards and returns a client
/// builder with redirects disabled and DNS pinned to the vetted addresses.
///
/// MCP HTTP/SSE servers are LLM-reachable (`mcp_server_add` is a model-callable
/// tool), so an unvetted URL could target cloud metadata / internal services and
/// echo the response back to the model. The caller finalizes the builder (e.g.
/// adds a request timeout — omitted for the long-lived SSE stream).
async fn guarded_client_builder(
    url: &str,
) -> Result<(reqwest::ClientBuilder, reqwest::Url), String> {
    // Local HTTP MCP servers are a legitimate pattern, so loopback is allowed
    // (mirroring the OAuth module). Link-local metadata and private ranges stay
    // blocked, and DNS is pinned so the vetted host can't rebind post-check.
    let policy = UrlPolicy::allow_loopback();
    let parsed = policy.validate_url(url)?;
    let addrs = policy.validate_dns_target(&parsed).await?;
    let host = parsed
        .host_str()
        .ok_or_else(|| "URL missing host".to_string())?
        .to_string();
    let builder = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .resolve_to_addrs(&host, &addrs);
    Ok((builder, parsed))
}

pub(super) async fn send_mcp_request(
    url: &str,
    transport: &McpTransport,
    headers: &HashMap<String, String>,
    session_id: Option<&str>,
    request: McpRequest,
) -> Result<McpHttpResponse, String> {
    match transport {
        McpTransport::Http => send_mcp_http_request(url, headers, session_id, request).await,
        McpTransport::Sse { sse_path } => {
            let responses = send_mcp_sse_sequence(url, sse_path, headers, vec![request]).await?;
            responses
                .into_iter()
                .last()
                .ok_or_else(|| "No MCP SSE response".to_string())
        }
        McpTransport::Stdio { command, args, env } => {
            send_mcp_stdio_request(command, args, env, request).await
        }
        McpTransport::Unix { socket_path } => send_mcp_unix_request(socket_path, request).await,
    }
}

async fn send_mcp_http_request(
    url: &str,
    headers: &HashMap<String, String>,
    session_id: Option<&str>,
    request: McpRequest,
) -> Result<McpHttpResponse, String> {
    let (builder, _) = guarded_client_builder(url).await?;
    let client = builder
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| format!("Failed to create MCP HTTP client: {e}"))?;
    let mut builder = client
        .post(url)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json, text/event-stream")
        .json(&request);
    for (key, value) in headers {
        builder = builder.header(key.as_str(), value.as_str());
    }
    if let Some(session_id) = session_id
        && !session_id.trim().is_empty()
    {
        builder = builder.header("Mcp-Session-Id", session_id);
    }
    let response = builder
        .send()
        .await
        .map_err(|e| format!("MCP HTTP request failed: {e}"))?;
    let status = response.status();
    let next_session_id = response
        .headers()
        .get("Mcp-Session-Id")
        .and_then(|value| value.to_str().ok())
        .map(str::to_string)
        .or_else(|| session_id.map(str::to_string));
    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        return Err(format!(
            "MCP server returned status {status}: {}",
            sanitize_error_body(&body)
        ));
    }
    if status == reqwest::StatusCode::ACCEPTED {
        return Ok(McpHttpResponse {
            response: McpResponse {
                jsonrpc: "2.0".to_string(),
                id: request.id.map(serde_json::Value::from),
                result: None,
                error: None,
            },
            session_id: next_session_id,
        });
    }
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .to_string();
    if content_type.contains("text/event-stream") {
        parse_sse_response(response, request.id)
            .await
            .map(|response| McpHttpResponse {
                response,
                session_id: next_session_id,
            })
    } else {
        response
            .json::<McpResponse>()
            .await
            .map(|response| McpHttpResponse {
                response,
                session_id: next_session_id,
            })
            .map_err(|e| format!("Failed to parse MCP response: {e}"))
    }
}

pub(super) async fn send_mcp_sse_sequence(
    base_url: &str,
    sse_path: &str,
    headers: &HashMap<String, String>,
    requests: Vec<McpRequest>,
) -> Result<Vec<McpHttpResponse>, String> {
    use futures::StreamExt;

    let sse_url = join_base_path(base_url, sse_path);
    // Guard the long-lived GET stream; no request timeout (the stream is meant
    // to stay open). Redirects are disabled and DNS is pinned by the helper.
    let (get_client_builder, _) = guarded_client_builder(&sse_url).await?;
    let client = get_client_builder
        .build()
        .map_err(|e| format!("Failed to create MCP SSE client: {e}"))?;
    let mut get_builder = client.get(&sse_url).header("Accept", "text/event-stream");
    for (key, value) in headers {
        get_builder = get_builder.header(key.as_str(), value.as_str());
    }
    let response = get_builder
        .send()
        .await
        .map_err(|e| format!("MCP SSE connect failed: {e}"))?;
    let status = response.status();
    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        return Err(format!(
            "MCP SSE endpoint returned status {status}: {}",
            safe_truncate(&sanitize_error_body(&body), 500)
        ));
    }
    let sse_cookie_header = merged_sse_cookie_header(headers, response.headers());

    let mut stream = response.bytes_stream().boxed();
    let mut reader = SseEventReader::default();
    let messages_url = loop {
        let Some((event, data)) = reader.next(&mut stream).await? else {
            return Err("MCP SSE stream ended before endpoint event".to_string());
        };
        if event.as_deref() == Some("endpoint") {
            break resolve_sse_endpoint(base_url, &data);
        }
    };

    // The endpoint event is server-controlled, so the POST target is a fresh
    // SSRF surface: re-validate it and use a client whose DNS is pinned to that
    // host (the GET client only pinned the SSE host).
    let (messages_client_builder, _) = guarded_client_builder(&messages_url).await?;
    let messages_client = messages_client_builder
        .build()
        .map_err(|e| format!("Failed to create MCP SSE messages client: {e}"))?;

    let mut responses = Vec::new();
    for request in requests {
        post_mcp_sse_request(
            &messages_client,
            &messages_url,
            headers,
            sse_cookie_header.as_deref(),
            &request,
        )
        .await?;
        let Some(request_id) = request.id else {
            responses.push(McpHttpResponse {
                response: McpResponse {
                    jsonrpc: "2.0".to_string(),
                    id: None,
                    result: None,
                    error: None,
                },
                session_id: None,
            });
            continue;
        };

        let response = loop {
            let Some((event, data)) = reader.next(&mut stream).await? else {
                return Err(format!(
                    "MCP SSE stream ended before response to request {request_id}"
                ));
            };
            if event.as_deref() == Some("endpoint") || data.trim().is_empty() {
                continue;
            }
            let parsed: McpResponse =
                serde_json::from_str(&data).map_err(|e| format!("Invalid MCP SSE JSON: {e}"))?;
            if mcp_response_id(&parsed) == Some(request_id) {
                break parsed;
            }
        };
        responses.push(McpHttpResponse {
            response,
            session_id: None,
        });
    }
    Ok(responses)
}

async fn post_mcp_sse_request(
    client: &reqwest::Client,
    messages_url: &str,
    headers: &HashMap<String, String>,
    cookie_header: Option<&str>,
    request: &McpRequest,
) -> Result<(), String> {
    let mut builder = client
        .post(messages_url)
        .timeout(std::time::Duration::from_secs(30))
        .header("Content-Type", "application/json")
        .json(request);
    for (key, value) in headers {
        if key.eq_ignore_ascii_case("cookie") && cookie_header.is_some() {
            continue;
        }
        builder = builder.header(key.as_str(), value.as_str());
    }
    if let Some(cookie) = cookie_header.filter(|cookie| !cookie.trim().is_empty()) {
        builder = builder.header(COOKIE, cookie);
    }
    let response = builder
        .send()
        .await
        .map_err(|e| format!("MCP SSE POST failed: {e}"))?;
    if response.status().is_success() {
        return Ok(());
    }
    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    Err(format!(
        "MCP SSE POST returned status {status}: {}",
        safe_truncate(&sanitize_error_body(&body), 500)
    ))
}

fn merged_sse_cookie_header(
    request_headers: &HashMap<String, String>,
    response_headers: &reqwest::header::HeaderMap,
) -> Option<String> {
    merge_cookie_headers(
        request_headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case("cookie"))
            .map(|(_, value)| value.as_str()),
        &set_cookie_pairs(response_headers),
    )
}

fn set_cookie_pairs(headers: &reqwest::header::HeaderMap) -> Vec<String> {
    headers
        .get_all(SET_COOKIE)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .filter_map(|value| value.split(';').next())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .collect()
}

fn merge_cookie_headers(upper_cookie: Option<&str>, sse_cookies: &[String]) -> Option<String> {
    let upper_pairs = upper_cookie.map(cookie_pairs).unwrap_or_default();
    let upper_names: HashSet<String> = upper_pairs
        .iter()
        .filter_map(|pair| cookie_name(pair))
        .map(|name| name.to_ascii_lowercase())
        .collect();

    let mut pairs: Vec<String> = sse_cookies
        .iter()
        .map(|pair| pair.trim())
        .filter(|pair| !pair.is_empty())
        .filter(|pair| {
            cookie_name(pair)
                .map(|name| !upper_names.contains(&name.to_ascii_lowercase()))
                .unwrap_or(true)
        })
        .map(str::to_string)
        .collect();
    pairs.extend(upper_pairs);

    if pairs.is_empty() {
        None
    } else {
        Some(pairs.join("; "))
    }
}

fn cookie_pairs(header: &str) -> Vec<String> {
    header
        .split(';')
        .map(str::trim)
        .filter(|pair| !pair.is_empty())
        .map(str::to_string)
        .collect()
}

fn cookie_name(pair: &str) -> Option<&str> {
    pair.split_once('=')
        .map(|(name, _)| name.trim())
        .filter(|name| !name.is_empty())
}

#[derive(Default)]
struct SseEventReader {
    buffer: String,
    event: Option<String>,
    data_lines: Vec<String>,
}

impl SseEventReader {
    async fn next(
        &mut self,
        stream: &mut futures::stream::BoxStream<'_, Result<bytes::Bytes, reqwest::Error>>,
    ) -> Result<Option<(Option<String>, String)>, String> {
        while let Some(chunk) = futures::StreamExt::next(stream).await {
            let chunk = chunk.map_err(|e| format!("Failed to read MCP SSE chunk: {e}"))?;
            self.buffer.push_str(&String::from_utf8_lossy(&chunk));
            while let Some(index) = self.buffer.find('\n') {
                let line = self.buffer[..index].trim_end_matches('\r').to_string();
                self.buffer.drain(..=index);
                if line.is_empty() {
                    if !self.data_lines.is_empty() {
                        let event = self.event.take();
                        let data = self.data_lines.join("\n");
                        self.data_lines.clear();
                        return Ok(Some((event, data)));
                    }
                    self.event = None;
                    continue;
                }
                if let Some(value) = line.strip_prefix("event:") {
                    self.event = Some(value.trim().to_string());
                } else if let Some(value) = line.strip_prefix("data:") {
                    self.data_lines.push(value.trim_start().to_string());
                }
            }
        }
        if self.data_lines.is_empty() {
            Ok(None)
        } else {
            let event = self.event.take();
            let data = self.data_lines.join("\n");
            self.data_lines.clear();
            Ok(Some((event, data)))
        }
    }
}

fn join_base_path(base: &str, path: &str) -> String {
    if path.starts_with("http://") || path.starts_with("https://") {
        return path.to_string();
    }
    format!("{}{}", base.trim_end_matches('/'), path)
}

fn resolve_sse_endpoint(base_url: &str, endpoint: &str) -> String {
    let endpoint = endpoint.trim();
    if endpoint.starts_with("http://") || endpoint.starts_with("https://") {
        endpoint.to_string()
    } else {
        join_base_path(base_url, endpoint)
    }
}

pub(super) async fn send_mcp_transport_sequence(
    transport: &McpTransport,
    requests: Vec<McpRequest>,
) -> Result<Vec<McpHttpResponse>, String> {
    match transport {
        McpTransport::Http | McpTransport::Sse { .. } => {
            Err("MCP HTTP sequence requires URL and headers".to_string())
        }
        McpTransport::Stdio { command, args, env } => {
            send_mcp_stdio_sequence(command, args, env, requests).await
        }
        McpTransport::Unix { socket_path } => send_mcp_unix_sequence(socket_path, requests).await,
    }
}

async fn send_mcp_stdio_request(
    command: &str,
    args: &[String],
    env: &HashMap<String, String>,
    request: McpRequest,
) -> Result<McpHttpResponse, String> {
    if command.trim().is_empty() {
        return Err("MCP stdio command is required".to_string());
    }
    if let Some(issue) = super::security::validate_stdio_config(command, args) {
        return Err(issue);
    }
    let safe_env = filter_dangerous_env(env);
    let mut child = tokio::process::Command::new(command)
        .args(args)
        .envs(&safe_env)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to spawn MCP stdio server: {e}"))?;
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| "Failed to open MCP stdio stdin".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "Failed to open MCP stdio stdout".to_string())?;
    write_jsonrpc_line(&mut stdin, &request).await?;
    drop(stdin);

    let response = if request.id.is_some() {
        read_jsonrpc_response(BufReader::new(stdout), request.id).await?
    } else {
        McpResponse {
            jsonrpc: "2.0".to_string(),
            id: None,
            result: None,
            error: None,
        }
    };
    let _ = child.wait().await;
    Ok(McpHttpResponse {
        response,
        session_id: None,
    })
}

pub(super) async fn send_mcp_stdio_sequence(
    command: &str,
    args: &[String],
    env: &HashMap<String, String>,
    requests: Vec<McpRequest>,
) -> Result<Vec<McpHttpResponse>, String> {
    if command.trim().is_empty() {
        return Err("MCP stdio command is required".to_string());
    }
    if let Some(issue) = super::security::validate_stdio_config(command, args) {
        return Err(issue);
    }
    let safe_env = filter_dangerous_env(env);
    let mut child = tokio::process::Command::new(command)
        .args(args)
        .envs(&safe_env)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to spawn MCP stdio server: {e}"))?;
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| "Failed to open MCP stdio stdin".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "Failed to open MCP stdio stdout".to_string())?;
    let responses = send_jsonrpc_sequence(&mut stdin, BufReader::new(stdout), &requests).await;
    drop(stdin);
    let _ = child.wait().await;
    responses
}

#[cfg(unix)]
async fn send_mcp_unix_request(
    socket_path: &str,
    request: McpRequest,
) -> Result<McpHttpResponse, String> {
    if socket_path.trim().is_empty() {
        return Err("MCP unix socket path is required".to_string());
    }
    let stream = tokio::net::UnixStream::connect(socket_path)
        .await
        .map_err(|e| format!("Failed to connect MCP unix socket: {e}"))?;
    let (reader, mut writer) = stream.into_split();
    write_jsonrpc_line(&mut writer, &request).await?;
    writer
        .shutdown()
        .await
        .map_err(|e| format!("Failed to close MCP unix writer: {e}"))?;

    let response = if request.id.is_some() {
        read_jsonrpc_response(BufReader::new(reader), request.id).await?
    } else {
        McpResponse {
            jsonrpc: "2.0".to_string(),
            id: None,
            result: None,
            error: None,
        }
    };
    Ok(McpHttpResponse {
        response,
        session_id: None,
    })
}

#[cfg(unix)]
async fn send_mcp_unix_sequence(
    socket_path: &str,
    requests: Vec<McpRequest>,
) -> Result<Vec<McpHttpResponse>, String> {
    if socket_path.trim().is_empty() {
        return Err("MCP unix socket path is required".to_string());
    }
    let stream = tokio::net::UnixStream::connect(socket_path)
        .await
        .map_err(|e| format!("Failed to connect MCP unix socket: {e}"))?;
    let (reader, mut writer) = stream.into_split();
    send_jsonrpc_sequence(&mut writer, BufReader::new(reader), &requests).await
}

#[cfg(not(unix))]
async fn send_mcp_unix_request(
    _socket_path: &str,
    _request: McpRequest,
) -> Result<McpHttpResponse, String> {
    Err("MCP unix transport is not supported on this platform".to_string())
}

#[cfg(not(unix))]
async fn send_mcp_unix_sequence(
    _socket_path: &str,
    _requests: Vec<McpRequest>,
) -> Result<Vec<McpHttpResponse>, String> {
    Err("MCP unix transport is not supported on this platform".to_string())
}

async fn send_jsonrpc_sequence<W, R>(
    writer: &mut W,
    reader: BufReader<R>,
    requests: &[McpRequest],
) -> Result<Vec<McpHttpResponse>, String>
where
    W: tokio::io::AsyncWrite + Unpin,
    R: tokio::io::AsyncRead + Unpin,
{
    for request in requests {
        write_jsonrpc_line(writer, request).await?;
    }
    writer
        .flush()
        .await
        .map_err(|e| format!("Failed to flush MCP requests: {e}"))?;

    let expected_ids: Vec<Option<u64>> = requests
        .iter()
        .filter_map(|request| request.id)
        .map(Some)
        .collect();
    let responses = read_jsonrpc_responses(reader, &expected_ids).await?;
    Ok(responses
        .into_iter()
        .map(|response| McpHttpResponse {
            response,
            session_id: None,
        })
        .collect())
}

async fn write_jsonrpc_line<W>(writer: &mut W, request: &McpRequest) -> Result<(), String>
where
    W: tokio::io::AsyncWrite + Unpin,
{
    let line =
        serde_json::to_string(request).map_err(|e| format!("Failed to encode MCP request: {e}"))?;
    writer
        .write_all(line.as_bytes())
        .await
        .map_err(|e| format!("Failed to write MCP request: {e}"))?;
    writer
        .write_all(b"\n")
        .await
        .map_err(|e| format!("Failed to write MCP request newline: {e}"))?;
    writer
        .flush()
        .await
        .map_err(|e| format!("Failed to flush MCP request: {e}"))
}

async fn read_jsonrpc_responses<R>(
    mut reader: BufReader<R>,
    expected_ids: &[Option<u64>],
) -> Result<Vec<McpResponse>, String>
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut responses = Vec::new();
    let mut line = String::new();
    while responses.len() < expected_ids.len() {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .await
            .map_err(|e| format!("Failed to read MCP response: {e}"))?;
        if bytes == 0 {
            return Err("No matching MCP response found".to_string());
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let response: McpResponse =
            serde_json::from_str(trimmed).map_err(|e| format!("Invalid MCP JSON: {e}"))?;
        if expected_ids.contains(&mcp_response_id(&response)) {
            responses.push(response);
        }
    }
    Ok(responses)
}

async fn read_jsonrpc_response<R>(
    mut reader: BufReader<R>,
    request_id: Option<u64>,
) -> Result<McpResponse, String>
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut line = String::new();
    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .await
            .map_err(|e| format!("Failed to read MCP response: {e}"))?;
        if bytes == 0 {
            return Err("No matching MCP response found".to_string());
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let response: McpResponse =
            serde_json::from_str(trimmed).map_err(|e| format!("Invalid MCP JSON: {e}"))?;
        if mcp_response_id(&response) == request_id {
            return Ok(response);
        }
    }
}

async fn parse_sse_response(
    response: reqwest::Response,
    request_id: Option<u64>,
) -> Result<McpResponse, String> {
    use futures::StreamExt;

    let mut stream = response.bytes_stream();
    let mut buffer = String::new();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| format!("Failed to read MCP SSE chunk: {e}"))?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));
        while let Some(index) = buffer.find('\n') {
            let line = buffer[..index].trim_end_matches('\r').to_string();
            buffer.drain(..=index);
            if let Some(response) = parse_sse_line(&line, request_id)? {
                return Ok(response);
            }
        }
    }
    if let Some(response) = parse_sse_line(buffer.trim(), request_id)? {
        return Ok(response);
    }
    Err("No matching MCP SSE response found".to_string())
}

fn parse_sse_line(line: &str, request_id: Option<u64>) -> Result<Option<McpResponse>, String> {
    let Some(json) = line.strip_prefix("data: ") else {
        return Ok(None);
    };
    let response: McpResponse =
        serde_json::from_str(json).map_err(|e| format!("Invalid MCP SSE JSON: {e}"))?;
    if mcp_response_id(&response) == request_id {
        Ok(Some(response))
    } else {
        Ok(None)
    }
}

fn mcp_response_id(response: &McpResponse) -> Option<u64> {
    response.id.as_ref().and_then(|id| match id {
        serde_json::Value::Number(number) => number.as_u64(),
        serde_json::Value::String(value) => value.parse::<u64>().ok(),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::header::{HeaderMap, HeaderValue};

    #[test]
    fn merges_sse_set_cookie_with_request_cookie() {
        let mut response_headers = HeaderMap::new();
        response_headers.append(
            SET_COOKIE,
            HeaderValue::from_static("mcp_session=sse-1; Path=/; HttpOnly"),
        );
        response_headers.append(SET_COOKIE, HeaderValue::from_static("route=blue; Path=/"));
        let mut request_headers = HashMap::new();
        request_headers.insert(
            "Cookie".to_string(),
            "iam=fresh; mcp_session=caller-wins".to_string(),
        );

        let cookie = merged_sse_cookie_header(&request_headers, &response_headers).unwrap();

        assert!(cookie.contains("iam=fresh"));
        assert!(cookie.contains("mcp_session=caller-wins"));
        assert!(cookie.contains("route=blue"));
        assert!(!cookie.contains("mcp_session=sse-1"));
    }

    #[test]
    fn uses_sse_cookie_when_request_cookie_absent() {
        let mut response_headers = HeaderMap::new();
        response_headers.append(
            SET_COOKIE,
            HeaderValue::from_static("mcp_session=sse-1; Path=/; HttpOnly"),
        );

        let cookie = merged_sse_cookie_header(&HashMap::new(), &response_headers).unwrap();

        assert_eq!(cookie, "mcp_session=sse-1");
    }

    #[test]
    fn filters_dangerous_env_vars() {
        let mut env = HashMap::new();
        env.insert("PATH".to_string(), "/usr/bin".to_string());
        env.insert("HOME".to_string(), "/home/user".to_string());
        env.insert("LD_PRELOAD".to_string(), "/tmp/evil.so".to_string());
        env.insert(
            "NODE_OPTIONS".to_string(),
            "--require=./evil.js".to_string(),
        );
        env.insert("BASH_ENV".to_string(), "/tmp/pwn.sh".to_string());
        env.insert("GITHUB_TOKEN".to_string(), "ghp_secret".to_string());
        env.insert("ANSIBLE_CONFIG".to_string(), "/tmp/evil.cfg".to_string());
        env.insert("TF_CLI_CONFIG_FILE".to_string(), "/tmp/evil.rc".to_string());
        env.insert("LD_LIBRARY_PATH".to_string(), "/tmp/evil".to_string());
        env.insert("PYTHONPATH".to_string(), "/tmp/evil".to_string());
        env.insert(
            "JAVA_TOOL_OPTIONS".to_string(),
            "-javaagent:/tmp/evil.jar".to_string(),
        );

        let filtered = filter_dangerous_env(&env);

        assert!(filtered.contains_key("PATH"));
        assert!(filtered.contains_key("HOME"));
        assert!(filtered.contains_key("GITHUB_TOKEN"));
        assert!(!filtered.contains_key("LD_PRELOAD"));
        assert!(!filtered.contains_key("NODE_OPTIONS"));
        assert!(!filtered.contains_key("BASH_ENV"));
        assert!(!filtered.contains_key("ANSIBLE_CONFIG"));
        assert!(!filtered.contains_key("TF_CLI_CONFIG_FILE"));
        assert!(!filtered.contains_key("LD_LIBRARY_PATH"));
        assert!(!filtered.contains_key("PYTHONPATH"));
        assert!(!filtered.contains_key("JAVA_TOOL_OPTIONS"));
    }

    #[test]
    fn filters_env_vars_case_insensitively() {
        let mut env = HashMap::new();
        env.insert("ld_preload".to_string(), "/tmp/evil.so".to_string());
        env.insert(
            "Node_Options".to_string(),
            "--require=./evil.js".to_string(),
        );
        env.insert("PATH".to_string(), "/usr/bin".to_string());

        let filtered = filter_dangerous_env(&env);

        assert!(filtered.contains_key("PATH"));
        assert!(!filtered.contains_key("ld_preload"));
        assert!(!filtered.contains_key("Node_Options"));
    }
}
