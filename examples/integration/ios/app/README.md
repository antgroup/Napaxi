# Napaxi iOS App Integration Check

This app is a minimal native iOS host check that consumes `packages/ios` through
an Xcode local Swift Package dependency. It is not a product demo; it exists to
compile-check the public native iOS SDK surface from a real iOS application
target.

The app covers config construction, platform context resolution, capability
profile/selection setup, host tool executors, and `NapaxiEngine.create(...)`
from the launch smoke path.

Build it from the repository root:

```sh
./tools/scripts/build.sh fast check-ios-app
```

The command regenerates the native iOS bridge artifacts, then runs a no-codesign
Xcode build of this app target for generic arm64 iOS device. iOS shell/Codex
sandbox capabilities are checked by verifying the bundled Alpine rootfs, QEMU
symbols, QEMU readiness, and a shell smoke command in the device report.

Run the launch smoke on a connected iPhone:

```sh
./tools/scripts/build.sh fast check-ios-device
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh fast check-ios-app-device
```

The device preflight checks `devicectl` availability without building. The
device gate signs the app, installs it with `devicectl`, launches it with a
unique smoke token, copies `Documents/napaxi-ios-app-smoke.txt` back from the
app data container, and checks that the report came from the current launch
and contains a native engine handle.
Set `IOS_DEVELOPMENT_TEAM` before the device gate for automatic signing; add
`IOS_ALLOW_PROVISIONING_UPDATES=1` when Xcode should create or update local
development signing assets. If your Apple team already has a different
development profile, set `IOS_BUNDLE_IDENTIFIER=dev.napaxi.integration` so the
signed app, launch, and app-data copy steps all use that bundle identifier.
For manual signing with an existing profile, set
`IOS_PROVISIONING_PROFILE_SPECIFIER` or `IOS_PROVISIONING_PROFILE_UUID`, plus
`IOS_CODE_SIGN_IDENTITY` if Xcode cannot infer the certificate.
Automatic provisioning requires a valid Xcode Accounts login for that team.
If Xcode reports `No Account for Team` or cannot find a profile for
`dev.napaxi.integration.iosapp`, refresh the Apple ID in Xcode settings or rerun
with signing variables that match an available development profile.

The preflight must show a usable physical iPhone before the app smoke can run.
States such as `tunnel=unavailable` or `developerMode=disabled` mean the
device/Xcode pairing layer is not ready; enable Developer Mode, trust/re-pair
the device, reconnect it, and wait for Xcode to finish device support setup.
A selected wired device may still print `ddiServices=false`; the smoke
continues so install/launch can activate device support or fail with the real
CoreDevice/Xcode error.

All reusable SDK behavior must remain in `packages/ios`; code under this
directory is iOS host integration check code only.
