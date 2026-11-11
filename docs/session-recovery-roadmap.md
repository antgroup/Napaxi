# Session Recovery Roadmap

> Status: daemonization roadmap — out of current CR scope.
> Reference: DIMA #2026111000120512225 §2.C (mapping OpenClaw #195661 —
> "preserve yielded roots across Gateway restarts").

This document records the design references Napaxi will draw on when the
gateway-daemonization track lands. It carries no code change in this CR;
it exists so the design references survive between cycles.

## Context

Napaxi today runs the codex engine as a single in-process supervisor. The
events below (drawn from the OpenClaw #195661 fix) describe the
yielded-root / restart-recovery properties a durable session-owner will
eventually need. They are tracked here, not implemented here:

- 2026-11-02 — SIGKILL recovery: a killed process leaves in-flight turns
  with no bounded terminal state; the mobile runtime surfaces no clean
  restart signal to the user.
- 2026-11-08 — start terminal-reply bounded grace: a turn that spanned a
  channel restart needs a classified terminal reply rather than a hang.

## Design references (from OpenClaw #195661)

These are design-idea references only — Napaxi re-implements, it does not
port OpenClaw code (MIT vs GPL-3.0-or-later; see `THIRD-PARTY-LICENSES.md`).

- **Yielded-root lifecycle persistence.** Dashboard/operator roots parked
  via `sessions_yield` lose their lifecycle on a Gateway restart today.
  Durably persisting the parked state across restarts is the precondition
  for any restart-recovery contract. Napaxi's analog: a daemonized
  gateway owner must park a yielded turn durably, not just in memory.
- **Reachable vs stopped-descendant distinction.** A
  requester/cohort index distinguishes waits that can still be resumed
  (reachable) from descendants whose owning process already stopped and
  need root reconciliation (stopped-descendant). Startup uses this
  distinction to avoid restoring stale execution authority. Napaxi's
  analog: on daemon restart, the recovery sweep must tell "parent still
  running" from "parent gone, child cannot resume".
- **Durable completion owner retaining original requester run identity.**
  The durable completion owner settles a yielded lifecycle by retaining
  the original requester's run identity — only that owner may settle
  the yielded root. Napaxi's analog: the daemon, not the spawn broker,
  owns completion of a yielded turn so a restart cannot orphan the
  requester.
- **Permanent delivery failure → classified run-failure notice.** When a
  yielded root can never be delivered (permanent handoff rejection), the
  batch retirement path emits the existing classified run-failure notice
  rather than leaving the requester parked forever. Napaxi's analog: a
  bounded failure path for unrecoverable yielded turns, surfacing a
  terminal reply on the originating thread.
- **Children do not independently replay.** Resumed children do not
  re-execute their turn body; only the durable completion owner advances
  the lifecycle. Truly ownerless mid-turn orphans keep the existing
  branch.

## Why this is out of scope here

These properties only matter once Napaxi runs the gateway as a durable
daemon (the runbook §3 gateway → xChannel transition). Under the current
single-process + codex-engine shape there is no yielded-root lifecycle
to preserve and no cross-process completion owner to retain. Implementing
the references ahead of that transition would be speculative work with no
runtime to host them.

## Tracking

Owned by the daemonization roadmap. Re-evaluate at the next gateway
daemonization milestone.
