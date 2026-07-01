# AGENTS.md

This file provides project instructions for AI coding agents working on Napaxi.

## Project Shape

- Napaxi is a mobile-native SDK project, not a Flutter-only project.
- `crates/core/` contains the Rust runtime kernel and adapter-facing API shared by the SDK.
- `crates/features/` contains feature-domain crates used by core, not adapter entrypoints.
- `vendor/` contains third-party patched or vendored dependencies such as `libsql-patched`.
- `crates/core/src/api/` is the common Napaxi Core API boundary for all adapters.
- `packages/` contains SDK adapter packages and binding bridge packages.
- `packages/api_bridge/` is the Rust FFI/FRB bridge over `napaxi_core::api`.
- `packages/api_contract/` is the adapter-layer API contract (methods, errors, capability matrix, fixtures) used by parity and integration checks.
- `packages/flutter/` is the Flutter adapter package.
- `packages/android/` is the native Android Kotlin SDK adapter.
- `packages/ios/` is the native iOS Swift Package SDK adapter.
- `packages/agent_provider/` is the provider-side SDK for Agent App actions (separate Android/iOS packages).
- Do not create a sibling `sdk/` tree or reintroduce `packages/napaxi_sdk`.
- `examples/` contains demo apps. Demo apps must consume SDK adapters and must not own reusable SDK implementation logic.
- `examples/flutter/` is the first demo target and depends on `../../packages/flutter`.
- `examples/flutter/` is an integration sample and capability validation app,
  not a second SDK layer. Keep UI state, demo-only models, pages, panels, and
  mockable demo clients there, but move reusable SDK/runtime behavior to
  `crates/` or `packages/`.
- `docs/` contains architecture, integration, and contribution documentation.
- `tools/scripts/` contains shared build, codegen, hygiene, and packaging helpers.

## SDK Boundary

- Runtime behavior belongs in `crates/`, especially `crates/core`.
- Packages must not depend on `crates/features/*` directly; feature behavior reaches adapters through `napaxi_core::api`.
- Feature crates must not depend on `crates/core`.
- Do not place third-party patched/vendor crates under `crates/core/` or `crates/features/`; use `vendor/`.
- SDK adapters must enter Rust core through `napaxi_core::api`; do not call `mobile_*` implementation modules directly from adapter code.
- Packages must not call top-level core internals such as `napaxi_core::android_assets`, `napaxi_core::android_linux_env`, or `napaxi_core::ios_ish_env`; expose adapter-needed hooks through `napaxi_core::api`.
- `mobile_*` module names are legacy implementation names, not public API. Do not add new `mobile_*` modules or crate-internal `crate::mobile_*` references. New runtime behavior should be typed/internal first, then explicitly exported through `api`.
- Do not add broad `pub use crate::mobile_*::*` exports in `crates/core/src/api`; keep API exports as small whitelists.
- Cross-cutting extension points belong in the core capability registry under
  `crates/core/src/capabilities/` and must be exposed through
  `napaxi_core::api::capability`.
- New LLM providers, built-in tools, MCP surfaces, platform tools, policy
  hooks, and background services must define a capability contract before they
  are exposed to adapters or demo apps.
- Channel/provider ownership has four layers. `crates/core` owns the reusable
  runtime, provider contract, capability/policy gates, and official first-party
  sans-IO protocol kits. `packages/api_bridge` only exposes `napaxi_core::api` to
  adapters. SDK adapter packages such as Flutter/Android/iOS stay thin: host
  context, lifecycle/background/permission glue, provider host wrappers, and FFI
  calls. Provider implementations own real platform I/O and may live in host
  apps, external packages, or optional first-party provider modules; demos must
  not own reusable provider/runtime logic.
- Official channel protocol decisions that must stay cross-adapter consistent
  should be core-owned as sans-IO helpers exposed through `napaxi_core::api`.
  Examples include payload shaping, endpoint routing, inbound normalization,
  webhook/gateway state machines, signing checks, Markdown/fallback mapping, and
  error/retry classification. Pin these protocol kits with shared fixtures so
  Flutter, Android, iOS, and tests bind one source of truth.
- External developers must be able to add channels without modifying `crates`.
  Their extension path is the SDK provider contract: register a manifest,
  submit normalized inbound messages, lease/deliver outbound messages, and let
  core handle routing, sessions, history, ask-human, policy, and outbound queue
  state. Add core APIs only when the shared channel contract is insufficient,
  not for every third-party provider.
- Real provider transports stay outside `crates/core` when they depend on
  platform lifecycle, OS permissions, vendor SDKs, secure storage, background
  execution, long-lived sockets, heartbeat timers, QR/login UI, Bluetooth, or
  host network policy. Core may own stateless, platform-neutral transports for
  domains that already live in core, but channel providers should default to
  sans-IO protocol in core plus transport in provider/host code.
- Capability IDs use stable reverse-domain-style SDK names such as
  `napaxi.llm.openai`, `napaxi.tool.shell`, or
  `napaxi.platform_tool.open_url`. Do not use adapter package names,
  generated bridge names, or demo names in capability IDs.
- V1 capabilities are compiled into the SDK and enabled through config or host
  declarations. Do not add runtime native plugin downloads or a plugin market
  path unless a task explicitly changes that architecture.
- Security or policy capabilities are core gates. Tool descriptor admission,
  tool invocation admission, provider admission, and model switching must not
  bypass the core policy chain.
- Prefer domain directories in `crates/core/src/` for implementation code, such as `runtime/`, `llm/`, `storage/`, `workspace/`, `session/`, `tools/`, `skills/`, `agents/`, `group/`, `mcp/`, `channel/`, `evolution/`, `platform/`, and `types/`.
- Core-owned Android/iOS environment implementations live under `crates/core/src/platform/`; adapter hooks should be routed through `api::platform`.
- Put implementation where ownership lives: runtime in `crates/`, adapter and host integration in `packages/`, demo-only code in `examples/`, shared build flow in `tools/scripts/`, and durable design notes in `docs/`.
- Keep crate roots conventional and small; do not use runtime crate roots as holding areas for detached specs, historical artifacts, or host build policy.
- Flutter integration should stay thin: adapt host platform context, FRB calls, and UI-facing models, but keep reusable runtime logic in Rust core.
- `packages/api_bridge/` is shared binding infrastructure, not Flutter internals. Keep it flat: root Rust entrypoints, `bridge/` for hand-written bridge modules, and `generated/` for codegen output.
- `packages/flutter/lib/` is flat by responsibility. Use `api/`, `models/`, `generated/`, `background/`, `platform_tools/`, and `convenience/`; do not add a persistent `lib/src/` layer.
- In `packages/flutter/android/`, keep manifest/assets/JNI/resources at the Android package root. Only Kotlin plugin source should remain under `android/src/main/kotlin/` for Flutter tooling.
- Mobile-specific capabilities such as platform bridges, file bridge support, background execution, platform context, and mobile tools belong in SDK adapters under `packages/`, not in demo apps.
- Flutter demo code must call public SDK APIs from `package:napaxi_flutter/napaxi_flutter.dart`; do not import generated bridge APIs, Rust core modules, SDK private files, or rely on storage/layout internals from the demo.
- Do not add dependencies on external monorepo paths or machine-local checkouts.

## Development Rules

- Prefer generic mobile SDK naming over Flutter-specific naming unless the file is explicitly inside a Flutter demo or Flutter package.
- Keep demo code integration-focused.
- Keep documentation short, concrete, and aligned with the repository layout.
- When adding a capability, update the core capability registry, adapter API
  wrappers, and `docs/mobile-capabilities.md` together.
- For SDK-facing changes, bug fixes, or behavior changes, preserve adapter
  parity across Flutter, Android, and iOS using
  `docs/sdk-adapter-parity.md`. Update matching adapter surfaces, shared
  fixtures/tests, or explicit unsupported states; do not leave silent gaps.
- Do not expose a new adapter option that directly toggles core behavior unless
  it maps to a capability profile, selection, or explicit core API.
- `.github/` may host issue and pull-request templates that mirror
  [`CONTRIBUTING.md`](CONTRIBUTING.md). Do not add `.github/workflows/`,
  `.cursor/`, or other tool-specific directories unless the task explicitly
  asks for that ecosystem support.
- Preserve existing user changes. Do not revert unrelated edits.

## Verification

- For bridge/core changes, run `./tools/scripts/build.sh check-boundary`.
- For SDK changes, run `cd packages/flutter && flutter analyze && flutter test`.
- For SDK public surface or wire-model changes, run the relevant adapter parity
  checks such as `./tools/scripts/build.sh check-android-parity` and the iOS
  parity/native checks described in `docs/sdk-adapter-parity.md`.
- For demo changes, run `cd examples/flutter && flutter analyze && flutter test`.
- For Android/iOS platform outputs, use `./tools/scripts/build.sh fast android` and `./tools/scripts/build.sh fast ios`.
- For Flutter validation, prefer the smallest useful verification first. Run a
  focused test file or `flutter test --plain-name ...` before full-suite
  `flutter test` when the change is local and the blast radius is small.
- Do not rerun full `flutter analyze` and full `flutter test` after every small
  edit by default. Use full Flutter validation for broader changes, before
  handoff, or when focused checks fail to give enough confidence.
- Use `flutter test --no-pub` only when `pubspec.yaml` and `pubspec.lock` are
  unchanged and dependencies are already resolved for that package directory.
  If dependencies changed, were cleaned, or have not been fetched in the
  current environment, run without `--no-pub`.

See `docs/ai-coding-guidelines.md` for more context.
