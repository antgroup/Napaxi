# Scripts

Shared build, codegen, hygiene, and packaging scripts live here.

Run them from the repository root, for example:

```bash
./tools/scripts/build.sh check-boundary
./tools/scripts/build.sh check-android-parity
./tools/scripts/build.sh check-ios-parity
./tools/scripts/build.sh check-ios
./tools/scripts/build.sh check-android-integration
./tools/scripts/build.sh check-android-integration-device
./tools/scripts/build.sh check-ios-native
./tools/scripts/build.sh check-ios-integration
./tools/scripts/build.sh check-ios-app
./tools/scripts/build.sh check-ios-device
./tools/scripts/build.sh check-ios-app-device
```

Check the public Android SDK migration surface against Flutter:

```bash
./tools/scripts/check-android-flutter-parity.js
```

Check the public iOS SDK migration surface, including Flutter generated bridge
function names, against Swift:

```bash
./tools/scripts/build.sh check-ios-parity
```

Run the offline native iOS SDK acceptance gate:

```bash
./tools/scripts/build.sh check-ios
```

This runs iOS/Flutter public surface parity, native Swift Package compile/tests
for iPhoneOS, independent host package integration, and the no-codesign Xcode
app build. It intentionally excludes the physical-device launch smoke; run
`check-ios-app-device` separately when a usable iPhone is connected.

Build and compile-check the native iOS Swift Package:

```bash
./tools/scripts/build.sh check-ios-native
```

This regenerates the Flutter and native Swift Package xcframeworks, then runs a
SwiftPM iPhoneOS build with tests of `packages/ios` so the iOS QEMU bridge placeholders, binary
bridge, Swift SDK target, and XCTest compile surface are checked together.
The Rust iOS bridge build defaults `NAPAXI_IOS_DEPLOYMENT_TARGET` to `16.0`;
set that environment variable when intentionally changing the package minimum.

Compile-check an independent native iOS host package consuming `packages/ios`:

```bash
./tools/scripts/build.sh check-ios-integration
```

This compiles `examples/integration/ios/host` and its XCTest target for
iPhoneOS, then runs the host-side smoke tests on macOS.

Build the native iOS integration app in `examples/integration/ios/app` through Xcode:

```bash
./tools/scripts/build.sh check-ios-app
```

Run the native iOS integration app on a connected iPhone:

```bash
./tools/scripts/build.sh check-ios-device
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
```

The device preflight checks `devicectl` state without building the SDK or app.
The device gate builds a signed app for the selected physical iOS device,
installs it with `devicectl`, launches it, copies the app-written smoke report
back from the app data container, and verifies the launch token plus native
engine handle. Set `IOS_DEVICE_ID` when more than one usable device is
connected; explicit device ids are still validated against `devicectl` before
any build starts. Set `IOS_ALLOW_PROVISIONING_UPDATES=1` when Xcode should
create or update provisioning profiles. `IOS_DEVELOPMENT_TEAM` is required
because the integration app project intentionally does not check in a team id.
Automatic provisioning still requires a valid Xcode Accounts login for that
team. `No Account for Team` means the keychain certificate may exist, but Xcode
cannot create or refresh profiles until the Apple ID is added or refreshed in
Xcode settings.

If `check-ios-device` reports devices with `tunnel=unavailable` or
`developerMode=disabled`, the SDK/app build is not the blocker yet. Enable
Developer Mode on the iPhone, trust or re-pair it in Xcode, reconnect USB, and
wait for Xcode/CoreDevice to finish Developer Disk Image services before
rerunning `check-ios-app-device`. A selected wired device may still print
`ddiServices=false`; the smoke continues so install/launch can activate device
support or fail with the real CoreDevice/Xcode error.

The generated bridge check requires exact `public func` Swift entrypoints for
Flutter bridge functions, so raw migration aliases cannot pass by merely
appearing in comments or unrelated helper code.
The summary also reports top-level generated bridge coverage while those raw
migration wrappers are being filled in domain by domain.

## FRB version consistency gate

`./tools/scripts/build.sh check-frb-version` (DIMA workitem 2026111700120705360)
guards the codegen/runtime drift class that SIGABRTs the app on launch:
`flutter_rust_bridge`'s runtime hard-asserts that the codegen version baked
into `frb_generated.dart` / `frb_generated.rs` equals the crate / pub package
that actually links. The gate compares five values and fails on any mismatch:

- `codegenVersion` in `packages/flutter/lib/generated/frb_generated.dart`
- `FLUTTER_RUST_BRIDGE_CODEGEN_VERSION` in `packages/api_bridge/generated/frb_generated.rs`
- the `flutter_rust_bridge = "=X.Y.Z"` pin in `packages/api_bridge/Cargo.toml`
- the resolved `version:` of `flutter_rust_bridge` in `packages/flutter/pubspec.lock`
- the resolved `version:` of `flutter_rust_bridge` in `examples/flutter/pubspec.lock`

It also verifies `packages/flutter/pubspec.yaml` declares `flutter_rust_bridge`
with a lower bound `>=2.13.0`, so pub cannot resolve to a pre-2.13.0 release
and silently re-introduce the drift. CI runs this step in `checks.yml`,
`flutter.yml` (both `sdk` and `demo` jobs), and `native.yml` (both `android`
and `ios` jobs).

After touching the bridge crate or bumping the Cargo / pubspec pin:

```
./tools/scripts/build.sh codegen
./tools/scripts/build.sh check-frb-version
cd packages/flutter && flutter pub get
cd examples/flutter && flutter pub get
```

Skipping `check-frb-version` lets codegen output slide out of sync with the
linked flutter_rust_bridge runtime, which is exactly the regression that
crashed the iOS device launch in the original incident.

## Device smoke survival window

The device smoke checks (`check-android-integration-device`,
`check-ios-app-device`) treat the app staying alive for N seconds after launch
as a pass condition rather than just relying on the launch return code. Set
`NAPAXI_DEVICE_SURVIVAL_SECONDS` (default `5`) to widen the window; the
gate polls once per second and FAILs immediately if the process disappears
within the window — catching the SIGABRT-at-launch false positive that
prompted this work.

## Layer 3: physical device regression

`./tools/scripts/layer3_device_regression.sh` runs the Maestro smoke flows on
physical devices: an Android phone over `adb` and/or an iPhone over
`devicectl`. It builds and installs the example app with the data-preserving
`adb install -r`, then drives the `.maestro` flows under
`examples/flutter/.maestro`.

Typical invocation (Android only, one device):

```bash
./tools/scripts/layer3_device_regression.sh --android-only --android-serial 7e78be85
```

Per-platform results land in `$HOME/testing/results/<timestamp>-layer3/`
(`android.json`, `ios.json`) together with an overall `verdict` line. Each
JSON records `steps.build / install / maestro`, a `verdict` of `PASS` / `FAIL`
/ `SKIP`, and (Android only) an `autoclick.taps` / `autoclick.exit_reason`
observational block that never affects the verdict.

### Android install auto-clicker

MIUI's "Continue install" dialog blocks unattended `adb install -r` on Xiaomi
handsets. `tools/scripts/android_install_autoclick.sh` is the in-tree
auto-clicker; layer 3 starts it in the background before the Maestro run and
kills it after, leaving the transcript at
`$RESULT_DIR/android-autoclick.log`. Detection stays on
`adb shell dumpsys window | grep -m1 mCurrentFocus` plus `adb shell input tap`,
and deliberately avoids UI Automator dump — that bridge mounts an
accessibility service that makes Flutter integration_test emit a false
`A SemanticsHandle was active at the end of the test` on tear-down.

One-time prerequisites on the device (apply via `adb shell`):

```bash
# Developer options -> "USB debugging (security settings)" = ON
# (manually; otherwise `adb shell input tap` raises INJECT_EVENTS)
# Screen unlocked before each run.
adb shell settings put global stay_on_while_plugged_in 7
adb shell settings put system screen_off_timeout 2147483647
```

Keeping the screen on avoids `INSTALL_FAILED_USER_RESTRICTED: Install
canceled by user` when the display sleeps mid-install. Override the tap
target per device with `--tap-x` / `--tap-y` or the `AUTOCLICK_TAP_X` /
`AUTOCLICK_TAP_Y` env vars (defaults `346 2483` are the Xiaomi 15 "Continue
install" button center).
