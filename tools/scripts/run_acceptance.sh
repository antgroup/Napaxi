#!/usr/bin/env bash
# Layer 6 orchestrator: run layer1 (flutter analyze + unit tests + coverage
# gates) and layer2 (Maestro smoke) back to back, then aggregate both
# result.json files into a single acceptance report.
#
# Usage:
#   tools/scripts/run_acceptance.sh [--skip-build] [--base <ref>] [--threshold <pct>]
#
#   --skip-build   pass through to layer2 (reuse the previously built APK)
#   --head         head ref layer1 runs against (default: origin/main);
#                  e.g. a delivery branch for a pre-merge green dry-run
#   --base         base ref for the changed-line coverage gate
#                  (default: origin/main~10)
#   --threshold    changed-line coverage percent (default: 80)
#
# The layer1/layer2 scripts may not have merged to main yet. When missing
# from the working tree they are bootstrapped from their PR branches
# (origin/feat/changed-line-coverage-gate, origin/feat/maestro-smoke) into
# $HOME/testing/bin/, and the Maestro flows into $HOME/testing/maestro-flows/.
# Once both PRs merge the in-tree copies win automatically.
#
# Output:
#   $HOME/testing/acceptance/<ts>/acceptance.json — aggregated report
#   $HOME/testing/acceptance/<ts>/layer{1,2}.log   — per-layer stdout/stderr
#   stdout final line, for the caller to relay (e.g. to DingTalk):
#   ACCEPTANCE {"verdict":"PASS|FAIL","layer1":"...","layer2":"...","report":"..."}
set -uo pipefail

REPO="${NAPAXI_REPO:-$HOME/repos/Napaxi}"
BIN_DIR="$HOME/testing/bin"
FLOW_OUT="$HOME/testing/maestro-flows"
HEAD_REF="origin/main"
BASE_REF="origin/main~10"
THRESHOLD="80"
SKIP_BUILD=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1 ;;
        --head)       HEAD_REF="$2"; shift ;;
        --base)       BASE_REF="$2"; shift ;;
        --threshold)  THRESHOLD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${_ACCEPTANCE_OUT:-$HOME/testing/acceptance/$TS}"
mkdir -p "$OUT_DIR" "$BIN_DIR" "$FLOW_OUT"

step() { echo "[acceptance] $*"; }

# Re-exec from a stable copy: layer1 checks out origin/main inside $REPO,
# which could swap this very file mid-read if we ran from the working tree.
if [ -z "${_ACCEPTANCE_REEXEC:-}" ]; then
    cp "${BASH_SOURCE[0]}" "$BIN_DIR/run_acceptance.sh"
    _ACCEPTANCE_REEXEC=1 _ACCEPTANCE_OUT="$OUT_DIR" \
        exec bash "$BIN_DIR/run_acceptance.sh" "$@"
fi

cd "$REPO" || exit 2
git fetch origin --quiet || step "warn: git fetch failed, using cached refs"

# Restore the original checkout when done (layer1 moves HEAD to origin/main).
ORIG_REF="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
cleanup() { git checkout -q "$ORIG_REF" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# --- bootstrap layer scripts ------------------------------------------------
# Copies land in $BIN_DIR so the layers run the same code regardless of which
# branch the working tree is on. In-tree copies (post-merge) take precedence.
bootstrap_file() { # <git-ref> <repo-path> <dest>
    local ref="$1" path="$2" dest="$3"
    if [ -f "$REPO/$path" ]; then
        cp "$REPO/$path" "$dest"
    elif git show "$ref:$path" > "$dest" 2>/dev/null; then
        step "bootstrapped $path from $ref"
    else
        step "ERROR: cannot obtain $path from tree or $ref" >&2
        return 1
    fi
    chmod +x "$dest"
}

bootstrap_file origin/feat/changed-line-coverage-gate \
    tools/scripts/layer1_gate.sh "$BIN_DIR/layer1_gate.sh" || exit 2
bootstrap_file origin/feat/maestro-smoke \
    tools/scripts/layer2_maestro_smoke.sh "$BIN_DIR/layer2_maestro_smoke.sh" || exit 2

# Maestro flows: in-tree if present, else extract the whole .maestro dir.
FLOW_DIR="$REPO/examples/flutter/.maestro"
if [ -d "$FLOW_DIR" ]; then
    cp -R "$FLOW_DIR"/. "$FLOW_OUT"/
else
    git ls-tree -r --name-only origin/feat/maestro-smoke \
        examples/flutter/.maestro/ | while read -r f; do
        mkdir -p "$FLOW_OUT/$(dirname "${f#examples/flutter/.maestro/}")"
        git show "origin/feat/maestro-smoke:$f" > "$FLOW_OUT/${f#examples/flutter/.maestro/}"
    done
    step "bootstrapped maestro flows from origin/feat/maestro-smoke"
fi

# --- run the layers ---------------------------------------------------------
run_layer() { # <name> <cmd...>
    local name="$1"; shift
    step "=== $name ==="
    "$@" > "$OUT_DIR/$name.log" 2>&1
    local rc=$?
    step "$name exit=$rc (log: $OUT_DIR/$name.log)"
    return $rc
}

# result.json written by a layer since the marker was touched
newest_result_since() {
    find "$HOME/testing/results" -mindepth 2 -maxdepth 2 \
        -name result.json -newer "$1" 2>/dev/null | sort | tail -1
}

touch "$OUT_DIR/.marker"
run_layer layer1 bash "$BIN_DIR/layer1_gate.sh" "$HEAD_REF" "$BASE_REF" "$THRESHOLD"
L1_JSON="$(newest_result_since "$OUT_DIR/.marker")"

touch "$OUT_DIR/.marker"
L2_SKIP=""
[ "$SKIP_BUILD" -eq 1 ] && L2_SKIP="--skip-build"
run_layer layer2 env NAPAXI_ROOT="$REPO" MAESTRO_FLOW_DIR="$FLOW_OUT" \
    bash "$BIN_DIR/layer2_maestro_smoke.sh" $L2_SKIP
L2_JSON="$(newest_result_since "$OUT_DIR/.marker")"

# --- aggregate --------------------------------------------------------------
SUMMARY="$(python3 - "$OUT_DIR/acceptance.json" "$L1_JSON" "$L2_JSON" <<'PY'
import json, os, sys

out_path, l1_path, l2_path = sys.argv[1:4]

def load(p):
    if p and os.path.exists(p):
        try:
            with open(p) as f:
                return json.load(f)
        except Exception:
            pass
    return {"verdict": "ERROR", "result_json": p or "not produced"}

l1, l2 = load(l1_path), load(l2_path)
v1, v2 = l1.get("verdict", "ERROR"), l2.get("verdict", "ERROR")
overall = "PASS" if v1 == "PASS" and v2 == "PASS" else "FAIL"
report = {
    "layer1": l1,
    "layer2": l2,
    "verdict": overall,
    "report": out_path,
}
with open(out_path, "w") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
print("ACCEPTANCE " + json.dumps(
    {"verdict": overall, "layer1": v1, "layer2": v2, "report": out_path},
    ensure_ascii=False))
PY
)"

step "report: $OUT_DIR/acceptance.json"
echo "$SUMMARY"
echo "$SUMMARY" | grep -q '"verdict": "PASS"'
