# AI Coding Guidelines

This document records repository-specific guidance for AI coding tools and human reviewers.

## Repository Intent

Napaxi is intended to be a mobile-generic SDK repository. Flutter is the first SDK adapter and demo target, but repository structure and naming should not imply that the project is only for Flutter.

## Boundaries

- Shared runtime logic belongs under `crates/core/`.
- Feature-domain logic belongs under `crates/features/`.
- The common adapter-facing Rust API belongs under `crates/core/src/api/`.
- SDK adapter and binding bridge packages belong under `packages/`.
- The Rust FFI/FRB bridge belongs under `packages/api_bridge/`.
- The Flutter adapter belongs under `packages/flutter/`.
- Demo code belongs under `examples/`.
- The Flutter demo belongs under `examples/flutter/`.
- Documentation belongs under `docs/`.
- Shared build/codegen/hygiene scripts belong under `tools/scripts/`.

Reusable SDK logic should not be placed inside demo apps. If a demo needs reusable behavior, move that behavior into an SDK adapter or Rust crate and let the demo consume it.

## Core And Features

- `crates/core/` is the runtime kernel and adapter-facing API owner. Its Cargo
  package remains `napaxi-core` and Rust library remains `napaxi_core`.
- `crates/features/*` contains domain feature crates used by core, not by
  packages directly.
- Feature crates must not depend on `crates/core`.
- Packages must not depend on feature crates directly; feature behavior reaches
  adapters through `napaxi_core::api`.
- Keep repository folder names concise inside `crates/`; do not add redundant
  `napaxi-` prefixes to crate directories.
- Third-party patched or vendored dependencies belong under `vendor/`, not under
  `crates/core/` or `crates/features/`.

## Core And Adapter Guidance

- SDK adapters should enter Rust through `napaxi_core::api::*`.
- Do not call `napaxi_core::mobile_*` implementation modules directly from adapter code.
- Do not call top-level core implementation modules such as
  `napaxi_core::android_assets`, `napaxi_core::android_linux_env`, or
  `napaxi_core::ios_ish_env` from packages; expose required hooks through
  `napaxi_core::api`.
- Treat `mobile_*` module names as legacy implementation names. Do not add new
  `mobile_*` modules or crate-internal `crate::mobile_*` references.
- New runtime behavior should be implemented in typed/internal core code first,
  then explicitly exported from the matching `api` module.
- Do not add `pub use crate::mobile_*::*` to `api`; use a small whitelist.
- Prefer domain directories for core implementation code, such as `runtime/`,
  `llm/`, `storage/`, `workspace/`, `session/`, `tools/`, `skills/`,
  `agents/`, `group/`, `mcp/`, `channel/`, `evolution/`, `platform/`, and
  `types/`.
- Core-owned Android/iOS environment implementations belong under
  `crates/core/src/platform/`, with adapter-needed hooks exposed through
  `api::platform`.
- Keep `crates/core/src/api/` adapter-neutral: no Flutter, Dart, FRB,
  Kotlin, Swift, MethodChannel, Pod, Gradle, or generated bridge concepts.
- Put runtime policy in core API or lower Rust implementation modules:
  workspace paths, session scope, skill storage, catalog operations, tool
  descriptor schema, approval/risk metadata, event schemas, and attachment
  metadata normalization.
- Put host glue in adapters: platform context, generated bridge bindings,
  plugin/service code, host capability declaration, host tool execution, and
  typed UI-facing wrappers.
- Flutter convenience helpers, such as local config storage, belong under
  `packages/flutter/lib/convenience/` and should be exported from
  `package:napaxi_flutter/convenience.dart`, not from the stable default entry.

## Capability Guidance

Napaxi extension points are core-owned capabilities, not ad hoc adapter toggles.
New capabilities should follow this order:

- Define the capability contract in `crates/core/src/capabilities/` with a
  stable `napaxi.*` ID, kind, version, platform support, risk, requirements,
  config schema, activation mode, and default-enabled behavior.
- Implement reusable behavior in core-owned runtime modules or feature crates,
  then expose only the adapter-needed API through `napaxi_core::api`.
- Add bridge and adapter wrappers under `packages/` after the core contract is
  stable. Host code may declare support and execute host-owned actions, but it
  must not own reusable runtime policy.
- Keep registered, available, and enabled states separate. A capability being
  compiled into the SDK does not mean the current host can carry it or that
  runtime config enabled it.
- Route LLM providers, built-in tools, platform tools, MCP surfaces, custom
  host tools, and media tools through the capability registry when adding or
  changing their public behavior.
- Treat policy/security capabilities as core admission gates. Descriptor
  admission, invocation admission, provider admission, and future model
  switching checks must pass through the core policy chain.

Do not add runtime native plugin downloads, plugin marketplace behavior, or
adapter-local plugin registries for v1 capability work unless the task
explicitly changes this architecture.

## Repository Placement Guidance

- Put implementation where ownership lives: runtime in `crates/`, adapter and
  host integration in `packages/`, demo-only code in `examples/`, shared build
  flow in `tools/scripts/`, and durable design notes in `docs/`.
- Keep crate roots conventional and small: Cargo metadata, source, tests, and
  crate-owned active assets or fixtures.
- Do not use runtime crate roots as holding areas for detached specs,
  historical artifacts, or host build policy.
- Interface specs and storage schemas should live with the component that owns
  and exercises them, or remain in `docs/` while still design material.

## Packages Guidance

- Do not create a sibling `sdk/` tree. SDK adapters and bridge packages belong
  under `packages/`.
- Do not reintroduce `packages/napaxi_sdk` or `package:napaxi_sdk/...`.
- Keep `packages/api_bridge/` adapter-neutral. It bridges bindings to
  `napaxi_core::api`; runtime rules stay in core.
- Keep `packages/api_bridge/` flat. Hand-written Rust lives at package root or
  under `bridge/`; generated Rust lives under `generated/`. A temporary
  codegen-only `src/` directory must be removed by tooling.
- Keep `packages/flutter/lib/` flat by responsibility. Use directories such as
  `api/`, `models/`, `generated/`, `background/`, `platform_tools/`, and
  `convenience/`; do not add a persistent `lib/src/` layer.
- Do not edit generated bridge files by hand.
- In `packages/flutter/android/`, keep manifest, assets, JNI libraries, and
  resources at the Android package root. Keep Kotlin plugin source under
  `android/src/main/kotlin/` because Flutter tooling requires that path.

## Demo App Guidance

`examples/flutter` is the single Flutter integration sample and capability
validation app. Keep it useful for host-app integrators, but do not let it become
a second SDK layer.

- Add new demo UI code to the existing `app/`, `demo_client/`, `models/`,
  `screens/`, `panels/`, or `widgets/` areas instead of growing `main.dart`.
- Demo client adapters are demo-only test seams. They must call public
  `napaxi_flutter` APIs and should not expose SDK internals as a new contract.
- If a demo feature needs workspace path rules, session compatibility, skill
  storage, tool dispatch, attachment metadata normalization, or other reusable
  behavior, implement that behavior in `crates/` or `packages/` and call it from
  the demo through the public SDK.
- Do not import generated bridge APIs, Rust core modules, or SDK private files
  from demo code.

## SDK Adapter Parity Guidance

Flutter demo work may prototype SDK behavior first, but the demo must not
become the contract owner. For any SDK-facing change, bug fix, or behavior
change, classify the contract impact and follow
[`sdk-adapter-parity.md`](sdk-adapter-parity.md).

- Treat public API methods, JSON fields, enum values, event shapes, error codes,
  default values, and state transitions as adapter contracts.
- Update Flutter, Android, and iOS adapter surfaces together, or add an
  explicit unsupported/experimental state for platforms that cannot carry the
  behavior yet.
- Add shared fixtures or golden behavior tests when a bug fix changes wire
  shape or runtime semantics.
- Run the relevant parity gates before handoff. Do not claim parity from a
  narrow demo test that does not cover the changed SDK contract.

## Naming Guidance

Use names that preserve the generic mobile SDK direction. Avoid prematurely naming reusable runtime components after Flutter unless the package is specifically a Flutter adapter.

Good default language:

- SDK package
- mobile runtime
- mobile capability
- platform bridge
- demo app

Avoid using "plugin" as the only model for mobile capabilities unless a concrete implementation is actually plugin-based.

## Tooling Guidance

`AGENTS.md` is the cross-agent entrypoint. `CLAUDE.md` exists for Claude Code compatibility and should point back to the shared instructions.

Do not add `.github/`, `.cursor/`, or similar tool-specific directories unless there is an explicit decision to support that tool or hosting workflow.

## Flutter Verification Guidance

Flutter CLI validation can be noticeably slow because `flutter analyze` and
`flutter test` commonly trigger dependency checks that print
`Resolving dependencies...` and `Downloading packages...` before doing useful
work. Treat full Flutter validation as a deliberate step, not something to rerun
after every small edit.

- Prefer the smallest useful verification first. For local demo/UI changes,
  start with a focused test file, a `flutter test --plain-name ...` filter, or
  another narrow check that directly exercises the change.
- Use full `flutter analyze` and full `flutter test` when the change spans
  multiple areas, touches shared SDK behavior, changes public contracts, or is
  about to be handed off.
- If a focused check fails in a way that suggests wider breakage, escalate to
  broader Flutter validation.
- Summarize what was actually run. Do not imply that a full Flutter suite was
  executed when only a focused check was used.

### When To Use `flutter test --no-pub`

`flutter test --no-pub` skips the automatic pub get step. It is appropriate only
when all of the following are true:

- `pubspec.yaml` and `pubspec.lock` are unchanged for that package.
- Dependencies were already resolved in the same package directory.
- No cleanup step removed `.dart_tool/` or otherwise invalidated the previous
  resolution.
- The goal is to rerun tests faster without changing the dependency graph.

Do not use `--no-pub` when:

- `pubspec.yaml` or `pubspec.lock` changed.
- The package has not fetched dependencies in the current environment yet.
- A prior command reported missing packages or stale resolution state.
- A clean checkout, cache reset, or cleanup step may have removed the resolved
  package state.

When in doubt, run `flutter test` without `--no-pub` once to establish a valid
dependency state, then use `flutter test --no-pub` for repeated local reruns.
