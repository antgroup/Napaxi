#!/usr/bin/env bash
# Test-stability ratchet for the Napaxi repo.
#
# Green CI must not be bought by skipping tests. This guard counts the
# skip/ignore markers in first-party test code and compares them against the
# checked-in limits defined in this script. The count may only go DOWN: adding
# a new `#[ignore]` (Rust) or `skip:` (Dart/flutter_test) fails CI until the
# limit is raised in the same change, which forces a reviewer to see the
# regression.
#
# Lowering the limits (re-enabling a test) is always allowed and the script
# nudges you to update the constants when you do.
#
# Third-party vendored code under vendor/ is intentionally excluded: we do not
# police upstream test discipline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

info() { printf '[INFO] %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

RUST_IGNORE_LIMIT=1
DART_SKIP_LIMIT=0

require_command() {
    command -v "$1" >/dev/null 2>&1 || err "$1 not found"
}

cd "$ROOT_DIR"
require_command git
require_command grep

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

info "Test-stability counts (first-party, vendor excluded):"
info "  Rust  #[ignore] : current=$RUST_IGNORE limit=$RUST_IGNORE_LIMIT"
info "  Dart  skip:      : current=$DART_SKIP limit=$DART_SKIP_LIMIT"

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
if [ "$RUST_IGNORE" -gt "$RUST_IGNORE_LIMIT" ]; then
    printf '[ERROR] Rust #[ignore] count rose above the limit (%s -> %s). Do not skip tests to make CI green.\n' "$RUST_IGNORE_LIMIT" "$RUST_IGNORE" >&2
    fail=1
fi
if [ "$DART_SKIP" -gt "$DART_SKIP_LIMIT" ]; then
    printf '[ERROR] Dart skip: count rose above the limit (%s -> %s). Do not skip tests to make CI green.\n' "$DART_SKIP_LIMIT" "$DART_SKIP" >&2
    fail=1
fi
[ "$fail" -eq 0 ] || err "Test-stability ratchet violated. If a skip is unavoidable, justify it in review and update the limits in tools/scripts/check-test-stability.sh."

# Encourage tightening the ratchet when skips are removed.
if [ "$RUST_IGNORE" -lt "$RUST_IGNORE_LIMIT" ] || [ "$DART_SKIP" -lt "$DART_SKIP_LIMIT" ]; then
    info "Skip count dropped below the checked-in limits — lower the constants in tools/scripts/check-test-stability.sh to lock in the improvement."
fi

info "Test-stability ratchet passed"
