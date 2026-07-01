# SDK Adapter 2.0 Goals

## North Star

Turn `packages/` from a set of hand-maintained per-platform adapters into a
contract-first, cross-platform SDK layer over `napaxi_core::api`.

The target is not a thicker SDK. The target is a steadier SDK: stable core
contract, stable cross-adapter behavior, stable error semantics, and stable
release boundaries.

## Ownership Boundaries

### `napaxi_core`

Owns runtime behavior and policy:

- agent runtime and session lifecycle
- workspace, memory, storage, and file policy
- skills, tools, MCP, automation, groups, and A2A semantics
- LLM configuration execution semantics
- core error taxonomy

### `packages/api_bridge`

Owns wire translation only:

- FFI / FRB / C ABI entrypoints
- JSON payload and stream forwarding
- handle lifecycle handoff
- standard result/error envelope conversion
- platform callback dispatch registration

It must not own runtime policy or duplicate core behavior.

### `packages/flutter`, `packages/ios`, `packages/android`

Own platform adaptation and typed SDK surfaces:

- host-facing typed APIs
- platform permissions, notifications, background service, file opening
- browser and platform-tool hosts
- native artifact loading
- compatibility aliases where explicitly labelled
- raw JSON escape hatches where explicitly labelled

They must not diverge from core semantics or invent adapter-only defaults for
shared runtime behavior.

## Migration Priorities

1. Restore package health: no conflicts, generated files are tool-owned, checks
   can run locally.
2. Standardize result/error envelopes for new wire methods.
3. Record all public adapter methods in `methods.yaml` before adding more
   surface area.
4. Split large glue files by responsibility before adding new responsibilities.
5. Move native artifacts behind a shared artifact boundary so Flutter and
   native Android/iOS packages consume the same outputs.
6. Add contract fixtures and parity checks for models shared by multiple
   adapters.

## Done Criteria

- New public package APIs are contract-first and have a stability label.
- No new adapter API uses `false`, `0`, `""`, or `[]` as an error sentinel.
- Flutter / iOS / Android behavior differences are documented in the capability
  matrix.
- Generated and build outputs are excluded from hand-edited source paths.
- `packages` architecture checks run as part of local hygiene.

## Current Vertical Slice

`workspace.json` is the first executable contract slice. It gates method names,
bridge mappings, Flutter/iOS/Android facade presence, standard result-envelope
fixtures, typed model field rules, fixture-to-response bindings, and unknown-field
preserve samples. New contract slices should follow this pattern before moving
toward decode parity tests and code generation.
