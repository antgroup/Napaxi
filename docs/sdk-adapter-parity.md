# SDK Adapter Parity

Napaxi keeps Flutter, Android, and iOS adapters aligned through a shared Core
API boundary, contract fixtures, and explicit unsupported states. This document
is the public checklist for SDK-facing changes.

## Principle

Reusable runtime behavior belongs in `crates/core` and reaches adapters through
`napaxi_core::api`. Adapter packages should be thin: host context, lifecycle,
permissions, background glue, typed facades, and platform execution.

When a feature is visible to SDK users, it should be classified for parity:

| Class | Meaning | Requirement |
| --- | --- | --- |
| Stable cross-adapter API | Public behavior expected on Flutter, Android, and iOS. | Update all adapters or add an explicit unsupported state. |
| Experimental API | Public but still evolving. | Keep contract fixtures current and document gaps. |
| Adapter-specific feature | Depends on platform-only capability. | Gate behind capability/profile and document platform support. |
| Demo-only behavior | Exists only in `examples/`. | Do not expose as reusable SDK behavior. |

## Evidence Checklist

For SDK-facing changes, include at least one of:

- Core API tests or fixtures.
- `packages/api_contract/` method/error/capability fixture updates.
- Flutter model/wrapper tests.
- Android Kotlin contract/model tests.
- iOS Swift contract/model tests.
- Documentation of an explicit unsupported state (for example, `napaxi.agent_engine.codex` is API-visible on Flutter/Android/iOS but currently runs only on Android and returns a clear unsupported error elsewhere).

## Required Updates

When adding or changing a public SDK surface:

1. Define or update the core API in `crates/core/src/api/`.
2. Keep `packages/api_bridge/` as a thin forwarding layer.
3. Update Flutter/Android/iOS typed facades where applicable.
4. Update shared fixtures or adapter tests.
5. Update user-facing docs, especially capability and integration docs.
6. Run the narrowest useful checks, then broader parity gates before handoff.

## Common Checks

```sh
./tools/scripts/build.sh check-boundary
./tools/scripts/build.sh check-android-parity
./tools/scripts/build.sh check-ios-parity
cd packages/flutter && flutter analyze --no-fatal-infos && flutter test
```

Native iOS checks are documented in [`sdk-integration.md`](sdk-integration.md).

## Explicit Agent App Provider Selection

Flutter, Android, and iOS expose `AgentProviderSelection` on their chat send
facades. The adapters encode the same one-turn canonical marker,
`@{provider:<provider_id>}`, before entering Core. Core resolves the Provider
before tool assembly, leaves the current/default Agent identity unchanged, and
does not persist the selection into later turns.

The same Agent App APIs expose `setAutoInvoke`/`set_auto_invoke` and return the
host-owned `auto_invoke_enabled`, `last_used_at`, and `use_count` package
metadata. Automatic invocation defaults off. Flutter, Android, and iOS must not
let Provider manifest values enable it; Core owns persistence and collision
validation for automatically exposed action tools.

Flutter, Android, and iOS Agent Provider install APIs also expose trusted
binding restore. Restore reuses the existing host instance id and shared
secret, keeps platform package/bundle and signing checks enabled, and never
registers a changed Provider identity implicitly. Flutter's platform action
executor may perform this restore automatically only for the standard
pre-execution `host_not_bound` failure and retries the unchanged request once.
The install APIs also expose trusted binding refresh. Refresh has the same
identity checks as restore but registers the latest Provider manifest in Core;
Core preserves host-owned auto-invoke and usage metadata. Android discovery
reports package version, last-update time, and explicit trusted-refresh
support. These values detect an in-place update but never replace package,
signing, Provider, or Agent identity validation.

Generated Android Agent Apps can also expose a model-hidden runtime diagnostics
endpoint. The Flutter Android Host bridge returns a typed
`AgentAppDiagnosticsSnapshot`; apps without the endpoint, Flutter on non-Android
platforms, native Android SDK hosts, and iOS currently return or document an
explicit unsupported state. Diagnostics are Provider-owned lifecycle data and
do not enter the Core tool/capability surface. The snapshot contains bounded
failure reports, structured runtime logs, and the Provider-owned detailed-log
setting; configuring that setting requires the same signed Host binding.

## Codex Model Configuration

Flutter, Android, and iOS expose matching typed model sync and clear methods.
The result contract contains `success`, `providerAvailable`, `modelUsable`,
`errorCode`, `error`, `model`, and `configChanged`. Android materializes the
selected main model into its Linux sandbox; iOS exposes the same API but keeps
Codex disabled until the `napaxi.platform.ios_qemu` sandbox backend is linked.
Other platforms return `unsupported_platform`. The raw TOML method remains
deprecated compatibility surface and is not a second configuration source.

The same adapters expose `listCodexAgentEngineThreads`,
`readCodexAgentEngineThread`, and `bindCodexAgentEngineThread`. Android queries
the core-owned app-server native thread store; iOS returns the typed
unsupported/not-ready result until the QEMU sandbox runner lands.

## Projects and Session Placement

Flutter, Android, and iOS expose the same project operations: register/list/
archive projects, get/list session placements, move a session with an explicit
workspace policy, and list project files. `SessionKey` has no project or
workspace field and therefore remains stable when a session moves.

The wire policies are `use_project_default`, `keep_current`, and
`use_personal_default`. Placement updates use an optional expected revision for
compare-and-swap conflict detection. A project is archived independently from
its workspace; files are retained and session display membership is cleared.

## Avoid

- Calling `mobile_*` implementation modules directly from adapters.
- Adding adapter options that toggle core behavior without a capability profile
  or explicit core API.
- Leaving silent gaps across adapters.
- Moving reusable runtime behavior into demo apps.
