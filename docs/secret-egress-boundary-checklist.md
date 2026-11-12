# Secret egress boundary — adoption checklist (未雨绸缪基线)

OpenClaw #186765 — `fix(secrets): Node fetch in exec can't reach local
HTTP servers with the secret egress proxy on`.

This file is a **pre-adoption checklist**, not an implementation.
Napaxi has **no secret egress proxy today** (full-tree grep finds no
egress / CONNECT-tunnel / loopback boundary surface), so there is
nothing to fix right now. The items below are the invariants OpenClaw
paid for once; if Napaxi ever routes tool / MCP / plugin or
exec-local-service traffic through a restricted egress proxy, every one
of them must hold on day one.

Source: `6769a69` in the OpenClaw 2026-11-05 snapshot (work item
2026110500120371822, "secret egress 边界未雨绸缪基线"). License note: OpenClaw
is MIT, Napaxi is GPL-3.0-or-later — this file records design rules, no
code is ported.

## When this checklist triggers

- A tool, MCP server, plugin, or exec helper starts calling out over the
  network; **and**
- that traffic is routed through a restricted secret-egress proxy (so
  egress can be policy-gated / audited); **or**
- the traffic targets a **local** HTTP service (loopback) that the
  egress proxy would otherwise tunnel to / intercept.

Until both halves are true the file is advisory only — there is no
egress boundary to gate.

## Invariants that must hold on adoption

1. **Loopback CONNECT must pin and bound.** A CONNECT tunnel to a
   loopback target must be pinned (single target, not re-targetable) and
   bounded to the requesting execution scope. A free-retargeting loopback
   tunnel is a sandbox escape.
2. **Bound protocol probe before handoff.** Before handing a tunnel to
   the inner request, probe that the target speaks the bound protocol;
   do not blind-handoff a tunnel to an arbitrary peer.
3. **Current-process authority check.** The egress proxy must verify it
   is handing off to the current, intended process authority — not a
   stale / re-parented one — before forwarding.
4. **Reject origin change & plaintext sentinel.** If the inner request
   changes origin, or a plaintext hop / sentinel leaks through the
   tunnel, the proxy refuses rather than forwarding. Origin change and
   plaintext sentinels are egress-boundary violations by definition.
5. **Release idle / already-ended peers.** CONNECT peers that end
   before sending bytes, or sit idle past the scope window, are
   released; they are not held open to be reused by a later request.

## Non-goal (deliberately not in this checklist)

- The background / detached exec process-hosting track (#185636 deep
  item) is a separate daemonization effort; the egress checklist above
  covers only the tunnel / authority surface of #186765.
- This checklist does not introduce any egress code. Adopting it means
  writing the boundary once both trigger halves above are true; until
  then it stays a design memo beside the runbook.

## Related

- DIMA 2026110500120371822 — `exec 结果保留语义 + secret egress 边界基线`.
- OpenClaw #185636 deep item (background/exec process hosting) lives on
  the daemonization track; its audit baseline for the sync-exec path is
  the `ShellExecResult` data contract (`crates/core/src/tools/builtin/shell.rs`)
  and the regression test `timeout_preserves_already_collected_stdout_when_killed`.
