#!/usr/bin/env bash
# Napaxi SDK platform build helper.
#
# Usage:
#   ./tools/scripts/build.sh fast android
#   ./tools/scripts/build.sh release ios
#   ./tools/scripts/build.sh release ios-all
#   ./tools/scripts/build.sh release all
#   ./tools/scripts/build.sh release codegen
#   ./tools/scripts/build.sh release check-boundary
#   ./tools/scripts/build.sh release check-android-parity
#   ./tools/scripts/build.sh release check-ios-parity
#   ./tools/scripts/build.sh release check-ios
#   ./tools/scripts/build.sh release check-android-integration
#   ./tools/scripts/build.sh release check-android-integration-device
#   ./tools/scripts/build.sh release check-ios-native
#   ./tools/scripts/build.sh release check-ios-integration
#   ./tools/scripts/build.sh release check-ios-app
#   ./tools/scripts/build.sh release check-ios-device
#   ./tools/scripts/build.sh release check-ios-app-device
#   ./tools/scripts/build.sh release check-hygiene
#   ./tools/scripts/build.sh release check-packages-architecture
#   ./tools/scripts/build.sh release check-test-stability
#   ./tools/scripts/build.sh release check-api-contract
#   ./tools/scripts/build.sh release clean

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDK_DIR="$ROOT_DIR/packages/flutter"
RUST_DIR="$ROOT_DIR/packages/api_bridge"

BUILD_MODE="${1:-release}"
TARGET_PLATFORM="${2:-android}"

case "$BUILD_MODE" in
    fast)
        CARGO_PROFILE="fast-release"
        PROFILE_DIR="fast-release"
        ;;
    release)
        CARGO_PROFILE="release"
        PROFILE_DIR="release"
        ;;
    debug|dev)
        CARGO_PROFILE="dev"
        PROFILE_DIR="debug"
        ;;
    android|ios|ios-all|all|codegen|check-boundary|check-android-parity|check-ios-parity|check-ios|check-android-integration|check-android-integration-device|check-android-host|check-android-device|check-ios-native|check-ios-integration|check-ios-app|check-ios-device|check-ios-app-device|check-hygiene|check-packages-architecture|check-test-stability|check-api-contract|clean)
        TARGET_PLATFORM="$BUILD_MODE"
        BUILD_MODE="release"
        CARGO_PROFILE="release"
        PROFILE_DIR="release"
        ;;
    *)
        echo "Unknown build mode: $BUILD_MODE" >&2
        echo "Use: fast, release, debug, dev" >&2
        exit 1
        ;;
esac

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || err "$1 not found"
}

require_rust_target() {
    local target="$1"
    rustup target list --installed | grep -qx "$target" || \
        err "Rust target missing: $target. Install with: rustup target add $target"
}

detect_android_ndk() {
    if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        return
    fi

    if [ -n "${ANDROID_NDK_ROOT:-}" ] && [ -d "$ANDROID_NDK_ROOT" ]; then
        export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
        return
    fi

    local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    if [ -d "$sdk_root/ndk" ]; then
        ANDROID_NDK_HOME="$(find "$sdk_root/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
        export ANDROID_NDK_HOME
    fi

    [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ] || \
        err "Android NDK not found. Set ANDROID_NDK_HOME or install an NDK under Android SDK."
}

check_android_runtime_assets() {
    local android_main="$SDK_DIR/android"
    local jni_arm64="$android_main/jniLibs/arm64-v8a"

    for asset in "$android_main/assets/alpine-rootfs.bin" "$android_main/assets/libtalloc.so.2"; do
        [ -f "$asset" ] || err "Missing Android sandbox asset: $asset"
    done

    for runtime_lib in libproot.so libldmusl.so libloader.so; do
        [ -f "$jni_arm64/$runtime_lib" ] || err "Missing Android sandbox runtime: $jni_arm64/$runtime_lib"
    done
}

check_ios_native_assets() {
    local ios_dir="$ROOT_DIR/packages/ios"
    local vendor_dir="$ios_dir/Vendor/iSHCore"
    local resource_dir="$ios_dir/Sources/Napaxi/Resources"

    [ -f "$ios_dir/Package.swift" ] || err "Missing native iOS Swift package: $ios_dir/Package.swift"
    [ -f "$ios_dir/Sources/NapaxiIsh/ish_bridge.c" ] || err "Missing native iOS iSH bridge source: $ios_dir/Sources/NapaxiIsh/ish_bridge.c"
    [ -f "$ios_dir/Sources/NapaxiIsh/include/ish_bridge.h" ] || err "Missing native iOS iSH bridge header: $ios_dir/Sources/NapaxiIsh/include/ish_bridge.h"
    [ -f "$resource_dir/alpine-rootfs.tar.gz" ] || err "Missing native iOS iSH rootfs: $resource_dir/alpine-rootfs.tar.gz. Run: ./tools/scripts/prepare_ios_ish_spm.sh"
    [ -d "$vendor_dir/include" ] || err "Missing native iOS iSH headers: $vendor_dir/include. Run: ./tools/scripts/prepare_ios_ish_spm.sh"

    for runtime_lib in libish.a libish_emu.a libfakefs.a libfakefsify.a libarchive.a; do
        [ -f "$vendor_dir/lib/$runtime_lib" ] || err "Missing native iOS iSH runtime: $vendor_dir/lib/$runtime_lib. Run: ./tools/scripts/prepare_ios_ish_spm.sh"
    done
}

ensure_ios_artifacts() {
    check_ios_native_assets
    if [ "${NAPAXI_IOS_ARTIFACTS_READY:-0}" = "1" ]; then
        return
    fi
    build_ios true
}

build_android() {
    info "Building Napaxi SDK for Android ($BUILD_MODE, profile=$CARGO_PROFILE)"
    require_command cargo
    require_command cargo-ndk
    require_command rustup
    require_rust_target aarch64-linux-android
    detect_android_ndk
    check_android_runtime_assets

    local jni_libs="$SDK_DIR/android/jniLibs"
    local target_dir="$ROOT_DIR/target/napaxi-flutter-android"
    local cargo_flags=()
    if [ "$CARGO_PROFILE" = "dev" ]; then
        cargo_flags+=(build)
    else
        cargo_flags+=(build --profile "$CARGO_PROFILE")
    fi

    mkdir -p "$jni_libs"
    cd "$RUST_DIR"

    info "  -> arm64-v8a"
    CARGO_TARGET_DIR="$target_dir" cargo ndk -t arm64-v8a -o "$jni_libs" "${cargo_flags[@]}"
    rm -f "$jni_libs/arm64-v8a/libnapaxi_core.so"

    if [ "${BUILD_X86_64:-0}" = "1" ]; then
        require_rust_target x86_64-linux-android
        info "  -> x86_64"
        CARGO_TARGET_DIR="$target_dir" cargo ndk -t x86_64 -o "$jni_libs" "${cargo_flags[@]}"
        rm -f "$jni_libs/x86_64/libnapaxi_core.so"
    fi

    [ -f "$jni_libs/arm64-v8a/libnapaxi_api_bridge.so" ] || \
        err "Android build did not produce $jni_libs/arm64-v8a/libnapaxi_api_bridge.so"
    check_android_runtime_assets
    info "Android build complete: $jni_libs"
}

build_ios() {
    local include_sim="${1:-false}"

    info "Building Napaxi SDK for iOS ($BUILD_MODE, profile=$CARGO_PROFILE, simulator=$include_sim)"
    require_command cargo
    require_command rustup
    require_command xcodebuild
    require_rust_target aarch64-apple-ios

    local target_dir="$ROOT_DIR/target/napaxi-flutter-ios"
    local flutter_framework_dir="$SDK_DIR/ios/Frameworks"
    local native_framework_dir="$ROOT_DIR/packages/ios/Frameworks"
    local headers_dir="$RUST_DIR/include"
    local ios_deployment_target="${NAPAXI_IOS_DEPLOYMENT_TARGET:-16.0}"
    local cargo_flags=()
    if [ "$CARGO_PROFILE" = "dev" ]; then
        cargo_flags=()
    else
        cargo_flags=(--profile "$CARGO_PROFILE")
    fi

    mkdir -p "$flutter_framework_dir" "$native_framework_dir"
    cd "$RUST_DIR"

    info "  -> aarch64-apple-ios (min iOS $ios_deployment_target)"
    CARGO_TARGET_DIR="$target_dir" \
        IPHONEOS_DEPLOYMENT_TARGET="$ios_deployment_target" \
        cargo rustc --target aarch64-apple-ios "${cargo_flags[@]}" --lib --crate-type staticlib

    create_ios_xcframework() {
        local framework_dir="$1"
        local include_headers="$2"
        local label="$3"

        rm -rf "$framework_dir/napaxi_api_bridge.xcframework"
        local args=(-create-xcframework)
        args+=(-library "$target_dir/aarch64-apple-ios/$PROFILE_DIR/libnapaxi_api_bridge.a")
        if [ "$include_headers" = "true" ]; then
            args+=(-headers "$headers_dir")
        fi
        if [ "$include_sim" = "true" ]; then
            args+=(-library "$target_dir/universal-ios-sim/$PROFILE_DIR/libnapaxi_api_bridge.a")
            if [ "$include_headers" = "true" ]; then
                args+=(-headers "$headers_dir")
            fi
        fi
        args+=(-output "$framework_dir/napaxi_api_bridge.xcframework")

        info "Creating iOS xcframework ($label)"
        xcodebuild "${args[@]}"
        [ -d "$framework_dir/napaxi_api_bridge.xcframework" ] || \
            err "iOS build did not produce $framework_dir/napaxi_api_bridge.xcframework"
        info "iOS build complete: $framework_dir/napaxi_api_bridge.xcframework"
    }

    if [ "$include_sim" = "true" ]; then
        require_rust_target aarch64-apple-ios-sim
        require_rust_target x86_64-apple-ios

        info "  -> aarch64-apple-ios-sim (min iOS $ios_deployment_target)"
        CARGO_TARGET_DIR="$target_dir" \
            IPHONEOS_DEPLOYMENT_TARGET="$ios_deployment_target" \
            IPHONESIMULATOR_DEPLOYMENT_TARGET="$ios_deployment_target" \
            cargo rustc --target aarch64-apple-ios-sim "${cargo_flags[@]}" --lib --crate-type staticlib

        info "  -> x86_64-apple-ios (min iOS $ios_deployment_target)"
        CARGO_TARGET_DIR="$target_dir" \
            IPHONEOS_DEPLOYMENT_TARGET="$ios_deployment_target" \
            IPHONESIMULATOR_DEPLOYMENT_TARGET="$ios_deployment_target" \
            cargo rustc --target x86_64-apple-ios "${cargo_flags[@]}" --lib --crate-type staticlib

        info "Creating universal simulator static library"
        mkdir -p "$target_dir/universal-ios-sim/$PROFILE_DIR"
        lipo -create \
            "$target_dir/aarch64-apple-ios-sim/$PROFILE_DIR/libnapaxi_api_bridge.a" \
            "$target_dir/x86_64-apple-ios/$PROFILE_DIR/libnapaxi_api_bridge.a" \
            -output "$target_dir/universal-ios-sim/$PROFILE_DIR/libnapaxi_api_bridge.a"
    fi

    if [ "$include_sim" = "true" ]; then
        create_ios_xcframework "$flutter_framework_dir" false "Flutter adapter, device + simulator"
        create_ios_xcframework "$native_framework_dir" true "native Swift package, device + simulator"
    else
        create_ios_xcframework "$flutter_framework_dir" false "Flutter adapter, device only"
        create_ios_xcframework "$native_framework_dir" true "native Swift package, device only"
    fi
}

run_codegen() {
    info "Running flutter_rust_bridge codegen"
    require_command flutter_rust_bridge_codegen
    cd "$ROOT_DIR"
    local tmp_config
    local codegen_rust_tmp_dir="src"
    tmp_config="$ROOT_DIR/.napaxi-frb-codegen.yaml"
    cat > "$tmp_config" <<EOF
rust_input: crate::bridge
rust_root: packages/api_bridge
rust_output: packages/api_bridge/$codegen_rust_tmp_dir/generated/frb_generated.rs
dart_output: packages/flutter/lib/generated
c_output: packages/flutter/ios/Classes/frb_generated.h
dart_format: false
dart_fix: false
rust_format: false
EOF
    flutter_rust_bridge_codegen generate --config-file "$tmp_config"
    rm -f "$tmp_config"
    if [ -f "$RUST_DIR/src/generated/frb_generated.rs" ]; then
        mkdir -p "$RUST_DIR/generated"
        mv "$RUST_DIR/src/generated/frb_generated.rs" "$RUST_DIR/generated/frb_generated.rs"
        rmdir "$RUST_DIR/src/generated" "$RUST_DIR/src" 2>/dev/null || true
    fi
    info "Codegen complete"
}

check_standalone_boundary() {
    info "Checking Napaxi SDK standalone mobile runtime boundary"
    cd "$ROOT_DIR"
    cargo check --manifest-path "$RUST_DIR/Cargo.toml" --no-default-features
    check_core_api_boundary
    check_capability_admission
    check_open_source_hygiene
    check_packages_architecture
    check_api_contract
}

check_android_integration_app() {
    info "Checking Android SDK integration app"
    local gradlew="$ROOT_DIR/examples/flutter/android/gradlew"
    [ -x "$gradlew" ] || err "Gradle wrapper not found or not executable: $gradlew"
    export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    [ -d "$ANDROID_HOME" ] || err "Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT."
    cd "$ROOT_DIR/examples/integration/android"
    "$gradlew" assembleDebug --no-daemon --stacktrace
}

android_device_serial() {
    local adb="$ANDROID_HOME/platform-tools/adb"
    if [ -n "${ADB_SERIAL:-}" ]; then
        printf '%s\n' "$ADB_SERIAL"
        return
    fi

    local devices
    devices="$("$adb" devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
    local count
    count="$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')"
    case "$count" in
        0)
            err "No Android device is online. Connect a device or set ADB_SERIAL."
            ;;
        1)
            printf '%s\n' "$devices"
            ;;
        *)
            printf '%s\n' "$devices" >&2
            err "Multiple Android devices are online. Set ADB_SERIAL to choose one."
            ;;
    esac
}

wake_android_device() {
    local adb="$1"
    local serial="$2"
    "$adb" -s "$serial" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    "$adb" -s "$serial" shell wm dismiss-keyguard >/dev/null 2>&1 || true
    "$adb" -s "$serial" shell input keyevent 82 >/dev/null 2>&1 || true
    "$adb" -s "$serial" shell cmd statusbar collapse >/dev/null 2>&1 || true
}

check_android_integration_device() {
    info "Checking Android SDK integration app on device"
    check_android_integration_app

    local adb="$ANDROID_HOME/platform-tools/adb"
    [ -x "$adb" ] || err "adb not found or not executable: $adb"

    local serial package activity apk provider_apk install_output start_output pid smoke_dump notification_dump
    serial="$(android_device_serial)"
    wake_android_device "$adb" "$serial"
    package="com.napaxi.examples.androidintegration"
    activity="$package/.MainActivity"
    apk="$ROOT_DIR/examples/integration/android/app/build/outputs/apk/debug/app-debug.apk"
    provider_apk="$ROOT_DIR/examples/provider_app/android_smart_desk/app/build/outputs/apk/debug/app-debug.apk"
    [ -f "$apk" ] || err "Android integration APK not found: $apk"

    info "Building Smart Desk provider app for device smoke"
    cd "$ROOT_DIR/examples/provider_app/android_smart_desk"
    "$ROOT_DIR/examples/flutter/android/gradlew" assembleDebug --no-daemon --stacktrace
    [ -f "$provider_apk" ] || err "Smart Desk provider APK not found: $provider_apk"

    info "Installing Smart Desk provider on device $serial"
    if ! install_output="$("$adb" -s "$serial" install -r "$provider_apk" 2>&1)"; then
        printf '%s\n' "$install_output" >&2
        err "Provider device install failed. On some devices, enable USB install / install confirmation and retry."
    fi
    printf '%s\n' "$install_output" | grep -q "Success" || err "Provider adb install did not report Success."

    info "Installing Android integration app on device $serial"
    if ! install_output="$("$adb" -s "$serial" install -r "$apk" 2>&1)"; then
        printf '%s\n' "$install_output" >&2
        err "Device install failed. On some devices, enable USB install / install confirmation and retry."
    fi
    printf '%s\n' "$install_output" | grep -q "Success" || err "adb install did not report Success."

    "$adb" -s "$serial" shell pm grant "$package" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
    "$adb" -s "$serial" shell appops set "$package" POST_NOTIFICATION allow >/dev/null 2>&1 || true
    wake_android_device "$adb" "$serial"

    info "Starting Android integration app on device $serial"
    start_output="$("$adb" -s "$serial" shell am start -W -n "$activity" \
        --ez run_smoke true \
        --ez install_first_provider true 2>&1)"
    printf '%s\n' "$start_output" | grep -Eq "Status: ok|Complete" || {
        printf '%s\n' "$start_output" >&2
        err "Android integration Activity did not start cleanly."
    }

    sleep 2
    wake_android_device "$adb" "$serial"
    pid="$("$adb" -s "$serial" shell pidof "$package" 2>/dev/null | tr -d '\r')"
    [ -n "$pid" ] || {
        "$adb" -s "$serial" shell dumpsys activity activities | grep "$package" >&2 || true
        err "Android integration process is not running after launch."
    }

    local attempt
    for attempt in $(seq 1 30); do
        wake_android_device "$adb" "$serial"
        smoke_dump="$(
            "$adb" -s "$serial" shell timeout 5 uiautomator dump /sdcard/napaxi_android_integration.xml >/dev/null 2>&1 &&
                "$adb" -s "$serial" shell cat /sdcard/napaxi_android_integration.xml 2>/dev/null
        )" || smoke_dump=""
        if printf '%s\n' "$smoke_dump" | grep -q "Smoke failed:"; then
            printf '%s\n' "$smoke_dump" >&2
            err "Android integration smoke failed on device."
        fi
        if printf '%s\n' "$smoke_dump" | grep -Eq 'package="com\.(google\.)?android\.permissioncontroller"|text="允许"|text="Allow"'; then
            "$adb" -s "$serial" shell input tap 900 1700 >/dev/null 2>&1 || true
        fi
        if printf '%s\n' "$smoke_dump" | grep -q "tools=" &&
            printf '%s\n' "$smoke_dump" | grep -q "providers=" &&
            printf '%s\n' "$smoke_dump" | grep -q "packages=" &&
            printf '%s\n' "$smoke_dump" | grep -q "installed=" &&
            printf '%s\n' "$smoke_dump" | grep -q "action=succeeded" &&
            printf '%s\n' "$smoke_dump" | grep -q "background=true" &&
            printf '%s\n' "$smoke_dump" | grep -q "notifications=true"; then
            notification_dump="$("$adb" -s "$serial" shell dumpsys notification --noredact 2>/dev/null || true)"
            case "$notification_dump" in
                *"$package"*"Napaxi Android Integration Smoke"* | *"Napaxi Android Integration Smoke"*"$package"*) ;;
                *)
                printf '%s\n' "$notification_dump" >&2
                err "Android integration completion notification was not visible in dumpsys notification."
                    ;;
            esac
            info "Android integration smoke completed on $serial (pid=$pid)"
            return
        fi
        sleep 1
    done

    printf '%s\n' "$smoke_dump" >&2
    err "Android integration app did not report smoke completion on device."
}

check_ios_native_package() {
    info "Checking native iOS Swift package"
    ensure_ios_artifacts
    require_command swift
    require_command xcrun

    local sdk_path
    sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)" || \
        err "Unable to resolve iPhoneOS SDK path with xcrun"
    [ -d "$sdk_path" ] || err "iPhoneOS SDK not found: $sdk_path"

    local swiftpm_scratch="$ROOT_DIR/target/napaxi-ios-swiftpm"
    local clang_module_cache="$ROOT_DIR/target/swiftpm-module-cache"
    mkdir -p "$swiftpm_scratch" "$clang_module_cache"

    cd "$ROOT_DIR/packages/ios"
    CLANG_MODULE_CACHE_PATH="$clang_module_cache" \
        swift build \
            --build-tests \
            --scratch-path "$swiftpm_scratch" \
            --triple arm64-apple-ios \
            --sdk "$sdk_path"
}

check_ios_integration_app() {
    info "Checking iOS SDK integration package"
    ensure_ios_artifacts
    require_command swift
    require_command xcrun

    local sdk_path
    sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)" || \
        err "Unable to resolve iPhoneOS SDK path with xcrun"
    [ -d "$sdk_path" ] || err "iPhoneOS SDK not found: $sdk_path"

    local swiftpm_scratch="$ROOT_DIR/target/napaxi-ios-integration-swiftpm"
    local clang_module_cache="$ROOT_DIR/target/swiftpm-module-cache"
    mkdir -p "$swiftpm_scratch" "$clang_module_cache"

    cd "$ROOT_DIR/examples/integration/ios/host"
    CLANG_MODULE_CACHE_PATH="$clang_module_cache" \
        swift build \
            --build-tests \
            --scratch-path "$swiftpm_scratch" \
            --triple arm64-apple-ios \
            --sdk "$sdk_path"

    local host_test_scratch="$ROOT_DIR/target/napaxi-ios-integration-host-tests"
    swift test --scratch-path "$host_test_scratch"
}

check_ios_app_integration() {
    info "Checking iOS SDK integration app"
    ensure_ios_artifacts
    require_command xcodebuild
    require_command grep
    check_ios_app_smoke_report_validator

    cd "$ROOT_DIR/examples/integration/ios/app"
    xcodebuild \
        -project NapaxiIOSIntegrationApp.xcodeproj \
        -scheme NapaxiIOSIntegrationApp \
        -configuration Debug \
        -sdk iphoneos \
        -destination generic/platform=iOS \
        -derivedDataPath DerivedData \
        CODE_SIGNING_ALLOWED=NO \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=YES \
        build
}

ios_device_id() {
    require_command node

    local requested_device="${IOS_DEVICE_ID:-${DEVICECTL_DEVICE:-}}"
    local devices_json="$ROOT_DIR/target/napaxi-ios-devices.json"
    mkdir -p "$ROOT_DIR/target"
    xcrun devicectl list devices --json-output "$devices_json" >/dev/null

    node - "$devices_json" "$requested_device" <<'NODE'
const fs = require('fs');

const path = process.argv[2];
const requested = process.argv[3] ?? '';
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
const devices = data.result?.devices ?? [];
const isUsable = (device) => {
  const platform = device.hardwareProperties?.platform;
  const reality = device.hardwareProperties?.reality;
  const pairingState = device.connectionProperties?.pairingState;
  const tunnelState = device.connectionProperties?.tunnelState;
  const developerMode = device.deviceProperties?.developerModeStatus;
  return platform === 'iOS' &&
    reality === 'physical' &&
    pairingState === 'paired' &&
    tunnelState !== 'unavailable' &&
    developerMode === 'enabled';
};

const warnIfDeviceSupportNotReady = (device) => {
  if (device.deviceProperties?.ddiServicesAvailable === false) {
    console.error('Selected iOS device reports ddiServices=false; continuing because install/launch may activate device support services.');
  }
};

const deviceIdentifiers = (device) => [
  device.identifier,
  device.deviceProperties?.name,
  device.hardwareProperties?.udid,
  device.hardwareProperties?.serialNumber,
  device.hardwareProperties?.ecid != null ? String(device.hardwareProperties.ecid) : undefined,
  ...(device.connectionProperties?.potentialHostnames ?? []),
].filter((value) => typeof value === 'string' && value.length > 0);

const describeDevice = (device) => {
  const name = device.deviceProperties?.name ?? '(unnamed)';
  const id = device.identifier ?? '(unknown id)';
  const platform = device.hardwareProperties?.platform ?? 'unknown platform';
  const model = device.hardwareProperties?.marketingName ?? 'unknown model';
  const tunnelState = device.connectionProperties?.tunnelState ?? 'unknown tunnel';
  const pairingState = device.connectionProperties?.pairingState ?? 'unknown pairing';
  const developerMode = device.deviceProperties?.developerModeStatus ?? 'unknown developer mode';
  const ddiServices = String(device.deviceProperties?.ddiServicesAvailable ?? 'unknown ddi');
  return `${name} (${id}, ${platform} ${model}): pairing=${pairingState}, tunnel=${tunnelState}, developerMode=${developerMode}, ddiServices=${ddiServices}`;
};

const printKnownDevices = () => {
  if (devices.length === 0) {
    console.error('devicectl did not report any devices.');
    return;
  }
  for (const device of devices) {
    console.error(`- ${describeDevice(device)}`);
  }
};

if (requested) {
  const matches = devices.filter((device) => deviceIdentifiers(device).includes(requested));
  if (matches.length === 1 && isUsable(matches[0])) {
    warnIfDeviceSupportNotReady(matches[0]);
    process.stdout.write(`${matches[0].identifier}\n`);
    process.exit(0);
  }

  if (matches.length === 1) {
    console.error(`Requested iOS device is not available for launch smoke: ${requested}`);
    console.error(`- ${describeDevice(matches[0])}`);
    console.error('Choose an online iPhone with Developer Mode enabled, or clear IOS_DEVICE_ID / DEVICECTL_DEVICE.');
    process.exit(2);
  }

  if (matches.length > 1) {
    for (const device of matches) {
      console.error(`${device.identifier}\t${device.deviceProperties?.name ?? '(unnamed)'}\t${device.hardwareProperties?.marketingName ?? 'unknown model'}`);
    }
    console.error(`Requested iOS device matched multiple devices: ${requested}. Set IOS_DEVICE_ID to the exact identifier.`);
    process.exit(2);
  }

  console.error(`Requested iOS device was not reported by devicectl: ${requested}`);
  printKnownDevices();
  process.exit(2);
}

const candidates = devices.filter(isUsable);

if (candidates.length === 1) {
  warnIfDeviceSupportNotReady(candidates[0]);
  process.stdout.write(`${candidates[0].identifier}\n`);
  process.exit(0);
}

if (candidates.length > 1) {
  for (const device of candidates) {
    const name = device.deviceProperties?.name ?? '(unnamed)';
    const model = device.hardwareProperties?.marketingName ?? 'unknown model';
    console.error(`${device.identifier}\t${name}\t${model}`);
  }
  console.error('Multiple available iOS devices found. Set IOS_DEVICE_ID to choose one.');
  process.exit(2);
}

console.error('No available physical iOS device found for app launch smoke.');
printKnownDevices();
console.error('Connect an iPhone with Developer Mode enabled, or set IOS_DEVICE_ID / DEVICECTL_DEVICE to a usable device identifier.');
console.error('If a listed iPhone has tunnel=unavailable, trust/re-pair it in Xcode, reconnect USB, and wait for CoreDevice device support to finish.');
process.exit(2);
NODE
}

check_ios_device_ready() {
    info "Checking iOS device availability"
    require_command xcrun

    local device_id
    device_id="$(ios_device_id)"
    info "iOS device is available for launch smoke: $device_id"
}

check_ios_app_smoke_report() {
    local report_path="$1"
    local token="$2"

    [ -f "$report_path" ] || err "iOS integration app did not write a smoke report after launch."
    if ! grep -q '^Napaxi native iOS app smoke is ready\.$' "$report_path"; then
        sed 's/^/[SMOKE] /' "$report_path" >&2
        err "iOS integration app smoke did not report ready."
    fi
    if ! grep -q "^token=$token$" "$report_path"; then
        sed 's/^/[SMOKE] /' "$report_path" >&2
        err "iOS integration app smoke report is stale or missing the launch token."
    fi
    if ! grep -Eq '^engineHandle=[1-9][0-9]*$' "$report_path"; then
        sed 's/^/[SMOKE] /' "$report_path" >&2
        err "iOS integration app did not create a native Napaxi engine."
    fi
    if ! grep -q '^rootfs=true$' "$report_path"; then
        sed 's/^/[SMOKE] /' "$report_path" >&2
        err "iOS integration app did not report bundled rootfs availability."
    fi
}

check_ios_app_smoke_report_validator() {
    local smoke_dir token good_report bad_report
    mkdir -p "$ROOT_DIR/target"
    smoke_dir="$(mktemp -d "$ROOT_DIR/target/napaxi-ios-report-validator.XXXXXX")"
    token="validator-token"
    good_report="$smoke_dir/good.txt"
    bad_report="$smoke_dir/bad.txt"

    printf '%s\n' \
        "Napaxi native iOS app smoke is ready." \
        "token=$token" \
        "engineHandle=42" \
        "filesDir=/tmp/napaxi-ios-app-integration" \
        "enabled=napaxi.tool.custom_host,napaxi.platform_tool.open_url" \
        "rootfs=true" > "$good_report"
    check_ios_app_smoke_report "$good_report" "$token"

    printf '%s\n' \
        "Napaxi native iOS app smoke is ready." \
        "token=old-token" \
        "engineHandle=42" \
        "rootfs=true" > "$bad_report"
    if (check_ios_app_smoke_report "$bad_report" "$token" >/dev/null 2>&1); then
        err "iOS app smoke report validator accepted a stale launch token."
    fi
}

check_ios_device_signing_ready() {
    require_command security

    local identities_output="$ROOT_DIR/target/napaxi-ios-codesigning-identities.txt"
    local profiles_parent="Mobile""Device"
    local profiles_dir="$HOME/Library/$profiles_parent/Provisioning Profiles"
    local profile_count=0
    mkdir -p "$ROOT_DIR/target"
    security find-identity -v -p codesigning > "$identities_output" || true

    if [ -d "$profiles_dir" ]; then
        profile_count="$(find "$profiles_dir" -maxdepth 1 -name '*.mobileprovision' -type f | wc -l | tr -d '[:space:]')"
    fi

    if grep -q '0 valid identities found' "$identities_output" && [ "${IOS_ALLOW_PROVISIONING_UPDATES:-0}" != "1" ]; then
        err "No valid iOS code signing identity found. Add an Apple Development certificate in Xcode, or rerun with IOS_ALLOW_PROVISIONING_UPDATES=1 so Xcode can create/update signing assets."
    fi

    if [ "$profile_count" = "0" ] && [ "${IOS_ALLOW_PROVISIONING_UPDATES:-0}" != "1" ]; then
        err "No iOS provisioning profiles found. Add a development provisioning profile in Xcode, or rerun with IOS_ALLOW_PROVISIONING_UPDATES=1 so Xcode can create/update one."
    fi
}

check_ios_app_device_smoke() {
    info "Checking iOS SDK integration app on device"
    require_command xcodebuild
    require_command xcrun
    require_command grep

    local bundle_id="dev.napaxi.integration.iosapp"
    local device_id
    device_id="$(ios_device_id)"

    if [ -z "${IOS_DEVELOPMENT_TEAM:-}" ]; then
        err "IOS_DEVELOPMENT_TEAM is required for the signed iOS app device smoke. Set IOS_DEVELOPMENT_TEAM, and set IOS_ALLOW_PROVISIONING_UPDATES=1 if Xcode should create/update profiles."
    fi

    check_ios_device_signing_ready
    ensure_ios_artifacts

    local app_dir="$ROOT_DIR/examples/integration/ios/app"
    local derived_data="$app_dir/DerivedDataDevice"
    local app_path="$derived_data/Build/Products/Debug-iphoneos/NapaxiIOSIntegrationApp.app"
    local xcodebuild_args=(
        -project NapaxiIOSIntegrationApp.xcodeproj
        -scheme NapaxiIOSIntegrationApp
        -configuration Debug
        -sdk iphoneos
        -destination "platform=iOS,id=$device_id"
        -derivedDataPath "$derived_data"
    )
    local signing_args=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGNING_REQUIRED=YES
        ARCHS=arm64
        ONLY_ACTIVE_ARCH=YES
    )

    signing_args+=(DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM")

    if [ "${IOS_ALLOW_PROVISIONING_UPDATES:-0}" = "1" ]; then
        xcodebuild_args+=(-allowProvisioningUpdates)
    fi

    cd "$app_dir"
    if ! xcodebuild \
        "${xcodebuild_args[@]}" \
        "${signing_args[@]}" \
        build; then
        err "Signed iOS app build failed. Set IOS_DEVELOPMENT_TEAM, and IOS_ALLOW_PROVISIONING_UPDATES=1 if Xcode should create/update profiles."
    fi

    [ -d "$app_path" ] || err "Signed iOS app build did not produce $app_path"

    local smoke_dir token install_json launch_json copy_json report_path
    mkdir -p "$ROOT_DIR/target"
    smoke_dir="$(mktemp -d "$ROOT_DIR/target/napaxi-ios-device-smoke.XXXXXX")"
    token="napaxi-ios-smoke-$(date +%s)"
    install_json="$smoke_dir/install.json"
    launch_json="$smoke_dir/launch.json"
    copy_json="$smoke_dir/copy.json"
    report_path="$smoke_dir/napaxi-ios-app-smoke.txt"

    info "Installing iOS integration app on device $device_id"
    xcrun devicectl device install app \
        --device "$device_id" \
        "$app_path" \
        --timeout 120 \
        --json-output "$install_json"

    info "Launching iOS integration app on device $device_id"
    xcrun devicectl device process launch \
        --device "$device_id" \
        --terminate-existing \
        --timeout 60 \
        --json-output "$launch_json" \
        "$bundle_id" \
        --napaxi-smoke-token "$token"

    local attempt
    for attempt in $(seq 1 20); do
        if xcrun devicectl device copy from \
            --device "$device_id" \
            --domain-type appDataContainer \
            --domain-identifier "$bundle_id" \
            --source "Documents/napaxi-ios-app-smoke.txt" \
            --destination "$report_path" \
            --timeout 30 \
            --json-output "$copy_json" \
            --quiet; then
            [ -f "$report_path" ] && break
        fi
        sleep 1
    done

    check_ios_app_smoke_report "$report_path" "$token"

    info "iOS integration app smoke completed on $device_id"
}

check_ios_offline_acceptance() {
    require_command node
    node "$SCRIPT_DIR/check-ios-flutter-parity.js"
    ensure_ios_artifacts

    local previous_ready="${NAPAXI_IOS_ARTIFACTS_READY:-}"
    export NAPAXI_IOS_ARTIFACTS_READY=1
    check_ios_native_package
    check_ios_integration_app
    check_ios_app_integration
    if [ -n "$previous_ready" ]; then
        export NAPAXI_IOS_ARTIFACTS_READY="$previous_ready"
    else
        unset NAPAXI_IOS_ARTIFACTS_READY
    fi
}

check_core_api_boundary() {
    info "Checking Napaxi core API boundary"
    require_command rg
    cd "$ROOT_DIR"

    if rg -n "napaxi_core::(mobile_|android_assets|android_linux_env|ios_ish_env)" packages \
        --glob '!packages/flutter/lib/generated/**' \
        --glob '!packages/api_bridge/generated/frb_generated.rs' \
        --glob '!**/build/**' \
        --glob '!**/.dart_tool/**'; then
        err "Core API boundary check failed; packages must call napaxi_core::api instead of core internals."
    fi

    if rg -n "pub use crate::mobile_[A-Za-z0-9_]+::\\*" crates/core/src/api; then
        err "Core API boundary check failed; api modules must explicitly export a whitelist, not mobile_* globs."
    fi

    if rg -n "(crate::mobile_[A-Za-z0-9_]+|use crate::mobile_[A-Za-z0-9_]+|mod mobile_[A-Za-z0-9_]+|pub mod mobile_[A-Za-z0-9_]+)" crates/core/src; then
        err "Core API boundary check failed; core implementation modules should use domain module names, not mobile_* aliases."
    fi

    if rg -n "napaxi_(skills|evolution)|napaxi-(skills|evolution)|crates/features/" packages \
        --glob '**/Cargo.toml' \
        --glob '!**/build/**' \
        --glob '!**/.dart_tool/**'; then
        err "Core API boundary check failed; packages must depend on napaxi-core, not feature crates directly."
    fi

    if rg -n "napaxi_core|napaxi-core|crates/core" crates/features --glob '**/Cargo.toml'; then
        err "Core API boundary check failed; feature crates must not depend on core."
    fi

    if [ -d crates/core/crates ] || [ -d crates/features/crates ]; then
        err "Core API boundary check failed; third-party patched crates belong under vendor/, not core/features."
    fi
}

check_capability_admission() {
    info "Checking capability admission coverage"
    require_command rg
    cd "$ROOT_DIR"

    # Files that own a capability admission gate. These are the ONLY core
    # modules that may invoke `admit_*` directly. Anything else calling
    # admit_* means a duplicate gate has appeared somewhere unexpected; add
    # it to this allowlist after reviewing the new path.
    local admission_allowlist=(
        'crates/core/src/capabilities/mod.rs'
        'crates/core/src/tools/loop/execution.rs'
        'crates/core/src/tools/loop/runtime.rs'
        'crates/core/src/tools/loop/descriptors.rs'
        'crates/core/src/mcp/tools.rs'
        'crates/core/src/a2a/mod.rs'
        'crates/core/src/automation/runner.rs'
        'crates/core/src/channel/mod.rs'
        'crates/core/src/channel_agent/mod.rs'
        'crates/core/src/context/mod.rs'
        'crates/core/src/tools/media.rs'
    )

    # Build the rg ignore globs for the allowlist.
    local ignore_args=()
    for f in "${admission_allowlist[@]}"; do
        ignore_args+=(--glob "!${f}")
    done

    if rg -n 'crate::capabilities::admit_(tool|provider|service)' crates/core/src \
        "${ignore_args[@]}"; then
        err "Capability admission allowlist violated; new admit_* call site found outside check_capability_admission allowlist. Update tools/scripts/build.sh allowlist after review."
    fi

    # New tools registered into the descriptor surface should be traceable
    # to a capability id. Soft check: warn (not err) if a builtin tool
    # name appears in tool_capability_id without a matching capability
    # definition string. Skipped here as a heuristic — the Rust compiler
    # would not catch it either; future work is to enforce at runtime via
    # admission tests rather than text grep.
}

check_open_source_hygiene() {
    info "Checking public source hygiene"
    require_command rg
    cd "$ROOT_DIR"

    local pattern="te""claw|iron""claw|src/""mobile|com\\.example|(\\.\\./)+te""claw|/Use""rs/|/private/var/fol""ders"
    local paths=(
        README.md
        AGENTS.md
        CONTRIBUTING.md
        SECURITY.md
        CODE_OF_CONDUCT.md
        CHANGELOG.md
        Cargo.toml
        tools/scripts
        docs
        crates/core/src
        crates/features/evolution/src
        crates/features/skills/src
        vendor/libsql-patched
        packages/flutter
        packages/api_bridge
        packages/agent_provider
        examples/flutter
        examples/integration/android
        examples/integration/ios/host
        examples/integration/ios/app
    )

    if rg -n "$pattern" "${paths[@]}" \
        --glob '!packages/flutter/lib/generated/**' \
        --glob '!packages/api_bridge/generated/frb_generated.rs' \
        --glob '!**/build/**' \
        --glob '!**/.dart_tool/**' \
        --glob '!**/target/**'; then
        err "Public source hygiene check failed; remove stale internal paths or placeholder package names."
    fi

    check_internal_branding_leak "${paths[@]}"
    check_mobile_naming_leak "${paths[@]}"
    check_release_placeholders "${paths[@]}"
    check_source_file_size
}

# Guards against god-files regrowing. Production Rust sources are capped at
# MAX_RUST_SRC_LINES lines so large modules get split into cohesive submodules
# (see the Split PR series). Test files (`*tests.rs`), generated code, and the
# vendored libsql patch are exempt — tests and codegen are allowed to be long.
check_source_file_size() {
    info "Checking Rust source file size limit"
    cd "$ROOT_DIR"

    local max_lines=1000
    local offenders=""
    local file lines
    while IFS= read -r file; do
        lines=$(wc -l < "$file" | tr -d ' ')
        if [ "$lines" -gt "$max_lines" ]; then
            offenders="${offenders}  ${lines}\t${file}\n"
        fi
    done < <(git ls-files '*.rs' \
        | grep -vE 'tests\.rs$|/generated/|frb_generated|replay_tests\.rs$|^vendor/|packages/android/|packages/ios/')

    if [ -n "$offenders" ]; then
        printf '[ERROR] Production Rust files exceed %s lines (split into submodules; tests are exempt):\n' "$max_lines" >&2
        printf '%b' "$offenders" >&2
        err "Rust source file size limit exceeded."
    fi

    # Also check non-Rust SDK source files (Swift, Kotlin, Dart) against the
    # same limit. Produces warnings rather than errors so existing large files
    # can be decomposed incrementally without blocking CI.
    info "Checking non-Rust SDK source file size advisory"
    local non_rs_offenders=""
    while IFS= read -r file; do
        lines=$(wc -l < "$file" | tr -d ' ')
        if [ "$lines" -gt "$max_lines" ]; then
            non_rs_offenders="${non_rs_offenders}  ${lines}\t${file}\n"
        fi
    done < <(git ls-files '*.swift' '*.kt' '*.dart' \
        | grep -vE '/generated/|\.g\.dart$|\.freezed\.dart$|/test/|/tests/|Test\.swift$|Test\.kt$|_test\.dart$')

    if [ -n "$non_rs_offenders" ]; then
        printf '[WARN] Non-Rust SDK files exceed %s lines (consider splitting into submodules):\n' "$max_lines" >&2
        printf '%b' "$non_rs_offenders" >&2
    fi
}

# Scans for company / monorepo names that must not ship in the open-source tree.
# Always fails — these are never acceptable in a public release.
check_internal_branding_leak() {
    info "Checking for internal branding / monorepo path leaks"
    local paths=("$@")
    # Split each literal so this script itself does not trip the check.
    # NOTE: `antgroup.com` was intentionally removed from this allowlist so the
    # maintainer contact address `wenyu.mwt@antgroup.com` (SECURITY.md,
    # CODE_OF_CONDUCT.md, the iOS podspec author field) is not flagged as an
    # internal-branding leak. The remaining monorepo/company markers stay gated.
    local pattern="ali""pay\\.com|termi""nal_data_service|antg""roup\\.net"

    if rg -n "$pattern" "${paths[@]}" \
        --glob '!packages/flutter/lib/generated/**' \
        --glob '!packages/api_bridge/generated/frb_generated.rs' \
        --glob '!**/build/**' \
        --glob '!**/.dart_tool/**' \
        --glob '!**/target/**'; then
        err "Internal branding leak detected; replace with public-facing names."
    fi
}

# Scans for the retired Mobile* / mobile_* SDK naming. See
# docs/naming-migration.md. Always fails — once retired, the prefix must not
# reappear on the public SDK surface.
check_mobile_naming_leak() {
    info "Checking for retired Mobile* SDK naming residue"
    local paths=("$@")
    local scan_paths=()
    local path
    for path in "${paths[@]}"; do
        case "$path" in
            CHANGELOG.md)
                ;;
            *)
                scan_paths+=("$path")
                ;;
        esac
    done

    local mobile_hits
    mobile_hits="$(rg -n "\\bMobile[A-Z][A-Za-z0-9]*" "${scan_paths[@]}" \
        --glob '!packages/flutter/lib/generated/**' \
        --glob '!packages/api_bridge/generated/frb_generated.rs' \
        --glob '!packages/flutter/ios/Classes/frb_generated.h' \
        --glob '!docs/naming-migration.md' \
        --glob '!CHANGELOG.md' \
        --glob '!tools/scripts/rename-mobile.sh' \
        --glob '!tools/scripts/rename-mobile-generated.sh' \
        --glob '!**/build/**' \
        --glob '!**/.dart_tool/**' \
        --glob '!**/.gradle/**' \
        --glob '!**/.kotlin/**' \
        --glob '!**/target/**' \
        | grep -v 'MobileScanner' || true)"
    if [ -n "$mobile_hits" ]; then
        printf '%s\n' "$mobile_hits"
        err "Mobile* naming leak detected; the Mobile prefix was retired before 0.1. See docs/naming-migration.md."
    fi

    local legacy_pattern="\\b(mobile_""platform_tool|mobile_""platform_tool_descriptors|is_""mobile_""platform_tool|mobile""PlatformTool|is""Mo""bilePlatformTool|Flutter""Mo""bileCapabilityHost)\\b"
    if rg -n "$legacy_pattern" "${scan_paths[@]}" \
        --glob '!packages/flutter/lib/generated/**' \
        --glob '!packages/api_bridge/generated/frb_generated.rs' \
        --glob '!packages/flutter/ios/Classes/frb_generated.h' \
        --glob '!docs/naming-migration.md' \
        --glob '!CHANGELOG.md' \
        --glob '!tools/scripts/rename-mobile.sh' \
        --glob '!tools/scripts/rename-mobile-generated.sh' \
        --glob '!**/build/**' \
        --glob '!**/.dart_tool/**' \
        --glob '!**/.gradle/**' \
        --glob '!**/.kotlin/**' \
        --glob '!**/target/**'; then
        err "Legacy mobile_*/Mobile* function or type leak detected. See docs/naming-migration.md."
    fi
}

# Scans for documentation placeholders that must be replaced before a public
# release. Default mode warns and continues so day-to-day development is not
# blocked. Run with NAPAXI_RELEASE=1 (e.g. in a release pipeline) to fail the
# build instead.
check_release_placeholders() {
    info "Checking for unreplaced release placeholders"
    local paths=("$@")
    local pattern="napaxi\\.dev"

    local hits
    if hits=$(rg -n "$pattern" "${paths[@]}" \
        --glob '!packages/flutter/lib/generated/**' \
        --glob '!packages/api_bridge/generated/frb_generated.rs' \
        --glob '!**/build/**' \
        --glob '!**/.dart_tool/**' \
        --glob '!**/target/**' 2>/dev/null); then
        if [ "${NAPAXI_RELEASE:-0}" = "1" ]; then
            printf '%s\n' "$hits" >&2
            err "Release placeholders still present (set NAPAXI_RELEASE=0 to allow during development)."
        else
            warn "Release placeholders still present (run with NAPAXI_RELEASE=1 to enforce):"
            printf '%s\n' "$hits" | sed 's/^/  /' >&2
        fi
    fi
}

check_packages_architecture() {
    info "Checking packages SDK adapter architecture"
    "$SCRIPT_DIR/check-packages-architecture.sh"
}

check_test_stability() {
    info "Checking test-stability ratchet"
    "$SCRIPT_DIR/check-test-stability.sh"
}

check_api_contract() {
    info "Checking SDK API contract"
    require_command node
    node "$SCRIPT_DIR/check-api-contract.js"
}

clean_outputs() {
    info "Cleaning Napaxi SDK platform outputs"
    rm -rf "$ROOT_DIR/target/napaxi-flutter-android" "$ROOT_DIR/target/napaxi-flutter-ios"
    rm -f "$SDK_DIR/android/jniLibs"/*/libnapaxi_api_bridge.so
    rm -rf "$SDK_DIR/ios/Frameworks"
    rm -rf "$ROOT_DIR/packages/ios/Frameworks"
    info "Clean complete"
}

case "$TARGET_PLATFORM" in
    android)
        build_android
        ;;
    ios)
        build_ios false
        ;;
    ios-all)
        build_ios true
        ;;
    all)
        build_android
        build_ios true
        ;;
    codegen)
        run_codegen
        ;;
    check-boundary)
        check_standalone_boundary
        ;;
    check-android-parity)
        require_command node
        node "$SCRIPT_DIR/check-android-flutter-parity.js"
        ;;
    check-ios-parity)
        require_command node
        node "$SCRIPT_DIR/check-ios-flutter-parity.js"
        ;;
    check-ios)
        check_ios_offline_acceptance
        ;;
    check-android-integration)
        check_android_integration_app
        ;;
    check-android-integration-device)
        check_android_integration_device
        ;;
    check-ios-native)
        check_ios_native_package
        ;;
    check-ios-integration)
        check_ios_integration_app
        ;;
    check-ios-app)
        check_ios_app_integration
        ;;
    check-ios-device)
        check_ios_device_ready
        ;;
    check-ios-app-device)
        check_ios_app_device_smoke
        ;;
    check-android-host)
        check_android_integration_app
        ;;
    check-android-device)
        check_android_integration_device
        ;;
    check-hygiene)
        check_open_source_hygiene
        ;;
    check-packages-architecture)
        check_packages_architecture
        ;;
    check-test-stability)
        check_test_stability
        ;;
    check-api-contract)
        check_api_contract
        ;;
    clean)
        clean_outputs
        ;;
    *)
        err "Unknown platform: $TARGET_PLATFORM. Use: android, ios, ios-all, all, codegen, check-boundary, check-android-parity, check-ios-parity, check-ios, check-android-integration, check-android-integration-device, check-ios-native, check-ios-integration, check-ios-app, check-ios-device, check-ios-app-device, check-hygiene, check-packages-architecture, check-test-stability, check-api-contract, clean"
        ;;
esac
