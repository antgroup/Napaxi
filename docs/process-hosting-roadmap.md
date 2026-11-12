# Process Hosting & Restart Recoverability Roadmap

OpenClaw-inspired guardrail checklists for the Napaxi daemon-ization and
egress-boundary roadmap. Each item is a review checklist to execute when the
named capability lands; Napaxi currently has no stall-watchdog, no graceful
restart, and no secret egress proxy, so none of these require code today.
Design thoughts only — no code is ported (OpenClaw MIT vs Napaxi
GPL-3.0-or-later; re-implement per governing rules).

Featured in DIMA #2026110800120444016. Continues the 11-02 / 11-07 / 11-08
process-hosting convergence sequence (SIGKILL recovery, main-thread stall
watchdog, start terminal-reply bounded grace).

## 1. compaction ↔ stall-watchdog nested-attachment (OpenClaw #194722)

When the 11-07 main-thread stall watchdog lands, `compaction.rs` must run via a
**nested attachment** on the existing watchdog owner — not by replacing the
foreground attempt. OpenClaw #194722 found that compaction executing inside the
foreground turn detached the watchdog from that turn, so the turn lost its
runtime-owned wait and was misjudged stalled/aborted even while making forward
progress.

Checklist for the watchdog-introducing CR:

- Compaction under a foreground turn attaches as a **nested** owner under the
  existing watchdog owner; it does not replace the foreground attempt.
- Parent retirement closes nested resources; nested cleanup must **not** close
  the parent, must **not** clear the parent's deadline, and must **not** revive
  a stale attempt.
- Standalone compaction (no foreground turn) keeps its current behavior.
- Tests cover: nested lifetime, independent deadlines, parent
  replacement/cancellation, and the direct-compaction boundary.

Audit: `crates/core/src/context/compaction.rs` currently uses `Instant::now()`
for timing and `Utc::now()` for stamps and has no watchdog / foreground turn
ownership / nested-attachment semantics — the gap is latent until the watchdog
arrives.

## 2. graceful-restart terminal-reply bounded grace (OpenClaw #195164)

When Napaxi supports graceful restart (daemon-ization), terminal partial
assistant replies must be preserved across the restart with a bounded
abort-settle grace — no chunks/heartbeats renewal.

Checklist:

- On graceful restart, give the terminal partial reply one **non-renewing**
  abort-settle grace (normal 2s / fast test 250ms).
- Chunks/heartbeats cannot renew the grace; once expired, reject pending
  iterator reads with the original abort reason.
- A producer that completes within the grace keeps its queued terminal readable.
- Session cleanup reuses a single `waitForEmbeddedAbortSettle` owner-consumed
  budget — no sequential abort-settle waits.
- Custody is never dropped early: a provider that ignores cancel and continues
  may retain Gateway shutdown to prevent a late write / release race. Only the
  logical cancellation is bounded; provider resources are not arbitrarily closed.
- boundaries: bounded logical cancellation only; do not arbitrarily close
  provider resources.

OpenClaw paid +27.4% SIGTERM-to-exit median for this; budget accordingly.

## 3. secret egress proxy / CONNECT resume (OpenClaw #195138 / #186765)

If a future phase introduces a restricted egress proxy, it must absorb both
#186765 (11-05 baseline) and #195138 (11-08 runtime hardening):

- After proxy handoff, immediately resume the guarded stream (two injection
  points: the decrypted TLS socket, and the sniffed plaintext CONNECT socket).
- The TLS handshake acceptance stays with the TLS server; the runtime only
  resumes the already-paused socket.
- Install the revocation guard **before** the injection points, not after.
- Pin/bound loopback CONNECT; reject forged target / Host headers; release
  idle or ended peers; cover bypass cleanup.
- No version branch, no new per-request op.

This is a mid/long-term item pending egress-boundary product decisions.

---

# Alternate napaxi-side process-hosting roadmap (PR #111 original)

# Process-hosting roadmap

Napaxi is single-process and reaches child processes (codex engine, exec)
through rpc / supervised channels rather than OpenClaw's long-lived supervised
Gateway. Several OpenClaw hardening items map to a daemonization + supervised
process track that Napaxi has not entered yet. This file records the design
checklists so the items are tracked against their OpenClaw sources instead of
being dropped; none are landed in the audit-baseline CRs that reference it.

Each section is a checklist plus its OpenClaw source id(s) and the trigger
that should start the work.

## §1 compaction ↔ watchdog nested-attachment (#194722)

The context-compaction watcher and the main-thread stall watchdog must not
nest-attach in a way where one falsifies the other's liveness signal (the
compaction watcher looking live while the worker thread that should drive it
is wedged). Checklist before enabling:

- [ ] Confirm the compaction watchdog's heartbeat owner is the same bounded
  owner as the stall watchdog, or document why they are independent.
- [ ] A nested-attach must re-arm the parent watchdog, not reset the child's
  observation window.
- [ ] Test: wedge the compaction worker thread; the stall watchdog must still
  fire (the compaction watcher does not mask it).

Trigger: land this when the stall watchdog in §2 is wired against a real
heartbeat owner, not before.

## §2 restart terminal-reply bounded grace (#195164)

When the process is restarted by an external supervisor (systemd / launchd /
app child), an in-flight terminal reply should get a bounded grace window to
flush before the old instance is killed, and the new instance should not
duplicate-emit the reply. Checklist:

- [ ] Define the grace window (strictly bounded, not unbounded wait).
- [ ] A reply flushed during grace must be marked so the new instance does
  not re-emit it as a fresh authored answer.
- [ ] On ungraceful kill, the in-flight reply is dropped, not partially
  emitted.

Trigger: land this with daemonization, where restart is a real path.

## §3 main-thread stall watchdog + external-supervisor recovery
(#194481, related #190964 / #191632)

OpenClaw #194481 has the supervised Gateway kill itself (SIGKILL) after 5
minutes without a heartbeat, relying on an external supervisor to restart and
on existing crash-recovery to resume eligible runs. Napaxi has only the
qqbot-protocol WS heartbeat (`channel/qqbot/gateway.rs`, an app-level liveness
signal) and no general main-thread stall watchdog, no supervisor-kill +
restart-resume chain. Checklist before introducing:

- [ ] Confirm the codex-engine main thread is plausibly subject to a stall
  (if the codex child-process rpc has no main-thread stall surface, downgrade
  the priority of this item).
- [ ] Reuse the existing bounded heartbeat owner (qqbot's or a new shared
  one); do NOT add a second independent watchdog.
- [ ] Define the stall threshold against the heartbeat owner; 5 min is an
  OpenClaw default, Napaxi's threshold should be sized to its own workload.
- [ ] On stall: SIGKILL self, write a `main-thread stall recovery:` terminal
  fact to stderr synchronously, do not wait for an inspector capture.
- [ ] External supervisor (systemd / launchd) restarts; existing
  crash-recovery resumes eligible runs.
- [ ] Inspector / startup profiling are exempt from the stall window; laptop
  sleep resets the observation window.

Trigger: this is on the daemonization + self-managed-process track, gated on
Napaxi deciding the external-supervisor deployment shape. It is long-term and
explicitly out of scope for the audit-baseline CRs that land in this file's
neighborhood.
