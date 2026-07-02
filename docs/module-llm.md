# LLM Adapter

The LLM module (`crates/core/src/llm/`) is the HTTP LLM adapter for the
standalone mobile SDK runtime. It turns session history plus a
`PlatformLlmConfig` into provider requests, dispatches them to the right
provider wire format, parses streaming and collected responses, and classifies
provider errors.

If you are adding a provider, changing request/response shaping, adjusting
output caps or cache policy, or touching error classification, this is the
module.

## Entry Points

The public surface is re-exported from `dispatch.rs`:

- `complete_with_history` / `complete_turn_with_raw_messages` — collected
  completion.
- `stream_with_history_cancelable` / `stream_turn_with_raw_messages` —
  streaming completion.

`openai_messages_from_mobile_history` (`messages.rs`) converts internal
`SessionMessage` history into wire messages. `LlmUsage` (`usage.rs`) carries
token accounting back to the context engine.

## Providers and Wire Formats

- `provider.rs` — provider selection and routing from config.
- `anthropic.rs` — Anthropic Messages API shaping (including consecutive-message
  merging).
- `gemini.rs` — Gemini request shaping, including system-instruction role
  handling.
- `openai_compatible.rs` — OpenAI-compatible chat completions, the default shape
  for many providers.
- `tool_schema.rs` — provider-specific tool/function schema sanitization.
- `cache_policy.rs` — prompt-cache breakpoint policy.
- `output_cap.rs` — max-output-token cap handling and overflow shaping.

## Transport and Parsing

- `http.rs` — the HTTP request layer.
- `sse.rs` and `sse/` — server-sent-events decoding for streaming responses.
- `messages.rs` — history-to-wire conversion shared across providers.

## Error Classification

`is_context_overflow_error` (in `mod.rs`) distinguishes genuine
context-window-overflow errors from unrelated provider errors (it excludes
"unsupported"/"unknown parameter"/"invalid parameter"-style messages so an
overflow retry is not triggered for parameter problems). This feeds the turn
module's context-overflow retry path.

## Where to Make a Change

- New provider: add a wire-format module, route it in `provider.rs`/`dispatch.rs`,
  and define its capability contract per `AGENTS.md` before exposing it.
- Request/response shape per provider: edit that provider's module, and pin
  behavior with the replay fixtures in `replay_tests.rs`.
- Token/window/cap behavior that the context engine relies on: keep `usage.rs`
  and `output_cap.rs` aligned with `crates/core/src/context/`.
