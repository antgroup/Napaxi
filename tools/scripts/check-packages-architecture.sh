#!/usr/bin/env bash
# Lightweight architecture guard for the packages/ SDK adapter layer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

info() { printf '[INFO] %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || err "$1 not found"
}

info "Checking packages architecture constraints"
cd "$ROOT_DIR"
require_command git
require_command grep

[ -d packages ] || err "Missing packages/ directory."
[ ! -d sdk ] || err "Do not create a sibling sdk/ tree; SDK adapters belong under packages/."
[ ! -d packages/napaxi_sdk ] || err "Do not reintroduce a generic packages/napaxi_sdk package."
[ ! -d packages/flutter/lib/src ] || err "packages/flutter/lib must stay flat by responsibility; do not add lib/src/."
[ -d packages/api_contract ] || err "Missing packages/api_contract/. Keep SDK adapter goals and contracts documented."

for contract_file in \
    packages/api_contract/README.md \
    packages/api_contract/goals.md \
    packages/api_contract/errors.yaml \
    packages/api_contract/methods.yaml \
    packages/api_contract/capability_matrix.yaml \
    packages/api_contract/workspace.json; do
    [ -f "$contract_file" ] || err "Missing SDK adapter contract file: $contract_file"
done

[ -d packages/api_contract/fixtures/workspace ] || err "Missing workspace API contract fixtures: packages/api_contract/fixtures/workspace"

if git grep -n -E '^(<<<<<<<|=======|>>>>>>>)' -- packages >/dev/null; then
    git grep -n -E '^(<<<<<<<|=======|>>>>>>>)' -- packages >&2
    err "Unresolved merge conflict markers found under packages/."
fi

if git ls-files packages | grep -E '(^|/)(build|\.build|\.dart_tool|\.gradle)(/|$)' >/dev/null; then
    git ls-files packages | grep -E '(^|/)(build|\.build|\.dart_tool|\.gradle)(/|$)' >&2
    err "Build/tool cache outputs must not be tracked under packages/."
fi

if git ls-files packages | grep -E '(^|/)napaxi_sdk(/|$)' >/dev/null; then
    git ls-files packages | grep -E '(^|/)napaxi_sdk(/|$)' >&2
    err "Generic napaxi_sdk package path is not allowed."
fi

# Generated bridge files may exist, but changes to them should come from codegen
# and be reviewed separately from hand-written adapter changes.
if git diff --name-only -- packages/flutter/lib/generated packages/api_bridge/generated \
    | grep -q .; then
    git diff --name-only -- packages/flutter/lib/generated packages/api_bridge/generated >&2
    err "Generated bridge files changed. Run codegen intentionally and review generated output separately."
fi

# Contract-first guard: public package docs must point maintainers at the API
# contract so future adapter work does not bypass it.
if ! grep -q 'api_contract/' packages/README.md; then
    err "packages/README.md must reference packages/api_contract/."
fi

info "Packages architecture constraints passed"
