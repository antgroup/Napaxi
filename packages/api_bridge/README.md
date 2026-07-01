# Napaxi API Bridge

Rust FFI bridge layer that exposes `napaxi_core::api` to platform adapters.

This crate produces `libnapaxi_api_bridge` (staticlib + cdylib) which is linked
by the Flutter Rust Bridge, Android JNI, and iOS Swift Package adapters. It
contains:

1. **C API surface** (`c_api/`) — `extern "C"` functions taking `i64` engine
   handles and JSON strings, returning C strings in the standard result
   envelope. This is the entry point for Android JNI and iOS Swift adapters.

2. **FRB bridge surface** (`bridge/`) — Typed functions consumed by the
   Flutter Rust Bridge code generator. They follow the same handle/JSON
   convention but use FRB-compatible types.

## Safety Guarantees

- Every `unsafe` block carries a `// SAFETY:` comment (enforced by
  `#![deny(clippy::undocumented_unsafe_blocks)]`).
- Every `extern "C"` entry point is wrapped in `catch_unwind`, returning a
  structured `err("panic", ...)` envelope on unwind. This prevents undefined
  behaviour when the crate is compiled with `panic = "abort"`.
- `cstr()` handles null pointers gracefully (returns empty string).
- `into_c_string()` sanitises interior NUL bytes via `\0` escape rather
  than truncating, preventing silent data corruption.
- `napaxi_api_string_free` has a documented safety contract: the caller must
  have exclusive ownership of the pointer.

## Wire Format

All functions return a JSON result envelope:

```json
{ "ok": true, "value": <any> }
```

or on error:

```json
{ "ok": false, "error": { "code": "<stable-code>", "message": "<human-readable>" } }
```

Error codes are defined in `docs/api-contract.md` and must remain stable across
releases.

## Legacy Compatibility

The C header exposes two sets of symbols:

- `napaxi_api_*` — canonical prefixed symbols (preferred).
- `napaxi_version` / `napaxi_string_free` — unprefixed aliases retained for
  backward compatibility with earlier integrations.

The Android bridge alias table (`android_bridge_alias`) maps ~50 legacy method
names for backward compatibility in the dispatch table.

## Testing

FFI roundtrip tests in `tests/ffi_roundtrip.rs` exercise the C ABI lifecycle:
workspace write/read/list, config retrieval, malformed config rejection, and
dead-handle error reporting. These are the only tests in the SDK that exercise
the actual FFI boundary.

```sh
cargo test -p napaxi_api_bridge
```

## Build

```sh
# Build the C static library for the current target
cargo build -p napaxi_api_bridge --release

# Cross-compile for Android
./tools/scripts/build.sh fast android

# Cross-compile for iOS
./tools/scripts/build.sh fast ios
```

## Related Packages

- [`crates/core`](../../crates/core/) — Runtime kernel providing `napaxi_core::api`
- [`packages/flutter`](../flutter/) — Flutter adapter consuming FRB bridge
- [`packages/android`](../android/) — Android adapter consuming C API via JNI
- [`packages/ios`](../ios/) — iOS adapter consuming C API via Swift
