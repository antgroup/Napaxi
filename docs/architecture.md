# Architecture

Napaxi contains repository-owned runtime crates, feature crates, and thin mobile
SDK adapters.

```text
Mobile App
  -> SDK adapter (`packages/flutter`, `packages/android`, `packages/ios`, ...)
  -> Napaxi Core API (`crates/core/src/api`)
  -> Runtime core (`crates/core`)
  -> Feature domain crates (`crates/features/*`)
  -> Android proot / iOS iSH platform environments where enabled
```

Demo apps consume SDK adapters through public integration surfaces only.
Reusable runtime behavior belongs in `crates/`, and adapter-specific host glue
belongs in `packages/`, not in `examples/`.

## Crates Layout

`crates/core/` is the Napaxi runtime kernel and the only Rust crate that SDK
adapters should enter. Its Cargo package remains `napaxi-core` and its Rust
library name remains `napaxi_core`, but the repository path omits the repeated
project prefix.

Core owns runtime orchestration and adapter-facing boundaries: `api`, engine
handles, chat/session/workspace/file policy, storage, tool registry and tool
loop, platform-neutral events and wire DTOs, platform hooks, and the integration
points that compose feature crates into the runtime.

`crates/features/` contains capability-domain crates that core uses. Feature
crates are not adapter entrypoints and must not depend on `crates/core`.
Current feature crates are:

- `crates/features/skills/`: skill manifests, SKILL.md parsing, validation,
  registry, and catalog domain logic.
- `crates/features/evolution/`: memory/skill review, pending actions,
  rollback, counters, and evolution policy.

Dependency direction is one-way:

```text
features/skills
  <- features/evolution
  <- core
  <- packages/api_bridge
```

Packages must not depend on feature crates directly. If an adapter needs a
feature behavior, expose it through `napaxi_core::api`.

`vendor/` contains third-party patched or vendored dependencies. These are not
Napaxi first-party crates and should not live under `crates/core/` or
`crates/features/`. The current `vendor/libsql-patched/` crate patches
`libsql` for mobile build/runtime compatibility through the workspace
`[patch.crates-io]` table.

## Core API Boundary

`crates/core/src/api/` is the common Napaxi Core API boundary for all SDK
adapters. Flutter, native Android/iOS adapters, React Native, and other
bindings should enter core through this namespace rather than calling
implementation modules directly.

The core API owns runtime semantics: engine handles, session scope, agent scope,
workspace and file path policy, skill and catalog operations, group/MCP APIs,
tool descriptors, tool risk and approval metadata, and event/wire schemas.

The core API must stay adapter-neutral. It must not mention Flutter, Dart, FRB,
Kotlin, Swift, MethodChannel, Pod, Gradle, or any generated bridge detail.
Adapter-friendly DTOs and JSON helpers belong under `api::wire`.

Legacy mobile-prefixed modules are implementation details. SDK adapters may call
`napaxi_core::api::*`, but should not import those internal modules directly.
The matching public type prefix and old platform-tool helper names have been
retired from the SDK surface; see `docs/naming-migration.md`. The boundary
check `tools/scripts/build.sh check-hygiene` keeps those prefixes from
reappearing.

## Capability Architecture

Napaxi extension points are core-owned capabilities. A capability is a compiled
SDK contract that can be discovered, checked against host support, and enabled
through explicit config. V1 does not dynamically download native plugins or
load a plugin marketplace at runtime.

`crates/core/src/capabilities/` owns the registry. Each capability has a stable
ID, kind, version, platform support, config schema, risk level, requirements,
default-enabled flag, and activation mode. Current capability kinds are
`llm_provider`, `tool`, `platform_tool`, `mcp`, `policy`, `service`, and
`agent_engine`. Adapters see these through `api::capability`.

Capability state has three separate concepts:

- Registered: the SDK binary contains the capability definition.
- Available: the current platform and host declaration can satisfy it.
- Enabled: runtime selection/config allows it to participate in execution.

Runtime engines persist the host capability profile and selection created at
engine initialization. Capability status queries, LLM provider routing, tool
descriptor admission, and tool invocation admission should all resolve against
that engine-scoped view unless an API explicitly supplies an override profile
or selection.

Engine state is kept inside the runtime scope wherever possible. Custom
tool pending responses are owned by the engine tool registry, human-loop
interjections and cancellation are files-dir scoped, MCP dynamic headers are
files-dir scoped, evolution in-flight review keys include the files dir, and
the admission decision trace is per-engine (via a `tokio::task_local` sink).
Policy hooks remain process-global by design (a host installs its chain once
per process); the documented invariant is that hooks are stateless predicates,
so sharing them across engines is safe.

Host adapters declare what they can carry through a capability profile. For
example, Flutter may declare `napaxi.platform_tool.*` when platform tools are
enabled. Core still decides status and routes execution through runtime-owned
registries. Host code executes platform/custom tools, collects platform
context, and exposes UI-facing wrappers, but it must not invent reusable
runtime policy.

LLM providers are capability-backed provider routes. OpenAI-compatible,
OpenAI, Anthropic, and Gemini are built-in provider capabilities; provider
aliases such as GLM and NearAI route through the OpenAI-compatible path.
Adding a provider requires a capability definition, provider route, tests, and
adapter model updates if the public config surface changes.

Tools are capability-backed even though the model still sees normal tool
descriptors. Built-in tools, MCP management tools, media tools, platform tools,
and host custom tools must be traceable to a capability ID where core owns that
mapping. Platform tool names, parameter schemas, risk, and permission
requirements remain core contracts shared by all adapters.

Agent App actions are a specialized host-carried tool capability:
`napaxi.tool.agent_app_action`. Agent App packages live in the agent domain,
generate or update an `AgentDefinition`, and expose only that Agent's action
manifest as tools during its turns. Core creates persisted proposals and
brokers results, while the connected app or backend owns confirmation, risk
checks, execution, and trusted result return. The detailed contract lives in
`docs/agent-app-actions.md`.

Policy capabilities are core gates, not optional side modules. Descriptor
admission, invocation admission, provider admission, agent-engine admission,
and service admission must pass through the core policy chain. Service-kind
capabilities (`napaxi.a2a.local`, `napaxi.a2a.deeplink`,
`napaxi.service.automation`) have their own `Service` admission gate at their
entry surface (accepting an A2A peer/deep-link, running a received task,
running an automation job) — the policy chain runs before any I/O, so a host
can deny a whole service, and every entry is traced. A security feature can add
a policy implementation, but it must not be the only code path enforcing policy.

The admission gate, the policy hook registration API, and the per-engine
admission trace are documented in `docs/capability-admission.md`. Policy hooks
are process-global (a host installs its policy chain once per process); the
admission *trace* is per-engine — each engine's `admission_trace()` returns
only its own decisions, scoped via a `tokio::task_local` sink set at the
turn/service/task entry points. New gates must be added to the allowlist in
`tools/scripts/build.sh::check_capability_admission` so the boundary check
fails if a duplicate gate appears somewhere unexpected.

## Core Crates Boundary

`napaxi-core` exposes SDK-facing runtime behavior through `napaxi_core::api`.
Adapter packages must not import implementation modules such as `mobile_*`,
`android_assets`, `android_linux_env`, or `ios_ish_env` directly.

`mobile_*` module names are legacy implementation names and should not be
reintroduced. New adapter-facing behavior must first be implemented as
typed/internal runtime code and then explicitly exposed through the matching
`api` module. Do not add broad `pub use crate::mobile_*::*` exports.

Core runtime implementation directories should be named by domain. Current
runtime implementation lives under domain directories such as
`crates/core/src/runtime/`, `llm/`, `storage/`, `workspace/`, `session/`,
`tools/`, `skills/`, `agents/`, `group/`, `mcp/`, `channel/`, `evolution/`,
`platform/`, and `types/`.

Platform hooks that adapters need, such as Android asset manager registration,
belong behind `api::platform` rather than top-level platform implementation
modules.

Core-owned platform environment implementations live under
`crates/core/src/platform/`. Keep root-level core files for API, runtime,
and domain modules rather than Android/iOS environment details.

### Repository Placement

Repository structure should communicate ownership. Runtime implementation
belongs in the owning Rust crate, SDK adapter and host integration code belongs
in `packages/`, demo-only code belongs in `examples/`, shared build flow belongs
in `tools/scripts/`, and durable design notes belong in `docs/`.

Keep crate roots conventional and small. A crate root should contain Cargo
metadata, source, tests, and assets or fixtures that the crate actively owns.
Do not use runtime crate roots as holding areas for old experiments, detached
specs, host build policy, or historical server artifacts.

Build and packaging policy should be explicit in shared scripts or package
tooling rather than hidden inside unrelated runtime crates. Interface specs and
storage schemas should live with the component that owns and exercises them, or
remain in `docs/` while they are still design material.

## SDK Adapter Boundary

`packages/` contains thin adapter packages and binding bridge packages.
`packages/api_bridge/` is the Rust FFI/FRB bridge over `napaxi_core::api`, and
`packages/flutter/` is the Flutter adapter using the Dart package name
`napaxi_flutter`, `packages/android/` is the native Android Kotlin adapter, and
`packages/ios/` is the native iOS Swift Package adapter.

`packages/api_contract/` is the adapter-layer API contract: method definitions,
error codes, capability matrix, and response fixtures. It serves as the
machine-readable source of truth that parity and integration checks validate
against. The contract is language-agnostic; each adapter's test suite verifies
that its surface matches the contract.

`packages/agent_provider/` is the provider-side SDK for Agent App actions (host
side and provider side). It ships as separate Android and iOS packages so that
third-party apps can integrate the provider protocol without depending on the
full Napaxi SDK.

Adapters may own host integration code: platform context collection, generated
bridge bindings, Flutter/Kotlin/Swift plugin glue, background service plumbing,
host capability declaration, host tool execution, and UI-facing typed wrappers.

Adapters must not own reusable runtime policy such as workspace path rules,
session fallback logic, skill storage, catalog behavior, tool descriptor schema,
attachment metadata normalization, or cross-adapter event semantics. Those
belong in `crates/core/src/api/` or lower Rust implementation modules.

Flutter keeps Rust JSON wire shapes behind typed model/facade methods. New SDK
surface should return Dart models or primitives rather than exposing raw JSON
strings. Internal JSON decoding helpers may live under `lib/api/`, but they are
not part of the stable public export.

Skill catalog integration is a provider boundary. The current provider may be
backed by ClawHub, but core SDK architecture should refer to it as the skill
catalog provider so another catalog implementation can replace it later.

The stable Flutter import is:

```dart
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
```

Advanced raw file/workspace APIs are exported from
`package:napaxi_flutter/advanced.dart`. Flutter convenience helpers such as local
configuration storage are exported from `package:napaxi_flutter/convenience.dart`
and are not core runtime configuration sources.

### Packages Layout Rules

`packages/` is the only home for SDK adapters and binding packages. Do not add
a sibling `sdk/` tree, and do not reintroduce a generic `napaxi_sdk` package.
Package directory names should describe adapter roles, such as `api_bridge/` or
`flutter/`.

`packages/api_bridge/` is shared binding infrastructure, not a Flutter package
subdirectory. It should expose FRB/FFI functions that delegate to
`napaxi_core::api`, and it should not own runtime policy. Its committed layout is
flat: Rust entrypoints live at package root, hand-written bridge modules live
under `bridge/`, and generated Rust lives under `generated/`. A temporary
codegen-only `src/` directory may be created by scripts, but it must not remain
in the working tree.

`packages/flutter/` is the Flutter adapter. Its Dart package name is
`napaxi_flutter`; its stable public entrypoint is `lib/napaxi_flutter.dart`.
Keep Dart modules directly under `lib/` by responsibility, for example `api/`,
`models/`, `generated/`, `background/`, `platform_tools/`, and `convenience/`.
Do not add a persistent `lib/src/` layer.

Generated bridge files are owned by codegen and must not be edited by hand:
`packages/flutter/lib/generated/`,
`packages/api_bridge/generated/frb_generated.rs`, and
`packages/flutter/ios/Classes/frb_generated.h`.

Android packaging in `packages/flutter/android/` should keep manifest, assets,
JNI libraries, and resources directly under the Android package root. The only
allowed `android/src/main/...` path is Kotlin plugin source, because Flutter
tooling requires the plugin class there.

Native artifact names follow the bridge package, not the Flutter adapter:
Android loads `libnapaxi_api_bridge.so`, and iOS packages
`napaxi_api_bridge.xcframework`.

## Demo App Boundary

`examples/flutter` is a single Flutter integration sample and capability
validation app. It exists to show how a host app consumes the Napaxi SDK and to
exercise SDK behavior through public integration surfaces. It is not a complete
product app, a reusable application framework, or proof that the repository is
Flutter-only.

The demo is not an SDK abstraction layer. It may contain UI state, demo-only
view models, mockable client adapters, pages, panels, and widgets. Reusable
runtime or SDK behavior must live in `crates/` or `packages/`.

Demo code should consume Napaxi through:

```dart
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
```

Demo code must not depend on SDK internals such as generated bridge modules,
SDK private source files, Rust core modules, storage layouts, session
compatibility details, workspace path rules, skill storage locations, tool
dispatch rules, attachment metadata normalization, or background execution
runtime policy.

If the demo needs reusable behavior, add that behavior to `crates/` or `packages/`
and then call it from the demo through the public SDK.

### Demo Layout

Keep `examples/flutter/lib` organized by responsibility:

- `main.dart`: app entrypoint and part-file assembly only.
- `app/`: app shell, theme, language scope, localized strings.
- `demo_client/`: demo-only SDK adapter and mockable client interface. This is a
  test seam, not a public SDK contract or recommended host-app abstraction.
- `models/`: demo view models and configuration state.
- `screens/`: page-level widgets.
- `panels/`: feature panels for sessions, workspace, skills, and similar areas.
- `widgets/`: reusable demo UI widgets.

New demo UI should go into the matching area instead of growing `main.dart`.

### Demo Tests

Demo tests should validate public SDK integration behavior and UI expression.
They should use shared test support fakes rather than duplicating mock clients,
and they should not assert SDK/core implementation details.
