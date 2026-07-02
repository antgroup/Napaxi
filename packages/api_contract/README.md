# Napaxi SDK API Contract

This directory is the contract home for the `packages/` adapter layer. It is
intentionally small today: the files here define the target shape that new
bridge methods and SDK facades should converge on before generation or stricter
CI checks are introduced.

## Goal

Make `packages/` a contract-first SDK adapter layer:

```text
napaxi_core::api contract
  -> packages/api_bridge wire methods
  -> Flutter / iOS / Android typed SDK facades
  -> cross-platform golden tests
```

Adapters should translate host platform concerns and typed models, not recreate
runtime policy. Shared behavior belongs in `napaxi_core::api`.

## Contract Files

- [`goals.md`](goals.md): SDK Adapter 2.0 target state and migration rules.
- [`errors.yaml`](errors.yaml): standard wire result and error envelope.
- [`methods.yaml`](methods.yaml): initial method namespace inventory and
  stability labels.
- [`capability_matrix.yaml`](capability_matrix.yaml): cross-adapter capability
  coverage and status.
- [`workspace.json`](workspace.json): first executable vertical slice covering
  workspace methods, adapter mappings, typed models, fixture bindings, and
  response-shape fixtures.

## Stability Labels

- `stable`: preferred typed API for new host integrations.
- `experimental`: available but still allowed to evolve.
- `compat`: kept for source migration or historical Flutter-shaped entrypoints.
- `raw`: JSON passthrough escape hatch over the core API.
- `generated`: codegen-owned; do not edit by hand.

## Rules for New Package APIs

1. Add or update the contract first when introducing a public adapter method.
2. New wire methods should use the standard `ResultEnvelope` from
   `errors.yaml`; do not introduce new `false` / `0` / empty-string error
   sentinels.
3. Public typed facades should document their stability label.
4. Raw JSON escape hatches are allowed, but they must preserve the same error
   envelope and method identity as typed facades.
5. Flutter, iOS, and Android model behavior should be backed by shared fixtures
   or parity tests when the surface exists on more than one adapter.
6. Contract fixtures must bind to the method response shapes they represent and
   include unknown fields when the model declares `unknownFields: preserve`.
7. Run `./tools/scripts/build.sh release check-api-contract` after changing
   contract files or any adapter surface covered by a contract vertical slice.
