#!/bin/bash
# layer1_gate.sh [head-ref] [base-ref] [threshold]
# 层①门禁：flutter analyze + flutter test --coverage + 全仓地板 + 变更行覆盖率
# 输出：$HOME/testing/results/<ts>/ 下的日志、报告与 result.json
set -uo pipefail
HEAD_REF="${1:-origin/main}"
BASE_REF="${2:-origin/main}"
THRESHOLD="${3:-80}"
REPO="$HOME/repos/Napaxi"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$HOME/testing/results/$TS"
mkdir -p "$OUT"
cd "$REPO" || exit 2

echo "== fetch & checkout $HEAD_REF ==" | tee "$OUT/run.log"
git fetch origin >>"$OUT/run.log" 2>&1
git checkout -q "$HEAD_REF" >>"$OUT/run.log" 2>&1 || { echo "checkout failed"; exit 2; }

# 门禁脚本：优先用仓库里的，没有则从 PR 分支取
GATE="$HOME/testing/changed_line_coverage.py"
if [ -f tools/scripts/changed_line_coverage.py ]; then
  GATE="tools/scripts/changed_line_coverage.py"
elif git show origin/feat/changed-line-coverage-gate:tools/scripts/changed_line_coverage.py > "$GATE" 2>/dev/null; then
  echo "gate script from PR branch" >> "$OUT/run.log"
fi

echo "== flutter analyze ==" | tee -a "$OUT/run.log"
cd packages/flutter
flutter pub get >>"$OUT/run.log" 2>&1
flutter analyze --no-fatal-infos > "$OUT/analyze.log" 2>&1
ANALYZE_EXIT=$?
echo "analyze exit=$ANALYZE_EXIT" | tee -a "$OUT/run.log"

echo "== flutter test --coverage ==" | tee -a "$OUT/run.log"
flutter test --coverage > "$OUT/flutter-test.log" 2>&1
TEST_EXIT=$?
echo "test exit=$TEST_EXIT" | tee -a "$OUT/run.log"
cd "$REPO"

echo "== floors ==" | tee -a "$OUT/run.log"
./tools/scripts/flutter-coverage-floor.sh packages/flutter/coverage/lcov.info > "$OUT/floor.log" 2>&1
FLOOR_EXIT=$?
echo "floor exit=$FLOOR_EXIT" | tee -a "$OUT/run.log"

echo "== changed-line gate (base=$BASE_REF threshold=$THRESHOLD) ==" | tee -a "$OUT/run.log"
python3 "$GATE" --lcov packages/flutter/coverage/lcov.info --base "$BASE_REF" \
  --threshold "$THRESHOLD" --report "$OUT/changed-lines.md" > "$OUT/changed.log" 2>&1
GATE_EXIT=$?
echo "gate exit=$GATE_EXIT" | tee -a "$OUT/run.log"

VERDICT=PASS
[ $ANALYZE_EXIT -ne 0 ] || [ $TEST_EXIT -ne 0 ] || [ $FLOOR_EXIT -ne 0 ] || [ $GATE_EXIT -ne 0 ] && VERDICT=FAIL
cat > "$OUT/result.json" <<JSON
{"verdict":"$VERDICT","head":"$HEAD_REF","base":"$BASE_REF","threshold":$THRESHOLD,
 "analyze_exit":$ANALYZE_EXIT,"test_exit":$TEST_EXIT,"floor_exit":$FLOOR_EXIT,"gate_exit":$GATE_EXIT,
 "out":"$OUT"}
JSON
echo "== VERDICT: $VERDICT ==" | tee -a "$OUT/run.log"
cat "$OUT/result.json"
