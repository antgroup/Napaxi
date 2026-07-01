# Tools Subsystem

The tools subsystem under `crates/core/src/tools/` owns everything about
**how a turn discovers, admits, executes, and records tool calls**. It spans the
tool registry boundary for host-provided tools, the LLM tool loop, and the
built-in tool groups (shell, file, web, http, media, memory, skill, MCP).

If you are adding a built-in tool, changing how tool descriptors are gathered or
admitted, or touching the tool execution loop, this is the area, and this doc is
the map.

The `tools/` directory is declared as several sibling modules in
`crates/core/src/lib.rs` (via `#[path = ...]`): `tool_registry`, `tool_loop`,
`builtin_tools`, `file_tools`, `memory_tools`, `web_search_tool`, `http_tool`,
`browser_tools`, `media_tools`, `web_fetch_tool`, and `skill_tools`.

## Registry (`tools/registry/`)

The tool boundary for host-provided custom tools. `ToolRegistry`
(`registry/registry.rs`) is the central object; the rest of the directory
supports it:

- `types.rs` — `ToolDescriptor`, `ToolEffect`, `ToolExecutionContext`,
  `ToolRequestDispatcher`, and the request-bridge type.
- `prepare.rs` — schema-driven argument preparation and validation
  (`prepare_tool_arguments`, `normalize_parameters_schema`).
- `rate_limit.rs` — per-tool sliding-window rate limiter and per-tool policy
  (`check_tool_rate_limit`).
- `redact.rs` — secret redaction for arguments and output, plus truncation
  (`redact_tool_arguments_json`, `sanitize_tool_output`).
- `pending.rs` — pending request tables and global request-id routing
  (`resolve_tool_execution`).
- `bridge.rs` — host tool dispatch over a request bridge.

## Tool Loop (`tools/loop/`, entry `tools/loop.rs`)

The Napaxi-owned LLM tool loop: the LLM <-> tool execution cycle that the turn
module drives during `ExecuteToolLoop`. Split into `descriptors.rs` (gathering
the active tool descriptors for a config), `execution.rs` (executing the tool
calls a turn produced, draining interjections, enforcing the tool-call limit),
`limits.rs`, `runtime.rs`, `trace.rs`, and `types.rs`.

## Built-in Tools (`tools/builtin/`)

Composition of the built-in tool groups, exposing `builtin_tools_and_handler`
and `mcp_tools_and_handler`:

- `handlers.rs` — per-group handler adapters (skill, memory, file, web, http,
  media).
- `mcp.rs` — the MCP server-management tool group.
- `shell.rs` / `shell_policy.rs` / `shell_safe.rs` / `shell_inject.rs` /
  `shell_util.rs` — the shell tool descriptor and dispatch, plus the shell
  security stack: the hard-gate/mode policy decision, the known-safe
  allow-list with per-argument validation, and shell-injection / data-piping
  detection.

## Other Tool Modules

- `file/` — read/write/list/apply-patch file tools, with descriptors, path
  handling, and progress reporting.
- `memory.rs` — memory tools over the workspace memory store.
- `web_search.rs`, `web_fetch.rs`, `http.rs` — outbound network tools.
- `browser.rs`, `media.rs` — browser automation and media tools.
- `skill.rs` — skill invocation tools.

## Where to Make a Change

- New built-in tool: add a group under `tools/builtin/` and wire it into
  `builtin_tools_and_handler`; register descriptors so the loop can gather them.
- New host-facing tool boundary behavior: change `tools/registry/`.
- Changing execution, limits, or tracing of the tool cycle: change
  `tools/loop/`.
- Security gates for shell or tool admission are core gates; keep them in
  `tools/builtin/shell_*` and the registry, and do not bypass them from adapter
  or demo code.
