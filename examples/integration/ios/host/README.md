# Napaxi iOS Host Integration Check

This package is a minimal native iOS host integration check that consumes
`packages/ios` through a local Swift Package dependency. It is not a product
demo; it exists to compile-check the public Swift SDK surface from an
independent host package.

The check covers config construction, capability profile/selection setup,
platform context resolution, custom tool and approval hosts, platform tool host
injection, and `NapaxiEngine.create(...)` availability from an independent host
package. The host tests run on macOS and assert the explicit non-iOS
unavailable path, while the iPhoneOS SwiftPM build compiles the native engine
creation path.

Run it from the repository root:

```sh
./tools/scripts/build.sh fast check-ios-integration
```

The command regenerates the native iOS bridge artifacts, runs an iPhoneOS
SwiftPM build for this package, and runs the host-side smoke tests on macOS.

The package intentionally keeps all reusable behavior in `packages/ios`; code
under this directory is iOS host integration check code only.
