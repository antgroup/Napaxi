#!/usr/bin/env bash
# Test-stability ratchet for the Napaxi repo.
#
# Green CI must not be bought by skipping tests. This guard counts the
# skip/ignore markers in first-party test code and compares them against a
# checked-in baseline. The count may only go DOWN: adding a new `#[ignore]`
# (Rust) or `skip:` (Dart/flutter_test) fails CI until the baseline is
# lowered in the same change, which forces a reviewer to see the regression.
#
# Lowering the baseline (re-enabling a test) is always allowed and the script
# nudges you to update the file when you do.
#
# Third-party vendored code under vendor/ is intentionally excluded: we do not
# police upstream test discipline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASELINE_FILE="$SCRIPT_DIR/test-skip-baseline.txt"

info() { printf '[INFO] %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || err "$1 not found"
}

cd "$ROOT_DIR"
require_command git
require_command grep

[ -f "$BASELINE_FILE" ] || err "Missing baseline file: $BASELINE_FILE"

# First-party test files only (exclude vendored third-party code), one per
# line. Newline-separated so we stay portable to bash 3.2 (no mapfile).
RUST_FILES="$(git ls-files '*.rs' | grep -v '^vendor/' || true)"
DART_FILES="$(git ls-files '*_test.dart' | grep -v '^vendor/' || true)"

# Count lines matching a pattern across a newline-separated file list.
count_pattern() {
    local pattern="$1"
    local files="$2"
    [ -n "$files" ] || { printf '0\n'; return; }
    printf '%s\n' "$files" \
        | tr '\n' '\0' \
        | xargs -0 grep -hE "$pattern" 2>/dev/null \
        | grep -cE "$pattern" || true
}

# List matching sites across a newline-separated file list (for visibility).
list_pattern() {
    local pattern="$1"
    local files="$2"
    [ -n "$files" ] || return 0
    printf '%s\n' "$files" \
        | tr '\n' '\0' \
        | xargs -0 grep -nE "$pattern" 2>/dev/null \
        | sed 's/^/  /' || true
}

# Rust `#[ignore]` (with or without a reason string).
RUST_IGNORE=$(count_pattern '#\[ignore' "$RUST_FILES")
# Dart/flutter_test `skip:` argument on test()/testWidgets()/group().
DART_SKIP=$(count_pattern 'skip:' "$DART_FILES")

# Read expected values from the baseline file (KEY=VALUE lines, '#' comments).
read_baseline() {
    local key="$1"
    grep -E "^${key}=" "$BASELINE_FILE" | head -1 | cut -d= -f2 | tr -d '[:space:]'
}
BASE_RUST=$(read_baseline RUST_IGNORE)
BASE_DART=$(read_baseline DART_SKIP)

[ -n "$BASE_RUST" ] || err "Baseline missing RUST_IGNORE= line in $BASELINE_FILE"
[ -n "$BASE_DART" ] || err "Baseline missing DART_SKIP= line in $BASELINE_FILE"

info "Test-stability counts (first-party, vendor excluded):"
info "  Rust  #[ignore] : current=$RUST_IGNORE baseline=$BASE_RUST"
info "  Dart  skip:      : current=$DART_SKIP baseline=$BASE_DART"

# Visibility: list exactly where the skips/ignores live so reviewers see them.
if [ "$RUST_IGNORE" -gt 0 ]; then
    info "Rust #[ignore] sites:"
    list_pattern '#\[ignore' "$RUST_FILES"
fi
if [ "$DART_SKIP" -gt 0 ]; then
    info "Dart skip: sites:"
    list_pattern 'skip:' "$DART_FILES"
fi

fail=0
if [ "$RUST_IGNORE" -gt "$BASE_RUST" ]; then
    printf '[ERROR] Rust #[ignore] count rose from %s to %s. Do not skip tests to make CI green.\n' "$BASE_RUST" "$RUST_IGNORE" >&2
    fail=1
fi
if [ "$DART_SKIP" -gt "$BASE_DART" ]; then
    printf '[ERROR] Dart skip: count rose from %s to %s. Do not skip tests to make CI green.\n' "$BASE_DART" "$DART_SKIP" >&2
    fail=1
fi
[ "$fail" -eq 0 ] || err "Test-stability ratchet violated. If a skip is unavoidable, justify it in review and update $BASELINE_FILE."

# Encourage tightening the ratchet when skips are removed.
if [ "$RUST_IGNORE" -lt "$BASE_RUST" ] || [ "$DART_SKIP" -lt "$BASE_DART" ]; then
    info "Skip count dropped below baseline — lower the numbers in $BASELINE_FILE to lock in the improvement."
fi

info "Test-stability ratchet passed"
