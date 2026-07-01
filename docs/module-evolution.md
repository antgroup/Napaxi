# Evolution

Evolution is Napaxi's self-improvement subsystem: after a chat turn, the runtime
can review the conversation and **propose** updates to the agent's memory or
skills. Proposals are queued, surfaced to the user as pending actions, and only
mutate the workspace when explicitly applied. Like skills, it spans **two
crates**:

```text
crates/features/evolution/   domain: the review job, LLM review handler,
                             pending queue, rollback, counters, fuzzy
                             find-and-replace, action tools, traits
        |
        v   (depended on by core; feature crate must NOT depend on core)
crates/core/src/evolution/   file-backed glue: post-turn triggers, background
                             review drivers, pending store, apply/reject API
        |
        v
crates/core/src/api/evolution.rs   adapter-facing handles
```

`crates/core/src/evolution/mod.rs` describes itself as exactly this:
"Mobile memory evolution glue — adapts `napaxi-evolution` to the file-backed
mobile runtime." The domain crate has no knowledge of the runtime or the
filesystem layout; core supplies both.

## The Post-Turn Flow

Evolution is not invoked directly by adapters during normal operation — it is
triggered as the `QueueEvolution` stage of a turn (see
[`module-turn.md`](module-turn.md)). The end-to-end flow:

```text
turn finalize.rs (QueueEvolution stage)
  -> evolution::queue_memory_review_after_turn   (queue.rs)
  -> evolution::queue_skill_review_after_turn    (queue.rs)
        |  each checks cadence/thresholds, and if due:
        v
     tokio::spawn  background review              (queue.rs: spawn_*_review)
        -> review_memory_now / review_skill_now   (review.rs)
              -> ReviewLlmHandler                  (executor.rs)  asks the LLM
              -> EvolutionReviewJob.perform_review (features/evolution job/)
        -> proposed actions written to the pending store  (store.rs)
        |
        v
   later, on the user's command:
     apply_pending_evolution / reject_pending_evolution  (pending_api.rs)
        -> EvolutionExecutor executes an applied action   (executor.rs)
```

The key property: the turn returns quickly. `queue_*_review_after_turn` does the
cadence check synchronously and then `tokio::spawn`s the actual LLM review so it
runs in the background — the user's turn is never blocked on a review. If a
review is queued, the turn reports a `QueuedEvolutionRun` in its final events.

## `core/src/evolution` — Glue

- **`mod.rs`** — The runtime types (`EvolutionRun`, `EvolutionRunRecord`,
  `QueuedEvolutionRun`, `PendingEvolution`, `PendingStatus`, diagnostic
  records) and the `maybe_review_*_after_turn` decision functions.
- **`queue.rs`** — `queue_memory_review_after_turn` /
  `queue_skill_review_after_turn`: cadence/threshold gate plus the
  `tokio::spawn` background drivers (`spawn_memory_review`,
  `spawn_skill_review`).
- **`review.rs`** — `review_memory_now` / `review_skill_now`: builds the review
  input from session history, runs the review, records diagnostics. Symbols are
  `pub(in crate::evolution)` — internal to the subsystem.
- **`executor.rs`** — `ReviewLlmHandler` (drives the LLM review call) and
  `EvolutionExecutor` (executes an action once a pending proposal is applied).
- **`store.rs`** — Atomic file persistence for the pending store and the
  diagnostics store (`load_pending_store`, `save_pending_store`,
  `append_diagnostic_record`).
- **`pending_api.rs`** — The adapter-facing query/mutate surface:
  `list_pending_evolution`, `list_evolution_runs`, `list_evolution_diagnostics`,
  and `apply_pending_evolution` / `reject_pending_evolution`, each with a
  `*_handle` variant that resolves the files dir from an engine handle.
- **`skill_consolidation.rs`** — `run_skill_consolidation_review`: a distinct
  review that consolidates overlapping/redundant skills.

## `features/evolution` — Domain

The `napaxi_evolution` crate owns the reusable review logic:

- **`job`** — `EvolutionReviewJob` (the builder-configured review unit,
  `perform_review`), `EvolutionReviewInput` / `EvolutionReviewOutput`, the
  `LlmReviewHandler` interface, and `llm_integration` (napaxi `LlmProvider`
  glue).
- **`queue`** — `PendingQueue` / `UserPendingQueue`, `PendingConfirmation`,
  `ConfirmationStatus` — the domain model for proposals awaiting confirmation.
- **`rollback`** — `RollbackManager`: snapshot-and-restore so an applied action
  can be undone.
- **`counter`** — Turn/usage counters that drive review cadence.
- **`fuzzy`** — `fuzzy_find_and_replace` / `FuzzyMatcher`: tolerant text edits
  for applying memory/skill changes against drifting content.
- **`hook`** — Evolution hook points.
- **`tools`** — `ActionExecutor` and the action-tool definitions a review can
  propose.
- **`traits`** / **`types`** / **`config`** / **`error`** / **`io`** — Shared
  contracts, DTOs (`MessageSnapshot`, …), `EvolutionConfig` / `SecurityPolicy`,
  the error type, and atomic IO helpers.

## Adapter Boundary

`crates/core/src/api/evolution.rs` re-exports the handles adapters call:
`list_pending_evolution_handle`, `list_evolution_runs_handle`,
`list_evolution_diagnostics_handle`, `apply_pending_evolution_handle`,
`reject_pending_evolution_handle`, and `run_skill_consolidation_review_handle`.
Adapters surface these as "review suggestions" UI; they must not reach into
`core::evolution` internals or depend on `features/evolution` directly.

## Why Two-Phase (Propose then Apply)

Evolution mutates durable user state — memory and installed skills. Doing that
automatically from a background LLM review would be both surprising and unsafe,
so the design splits **proposing** (background, automatic, non-destructive:
writes only to the pending store) from **applying** (foreground, explicit,
destructive: runs through `EvolutionExecutor` with `RollbackManager` backing).
The pending store is the seam between the two, and `apply`/`reject` are the only
paths that change the workspace.

## Where to Make a Change

- New review *type* or what a review proposes → `features/evolution`
  (`job`, `tools`) plus a glue driver in `core/src/evolution/review.rs`.
- Change *when* reviews fire → `core/src/evolution/queue.rs` cadence gate and
  `features/evolution/counter`.
- New pending-action query or apply behavior → `core/src/evolution/pending_api.rs`
  + an `api/evolution.rs` handle.
- Anything adapters should see → it must land in `api/evolution.rs`.
