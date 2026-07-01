# Napaxi libsql patch notes

This directory holds a vendored copy of `libsql` carrying Napaxi-specific
patches for mobile build and runtime compatibility. It is referenced from the
workspace `Cargo.toml` via:

```toml
[patch.crates-io]
libsql = { path = "vendor/libsql-patched" }
```

This file documents what is patched, why, and the cadence at which the patch
is refreshed against upstream. The upstream project's own documentation
(`README.md`, `DEVELOPING.md`) is preserved unchanged.

## Upstream baseline

- Upstream: <https://github.com/tursodatabase/libsql>
- Vendored version: `libsql 0.6.0` (per `Cargo.toml` in this directory)
- Last refresh: forked into Napaxi before this README was written; see the
  git log of this directory for the most recent rebase commit.

## Why we patch

Mobile builds (`aarch64-linux-android`, `aarch64-apple-ios`, Android proot
runtime, iOS iSH environment) exercise libsql build flags and feature
combinations that upstream does not currently smoke-test. The patches here
exist to keep Napaxi building on the mobile targets supported by
`./tools/scripts/build.sh release {android,ios}`.

The patches are intentionally minimal. If a change can land upstream instead
of here, prefer that path.

## Patch manifest

This is the authoritative list of every Napaxi-specific deviation from the
vendored upstream baseline. Keep it exhaustive: a reader should be able to
reconstruct the full diff against upstream `libsql 0.6.0` from this table
alone, and a future rebase should re-apply exactly these changes.

### 1. iOS-tolerant SQLite threading configuration

- **File:** `src/local/database.rs` (in `Database::new`, the `LIBSQL_INIT`
  once-block).
- **What:** Upstream hard-`assert_eq!`s that `sqlite3_config(SERIALIZED)`
  returns `SQLITE_OK`. On iOS the system pre-initializes SQLite for its own
  use, so that call returns `SQLITE_MISUSE` (21) and the assert aborts the
  host app. The patch (a) retries once after `sqlite3_shutdown()`, and (b)
  splits the failure path by target: `#[cfg(target_os = "ios")]` logs a
  warning and continues (the bundled SQLite is already built
  `SQLITE_THREADSAFE=1`, so the threading mode is correct regardless), while
  `#[cfg(not(target_os = "ios"))]` keeps the original upstream assert.
- **Why it can't be a build flag:** the conflict is a runtime property of the
  iOS process, not a compile-time feature.
- **Upstream status:** not yet filed. **TODO(maintainer):** open an upstream
  issue/PR proposing a non-aborting path when the host process has already
  initialized SQLite (e.g. return an error from `Database::new` instead of
  asserting), and link it here. Until then this patch must be re-applied on
  every rebase.

### Cargo.toml / build system

- **No** `[patch]`, `[replace]`, dependency-version, or feature-flag
  deviations from upstream. `Cargo.toml` is the cargo-normalized form; there
  is no `Cargo.toml.orig`. The only functional patch is the source change
  above.

When adding a new patch, add a numbered entry here in the same shape (File /
What / Why / Upstream status) **in the same commit** as the code change.
`tools/scripts/check-test-stability.sh` does not police this; reviewers do.

## Rebase cadence

- Target rhythm: every **3 months**, or sooner if a security advisory lands
  against the upstream `libsql` release.
- Next scheduled rebase: **2026-09-01**.
- Owner: any maintainer cutting an Napaxi minor release per
  [`RELEASING.md`](../../RELEASING.md) should confirm that the rebase
  schedule has not slipped.

Rebase workflow:

```sh
cd vendor/libsql-patched
git remote add upstream https://github.com/tursodatabase/libsql.git  # once
git fetch upstream
# Inspect upstream releases; pick the new target tag.
# Replay Napaxi-specific patches on top.
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
   mobile targets without local patches.
2. Upstream CI covers those targets so future regressions are caught.
3. Napaxi's pinned `napaxi-core` features and feature flags reach those builds
   without bespoke wiring.

When that happens, delete this directory, remove the `[patch.crates-io]`
entry in the workspace `Cargo.toml`, and pin `libsql` as a normal
`crates.io` dependency.
