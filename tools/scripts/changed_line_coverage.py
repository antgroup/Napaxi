#!/usr/bin/env python3
"""Changed-line coverage gate.

Computes line coverage restricted to lines added/modified in the current
checkout relative to a base ref (default: merge-base of origin/main...HEAD),
using an lcov file produced by a test run (e.g. `flutter test --coverage` or
`cargo llvm-cov --lcov`).

Unlike tools/scripts/flutter-coverage-floor.sh (a whole-lib regression floor),
this gate answers the review question "are the lines THIS CHANGE adds/tests?".
It is scoped to a path prefix (default packages/flutter/lib) so one lcov file
can serve one gate.

Usage:
  changed_line_coverage.py --lcov <lcov.info> [--base <ref>] [--head <ref>]
      [--prefix <repo-relative-prefix>] [--threshold <pct>]
      [--report <out.md>] [--max-uncovered-listed <n>]

Exit code: 0 when changed-line coverage >= threshold (or when there are no
coverable changed lines — nothing to gate), 1 below threshold, 2 on usage /
environment errors.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def run_git(args: list[str]) -> str:
    proc = subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False
    )
    if proc.returncode != 0:
        raise SystemExit(
            f"[ERROR] git {' '.join(args)} failed:\n{proc.stderr.strip()}"
        )
    return proc.stdout


def changed_lines(base: str, head: str, prefix: str) -> dict[str, set[int]]:
    """Return {repo-relative path: set of added line numbers} under prefix."""
    merge_base = run_git(["merge-base", base, head]).strip()
    diff = run_git(
        ["diff", "--unified=0", f"{merge_base}..{head}", "--", prefix]
    )
    result: dict[str, set[int]] = {}
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[len("+++ b/"):]
        elif line.startswith("+++ "):  # /dev/null (deleted file)
            path = None
        elif line.startswith("@@") and path:
            m = HUNK_RE.match(line)
            if not m:
                continue
            start, count = int(m.group(1)), int(m.group(2) or "1")
            if count == 0:
                continue  # pure deletion hunk
            result.setdefault(path, set()).update(range(start, start + count))
    return result


def lcov_hits(lcov_path: str) -> dict[str, dict[int, int]]:
    """Return {normalized path: {line: hit count}} from an lcov file."""
    records: dict[str, dict[int, int]] = {}
    current = None
    with open(lcov_path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("SF:"):
                current = normalize_path(line[3:])
                records.setdefault(current, {})
            elif line.startswith("DA:") and current is not None:
                num, _, hits = line[3:].partition(",")
                records[current][int(num)] = int(float(hits or 0))
            elif line == "end_of_record":
                current = None
    return records


def normalize_path(p: str) -> str:
    """Map an lcov SF path to a repo-relative path when recognizable."""
    p = p.replace(os.sep, "/")
    for marker in ("packages/flutter/", "packages/ios/", "crates/"):
        idx = p.find(marker)
        if idx != -1:
            return p[idx:]
    return p.lstrip("/")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lcov", required=True)
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--prefix", default="packages/flutter/lib")
    ap.add_argument("--threshold", type=float, default=80.0)
    ap.add_argument("--report", default="")
    ap.add_argument("--max-uncovered-listed", type=int, default=50)
    args = ap.parse_args()

    if not os.path.isfile(args.lcov):
        print(f"[ERROR] lcov file not found: {args.lcov}", file=sys.stderr)
        return 2

    changes = changed_lines(args.base, args.head, args.prefix)
    coverage = lcov_hits(args.lcov)

    total = covered = 0
    uncovered: list[tuple[str, int]] = []
    for path, lines in sorted(changes.items()):
        hits = coverage.get(path, {})
        for ln in sorted(lines):
            if ln not in hits:
                continue  # non-executable line (comment, brace, blank)
            total += 1
            if hits[ln] > 0:
                covered += 1
            else:
                uncovered.append((path, ln))

    pct = 100.0 * covered / total if total else 100.0
    status = "PASS" if pct >= args.threshold else "FAIL"
    summary = (
        f"changed-line coverage: {pct:.1f}% ({covered}/{total} coverable "
        f"lines) under {args.prefix} vs {args.base} — threshold "
        f"{args.threshold:.0f}% → {status}"
    )
    print(f"[{'INFO' if status == 'PASS' else 'ERROR'}] {summary}")

    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(f"# Changed-line coverage\n\n{summary}\n\n")
            if uncovered:
                fh.write("## Uncovered changed lines\n\n")
                for path, ln in uncovered[: args.max_uncovered_listed]:
                    fh.write(f"- `{path}:{ln}`\n")
                if len(uncovered) > args.max_uncovered_listed:
                    fh.write(
                        f"\n… and {len(uncovered) - args.max_uncovered_listed} more\n"
                    )
        print(f"[INFO] report written: {args.report}")

    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
