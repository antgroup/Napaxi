# Context Engine

The context module (`crates/core/src/context/`) is the core-owned **context
engine and session-compaction** layer. It estimates token usage, infers the
model's context window, decides when history must be compacted, and produces the
status that the runtime surfaces to adapters. Its capability id is
`napaxi.service.context_engine` (`CONTEXT_ENGINE_CAPABILITY_ID`).

If you are changing token budgeting, the compaction trigger or output, or the
context status display, this is the module.

## Submodules

- `state.rs` — persisted per-thread context state types and load/save:
  `ContextState`, `ContextBudgetStatus`, `ContextTokenBreakdown`,
  `LastPromptSnapshot`.
- `budget.rs` — token estimation, model-window inference, and response-reserve
  routing: `ContextBudgetPlanner`, `context_window_tokens`,
  `model_context_breakdown`, `response_reserve_tokens`,
  `build_preflight_snapshot`, and the config-fingerprint helpers.
- `compaction.rs` — history compaction and tool-output reduction:
  `compact_history`, `has_compactable_middle`, `tail_messages`,
  `visible_history_from_state`. It also owns the structured-summary section
  contract (Decisions, Open TODOs, Constraints/Rules, Pending user asks, Exact
  identifiers, Tool outcomes) and the retry prompt when a summary misses
  required headings.
- `display.rs` — context status display and snapshot-freshness helpers:
  `display_context_usage`, `display_context_delta`, `usage_percent`.
- `resolver.rs` — context resolution wiring.

## How It Fits

`budget.rs` consumes `LlmUsage` from the LLM module to keep token accounting
honest, and feeds `PlatformLlmConfig`-derived window details. The turn module's
context-overflow retry relies on the LLM module's overflow classification and on
this module's compaction to shrink history before retrying.

## Where to Make a Change

- New model window sizes: update `budget.rs` window inference (and keep it
  consistent with any model catalog the LLM module uses).
- Changing what survives compaction: edit `compaction.rs`; the summary section
  headings are a contract — keep the prompt, the validation, and the retry text
  in sync.
- New status fields shown to adapters: extend `state.rs` and `display.rs`
  together so persisted state and rendered status agree.
