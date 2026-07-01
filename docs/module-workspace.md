# Workspace Subsystem

The workspace module (`crates/core/src/workspace/`) owns the **file-backed
workspace** for the standalone mobile SDK runtime: memory files, the turn
journal, profile storage, search and indexed recall, and the system-prompt
assembly built from those files. Its public surface is preserved through
re-exports in `mod.rs`.

If you are changing how memory or journal files are read/written, how the system
prompt is assembled, or how recall/search works, this is the module.

## Paths and Types

- `paths.rs` — file-name constants, account/agent scoping, and path
  normalization. All workspace files are scoped per account and agent.
- `types.rs` — DTOs returned over the workspace API.
- `meta.rs` — shared time, preview, and error-JSON helpers.

## Files

- `files.rs` — read / write / append / delete / list, including the
  `_handle` (engine-handle) and `_checked` variants used by the bridge.

## Memory-Derived Surfaces

- `prompt.rs` — system-prompt assembly from memory files.
- `journal.rs` — turn append, listing, and read, with a legacy daily-file
  fallback.
- `profile.rs` — profile JSON storage and the derived prompt-document sync.

## Search and Recall

- `search.rs` — term-frequency search across memory and journal.
- `recall/` — indexed recall over memory and journal, backed by the vendored
  `libsql-patched` dependency.

## Migration

- `reseed.rs` — seeding and migration from legacy memory layouts.
- `seeds/` — seed content.

## Where to Make a Change

- New workspace file type: add its name/scoping in `paths.rs`, its read/write in
  `files.rs`, and a DTO in `types.rs`; expose it through `napaxi_core::api`, not
  directly to adapters.
- Changing prompt assembly: edit `prompt.rs` and keep `profile.rs`'s derived
  prompt-document sync consistent.
- Recall is libsql-backed; keep the dependency under `vendor/`, never under
  `crates/`.
