# Changelog

All notable changes to Napaxi are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

## [1.0.0] - 2026-07-02

### Added

- First public SDK release tag for Napaxi's Flutter, Android, iOS, and Rust
  adapter-facing SDK surface.
- Public contact path for project questions and release coordination.

## [0.1.1] - 2026-06-05

### Added

- FFI live-handle lifecycle integration test in
  `packages/api_bridge/tests/ffi_roundtrip.rs`: links `napaxi_api_bridge` as a
  downstream crate and drives the real C ABI entry points
  (`napaxi_api_create_engine` → `napaxi_api_call_json` → `napaxi_api_get_config`
  → `napaxi_api_dispose_engine` → `napaxi_api_string_free`) through a full
  hermetic round-trip — engine creation, a `workspace` write/read/list
  round-trip, config read-back, malformed-config rejection, and the
  panic-free dead-handle path. Complements the in-crate `c_api` wire-contract
  tests, which only dispatch against a dead handle; this is the first test
  that exercises the `core → bridge → host` seam with a live engine. The crate
  now also emits a `lib` (rlib) artifact alongside `cdylib`/`staticlib` so the
  test can link it; the mobile native build overrides crate-type on the CLI,
  so no shipped artifact changes.
- FFI wire-contract tests in `packages/api_bridge/c_api/mod.rs`: the
  `ok`/`err`/`ok_raw` JSON envelope shapes, C-string round-trip (including
  Unicode and interior-NUL sanitization), null-pointer tolerance, payload
  field aliasing, and the streaming `error` event shape the Dart
  `ChatEvent` decoder consumes. Locks the C ABI boundary against silent drift.
- `#![deny(clippy::undocumented_unsafe_blocks)]` scoped to the hand-written
  `c_api` module, with `// SAFETY:` comments on every `unsafe` block and a
  `# Safety` doc on `napaxi_api_string_free`. Scoped to the module on purpose:
  the FRB-generated `frb_generated.rs` is not hand-audited.
- Dart tests for the FFI decode boundary: `packages/flutter/test/chat_event_test.dart`
  (the `ChatEvent.fromMap` streaming-event contract, mirroring the Rust side)
  and `packages/flutter/test/json_codec_test.dart` (the FRB JSON unwrap layer
  and `{"error":...}` envelope handling).
- `.github/workflows/rust.yml`, `checks.yml`, `flutter.yml`, and
  `supply-chain.yml` — first CI gate. Runs `cargo fmt/clippy/check/test`,
  `check-boundary`, `check-hygiene`, Flutter analyze/test for SDK and demo,
  and `cargo deny check` + `cargo audit`. This is an explicit per-task
  authorization for `.github/workflows/` per the rule in `AGENTS.md`.
  `cargo clippy -D warnings` and the full `cargo test` (including
  `napaxi_api_bridge`) are now hard gates — see the Changed/Fixed sections.
- `.github/dependabot.yml` covering `cargo`, `github-actions`, and `pub`
  (for `packages/flutter` and `examples/flutter`), with weekly cadence and
  grouped Tokio/Tracing/Serde updates.
- `.github/workflows/native.yml` — the first multi-platform native CI gate.
  Cross-compiles the SDK for the mobile targets so a break in the Android
  (`.so`) or iOS (`xcframework`) build is caught in CI rather than only on a
  developer's machine. The `android` job builds on `ubuntu-latest` (LFS
  checkout for the sandbox runtime assets, `cargo-ndk` + NDK r27c); the `ios`
  job builds on `macos-latest` and is gated to pull requests that touch native
  paths, since macOS runners are scarce. Scope is "does the native artifact
  compile and link" — it does not assemble an APK, code-sign, or boot a
  simulator. This is an explicit per-task authorization for
  `.github/workflows/` per the rule in `AGENTS.md`.
- `.github/workflows/parity.yml` — dedicated Android/iOS↔Flutter adapter
  parity gate (pure Node, `ubuntu-latest`). Split out of `native.yml`, which
  only triggered on `crates/**` / `packages/api_bridge/**` and so silently
  skipped the parity check on adapter-only changes (a removed Kotlin method,
  an edited Swift type, a Dart surface tweak, or an edit to the parity scripts
  themselves) — the "silent adapter gap" `AGENTS.md` forbids. The new workflow
  triggers on every adapter tree (`packages/flutter/lib`, `packages/android`,
  `packages/ios`, `packages/agent_provider`) and on the parity scripts, so the
  gate runs exactly when the surfaces it compares can drift.
- `deny.toml` — cargo-deny policy: advisories deny vulnerabilities and
  yanked crates, license allowlist for the workspace's current dependency
  graph, ban-on-unknown-registry/git.
- `RELEASING.md` — full release flow including version bumps, CHANGELOG
  promotion, native artifact build via `./tools/scripts/build.sh release`,
  Flutter SDK sync via `tools/scripts/sync_prebuilt_to_release_repo.sh`,
  and tagging.
- `vendor/libsql-patched/NAPAXI-PATCH.md` — documents why we vendor libsql,
  the rebase cadence (next rebase scheduled 2026-09-01), and the exit
  criteria for deleting the vendor directory.
- `docs/sdk-integration.md` — new "Current Limitations & Long-Term Plan"
  section recording the iSH-based iOS path and the vendored libsql as
  intentional, time-bound trade-offs rather than the final shape.
- `crates/core/benches/core_hot_path.rs` — criterion bench scaffold with
  a first SSE-parse baseline; wired through `[dev-dependencies] criterion`
  and `[[bench]]` in `crates/core/Cargo.toml`. Not run in CI.
- `LICENSE` (GPL-3.0-or-later) and `NOTICE` at the repository root.
- `CONTRIBUTING.md` covering setup, repository layout, boundary rules,
  workflow, and local verification commands.
- `SECURITY.md` with private vulnerability reporting process and integrator
  hardening notes.
- `CODE_OF_CONDUCT.md` based on Contributor Covenant 2.1.
- Crate metadata (`license`, `description`, `repository`, `homepage`,
  `readme`, `keywords`, `categories`, `rust-version`, `authors`) on
  `napaxi-core`, `napaxi_api_bridge`, `napaxi_skills`, and `napaxi_evolution`.
- `rust-toolchain.toml` pinning the workspace to Rust 1.92.
- `rustfmt.toml` and `.editorconfig` to align formatting across editors.
- `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/`
  (bug report, feature request, config) mirroring `CONTRIBUTING.md`.
- `tools/scripts/build.sh check-hygiene` now also scans
  `AGENTS.md / CONTRIBUTING.md / SECURITY.md / CODE_OF_CONDUCT.md / CHANGELOG.md`
  and all of `docs/`, `packages/api_bridge/`, and `packages/agent_provider/`.
- New `check_internal_branding_leak` sub-check (always fails) for company /
  monorepo names that must not ship publicly.
- New `check_release_placeholders` sub-check (warns by default; set
  `NAPAXI_RELEASE=1` to enforce) for unreplaced public-domain placeholders.
- New `check_mobile_naming_leak` sub-check (always fails) in
  `tools/scripts/build.sh check-hygiene`. Prevents the retired `Mobile*`
  type prefix or the legacy `mobile_platform_tool_*`,
  `isMobilePlatformTool`, and `FlutterMobileCapabilityHost` names from
  reappearing on the SDK surface.

### Security

- **Constant-time HMAC comparison on every signature-verification path.** The
  earlier timing-safe fix covered A2A deep-link envelopes and agent-app
  triggers but missed `a2a::signing::verify_peer_message`, which still compared
  the HMAC tag with a short-circuiting `==`. All three paths now route through
  the shared `crate::crypto::constant_time_eq`, which is backed by the audited
  [`subtle`] crate (`ConstantTimeEq`) rather than a hand-rolled `diff |= a ^ b`
  loop a future compiler is free to optimize into a data-dependent branch.
  `subtle` was already in the dependency tree transitively (via rustls); it is
  now a direct dependency of `napaxi-core`.

### Changed

- **De-duplicated the HMAC-signing primitives into `crate::crypto`.** The four
  byte-identical helpers (`constant_time_eq`, `hmac_sha256_base64_no_pad`,
  `sha256_base64_no_pad`, `canonical_json`) were copy-pasted in both
  `a2a/signing.rs` and `agents/agent_app/signing.rs`; security-sensitive code
  with two definitions drifts. They now live once in
  `crates/core/src/crypto/mod.rs`, with focused unit tests. The
  domain-specific signed-payload layout stays in each caller's `signing`
  module. Pure consolidation — no wire-format or behavior change (489 core
  tests, including the signature accept/reject/replay cases, unchanged).
- **Closed the CI quality gates.** `cargo clippy --workspace --all-targets
  -- -D warnings` is now a hard gate (dropped `continue-on-error`): the
  workspace is warning-clean. Lint classes that flag deliberate design rather
  than defects (`too_many_arguments`, `field_reassign_with_default`,
  `type_complexity`, `enum_variant_names`, `module_inception`,
  `large_enum_variant`) are allowed once in `[workspace.lints]` with rationale
  instead of scattered `#[allow]`s. The `cargo fmt` check now runs on nightly
  rustfmt, because `rustfmt.toml` enables nightly-only `imports_granularity` /
  `group_imports`; build/lint/test stay pinned to 1.92.
- **Promoted `warn(clippy::unwrap_used)` to the `api_bridge` crate root** so it
  covers the entire hand-written FFI surface — the C ABI in `c_api/mod.rs` and
  `c_api/dispatch.rs`, and the JNI entrypoints — not just `bridge/`. A panic
  across the C ABI is undefined behaviour and mobile builds use
  `panic = "abort"`, so an `unwrap` on the bridge is a host-app crash; with
  `-D warnings` as a CI gate it is now a build failure instead. The
  FRB-generated module is exempted with a single documented `#[allow]`.
  Mirrors the crate-root lint already in `napaxi-core` and `napaxi_skills`.
- **Split every production Rust file over 1000 lines** into cohesive submodules
  (pure code motion, no behavior change), and added a `check-hygiene` guard
  (`check_source_file_size`) that caps production `.rs` files at 1000 lines so
  god-files cannot regrow. Tests, generated code, vendored crates, and
  `packages/android|ios` are exempt. Files split: `context/mod.rs`,
  `evolution/tools.rs`, `skills/registry/mod.rs`, `evolution/job/mod.rs`,
  `api_bridge/c_api.rs`, and `api_bridge/bridge/mod.rs`. The api_bridge splits
  were verified to keep all 17 exported FFI symbols and the FRB module paths
  unchanged.

- **Retired the `Mobile*` naming on the public SDK surface.** All 63 legacy
  `Mobile*` types and 3 `mobile_*` free functions documented in
  `docs/naming-migration.md` were renamed across `napaxi_core::api`, the FRB
  bridge, the Flutter SDK, and the Android SDK. Highlights:
  `MobileEngine` → `Engine`, `MobileSessionMessage` → `SessionMessage`,
  `MobileToolDescriptor` → `ToolDescriptor`,
  `MobileCapabilityContext` → `CapabilityContext`,
  `FlutterMobileCapabilityHost` → `FlutterCapabilityHost`,
  `mobile_platform_tool_descriptors_json` →
  `platform_tool_descriptors_json`, `is_mobile_platform_tool` →
  `is_platform_tool`. No `#[deprecated]` aliases were kept: the SDK is
  pre-0.1 and has no external consumers to soft-migrate, so the staged
  deprecation plan in `docs/naming-migration.md` was collapsed into a
  single atomic rename. See the "Completed" section of that document for
  the full inventory and helper scripts.
- `napaxi_skills` and `napaxi_evolution` are now licensed
  `GPL-3.0-or-later` to align the workspace on a single license.
- `AGENTS.md` allows `.github/` for issue and PR templates while still
  requiring an explicit task to introduce `.github/workflows/` or other
  tool-specific directories.

### Fixed

- Gated the `ios_ish_readiness_is_false_without_ios_runtime` test in
  `packages/api_bridge/c_api.rs` with `#[cfg(target_os = "ios")]` (it called
  iOS-only FFI entrypoints), so `cargo test` no longer needs to exclude the
  whole `napaxi_api_bridge` crate. The bridge crate's host-runnable tests run
  in CI again.
- Fixed the `core_hot_path` bench, which still imported the retired
  `mobile_platform_tool_descriptors*` names and broke `cargo *--all-targets`.
- Serialized the admission-decision buffer tests against each other; they share
  a capacity-bounded global ring buffer and could intermittently evict each
  other's entries under parallel execution.
- Replaced two `RwLock::write` calls that only read with `read` (evolution
  counters), removed a dead `cancel_signalled` store in the tool loop, and
  added the missing `# Safety` section on `napaxi_string_free`.

- `cargo check --workspace` now produces zero warnings. Unused-import noise
  in re-export aggregator modules is suppressed at the file level; reserved
  public symbols on the LLM, storage, MCP, runtime, skills, tools, and
  workspace surfaces carry per-item `#[allow(dead_code)]` notes explaining
  why they stay on the API.

### Documentation

- `docs/README.md` is the new index. Stable references and internal records
  are now separated.
- Archived internal migration notes and completed work-item logs were removed
  from the public documentation tree before open-source release.
- Added `docs/naming-migration.md`: inventory of the 31 `Mobile*` public
  types and 2 `mobile_*` public functions on the SDK surface, target
  renames, and the five-stage deprecation plan for retiring them before
  0.2.0.

### Initial

- Initialize repository structure.
