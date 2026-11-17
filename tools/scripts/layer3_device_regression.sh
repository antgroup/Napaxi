#!/usr/bin/env bash
# Layer 3 gate: run the Maestro smoke flows on PHYSICAL devices —
# an Android phone over adb and/or an iPhone over devicectl.
#
# Usage:
#   tools/scripts/layer3_device_regression.sh [--skip-build]
#       [--android-serial <serial>] [--ios-udid <udid>]
#       [--android-only] [--ios-only]
#
# Env:
#   ANDROID_HOME     Android SDK root (default: $HOME/Library/Android/sdk)
#   JAVA_HOME        JDK 17; auto-detected via /usr/libexec/java_home if unset
#   IOS_TEAM_ID      Apple Team ID for on-device signing (default: SL3WHU96U7)
#
# Prerequisites (manual, one-time):
#   Android: USB debugging enabled, `adb devices` shows the phone authorized.
#   iOS:     iPhone paired+trusted, Developer Mode on, and an Apple ID that
#            belongs to $IOS_TEAM_ID added under Xcode > Settings > Accounts
#            (automatic signing then issues a Development certificate and
#            registers the device UDID).
#
# Results are written to $HOME/testing/results/<timestamp>-layer3/ with one
# result JSON per attempted platform and an overall verdict line.
set -uo pipefail

ROOT_DIR="${NAPAXI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
APP_DIR="$ROOT_DIR/examples/flutter"
FLOW_DIR="${MAESTRO_FLOW_DIR:-$APP_DIR/.maestro}"
IOS_TEAM_ID="${IOS_TEAM_ID:-SL3WHU96U7}"
BUNDLE_ID="com.napa.app.test"
SKIP_BUILD=0
ANDROID_SERIAL=""
IOS_UDID=""
DO_ANDROID=1
DO_IOS=1

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1 ;;
        --android-serial) ANDROID_SERIAL="$2"; shift ;;
        --ios-udid) IOS_UDID="$2"; shift ;;
        --android-only) DO_IOS=0 ;;
        --ios-only) DO_ANDROID=0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"

if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    [ -n "$JAVA_HOME" ] && export JAVA_HOME
fi

MAESTRO_BIN="$(command -v maestro || true)"
[ -n "$MAESTRO_BIN" ] || MAESTRO_BIN="$HOME/.maestro/bin/maestro"
[ -n "$MAESTRO_BIN" ] && [ -x "$MAESTRO_BIN" ] || { echo "maestro CLI not found" >&2; exit 2; }

TS="$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$HOME/testing/results/$TS-layer3"
mkdir -p "$RESULT_DIR"
cd "$ROOT_DIR"

step() { echo "[layer3] $*"; }

# --- Device detection -------------------------------------------------------

detect_android() {
    [ -n "$ANDROID_SERIAL" ] && return 0
    # Physical devices have serials that do not start with "emulator-".
    ANDROID_SERIAL="$("$ADB" devices | awk '$2=="device" && $1 !~ /^emulator-/ {print $1; exit}')"
}

detect_ios() {
    [ -n "$IOS_UDID" ] && return 0
    # `xcrun devicectl list devices` prints a table; grab the UDID of the
    # first device whose connection state is "connected".
    IOS_UDID="$(xcrun devicectl list devices 2>/dev/null \
        | awk '/connected/ && /[0-9A-Fa-f-]{20,}/ {
            for (i=1; i<=NF; i++) if ($i ~ /^[0-9A-Fa-f-]{20,}$/) {print $i; exit}
          }')"
}

# --- Android ----------------------------------------------------------------

A_BUILD="skipped"; A_INSTALL="skipped"; A_MAESTRO="skipped"

run_android() {
    detect_android
    if [ -z "$ANDROID_SERIAL" ]; then
        step "android: no physical device found, skipped"
        return
    fi
    step "android: device $ANDROID_SERIAL"
    A_BUILD="skipped"; A_INSTALL="failed"; A_MAESTRO="failed"

    if [ "$SKIP_BUILD" -eq 0 ]; then
        step "android: build.sh fast android (rust libs)"
        ./tools/scripts/build.sh fast android > "$RESULT_DIR/android-build-rust.log" 2>&1 || true
        step "android: flutter build apk --debug"
        if (cd "$APP_DIR" && flutter build apk --debug) > "$RESULT_DIR/android-build.log" 2>&1; then
            A_BUILD="passed"
        else
            A_BUILD="failed"
            echo "android build failed, see $RESULT_DIR/android-build.log" >&2
            return
        fi
    fi

    local apk="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
    step "android: install -> $ANDROID_SERIAL"
    if "$ADB" -s "$ANDROID_SERIAL" install -r "$apk" > "$RESULT_DIR/android-install.log" 2>&1 \
        && grep -q Success "$RESULT_DIR/android-install.log"; then
        A_INSTALL="passed"
    else
        echo "android install failed, see $RESULT_DIR/android-install.log" >&2
        return
    fi

    step "android: maestro test --device $ANDROID_SERIAL"
    if "$MAESTRO_BIN" test --device "$ANDROID_SERIAL" "$FLOW_DIR" --format junit \
        --output "$RESULT_DIR/android-maestro.xml" > "$RESULT_DIR/android-maestro.log" 2>&1; then
        A_MAESTRO="passed"
    fi

    # Non-fatal signature audit (keytool/apksigner optional).
    local apksigner
    apksigner="$(ls "$ANDROID_HOME"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
    if [ -n "$apksigner" ]; then
        "$apksigner" verify --verbose --print-certs "$apk" \
            > "$RESULT_DIR/android-certs.log" 2>&1 || true
    fi
}

# --- iOS --------------------------------------------------------------------

I_BUILD="skipped"; I_INSTALL="skipped"; I_MAESTRO="skipped"

run_ios() {
    detect_ios
    if [ -z "$IOS_UDID" ]; then
        step "ios: no connected device found, skipped"
        return
    fi
    step "ios: device $IOS_UDID (team $IOS_TEAM_ID)"
    I_BUILD="skipped"; I_INSTALL="failed"; I_MAESTRO="failed"

    if [ "$SKIP_BUILD" -eq 0 ]; then
        step "ios: build.sh fast ios (rust xcframework)"
        ./tools/scripts/build.sh fast ios > "$RESULT_DIR/ios-build-rust.log" 2>&1 || true
        # Automatic signing: Xcode issues a Development certificate and a
        # profile covering this device UDID. Requires the team account in
        # Xcode > Settings > Accounts. -allowProvisioningUpdates lets
        # xcodebuild create/update the profile without UI interaction.
        step "ios: xcodebuild Debug for device (automatic signing)"
        if (cd "$APP_DIR/ios" && xcodebuild \
                -workspace Runner.xcworkspace -scheme Runner \
                -configuration Debug \
                -destination "id=$IOS_UDID" \
                DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
                CODE_SIGN_STYLE=Automatic \
                -allowProvisioningUpdates \
                build) > "$RESULT_DIR/ios-build.log" 2>&1; then
            I_BUILD="passed"
        else
            I_BUILD="failed"
            echo "ios build failed, see $RESULT_DIR/ios-build.log" >&2
            return
        fi
    fi

    local app="$APP_DIR/build/ios/iphoneos/Runner.app"
    if [ ! -d "$app" ]; then
        # 裸 `xcodebuild -workspace Runner.xcworkspace build`（无 -derivedDataPath）的产物
        # 落在 ~/Library/Developer/Xcode/DerivedData/Runner-*/Build/Products/Debug-iphoneos。
        app="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Runner-*/Build/Products/Debug-iphoneos/Runner.app 2>/dev/null | head -1)"
        if [ -n "$app" ] && [ -d "$app" ]; then
            echo "ios: using DerivedData product $app"
        else
            echo "ios: Runner.app not found (build/ios/iphoneos nor DerivedData)" >&2
            return
        fi
    fi
    step "ios: install -> $IOS_UDID"
    if xcrun devicectl device install app --device "$IOS_UDID" "$app" \
        > "$RESULT_DIR/ios-install.log" 2>&1; then
        I_INSTALL="passed"
    else
        echo "ios install failed, see $RESULT_DIR/ios-install.log" >&2
        return
    fi

    step "ios: maestro test --device $IOS_UDID"
    if "$MAESTRO_BIN" test --device "$IOS_UDID" "$FLOW_DIR" --format junit \
        --output "$RESULT_DIR/ios-maestro.xml" > "$RESULT_DIR/ios-maestro.log" 2>&1; then
        I_MAESTRO="passed"
    fi
}

# --- Run + verdict ----------------------------------------------------------

[ "$DO_ANDROID" -eq 1 ] && run_android
[ "$DO_IOS" -eq 1 ] && run_ios

write_platform_json() {
    local file="$1" platform="$2" build="$3" install="$4" maestro="$5"
    local verdict="SKIP"
    if [ "$install" != "skipped" ]; then
        verdict="PASS"
        { [ "$build" = "passed" ] || [ "$build" = "skipped" ]; } || verdict="FAIL"
        [ "$install" = "passed" ] || verdict="FAIL"
        [ "$maestro" = "passed" ] || verdict="FAIL"
    fi
    cat > "$file" <<EOF
{
  "layer": "device-regression",
  "platform": "$platform",
  "steps": { "build": "$build", "install": "$install", "maestro": "$maestro" },
  "verdict": "$verdict"
}
EOF
    echo "$verdict"
}

OVERALL="PASS"
if [ "$DO_ANDROID" -eq 1 ]; then
    AV="$(write_platform_json "$RESULT_DIR/android.json" android "$A_BUILD" "$A_INSTALL" "$A_MAESTRO")"
    [ "$AV" = "FAIL" ] && OVERALL="FAIL"
    step "android verdict=$AV"
fi
if [ "$DO_IOS" -eq 1 ]; then
    IV="$(write_platform_json "$RESULT_DIR/ios.json" ios "$I_BUILD" "$I_INSTALL" "$I_MAESTRO")"
    [ "$IV" = "FAIL" ] && OVERALL="FAIL"
    step "ios verdict=$IV"
fi

echo "[layer3] verdict=$OVERALL results=$RESULT_DIR"
[ "$OVERALL" = "PASS" ]
