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
- Documentation of an explicit unsupported state.

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

## Avoid

- Calling `mobile_*` implementation modules directly from adapters.
- Adding adapter options that toggle core behavior without a capability profile
  or explicit core API.
- Leaving silent gaps across adapters.
- Moving reusable runtime behavior into demo apps.
