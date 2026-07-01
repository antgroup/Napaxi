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
SwiftPM iPhoneOS build with tests of `packages/ios` so the C iSH target, binary
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
