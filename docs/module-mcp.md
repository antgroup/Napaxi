# MCP Subsystem

The MCP module (`crates/core/src/mcp/`) owns **file-backed MCP (Model Context
Protocol) server state** for the standalone mobile SDK runtime: registering MCP
servers, listing and calling their tools, OAuth flows, and the request
transports. Its public surface is preserved through re-exports in `mod.rs`.

If you are adding MCP transport support, changing how remote tools are loaded or
prefixed, or touching the MCP OAuth flow, this is the module.

## Server Lifecycle

- `types.rs` — public DTOs: `McpServer`, `McpTool`, OAuth types, transport
  descriptors.
- `servers.rs` — add / remove / list / activate / deactivate servers.
- `store.rs` — catalog persistence (per-account scoped; see
  `LEGACY_DEFAULT_ACCOUNT_ID` for the pre-scoping default).
- `handles.rs` — engine-handle wrappers used by the bridge.

## Tools

- `tools.rs` — `list_tools`, `tool_descriptors`, `call_tool`,
  `load_remote_tools`.
- `tool_descriptor.rs` — tool-name prefixing and the JSON descriptor shape that
  lets remote MCP tools flow through the same tool registry as built-ins.

## OAuth

- `oauth_flow.rs` — high-level `start_oauth` / `finish_oauth`.
- `oauth.rs` — low-level OAuth metadata discovery, PKCE, and token exchange.

## Transport and Helpers

- `transport.rs` — HTTP / SSE / stdio / unix request transports.
- `headers.rs` — effective and dynamic header resolution.
- `helpers.rs` — JSON formatters, header parsing, transport hinting, JSON-RPC
  envelopes, error-body sanitization, and safe truncation.
- `security.rs` — MCP-specific security checks (e.g. stdio env safety and
  exfiltration guards).

## Where to Make a Change

- New transport: extend `transport.rs` and the transport hints in `helpers.rs`.
- Changing how remote tools appear to the model: edit `tool_descriptor.rs` and
  `tools.rs`; the prefixing keeps remote tool names from colliding with
  built-ins.
- MCP is admitted through the same core policy chain as other tools; security
  gates belong in `security.rs` and the core tool boundary, not in adapter code.
