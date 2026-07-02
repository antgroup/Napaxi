# Packages

SDK adapters and binding bridge packages live here.

- `api_contract/`: Contract-first SDK adapter goals, method inventory,
  capability matrix, and standard wire error envelope.
- `api_bridge/`: Rust FFI/FRB bridge over `napaxi_core::api`.
- `flutter/`: Flutter adapter package.
- `ios/`: Native Swift Package adapter over the stable C ABI.
- `android/`: Native Kotlin Android adapter over the shared JNI bridge.
- `agent_provider/`: Provider-side protocol helper packages.


## SDK Adapter 2.0 Target

`packages/` is moving toward a contract-first adapter model:

```text
napaxi_core::api contract
  -> api_bridge wire methods
  -> Flutter / iOS / Android typed facades
  -> cross-platform golden tests
```

See `api_contract/` for the target contract, standard error envelope, method
inventory, and capability matrix. New public package APIs should start from that
contract, carry a stability label (`stable`, `experimental`, `compat`, `raw`, or
`generated`), and avoid adding new error sentinels such as `false`, `0`, or an
empty string.

## Rules

- Keep all SDK adapter and bridge packages under `packages/`; do not create a
  sibling `sdk/` tree.
- Do not reintroduce a generic `napaxi_sdk` package. Adapter package names should
  describe their role.
- `api_bridge/` delegates to `napaxi_core::api` and does not own runtime policy.
- `api_bridge/` stays flat: root Rust entrypoints, `bridge/` for hand-written
  bridge modules, and `generated/` for FRB output.
- `flutter/lib/` stays flat by responsibility; do not add `lib/src/`.
- Generated bridge files are codegen-owned and should not be edited by hand.
- `flutter/android/` keeps manifest, assets, JNI libraries, and resources at
  package root. Kotlin plugin source remains under `android/src/main/kotlin/`
  because Flutter tooling requires that path.
