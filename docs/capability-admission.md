# Capability Admission

This document describes how capability admission works in Napaxi, where the
gates live, and how to add new ones safely.

## Concept

Capabilities are first-class extension points in the SDK. Every LLM
provider, built-in tool, MCP tool, and platform tool is backed by a
capability definition that names:

- a stable `napaxi.*` id
- a kind (`llm_provider`, `tool`, `platform_tool`, `mcp`, `policy`,
  `service`)
- a risk level (low/medium/high/critical)
- an activation mode (`always`, `config`, `host`, `policy`)

A capability moves through three states:

1. **Registered** — compiled into the SDK binary
2. **Available** — the current platform + host capability profile can
   satisfy the capability's requirements
3. **Enabled** — runtime config selected it for the current engine

A capability that is registered but disabled (or available but not
enabled) does not participate in tool descriptors, provider routing, or
invocation.

## Admission gates

Five gate kinds run through the central policy chain in
`crates/core/src/capabilities/mod.rs`. The first three run inside the agent
loop; `AgentEngine` gates engine selection; `Service` gates the entry surface
of a Service-kind capability.

| Gate kind     | Called from                                          | When                                         |
| ------------- | ---------------------------------------------------- | -------------------------------------------- |
| `Descriptor`  | `tools/loop/descriptors.rs`, `mcp/tools.rs`          | Building the tool list shown to the LLM      |
| `Invocation`  | `tools/loop/execution.rs`, `mcp/tools.rs`            | Just before executing a tool the LLM picked  |
| `Provider`    | `capabilities::resolve_llm_provider_for_config`      | Just before opening an LLM provider session  |
| `AgentEngine` | agent-engine routing                                 | Selecting which agent engine handles a turn  |
| `Service`     | `a2a/mod.rs`, `automation/runner.rs`, `context/mod.rs` | A Service capability's entry surface is hit  |

The `Service` gate covers all four Service-kind capabilities:
`napaxi.a2a.local`, `napaxi.a2a.deeplink`, `napaxi.service.automation`, and
`napaxi.service.context_engine`. It gates the **intake and execution** entry
surfaces — accepting an A2A peer invite or deep link, running a received task,
running an automation job, and context compaction/status. Read-only operations
(listing peers, listing tasks, querying history) are intentionally *not* gated:
denying reads would hide data the user already owns. The admission trace
therefore covers service entry + execution, not every read/list API call. If a
full operation audit is needed, instrument at a layer above admission.

Each gate constructs a `CapabilityAdmission { kind, subject, capability_id }`
and runs the registered policy chain. **The first `Deny` short-circuits
the chain.**

```text
Tool/provider/MCP call
        │
        ▼
  ┌──────────────────────┐
  │  require_enabled?    │  ◄── host/config declarative check
  └──────────┬───────────┘
             │ ok
             ▼
  ┌──────────────────────┐
  │  policy chain        │  ◄── per-call policy hooks
  │  (admit_typed)       │
  └──────────┬───────────┘
             │ ok       │ deny
             ▼          ▼
        execute     CapabilityError::Denied
```

## Adding a policy hook

Hooks live in process-global state. Use `register_policy_hook` from
`napaxi_core::api::capability` and **bind the returned `PolicyHookGuard`**
to control lifetime:

```rust
use std::sync::Arc;
use napaxi_core::api::capability::{
    register_policy_hook,
    CapabilityAdmissionDecision,
    CapabilityAdmissionKind,
};

let guard = register_policy_hook(Arc::new(|admission| {
    if matches!(admission.kind, CapabilityAdmissionKind::Provider)
        && admission.subject.starts_with("external_")
    {
        CapabilityAdmissionDecision::Deny("external providers blocked in regulated mode".into())
    } else {
        CapabilityAdmissionDecision::Allow
    }
}));

// The hook is removed when `guard` is dropped. Call
// `guard.deregister()` to remove it explicitly.
```

> This example is also a compile-checked `no_run` doctest on
> `register_policy_hook` (in `crates/core/src/capabilities/hooks.rs`);
> `cargo test --doc` verifies it against the live API, so it cannot silently rot
> if the signature changes.

Hooks are evaluated in registration order. Order matters for trace
clarity but not for the final decision — any Deny wins.

## Admission trace

`admit_typed` records every decision into a ring buffer (cap 100). Recording
is **scoped per engine**: when an engine operation is running (its turn,
service intake, or task execution is wrapped in `with_admission_sink`), the
decision lands in that engine's own buffer. Admissions outside any engine
scope fall back to a process-global buffer.

`EngineHandle::admission_trace()` returns this engine's own decisions (with a
stale-handle check), so two engines on the same process no longer share one
history:

```rust
let trace = engine_handle.admission_trace()?; // Vec<AdmissionDecisionRecord>
```

The free function `recent_admission_decisions()` returns the process-global
fallback buffer — decisions that were recorded outside any engine scope (e.g.
in a spawned sub-task that escaped the scope). Adapter UIs can render either:

```rust
use napaxi_core::api::capability::recent_admission_decisions;

for record in recent_admission_decisions() {
    println!(
        "[{}] {} {:?} {} → {} ({})",
        record.recorded_at,
        record.capability_id,
        record.kind,
        record.subject,
        if record.allowed { "allow" } else { "deny" },
        record.reason,
    );
}
```

Policy hooks remain process-global (a host installs its policy chain once per
process); it is the *trace* that is now per-engine.

## Adding a new capability

1. Define the capability in `crates/core/src/capabilities/mod.rs::definitions`
   with a stable `napaxi.*` id, kind, version, risk, requirements,
   default-enabled flag, and activation mode.
2. If the capability has its own subject naming (a new tool name family,
   a new provider name), add it to `tool_capability_id` /
   `provider_capability_id` so the admission record carries the right
   capability id (instead of falling back to the raw subject).
3. Wire the capability into the runtime path that uses it (the tool
   loop, MCP loader, provider resolver) so admission runs *before*
   execution / IO.
4. Update `docs/mobile-capabilities.md` if the capability is part of the
   public surface.

## Where admission gates live

The boundary check script (`tools/scripts/build.sh check-boundary`) keeps
an explicit allowlist of files that may call `admit_*` directly:

- `crates/core/src/capabilities/mod.rs` — the admission implementation
- `crates/core/src/tools/loop/descriptors.rs` — descriptor gate for
  built-in / host / platform tools
- `crates/core/src/tools/loop/execution.rs` — invocation gate for the
  same set
- `crates/core/src/mcp/tools.rs` — descriptor + invocation gates for
  MCP tools

Adding a new gate file means adding it to the allowlist after review —
think of the allowlist as a one-line PR description of "where can policy
deny things."

## Shell command safety and the admission boundary

Shell command safety decisions (read-only allow, prompt, deny) are resolved
entirely at the tool layer. The `ShellDecision` enum is intentionally separate
from the binary `CapabilityAdmissionDecision { Allow, Deny }` used here: shell
safety needs a three-way outcome (allow / prompt-the-host / deny) that does not
fit the admission chain's short-circuit model. Capability admission still gates
whether the shell *tool itself* is available; once admitted, the shell tool's
own safety layer decides what to do with the specific command.

## Roadmap

- ~~Per-engine isolation of the admission trace buffer (currently global)~~
  **Done.** Admission traces are now scoped per engine via `with_admission_sink`
  (see [Admission trace](#admission-trace)); the fallback is process-global.
- Capability definitions for individual MCP servers, so the trace carries
  `napaxi.mcp.{server}` instead of the raw subject prefix
- Demo trace panel that subscribes to admission decisions in real time
- Bridge layer that surfaces admission denies to Dart as structured
  `CapabilityError::Denied` (wire envelope) instead of `bool`/error
  strings
