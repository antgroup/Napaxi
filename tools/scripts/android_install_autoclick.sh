#!/usr/bin/env bash
# Android install-dialog auto-clicker.
#
# Polls the foreground window via `adb shell dumpsys window | grep -m1
# mCurrentFocus`; when the MIUI / AOSP package installer installer activity
# surfaces (com.miui.securitycenter / com.miui.permcenter.install.
# AdbInstallActivity / packageinstaller / PackageInstaller), it taps a
# configurable screen coordinate so an unattended `adb install -r` flow can
# confirm the "Continue install" prompt without a human.
#
# Usage:
#   tools/scripts/android_install_autoclick.sh --serial <serial> \
#       [--timeout <seconds>] [--tap-x <int>] [--tap-y <int>] \
#       [--interval <seconds>] [--adbin <adb binary>] [--log <path>]
#
# Environment overrides:
#   AUTOCLICK_TAP_X        default tap X (CLI --tap-x wins)
#   AUTOCLICK_TAP_Y        default tap Y (CLI --tap-y wins)
#   AUTOCLICK_TIMEOUT      default lifetime seconds (CLI --timeout wins)
#   AUTOCLICK_INTERVAL     default poll step seconds (CLI --interval wins)
#   ANDROID_HOME           Android SDK root, used to locate adb
#   AUTOCLICK_ADB          explicit adb binary path (CLI --adbin wins)
#
# Pre-requisites (manual, one-time, document in tools/scripts/README*.md):
#   - Developer options -> "USB debugging (security settings)" = ON.
#     Without it, `adb shell input tap` raises INJECT_EVENTS SecurityException.
#   - Screen unlocked.
#   - Phone plugged in, and these settings applied once via adb:
#       adb shell settings put global stay_on_while_plugged_in 7
#       adb shell settings put system screen_off_timeout 2147483647
#     Keeping the screen on avoids INSTALL_FAILED_USER_RESTRICTED
#     ("Install canceled by user") when the display sleeps mid-install.
#
# Red lines (DO NOT VIOLATE):
#   - Never uninstall packages, clear package data, run flutter's clean
#     subcommand, or wipe data; the surrounding flow only uses the
#     data-preserving `adb install -r` form (never the downgrade flag).
#   - Never use the `uiauto`+`mator` dump / run subcommands. The UI Automator
#     bridge mounts an accessibility service, which makes Flutter
#     integration_test raise "A SemanticsHandle was active at the end of the
#     test" on tear-down — a false-negative verified by a three-state
#     comparison. Detection MUST stay on `dumpsys window` + `input tap`.
#
# Exit reasons (last log line keywords):
#   TIMEOUT     --timeout reached, normal exit (status 0)
#   SIGNAL      received TERM/INT, normal exit (status 0)
#   ADB_UNREACHABLE  adb unreachable for >=3 consecutive polls (status 1)
#
set -uo pipefail

# ---- defaults -------------------------------------------------------------

DEFAULT_TAP_X=346
DEFAULT_TAP_Y=2483
DEFAULT_TIMEOUT=600
DEFAULT_INTERVAL=1.5

SERIAL=""
TAP_X="${AUTOCLICK_TAP_X:-$DEFAULT_TAP_X}"
TAP_Y="${AUTOCLICK_TAP_Y:-$DEFAULT_TAP_Y}"
TIMEOUT="${AUTOCLICK_TIMEOUT:-$DEFAULT_TIMEOUT}"
INTERVAL="${AUTOCLICK_INTERVAL:-$DEFAULT_INTERVAL}"
ADBIN="${AUTOCLICK_ADB:-}"
LOG_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --serial)    SERIAL="$2"; shift ;;
        --timeout)   TIMEOUT="$2"; shift ;;
        --tap-x)     TAP_X="$2"; shift ;;
        --tap-y)     TAP_Y="$2"; shift ;;
        --interval)  INTERVAL="$2"; shift ;;
        --adbin)     ADBIN="$2"; shift ;;
        --log)       LOG_FILE="$2"; shift ;;
        -h|--help)
            sed -n '2,40p' "$0"
            exit 0
            ;;
        *) echo "android_install_autoclick: unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$SERIAL" ]; then
    echo "android_install_autoclick: --serial is required" >&2
    exit 2
fi

case "$TAP_X" in
    ''|*[!0-9]*) echo "android_install_autoclick: --tap-x must be a positive int" >&2; exit 2 ;;
esac
case "$TAP_Y" in
    ''|*[!0-9]*) echo "android_install_autoclick: --tap-y must be a positive int" >&2; exit 2 ;;
esac
case "$TIMEOUT" in
    ''|*[!0-9]*) echo "android_install_autoclick: --timeout must be a positive int (seconds)" >&2; exit 2 ;;
esac

# Locate adb.
if [ -z "$ADBIN" ]; then
    if [ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
        ADBIN="$ANDROID_HOME/platform-tools/adb"
    else
        ADBIN="$(command -v adb || true)"
    fi
fi
if [ -z "$ADBIN" ] || [ ! -x "$ADBIN" ]; then
    echo "android_install_autoclick: adb not found (set --adbin or ANDROID_HOME)" >&2
    exit 2
fi

# ---- logging --------------------------------------------------------------

ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

emit() {
    local line="$(ts) $*"
    if [ -n "$LOG_FILE" ]; then
        echo "$line" >> "$LOG_FILE"
    fi
    # Always also surface on stderr so a foreground invoker can see it; layer3
    # redirects stdout/stderr of the nohup child to a runner log.
    echo "$line" >&2
}

# ---- state ----------------------------------------------------------------

TAPS=0
EXIT_REASON="UNKNOWN"
ADB_FAIL_STREAK=0
STOP=0

on_signal() {
    STOP=1
    EXIT_REASON="SIGNAL"
}
trap on_signal INT TERM

# Write a single start line so a verifier can grep "start" + serial + tap_x.
emit "start serial=$SERIAL tap_x=$TAP_X tap_y=$TAP_Y timeout=$TIMEOUT"

DEADLINE=$(( $(date +%s) + TIMEOUT ))

while [ "$STOP" -eq 0 ]; do
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then
        EXIT_REASON="TIMEOUT"
        break
    fi

    focus="$("$ADBIN" -s "$SERIAL" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)"
    rc=$?
    if [ -z "$focus" ] || [ "$rc" -ne 0 ]; then
        ADB_FAIL_STREAK=$((ADB_FAIL_STREAK + 1))
        if [ "$ADB_FAIL_STREAK" -ge 3 ]; then
            EXIT_REASON="ADB_UNREACHABLE"
            emit "warn adb unreachable streak=$ADB_FAIL_STREAK"
            emit "exit reason $EXIT_REASON taps=$TAPS"
            exit 1
        fi
        sleep "$INTERVAL"
        continue
    fi
    ADB_FAIL_STREAK=0

    # Hit if any installer window keyword is present. Keep the list literal
    # so future maintainers can append new installer activities without a
    # regex black-list false-pane.
    case "$focus" in
        *com.miui.securitycenter*|*com.miui.permcenter.install.AdbInstallActivity*|*packageinstaller*|*PackageInstaller*)
            emit "dialog detected window=$focus"
            if "$ADBIN" -s "$SERIAL" shell input tap "$TAP_X" "$TAP_Y" >/dev/null 2>&1; then
                TAPS=$((TAPS + 1))
                emit "tapped $TAP_X $TAP_Y"
            else
                emit "warn tap failed rc=$? x=$TAP_X y=$TAP_Y"
            fi
            ;;
    esac

    sleep "$INTERVAL"
done

if [ "$EXIT_REASON" = "UNKNOWN" ]; then
    EXIT_REASON="SIGNAL"
fi

emit "exit reason $EXIT_REASON taps=$TAPS"
exit 0
