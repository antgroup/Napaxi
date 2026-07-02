# Napaxi libsql-sqlite3-parser patch notes

This directory holds a vendored copy of `libsql-sqlite3-parser` referenced from
the workspace `Cargo.toml` via:

```toml
[patch.crates-io]
libsql-sqlite3-parser = { path = "vendor/libsql-sqlite3-parser-patched" }
```

This file documents what is patched, why, and the cadence at which the patch
is refreshed against upstream. The upstream project's own documentation
(`README.md`) is preserved unchanged.

## Upstream baseline

- Upstream: <https://github.com/tursodatabase/libsql> (subtree: `sql-parser`)
- Vendored version: `libsql-sqlite3-parser 0.13.0` (per `Cargo.toml` in this
  directory)
- Last refresh: vendored alongside `libsql 0.6.0` into Napaxi; see the git log
  of this directory for the most recent rebase commit.

## Why we vendor

The `libsql` crate (patched in `vendor/libsql-patched/`) depends on
`libsql-sqlite3-parser`. When `libsql` is pinned via `[patch.crates-io]`, Cargo
requires that all transitive patched dependencies also reside under the same
workspace. This vendored copy exists primarily to satisfy that constraint —
without it, the `libsql` patch would not compile.

## Patch manifest

### Cargo.toml / build system

- `Cargo.toml` is the cargo-normalized form; `Cargo.toml.orig` is the original.
- `build.rs` keeps the upstream lemon generation path, but falls back to the
  vendored `generated/parse.rs` when the host-side lemon compiler cannot be
  built or executed. This keeps mobile SDK release builds deterministic on
  constrained macOS/CI hosts.

If a future mobile-specific source patch becomes necessary, add a numbered
entry here in the same shape as the `libsql-patched/NAPAXI-PATCH.md` convention
(File / What / Why / Upstream status) **in the same commit** as the code
change.

## Rebase cadence

- Target rhythm: every **3 months**, aligned with the `libsql-patched` rebase.
- Next scheduled rebase: **2026-09-01**.
- Owner: any maintainer cutting an Napaxi minor release per
  [`RELEASING.md`](../../RELEASING.md) should confirm that the rebase
  schedule has not slipped.

Rebase workflow:

```sh
cd vendor/libsql-sqlite3-parser-patched
# Replace with fresh copy from the upstream libsql repository subtree:
rm -rf src build.rs CMakeLists.txt generated tests benches
cp -r <upstream-libsql>/sql-parser/src .
cp -r <upstream-libsql>/sql-parser/build.rs .
# ...etc.
cargo check --workspace                       # from repo root
cargo test --workspace --no-fail-fast
./tools/scripts/build.sh release android
./tools/scripts/build.sh release ios
```

Bump the **Vendored version** line above and the rebase date when the work
lands.

## Exit criteria

This vendor directory should be removed when **all** of the following hold:

1. Upstream `libsql` releases a version that builds cleanly for the Napaxi
   mobile targets without local patches (removing the need for the
   `libsql-patched` vendor directory).
2. The `[patch.crates-io]` entry for `libsql` is removed from the workspace
   `Cargo.toml`.
3. `libsql-sqlite3-parser` can be consumed as a normal `crates.io` dependency.

When that happens, delete this directory, remove the corresponding
`[patch.crates-io]` entry in the workspace `Cargo.toml`, and pin
`libsql-sqlite3-parser` as a normal dependency.
