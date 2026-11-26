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
#   ANDROID_HOME          Android SDK root (default: $HOME/Library/Android/sdk)
#   JAVA_HOME             JDK 17; auto-detected via /usr/libexec/java_home if unset
#   IOS_TEAM_ID            Apple Team ID for on-device signing (default: SL3WHU96U7)
#   AUTOCLICK_TAP_X       override autoclick tap X (default 346, Xiaomi 15)
#   AUTOCLICK_TAP_Y       override autoclick tap Y (default 2483, Xiaomi 15)
#   AUTOCLICK_TIMEOUT     autoclick lifetime seconds (default 600)
#   UI_FRAMEWORK          android smoke driver: u2 (uiautomator2, default) | maestro (legacy)
#   U2_VENV_PY            python venv for u2 mode (default: $HOME/testing/u2env/bin/python)
#   UI_SUITE              u2 suite: L0|L1|all (default L0); ignored under maestro
#   DEVPOOL_JOB_ID        short id forwarded as --run-id to u2_runner.py
#
# Prerequisites (manual, one-time):
#   Android: USB debugging enabled, `adb devices` shows the phone authorized.
#            Additionally, for unattended install the auto-clicker requires:
#              - Developer option "USB debugging (security settings)" = ON
#                (otherwise `adb shell input tap` raises INJECT_EVENTS).
#              - Screen unlocked.
#              - Phone plugged in with:
#                  adb shell settings put global stay_on_while_plugged_in 7
#                  adb shell settings put system screen_off_timeout 2147483647
#                to keep the screen on and avoid INSTALL_FAILED_USER_RESTRICTED.
#   iOS:     iPhone paired+trusted, Developer Mode on, and an Apple ID that
#            belongs to $IOS_TEAM_ID added under Xcode > Settings > Accounts
#            (automatic signing then issues a Development certificate and
#            registers the device UDID).
#
# Results are written to $HOME/testing/results/<timestamp>-layer3/ with one
# result JSON per attempted platform and an overall verdict line. The Android
# JSON additionally records `autoclick.taps` / `autoclick.exit_reason` and the
# raw auto-clicker transcript is kept at $RESULT_DIR/android-autoclick.log.
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

# UI framework for the android smoke step: u2 (uiautomator2, default) or
# maestro (legacy fallback). maestro path is preserved verbatim below.
UI_FRAMEWORK="${UI_FRAMEWORK:-u2}"
case "$UI_FRAMEWORK" in
    u2|maestro) ;;
    *) echo "unknown UI_FRAMEWORK: $UI_FRAMEWORK (expected u2|maestro)" >&2; exit 2 ;;
esac
U2_VENV_PY="${U2_VENV_PY:-$HOME/testing/u2env/bin/python}"

# u2 suite scope (plan 交付物 8 §2): L0|L1|all; ignored under maestro branch.
UI_SUITE="${UI_SUITE:-L0}"
case "$UI_SUITE" in
    L0|L1|all) ;;
    *) echo "unknown UI_SUITE: $UI_SUITE (expected L0|L1|all)" >&2; exit 2 ;;
esac

MAESTRO_BIN="$(command -v maestro || true)"
[ -n "$MAESTRO_BIN" ] || MAESTRO_BIN="$HOME/.maestro/bin/maestro"
# maestro CLI is required only when its path is actually exercised: the maestro
# android branch, or any iOS run (iOS step always uses maestro). In u2 +
# --android-only mode maestro is never invoked, so a missing CLI must not
# hard-fail the gate — the negative control (验收 B) must reach a verdict line
# rather than exit 2 on a dependency it does not use.
if [ "$UI_FRAMEWORK" = "maestro" ] || [ "$DO_IOS" -eq 1 ]; then
    [ -n "$MAESTRO_BIN" ] && [ -x "$MAESTRO_BIN" ] || { echo "maestro CLI not found" >&2; exit 2; }
fi

TS="$(date +%Y%m%d-%H%M%S)"
# devpool 闸口注入 DEVPOOL_RESULT_DIR(=$POOL/results/<jobid>) 时产物落该目录（单层，满足
# 验收 E：android.json 直接在 results/<jobid>/ 下）；无注入时回退原 timestamped 单跑目录。
RESULT_DIR="${DEVPOOL_RESULT_DIR:-$HOME/testing/results/$TS-layer3}"
mkdir -p "$RESULT_DIR"
cd "$ROOT_DIR"

step() { echo "[layer3] $*"; }

# Auto-clicker state (filled in run_android, consumed by write_platform_json).
A_AUTOCLICK_TAPS=0
A_AUTOCLICK_EXIT="not_run"
AUTOCLICK_PID=""

cleanup_autoclick() {
    if [ -n "${AUTOCLICK_PID:-}" ] && kill -0 "$AUTOCLICK_PID" 2>/dev/null; then
        kill "$AUTOCLICK_PID" 2>/dev/null || true
        local i
        for i in $(seq 1 10); do
            kill -0 "$AUTOCLICK_PID" 2>/dev/null || break
            sleep 0.3
        done
        kill -9 "$AUTOCLICK_PID" 2>/dev/null || true
    fi
    # Sweep any residue auto-clicker targeting the same serial.
    if [ -n "${ANDROID_SERIAL:-}" ]; then
        pkill -f "android_install_autoclick.sh --serial $ANDROID_SERIAL" 2>/dev/null || true
    fi
}
trap cleanup_autoclick EXIT

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
# Per-case records harvested from u2_runner.py summary.json (plan 交付物 8 §4).
# Empty list when maestro branch ran (no cases) or u2 failed before writing summary.
A_CASES="[]"

run_android() {
    detect_android
    if [ -z "$ANDROID_SERIAL" ]; then
        step "android: no physical device found, skipped"
        # In u2 mode a missing device is not a silent skip — the gate must
        # still go red (验收 B negative control). Mark the smoke step blocked
        # so write_platform_json forces verdict=FAIL rather than SKIP.
        if [ "$UI_FRAMEWORK" = "u2" ]; then
            A_MAESTRO="blocked"
        fi
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

    # Start the install-dialog auto-clicker in the background. It taps
    # "Continue install" if MIUI/aosp installer foregrounds; never changes
    # the layer3 verdict — only writes taps/exit_reason at the end.
    local autoclick_log="$RESULT_DIR/android-autoclick.log"
    : > "$autoclick_log"
    local autoclick_runner_log="$RESULT_DIR/android-autoclick.runner.log"
    : > "$autoclick_runner_log"
    local autoclick_bin="$ROOT_DIR/tools/scripts/android_install_autoclick.sh"
    if [ -x "$autoclick_bin" ]; then
        nohup "$autoclick_bin" \
            --serial "$ANDROID_SERIAL" \
            --tap-x "${AUTOCLICK_TAP_X:-346}" \
            --tap-y "${AUTOCLICK_TAP_Y:-2483}" \
            --timeout "${AUTOCLICK_TIMEOUT:-600}" \
            --log "$autoclick_log" \
            > "$autoclick_runner_log" 2>&1 &
        AUTOCLICK_PID=$!
        step "android: autoclick started pid=$AUTOCLICK_PID log=$autoclick_log"
    else
        step "android: autoclick binary missing ($autoclick_bin); continuing without auto-tap"
        A_AUTOCLICK_EXIT="missing"
    fi

    # UI smoke step. android.json keeps the field name `steps.maestro` for
    # downstream compatibility; only the implementation behind A_MAESTRO
    # switches on UI_FRAMEWORK. u2 runs the python smoke via the Mac mini
    # venv (~/testing/u2env); a missing venv is "blocked" (verdict=FAIL,
    # never a silent pass). maestro preserves the legacy path verbatim.
    step "android: ui smoke ($UI_FRAMEWORK) --device $ANDROID_SERIAL"
    if [ "$UI_FRAMEWORK" = "u2" ]; then
        if [ ! -x "$U2_VENV_PY" ]; then
            step "android: u2 venv missing ($U2_VENV_PY) -> blocked"
            A_MAESTRO="blocked"
            A_CASES="[]"
        elif [ ! -d "$ROOT_DIR/tests/device/cases" ]; then
            step "android: u2 cases dir missing ($ROOT_DIR/tests/device/cases) -> blocked"
            A_MAESTRO="blocked"
            A_CASES="[]"
        else
            "$U2_VENV_PY" "$ROOT_DIR/tools/scripts/u2_runner.py" \
                --serial "$ANDROID_SERIAL" \
                --suite "$UI_SUITE" \
                --run-id "${DEVPOOL_JOB_ID:-local}" \
                --out-dir "$RESULT_DIR" \
                > "$RESULT_DIR/android-maestro.log" 2>&1
            rc=$?
            case "$rc" in
                0) A_MAESTRO="passed" ;;
                1) A_MAESTRO="failed" ;;
                *) A_MAESTRO="blocked" ;;
            esac
            if [ -f "$RESULT_DIR/summary.json" ]; then
                A_CASES="$(python3 -c "import json,sys; print(json.dumps(json.load(open('$RESULT_DIR/summary.json')).get('cases',[])))" 2>/dev/null || echo '[]')"
            else
                A_CASES="[]"
            fi
        fi
    else
        if "$MAESTRO_BIN" test --device "$ANDROID_SERIAL" "$FLOW_DIR" --format junit \
            --output "$RESULT_DIR/android-maestro.xml" > "$RESULT_DIR/android-maestro.log" 2>&1; then
            A_MAESTRO="passed"
        fi
        A_CASES="[]"
    fi

    # Stop the auto-clicker and harvest its summary. Any auto-clicker
    # failure is non-fatal — the maestro verdict above is authoritative.
    cleanup_autoclick
    AUTOCLICK_PID=""

    if [ -f "$autoclick_log" ]; then
        # The last `exit reason <REASON> taps=<N>` line is the authoritative
        # summary written by android_install_autoclick.sh on any exit.
        local reason_line taps
        reason_line="$(grep 'exit reason' "$autoclick_log" | tail -1 || true)"
        if [ -n "$reason_line" ]; then
            A_AUTOCLICK_EXIT="$(echo "$reason_line" | sed -E 's/.*exit reason ([^ ]+).*/\1/')"
            taps="$(echo "$reason_line" | sed -E 's/.*taps=([0-9]+).*/\1/')"
            case "$taps" in
                ''|*[!0-9]*) A_AUTOCLICK_TAPS=0 ;;
                *) A_AUTOCLICK_TAPS="$taps" ;;
            esac
        else
            A_AUTOCLICK_EXIT="no_summary"
        fi
    fi
    step "android: autoclick taps=$A_AUTOCLICK_TAPS exit_reason=$A_AUTOCLICK_EXIT"

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
        # -derivedDataPath pins the build output to a per-run directory so
        # the showBuildSettings lookup below can deterministically locate
        # the .app instead of globbing ~/Library/.../DerivedData/Runner-*.
        step "ios: xcodebuild Debug for device (automatic signing, per-run DerivedData)"
        if (cd "$APP_DIR/ios" && xcodebuild \
                -workspace Runner.xcworkspace -scheme Runner \
                -configuration Debug \
                -destination "id=$IOS_UDID" \
                DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
                CODE_SIGN_STYLE=Automatic \
                -allowProvisioningUpdates \
                -derivedDataPath "$RESULT_DIR/ios-derived" \
                build) > "$RESULT_DIR/ios-build.log" 2>&1; then
            I_BUILD="passed"
        else
            I_BUILD="failed"
            echo "ios build failed, see $RESULT_DIR/ios-build.log" >&2
            return
        fi
    fi

    # Locate the .app via -showBuildSettings against the SAME -derivedDataPath
    # used for the build, so TARGET_BUILD_DIR / FULL_PRODUCT_NAME always refer
    # to this run's per-run DerivedData. Any failure (xcodebuild nonzero,
    # missing field, missing directory) is treated as "not located": write
    # the cause to ios-install.log, set I_BUILD=failed, and return loudly
    # (this is the negative-control contract — never silently skip).
    local app=""
    local settings_log="$RESULT_DIR/ios-showBuildSettings.log"
    if (cd "$APP_DIR/ios" && xcodebuild \
            -workspace Runner.xcworkspace -scheme Runner \
            -configuration Debug \
            -destination "id=$IOS_UDID" \
            DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
            CODE_SIGN_STYLE=Automatic \
            -allowProvisioningUpdates \
            -derivedDataPath "$RESULT_DIR/ios-derived" \
            -showBuildSettings) > "$settings_log" 2>&1; then
        local tbd fpn
        tbd="$(awk -F' *= *' '/^[[:space:]]*TARGET_BUILD_DIR[[:space:]]*=/{
            sub(/^[[:space:]]+/, "", $1);
            if ($1=="TARGET_BUILD_DIR") { print $2; exit }
        }' "$settings_log")"
        fpn="$(awk -F' *= *' '/^[[:space:]]*FULL_PRODUCT_NAME[[:space:]]*=/{
            sub(/^[[:space:]]+/, "", $1);
            if ($1=="FULL_PRODUCT_NAME") { print $2; exit }
        }' "$settings_log")"
        if [ -n "$tbd" ] && [ -n "$fpn" ] && [ -d "$tbd/$fpn" ]; then
            app="$tbd/$fpn"
        fi
    fi

    if [ -z "$app" ] || [ ! -d "$app" ]; then
        {
            echo "ios: Runner.app not located via -showBuildSettings."
            echo "derivedDataPath: $RESULT_DIR/ios-derived"
            echo "showBuildSettings log: $settings_log"
            if [ -f "$settings_log" ]; then
                echo '---- showBuildSettings tail ----'
                tail -50 "$settings_log"
            else
                echo 'showBuildSettings did not run; no log.'
            fi
            echo '---- ios-build.log tail (if any) ----'
            [ -f "$RESULT_DIR/ios-build.log" ] && tail -50 "$RESULT_DIR/ios-build.log"
        } > "$RESULT_DIR/ios-install.log" 2>&1
        I_BUILD="failed"
        echo "ios: Runner.app not located, see $RESULT_DIR/ios-install.log" >&2
        return
    fi
    step "ios: located app $app"

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
    local basename="$1" platform="$2" build="$3" install="$4" maestro="$5"
    # Only receive the filename (android.json / ios.json) and join with
    # $RESULT_DIR here, so callers cannot accidentally double-join and
    # produce $RESULT_DIR/$RESULT_DIR/<name>. Result path is always a
    # single level under $RESULT_DIR (itself $HOME/testing/results/<ts>-layer3).
    local out="$RESULT_DIR/$basename"
    local verdict="SKIP"
    if [ "$install" != "skipped" ]; then
        verdict="PASS"
        { [ "$build" = "passed" ] || [ "$build" = "skipped" ]; } || verdict="FAIL"
        [ "$install" = "passed" ] || verdict="FAIL"
        [ "$maestro" = "passed" ] || verdict="FAIL"
    fi
    # A "blocked" smoke step (u2 venv missing, or no device in u2 mode) forces
    # FAIL even when install was skipped — the gate must not go green silently
    # when its run dependency is absent (验收 B negative control).
    [ "$maestro" = "blocked" ] && verdict="FAIL"

    local autoclick_block
    if [ "$platform" = "android" ]; then
        # Additive, nullable-safe: downstream aggregators only read
        # steps/verdict; autoclick is observational and never affects verdict.
        autoclick_block="\"autoclick\": { \"taps\": $A_AUTOCLICK_TAPS, \"exit_reason\": \"$A_AUTOCLICK_EXIT\" },"
    else
        autoclick_block="\"autoclick\": null,"
    fi

    cat > "$out" <<EOF
{
  "layer": "device-regression",
  "platform": "$platform",
  "steps": { "build": "$build", "install": "$install", "maestro": "$maestro" },
  $autoclick_block
  "cases": $A_CASES,
  "verdict": "$verdict"
}
EOF
    echo "$verdict"
}

OVERALL="PASS"
if [ "$DO_ANDROID" -eq 1 ]; then
    AV="$(write_platform_json android.json android "$A_BUILD" "$A_INSTALL" "$A_MAESTRO")"
    [ "$AV" = "FAIL" ] && OVERALL="FAIL"
    step "android verdict=$AV"
fi
if [ "$DO_IOS" -eq 1 ]; then
    IV="$(write_platform_json ios.json ios "$I_BUILD" "$I_INSTALL" "$I_MAESTRO")"
    [ "$IV" = "FAIL" ] && OVERALL="FAIL"
    step "ios verdict=$IV"
fi

echo "[layer3] verdict=$OVERALL results=$RESULT_DIR"
[ "$OVERALL" = "PASS" ]
