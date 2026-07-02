#!/usr/bin/env bash
# Coverage floor for the Napaxi core public API boundary.
#
# `crates/core/src/api/` is the single surface every SDK adapter (Flutter,
# Android, iOS) enters the Rust core through. It is the highest-value code to
# keep covered, so it gets its own floor independent of the workspace total.
#
# This script parses an lcov file (produced by `cargo llvm-cov --lcov`),
# computes the line-coverage percentage for files under
# `crates/core/src/api/`, ALWAYS prints it, and fails if it is below the
# checked-in floors defined in this script.
#
# The floor is a regression catcher (e.g. "someone deleted the API tests"), not
# a quality target. Keep it pinned to the last reviewed CI baseline, then raise
# it deliberately as coverage improves.
#
# Usage: coverage-floor.sh <lcov-file>

set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

CORE_API_MIN_LINES=74
CORE_SRC_MIN_LINES=0

LCOV_FILE="${1:-}"
[ -n "$LCOV_FILE" ] || err "Usage: coverage-floor.sh <lcov-file>"
[ -f "$LCOV_FILE" ] || err "lcov file not found: $LCOV_FILE"

# Sum DA: (line-hit) records for files matching a path substring.
# lcov format: `SF:<path>` opens a file section; `DA:<line>,<hits>` per line;
# `end_of_record` closes it. We track whether the current section is in scope.
read_counts() {
    awk -v scope="$1" '
        /^SF:/ {
            path = substr($0, 4)
            inscope = (index(path, scope) > 0)
            next
        }
        /^DA:/ {
            if (inscope) {
                split(substr($0, 4), a, ",")
                total++
                if (a[2] + 0 > 0) covered++
            }
            next
        }
        /^end_of_record/ { inscope = 0 }
        END { printf "%d %d\n", covered + 0, total + 0 }
    ' "$LCOV_FILE"
}

# --- Floor 1: the public API boundary (crates/core/src/api/) -----------------
set -- $(read_counts "crates/core/src/api/")
COVERED="$1"
TOTAL="$2"

if [ "$TOTAL" -eq 0 ]; then
    err "No coverage data found for crates/core/src/api/ in $LCOV_FILE. Did llvm-cov run against the api boundary?"
fi

# Integer percentage (floored) to avoid bc/float dependency.
PCT=$(( COVERED * 100 / TOTAL ))

info "Core API boundary line coverage: ${PCT}% (${COVERED}/${TOTAL} lines) — floor ${CORE_API_MIN_LINES}%"

if [ "$PCT" -lt "$CORE_API_MIN_LINES" ]; then
    err "Core API coverage ${PCT}% is below the floor of ${CORE_API_MIN_LINES}%. Add tests for crates/core/src/api/, or justify lowering the floor in review."
fi

if [ "$PCT" -gt "$CORE_API_MIN_LINES" ]; then
    info "Coverage exceeds the floor — raise CORE_API_MIN_LINES in tools/scripts/coverage-floor.sh to ${PCT} to lock it in."
fi

# --- Floor 2: the whole napaxi-core src (catches the execution layer) ---------
set -- $(read_counts "crates/core/src/")
SRC_COVERED="$1"
SRC_TOTAL="$2"

if [ "$SRC_TOTAL" -eq 0 ]; then
    err "No coverage data found for crates/core/src/ in $LCOV_FILE."
fi

SRC_PCT=$(( SRC_COVERED * 100 / SRC_TOTAL ))

info "napaxi-core/src line coverage: ${SRC_PCT}% (${SRC_COVERED}/${SRC_TOTAL} lines) — floor ${CORE_SRC_MIN_LINES}%"

if [ "$SRC_PCT" -lt "$CORE_SRC_MIN_LINES" ]; then
    err "napaxi-core/src coverage ${SRC_PCT}% is below the floor of ${CORE_SRC_MIN_LINES}%. The core execution layer (turn/llm/mcp/...) regressed; add tests or justify lowering the floor in review."
fi

if [ "$SRC_PCT" -gt "$CORE_SRC_MIN_LINES" ]; then
    info "Whole-src coverage exceeds the floor — raise CORE_SRC_MIN_LINES in tools/scripts/coverage-floor.sh to ${SRC_PCT} after reviewing the CI baseline."
fi

info "Core coverage floors passed"
