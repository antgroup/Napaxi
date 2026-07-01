# Turn Lifecycle

The turn module (`crates/core/src/turn/`) owns the business flow for **one chat
turn**: taking a user message, preparing the prompt, running the tool loop
against the LLM, persisting traces and history, and scheduling post-turn
evolution. It is the layer between the runtime handle / bridge (which deals with
engine handles and bridge-facing JSON) and the lower-level tool loop, LLM, and
storage subsystems.

If you are changing how a turn executes — adding a step, changing what gets
persisted, altering streaming behavior, or touching context-overflow handling —
this is the module, and this doc is the map.

## Entry Points

Two public entrypoints, both in `turn::orchestration`:

- `run_turn(input, is_cancelled) -> Vec<ChatEvent>` — **collected** mode.
  Runs the whole turn and returns the full event list at the end.
- `stream_turn(input, emit, is_cancelled)` — **streaming** mode. Emits each
  `ChatEvent` through the `emit` callback as it happens.

Both take a `TurnInput` (`turn/mod.rs`) carrying everything a turn needs: the
files dir and workspace files dir, the config JSON, agent and session
identifiers, the user message and attachments JSON, the tool registry plus any
extra/custom tool descriptors, the iteration cap, and the optional agent-engine
selection.

`TurnMode::{Collected, Streaming}` distinguishes the two paths where shared code
needs to branch.

## The Stage Lifecycle

A turn is modeled as an ordered sequence of stages (`TurnStage` in
`turn/mod.rs`). Every stage is wrapped in lifecycle-hook callbacks so progress,
warnings, and failures are observable without the driver knowing who is
listening:

```text
ParseInput
  -> PreparePrompt          prepare.rs : build PreparedTurn (prompt plan, config, history)
  -> PersistUserMessage      history.rs : record the incoming user message + attachments
  -> BuildHistory            history.rs : assemble LLM history for the tool loop
  -> ExecuteToolLoop         orchestration/{collected,streaming}.rs : the LLM <-> tool cycle
  -> PersistAssistantTrace   finalize.rs : persist the assistant trace
  -> AppendJournal           finalize.rs : append the turn to the session journal
  -> QueueEvolution          finalize.rs : schedule post-turn memory/skill review
  -> EmitFinalEvents         finalize.rs : emit the terminal events
```

The stage names are not just logging labels — they are the contract the
diagnostics recorder and any other hook key off. Adding a step to the turn means
adding a `TurnStage` variant and emitting the matching `stage_started` /
`stage_completed` pair, not threading a new boolean through the driver.

## Lifecycle Hooks

`TurnLifecycleHooks` (`turn/mod.rs`) is the observation seam. The driver calls,
per stage: `stage_started`, `stage_completed`, `stage_warning`, `stage_failed`,
plus `prompt_prepared`, `context_event`, and `turn_completed`. All methods have
default no-op bodies, so an implementation only overrides what it cares about.

Two things ride on this trait:

- `TurnDiagnosticsRecorder` (`diagnostics.rs`) — the production hook. It records
  a per-stage diagnostic trail (bounded by `TURN_DIAGNOSTICS_LIMIT`) and
  `persist()`s it after the turn so a stuck or failed turn is inspectable.
- Tests use custom hooks via `run_turn_with_hooks` / `stream_turn_with_hooks`
  to assert the exact stage sequence and the events delivered at each step.

`context_event` returns a bool: `true` means the hook already delivered the
event to the caller (the streaming path), so the driver must not also collect
it. This is how one driver body serves both collected and streaming modes.

## Collected vs Streaming Drivers

`turn::orchestration` holds both drivers and the shared checkpoint policy:

- `collected.rs` accumulates events into a `Vec` and returns them.
- `streaming.rs` forwards events through the emit callback as they occur.

`run_turn` / `stream_turn` are thin wrappers that construct the
`TurnDiagnosticsRecorder`, call the `*_with_hooks` driver, then `persist()` the
diagnostics. Keeping the `orchestration::*` paths stable lets `turn::mod`
re-export them and lets tests target the drivers directly.

### Checkpoint policy

`checkpoint_after_event` (`orchestration/mod.rs`) decides which events are
durable checkpoints during the tool loop — tool calls and results, agent
delegation calls and results, and human-loop ask/response events. After a
checkpointed event the in-progress history is persisted
(`persist_turn_history_segments`) so an interrupted turn can resume or be
inspected without losing the tool-call trail.

## Context-Overflow Retry

If the tool loop fails because the prompt overflowed the model context, the
collected driver does not just error out. It calls
`reprepare_turn_after_context_overflow_with_hooks` (`prepare.rs`) to rebuild a
trimmed `PreparedTurn` and retries the tool loop once. This retry path is the
main reason the driver body is long; the rest is the happy path plus
cancellation handling. Cancellation at any point routes through
`finish_cancelled_turn`; success routes through `finish_successful_turn`
(`finalize.rs`), both producing a `TurnOutcomeSummary` whose
`into_emitted_events()` yields the terminal events.

## Cancellation & Grace Windows

Stopping a turn is cooperative and spans two layers with two distinct
timeouts. Treat the following as a contract — changing either bound requires
updating the other layer and this section.

**Generation-scoped cancel (Rust core).** `runtime::session_runtime` tracks a
monotonic *generation* per session. `begin_turn` (and the manual-style
`clear_session_cancellation` used by agents/a2a/automation/group) bumps the
generation and clears any pending cancel; `cancel_session_key` marks the
generation that was current under the lock. A turn only observes a cancel
aimed at *its own* generation. Invariant: **a cancel issued against turn N can
never be observed by turn N+1**, even if it lands in the instant the next turn
starts. This removes the stale-cancel race the old membership-set model had.
The `is_cancelled` closure threaded into `run_turn`/`stream_turn` is what the
turn polls.

**Tool-cancel grace (Rust core): ~2s.** When a turn is cancelled mid tool
call, `tools/loop/execution.rs` polls the cancel flag every
`TOOL_CANCEL_POLL_INTERVAL` (100ms). A cooperative handler returns promptly; an
uncooperative one (no cancellation path) is force-returned after
`TOOL_CANCEL_GRACE_PERIOD` (2s) via `wait_for_cancel_with_grace`, which drops
the handler future and emits the cancellation result. The dropped future may
leave background work running — the grace bound caps how long the *turn* waits,
not the handler's own cleanup.

**Stream-drain grace (Dart adapter): 4s.** The Flutter demo awaits the Rust
event stream's `onDone` after issuing stop; if the stream does not close within
~4s it force-cancels the subscription locally and completes in-flight tool
cards. The 4s host window is deliberately larger than the 2s core grace so the
core's terminal/`Interrupted` events normally arrive first; the host timer is
the backstop for a stream that never closes. Under `flutter_test`'s fake async
this timer must be advanced explicitly (`pump(Duration(seconds: 5))`) or the
stop path appears to hang.

Events that survive cancellation (terminal/`Interrupted`/`ToolResult`) are
classified by `event_survives_cancel` in `turn/orchestration/streaming.rs`;
progress events (deltas, thinking, tool-output chunks) are dropped once
cancelled. Tests for these bounds live in `runtime/session_runtime.rs` (the
generation race, including a threaded concurrent cancel-vs-begin stress) and
`tools/loop/tests.rs` (grace-period force-return).

## Prompt Preparation

`prepare.rs` produces a `PreparedTurn`, and `prompt.rs` owns prompt assembly:
`PromptPlan`, the prompt-section model (`PromptSection`, priority, visibility,
source), and `compile_prompt_sections` / `prepare_prompt_sections`. The
`PromptPlanSummary` is what the `prompt_prepared` hook receives, so observers see
what went into the prompt without holding the full plan. `prepare_chat_config`
turns the incoming `ChatRuntimeInput` into the runtime config the turn uses.

## Attachments

`attachments.rs` handles incoming attachments: parsing scene-prompt attachments,
persisting attachment files into the files dir, and building the content parts /
metadata JSON the LLM history needs (`attachment_content_parts_with_mode`,
`persist_attachment_files`, `attachment_metadata_json`).

## Post-Turn Evolution

The `QueueEvolution` stage (`finalize.rs`) is where the turn hands off to the
evolution subsystem. It calls `crate::evolution::queue_memory_review_after_turn`
and `queue_skill_review_after_turn` with the updated session history; each may
return a `QueuedEvolutionRun` that is reported in the final events. The review
itself runs in the background — see [`module-evolution.md`](module-evolution.md).

## File Map

| File | Responsibility |
| --- | --- |
| `mod.rs` | `TurnInput`, `TurnMode`, `TurnStage`, `TurnLifecycleHooks`, shared helpers, module wiring |
| `orchestration/mod.rs` | `run_turn` / `stream_turn` entrypoints, checkpoint policy |
| `orchestration/collected.rs` | Collected-mode driver + context-overflow retry |
| `orchestration/streaming.rs` | Streaming-mode driver |
| `prepare.rs` | `PreparedTurn`, prompt/config/history preparation, overflow re-prepare |
| `prompt.rs` | Prompt plan, prompt-section model, prompt compilation |
| `attachments.rs` | Attachment parsing, persistence, content parts/metadata |
| `history.rs` | User-message persistence, history assembly, segment persistence |
| `finalize.rs` | Trace persistence, journal append, evolution queueing, terminal events |
| `diagnostics.rs` | `TurnDiagnosticsRecorder` lifecycle hook + diagnostic records |
| `tests.rs` | Stage-sequence and behavior tests via custom hooks |

## Conventions

- Runtime-handle and bridge-facing JSON concerns belong in `runtime`, not here.
- New turn steps become `TurnStage` variants with matching hook calls — do not
  add ad-hoc progress flags.
- One driver body should serve both modes; branch through `TurnMode` and the
  `context_event` return value rather than forking the flow.
