#!/usr/bin/env bash
# Coverage floor for the Flutter SDK adapter (packages/flutter/lib).
#
# Mirrors tools/scripts/coverage-floor.sh (the Rust core-API floor) for the
# Dart side: parses the lcov produced by `flutter test --coverage`, computes
# the overall line-coverage percentage for packages/flutter/lib, ALWAYS prints
# it, and fails if it is below the checked-in floor defined in this script.
#
# Like the Rust floor, this is a regression catcher (e.g. "someone deleted the
# model tests"), not a quality target. The number may only go UP: raise the
# checked-in minimum when real coverage improves to lock it in.
#
# Note: the api/*.dart FFI wrappers are thin pass-throughs exercised through
# integration, not unit tests, so they sit near 0% and pull the aggregate down.
# The floor is set on the whole-lib aggregate intentionally — it catches
# regressions in the model/codec/convenience layers that DO carry unit tests.
#
# Usage: flutter-coverage-floor.sh <lcov-file>

set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

FLUTTER_SDK_MIN_LINES=35

LCOV_FILE="${1:-}"
[ -n "$LCOV_FILE" ] || err "Usage: flutter-coverage-floor.sh <lcov-file>"
[ -f "$LCOV_FILE" ] || err "lcov file not found: $LCOV_FILE"

# Sum all DA: line-hit records (flutter coverage already scopes to lib/).
read_counts() {
    awk '
        /^DA:/ {
            split(substr($0, 4), a, ",")
            total++
            if (a[2] + 0 > 0) covered++
        }
        END { printf "%d %d\n", covered + 0, total + 0 }
    ' "$LCOV_FILE"
}

set -- $(read_counts)
COVERED="$1"
TOTAL="$2"

if [ "$TOTAL" -eq 0 ]; then
    err "No coverage data found in $LCOV_FILE. Did 'flutter test --coverage' run?"
fi

PCT=$(( COVERED * 100 / TOTAL ))

info "Flutter SDK line coverage: ${PCT}% (${COVERED}/${TOTAL} lines) — floor ${FLUTTER_SDK_MIN_LINES}%"

if [ "$PCT" -lt "$FLUTTER_SDK_MIN_LINES" ]; then
    err "Flutter SDK coverage ${PCT}% is below the floor of ${FLUTTER_SDK_MIN_LINES}%. Add tests under packages/flutter, or justify lowering the floor in review."
fi

if [ "$PCT" -gt "$FLUTTER_SDK_MIN_LINES" ]; then
    info "Coverage exceeds the floor — raise FLUTTER_SDK_MIN_LINES in tools/scripts/flutter-coverage-floor.sh to ${PCT} to lock it in."
fi

info "Flutter SDK coverage floor passed"
