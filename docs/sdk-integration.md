# SDK Integration

The Flutter demo consumes the repository-local SDK package:

```yaml
dependencies:
  napaxi_flutter:
    path: ../../packages/flutter
```

The SDK package uses the Rust crates in this repository, including `crates/core`, through local Cargo path dependencies.

## Native Build

Build native artifacts from the repository root:

```sh
./tools/scripts/build.sh fast android
./tools/scripts/build.sh fast ios
./tools/scripts/build.sh fast ios-all
```

On Windows, run direct `build.sh` commands from Git Bash. Android Gradle builds
auto-detect Git Bash for this script; if detection fails, set `NAPAXI_BASH` to
the full path of your Git Bash `bash.exe`.

Generated bridge outputs are intentionally ignored by git:

- `packages/flutter/android/jniLibs/*/libnapaxi_api_bridge.so`
- `packages/flutter/ios/Frameworks/napaxi_api_bridge.xcframework`
- `packages/ios/Frameworks/napaxi_api_bridge.xcframework`

Android proot runtime assets under `packages/flutter/android/assets` and the checked-in proot helper libraries are source assets for the SDK and should remain available. These prebuilt third-party binaries are stored via Git LFS; their provenance and integrity hashes are documented in `packages/flutter/android/jniLibs/THIRD-PARTY.md`, and their licenses (including GPL/LGPL) in `THIRD-PARTY-LICENSES.md`. A working `git lfs` install is required to check them out.
The native Swift Package in `packages/ios` is wired for the iOS QEMU sandbox
backend. iOS keeps the stable artifact name `alpine-rootfs.bin` but bakes a
separate lightweight rootfs profile instead of Android's full APK-build image:
Python, Node/npm, shell, curl/wget, zip/unzip, and git are included, while Codex
CLI, OpenJDK, Android SDK/build-tools, qemu-x86_64, and the x86_64 sysroot are
not packaged. The iOS shell sandbox capability becomes available when the QEMU
artifacts are linked, the rootfs resource is packaged, and the host enables the
capabilities; the Codex agent-engine capability remains disabled on iOS. The
generated `packages/ios/Frameworks/napaxi_api_bridge.xcframework` binary target
with headers/modulemap must still exist locally before opening the package in
Xcode or running SwiftPM iOS builds.
The native Swift Package declares iOS 16 as its minimum iOS deployment target.
The Rust bridge build defaults `NAPAXI_IOS_DEPLOYMENT_TARGET` to `16.0` so
generated xcframework object files match that minimum deployment target.

## Verification

```sh
./tools/scripts/build.sh check-boundary
./tools/scripts/build.sh check-ios
./tools/scripts/build.sh check-ios-native
./tools/scripts/build.sh check-ios-integration
./tools/scripts/build.sh check-ios-app
./tools/scripts/build.sh check-ios-device
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
./tools/scripts/build.sh check-ios-parity
cd packages/flutter && flutter analyze --no-fatal-infos && flutter test
cd examples/flutter && flutter analyze --no-fatal-infos && flutter test
```

When `HTTP_PROXY` or `HTTPS_PROXY` is set, make sure `NO_PROXY` includes
`localhost`, `127.0.0.1`, and `::1` before running `flutter test`; the Flutter
test harness uses a local socket between `flutter_tester` and the test runner.

`check-ios` is the offline native iOS SDK acceptance gate: it runs iOS/Flutter
public surface parity, native Swift Package iPhoneOS compile/tests, independent
host package integration, and the no-codesign Xcode app build. Run
`check-ios-device` preflights `devicectl` availability without building.
Run `check-ios-app-device` separately for physical-device launch proof.
Because the device smoke installs a signed app, `IOS_DEVELOPMENT_TEAM` is
required. Use `IOS_ALLOW_PROVISIONING_UPDATES=1` when Xcode should create or
update the local development certificate and provisioning profile.
Automatic provisioning still requires the matching Apple ID to be logged in and
valid in Xcode Accounts; an existing keychain certificate alone is not enough.
If Xcode reports `No Account for Team` or `No profiles for
'dev.napaxi.integration.iosapp' were found`, open Xcode settings, refresh the
Apple ID for that team, then rerun the device smoke with the same team id.

The physical-device gate requires `devicectl` to report an available iPhone.
If the preflight prints `tunnel=unavailable` or `developerMode=disabled`, fix
the device/Xcode pairing state before rerunning the app launch smoke. Typical
fixes are enabling Developer Mode on the iPhone, trusting/re-pairing the device
in Xcode, reconnecting USB, and waiting for Xcode to mount Developer Disk Image
services. A selected wired device may still print `ddiServices=false`; the
device smoke continues so install/launch can activate device support or fail
with the real CoreDevice/Xcode error.

## Current Limitations & Long-Term Plan

A few pieces of the integration story are intentional trade-offs rather than
the final shape. They are recorded here so integrators do not have to
reverse-engineer them.

### iOS QEMU sandbox

The native iOS SDK in `packages/ios` calls the same `napaxi_core::api` boundary
as the Flutter adapter through the stable C ABI. Shell-like platform execution
is routed through Napaxi's iOS QEMU backend. The contract keeps the stable
`alpine-rootfs.bin` resource name, but iOS uses a lightweight rootfs profile
instead of Android's full APK-build profile. The platform-specific runner is the
vendored lower-level QEMU C bridge and static libraries.

- Native Swift hosts should consume `packages/ios`; Flutter continues to
  consume `packages/flutter`. Both adapters share `packages/api_bridge` and
  `napaxi_core::api`.
- Do not depend on sandbox-specific filesystem layout or shell semantics from
  adapter code; route everything through `napaxi_core::api::platform`.
- If the iOS QEMU runtime is not linked or the rootfs is not packaged, the
  shell sandbox capability is disabled and the `napaxi_api_ios_qemu_*`
  readiness entrypoints return false. The Codex agent-engine capability remains
  disabled on iOS because the lightweight rootfs does not package Codex CLI.
- The native device gate requires a connected physical iOS device. It signs the
  integration app, installs it with `devicectl`, launches it, then copies back
  the app-written smoke report and checks the launch token plus native engine
  handle.

### Vendored `libsql`

`vendor/libsql-patched/` is a vendored copy of `libsql` with mobile build
fixes, wired through `[patch.crates-io]` in the workspace `Cargo.toml`.

- Patches are minimal and exist only to keep mobile targets building.
- Rebase cadence and exit criteria live in
  [`vendor/libsql-patched/NAPAXI-PATCH.md`](../vendor/libsql-patched/NAPAXI-PATCH.md).
- The intent is to delete this vendor directory once upstream builds cleanly
  for `aarch64-linux-android` and `aarch64-apple-ios` without local
  patches, and upstream CI catches future regressions on those targets.
