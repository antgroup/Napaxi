#!/usr/bin/env bash
# Coverage floor for the Flutter SDK adapter (packages/flutter/lib).
#
# Mirrors tools/scripts/coverage-floor.sh (the Rust core-API floor) for the
# Dart side: parses the lcov produced by `flutter test --coverage`, computes
# the overall line-coverage percentage for packages/flutter/lib, ALWAYS prints
# it, and fails if it is below the floor in flutter-coverage-baseline.txt.
#
# Like the Rust floor, this is a regression catcher (e.g. "someone deleted the
# model tests"), not a quality target. The number may only go UP: raise
# FLUTTER_SDK_MIN_LINES when real coverage improves to lock it in.
#
# Note: the api/*.dart FFI wrappers are thin pass-throughs exercised through
# integration, not unit tests, so they sit near 0% and pull the aggregate down.
# The floor is set on the whole-lib aggregate intentionally — it catches
# regressions in the model/codec/convenience layers that DO carry unit tests.
#
# Usage: flutter-coverage-floor.sh <lcov-file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASELINE_FILE="$SCRIPT_DIR/flutter-coverage-baseline.txt"

info() { printf '[INFO] %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

LCOV_FILE="${1:-}"
[ -n "$LCOV_FILE" ] || err "Usage: flutter-coverage-floor.sh <lcov-file>"
[ -f "$LCOV_FILE" ] || err "lcov file not found: $LCOV_FILE"
[ -f "$BASELINE_FILE" ] || err "Missing baseline file: $BASELINE_FILE"

FLOOR="$(grep -E '^FLUTTER_SDK_MIN_LINES=' "$BASELINE_FILE" | head -1 | cut -d= -f2 | tr -d '[:space:]')"
[ -n "$FLOOR" ] || err "Baseline missing FLUTTER_SDK_MIN_LINES= line in $BASELINE_FILE"

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

info "Flutter SDK line coverage: ${PCT}% (${COVERED}/${TOTAL} lines) — floor ${FLOOR}%"

if [ "$PCT" -lt "$FLOOR" ]; then
    err "Flutter SDK coverage ${PCT}% is below the floor of ${FLOOR}%. Add tests under packages/flutter, or justify lowering the floor in review."
fi

if [ "$PCT" -gt "$FLOOR" ]; then
    info "Coverage exceeds the floor — raise FLUTTER_SDK_MIN_LINES in $BASELINE_FILE to ${PCT} to lock it in."
fi

info "Flutter SDK coverage floor passed"
