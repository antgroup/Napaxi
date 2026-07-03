# Contributing to Napaxi

Thanks for your interest in Napaxi. This guide covers how to set up a working
environment, the boundaries the codebase enforces, and how to get a change
landed.

For project-wide rules and AI-tool guidance see [`AGENTS.md`](AGENTS.md). For
architecture context see [`docs/architecture.md`](docs/architecture.md).

## Code of Conduct

This project adheres to the
[Contributor Covenant](CODE_OF_CONDUCT.md). By participating you agree to
uphold it.

## Reporting Security Issues

Do **not** open a public GitHub issue for security vulnerabilities. Follow the
process in [`SECURITY.md`](SECURITY.md).

## Development Setup

You will need:

- Rust toolchain (stable, edition 2024, rust-version ≥ 1.92). Install
  `cargo`, then run `rustup target add` for any mobile targets you plan to
  build (e.g. `aarch64-linux-android`, `aarch64-apple-ios`).
- Flutter SDK ≥ 3.19 with Dart ≥ 3.3 for any change under `packages/flutter/`
  or `examples/flutter/`.
- `ripgrep` (`rg`) — the boundary checker uses it.
- For mobile native builds: Android NDK and/or Xcode command-line tools, see
  [`docs/sdk-integration.md`](docs/sdk-integration.md).

Clone and verify:

```sh
git clone <repo-url> napaxi
cd napaxi
cargo check --manifest-path crates/core/Cargo.toml
./tools/scripts/build.sh check-boundary
```

## Repository Layout

| Path | Purpose |
| --- | --- |
| `crates/core/` | Rust runtime kernel and adapter-facing API (`napaxi_core::api`). |
| `crates/features/*` | Feature-domain crates consumed by core. Must not depend on core. |
| `packages/api_bridge/` | Flutter Rust Bridge / FFI binding layer over `napaxi_core::api`. |
| `packages/flutter/` | Flutter adapter package (`napaxi_flutter`). |
| `packages/agent_provider/` | Provider-side SDK for Agent App actions. |
| `examples/flutter/` | Flutter integration demo that consumes the SDK as a host app would. |
| `examples/provider_app/` | Sample provider apps for Agent App actions. |
| `vendor/` | Third-party patched dependencies (e.g. `libsql-patched`). |
| `tools/scripts/` | Build, codegen, hygiene, and packaging helpers. |
| `docs/` | Architecture, integration, and design notes. |

Where to put new code:

- Reusable runtime behavior → `crates/`.
- Adapter and host integration → `packages/`.
- Demo-only UI, state, panels → `examples/`.
- Build, codegen, hygiene scripts → `tools/scripts/`.
- Durable design notes → `docs/`.

## Boundaries

Napaxi enforces a few hard rules. The script
`./tools/scripts/build.sh check-boundary` turns each into a compile-time
or `rg`-level check. The most important:

1. Adapters enter Rust through `napaxi_core::api::*`. Do not import
   `napaxi_core::mobile_*`, `napaxi_core::android_assets`,
   `napaxi_core::android_linux_env`, or `napaxi_core::ios_ish_env` from
   `packages/`.
2. Packages must not depend on feature crates directly. Feature behavior
   reaches adapters through `napaxi_core::api`.
3. Feature crates must not depend on `crates/core`.
4. Third-party patched crates live under `vendor/`, not under
   `crates/core/` or `crates/features/`.
5. `api/` modules export an explicit whitelist; no `pub use crate::mobile_*::*`
   globs.
6. Generated bridge files (`packages/flutter/lib/generated/`,
   `packages/api_bridge/generated/frb_generated.rs`,
   `packages/flutter/ios/Classes/frb_generated.h`) are owned by codegen and
   must not be edited by hand.

Adding a new cross-cutting feature (LLM provider, built-in tool, MCP surface,
platform tool, policy hook, background service)? Define a capability contract
first in `crates/core/src/capabilities/` and expose it through
`napaxi_core::api::capability`. See [`docs/mobile-capabilities.md`](docs/mobile-capabilities.md).

Any SDK-facing change, including bug fixes and behavior changes, must preserve
adapter parity across Flutter, Android, and iOS. Classify the change and follow
the evidence rules in [`docs/sdk-adapter-parity.md`](docs/sdk-adapter-parity.md).

## Workflow

1. Open an issue describing the bug or feature before large changes. Small
   fixes can go straight to a PR.
2. Create a topic branch from `main`. Branch names like
   `feat/<area>-<short>`, `fix/<area>-<short>`, `refactor/<area>-<short>`,
   `chore/<short>`, `docs/<short>` are common in this repo.
3. Make focused commits. Use imperative, scoped messages, e.g.:
   - `feat(core): add capability admission for browser tool`
   - `fix(flutter): debounce capability profile updates`
   - `refactor(core): split mcp/oauth into discovery and token modules`
   - `docs(architecture): clarify adapter boundary rules`
4. Run the local verification commands below.
5. Push and open a PR against `main`. Link the issue and describe the user
   impact and test plan.
6. Complete the applicable Contributor License Agreement (CLA) before the PR is
   merged. See [`CLA.md`](CLA.md).
7. By contributing you agree your work is licensed under GPL-3.0-or-later (see
   [`LICENSE`](LICENSE)), subject to the CLA requirement above.

## Local Verification

Run the smallest useful check first; fall back to the full suite before
handoff.

```sh
# Rust + boundary
./tools/scripts/build.sh check-boundary
cargo check --manifest-path crates/core/Cargo.toml
cargo test  --manifest-path crates/core/Cargo.toml -- --quiet

# Flutter SDK
cd packages/flutter
flutter analyze --no-fatal-infos
flutter test

# Flutter demo
cd examples/flutter
flutter analyze --no-fatal-infos
flutter test
```

Prefer `flutter test --plain-name <name>` for focused tests when the blast
radius is small. Only use `flutter test --no-pub` when `pubspec.lock` is
unchanged and dependencies are already resolved.

For native artifacts:

```sh
./tools/scripts/build.sh fast android
./tools/scripts/build.sh fast ios
```

### Coverage

CI runs a `coverage` workflow (`.github/workflows/coverage.yml`) and uploads
both lcov reports as build artifacts. To reproduce locally:

```sh
# Rust (needs cargo-llvm-cov: `cargo install cargo-llvm-cov --locked`)
# Rust (napaxi-core; the api-boundary floor measures this crate)
cargo llvm-cov --package napaxi-core --lcov --output-path lcov.info
cargo llvm-cov --package napaxi-core report   # human-readable summary

# Flutter
cd packages/flutter && flutter test --coverage   # writes coverage/lcov.info
```

Two regression-catcher coverage floors are enforced in CI (`coverage.yml`):

- `tools/scripts/coverage-floor.sh lcov.info` — the core public API boundary
  (`crates/core/src/api/`), with `CORE_API_MIN_LINES` and
  `CORE_SRC_MIN_LINES` maintained directly in
  `tools/scripts/coverage-floor.sh`.
- `tools/scripts/flutter-coverage-floor.sh packages/flutter/coverage/lcov.info`
  — the Flutter SDK lib aggregate, with `FLUTTER_SDK_MIN_LINES` maintained
  directly in `tools/scripts/flutter-coverage-floor.sh`.

Treat these floors as reviewed regression baselines. Raise them when CI reports
a sustainably higher percentage, and lower them only with an explicit review
note explaining the test or instrumentation change. The Rust floor scopes to
`napaxi-core` rather than `--workspace` because the vendored
`libsql-sqlite3-parser` build script can break under `cargo llvm-cov`'s
instrumented target dir, and the api boundary lives entirely in `napaxi-core`.

## Pull Request Expectations

- All commits build and pass `check-boundary`.
- Public Dart SDK surface under `packages/flutter/lib/napaxi_flutter.dart`
  remains stable. If you must break it, call it out explicitly in the PR
  description and update [`CHANGELOG.md`](CHANGELOG.md).
- New capabilities update `crates/core/src/capabilities/`, the matching
  `api::*` wrapper, and [`docs/mobile-capabilities.md`](docs/mobile-capabilities.md)
  together.
- SDK-facing changes classify the affected contract, update matching adapter
  surfaces or explicit unsupported states, and include parity evidence from
  [`docs/sdk-adapter-parity.md`](docs/sdk-adapter-parity.md).
- Generated bridge files are regenerated, not edited by hand. The codegen
  command lives in `./tools/scripts/build.sh codegen`.
- Do not commit local build output, Flutter caches, machine-local absolute
  paths, or platform-prebuilt artifacts.

## License of Contributions

Napaxi is licensed under [GPL-3.0-or-later](LICENSE). All contributions are
accepted under that license. By submitting a contribution you certify that you
have the right to do so and that your contribution may be redistributed under
GPL-3.0-or-later.

## Contributor License Agreement

External contributions require a completed Contributor License Agreement before
merge. Use the Individual CLA when contributing as yourself, and the Corporate
CLA when the contribution is owned or controlled by an employer or other legal
entity.

The official Ant Group CLA forms and signing requirements are listed in
[`CLA.md`](CLA.md). Automated CLA enforcement depends on the code hosting
platform; until that check is enabled, maintainers may manually verify CLA
completion before merging external pull requests.

## Questions

If something is unclear, open a discussion or a draft PR with the question in
the description. We would rather answer early than rebuild later.
