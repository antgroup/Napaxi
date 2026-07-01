#!/usr/bin/env python3
"""Detect hanging tests in examples/flutter/test/widget_test.dart.

Runs every top-level `test(...)` / `testWidgets(...)` declared in the file
ONE AT A TIME via `flutter test --plain-name '<name>'`, with a hard
per-test timeout enforced from Python (macOS has no `timeout` binary).

Parallelism: defaults to 2 workers — `flutter test` is heavy (each run
spawns its own dart compiler + isolate), so going higher tends to make
machines page and timeouts spike. Override with --jobs.

Per-test outcomes:
  PASS     — exited 0 within the timeout
  FAIL     — exited non-zero within the timeout (assertion / error)
  TIMEOUT  — still running when the timeout fired (likely a hang)
  ERROR    — script-side problem launching the process

Each run's full output goes to: <log-dir>/<slug>.log
A summary CSV is written to:    <log-dir>/_summary.csv

Usage (run from anywhere):
    python3 tools/scripts/check-flutter-test-hangs.py \
        [--timeout 30] [--jobs 2] [--filter substr] [--list]

Common one-liner from the flutter demo dir:
    python3 ../../tools/scripts/check-flutter-test-hangs.py --timeout 30
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
FLUTTER_DIR = Path(__file__).resolve().parents[1]
TEST_FILE_REL = "test/widget_test.dart"
DEFAULT_LOG_DIR = REPO_ROOT / ".tmp" / "flutter-test-hangs"

# Matches:  test('name', ...)   testWidgets('name', ...)
# Across newlines/whitespace between the opening paren and the string.
# Captures the (single-quoted) name in group 2. Escaped quotes inside the
# string are tolerated.
TEST_DECL_RE = re.compile(
    r"\b(testWidgets|test)\(\s*'((?:[^'\\]|\\.)*)'\s*,",
    re.S,
)


@dataclass
class TestCase:
    kind: str      # 'test' or 'testWidgets'
    name: str
    line: int


@dataclass
class Result:
    case: TestCase
    status: str          # PASS / FAIL / TIMEOUT / ERROR
    rc: int | None
    elapsed: float
    log_path: Path
    note: str = ""


def parse_tests(test_file: Path) -> list[TestCase]:
    src = test_file.read_text(encoding="utf-8")
    # build a line-offset index so we can report the source line for each match
    line_starts = [0]
    for i, ch in enumerate(src):
        if ch == "\n":
            line_starts.append(i + 1)

    def line_of(offset: int) -> int:
        # binary search
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    cases: list[TestCase] = []
    seen: set[str] = set()
    for m in TEST_DECL_RE.finditer(src):
        kind, name = m.group(1), m.group(2)
        if name in seen:
            # name collisions would break --plain-name targeting; refuse
            # rather than silently mis-attribute results
            print(
                f"FATAL: duplicate test name {name!r} — --plain-name is ambiguous.",
                file=sys.stderr,
            )
            sys.exit(2)
        seen.add(name)
        cases.append(TestCase(kind=kind, name=name, line=line_of(m.start())))
    return cases


def slugify(name: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("_")
    return s[:120] or "test"


def kill_process_group(proc: subprocess.Popen) -> None:
    """Kill the whole process group rooted at `proc`.

    `flutter test` spawns a dart compiler + isolate; signalling just `proc.pid`
    leaves the children alive and the script appears to hang. We start each
    run in its own group via start_new_session=True, so we can SIGKILL the
    entire group here.
    """
    if proc.poll() is not None:
        return
    try:
        pgid = os.getpgid(proc.pid)
    except ProcessLookupError:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        try:
            proc.wait(timeout=3)
            return
        except subprocess.TimeoutExpired:
            continue


def run_one(
    flutter: str,
    case: TestCase,
    timeout: float,
    log_dir: Path,
    no_pub: bool,
) -> Result:
    log_path = log_dir / f"{case.line:04d}_{slugify(case.name)}.log"
    cmd = [flutter, "test"]
    if no_pub:
        cmd.append("--no-pub")
    cmd += [
        "--reporter", "expanded",
        "--plain-name", case.name,
        TEST_FILE_REL,
    ]

    started = time.monotonic()
    with log_path.open("w", encoding="utf-8") as lf:
        lf.write(f"# CMD: {' '.join(cmd)}\n")
        lf.write(f"# cwd: {FLUTTER_DIR}\n")
        lf.write(f"# timeout: {timeout}s\n")
        lf.write(f"# started: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        lf.flush()
        try:
            proc = subprocess.Popen(
                cmd,
                cwd=FLUTTER_DIR,
                stdout=lf,
                stderr=subprocess.STDOUT,
                start_new_session=True,  # so we can kill the whole group
            )
        except FileNotFoundError as exc:
            return Result(case, "ERROR", None, 0.0, log_path, note=str(exc))

        try:
            rc = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            kill_process_group(proc)
            elapsed = time.monotonic() - started
            lf.write(f"\n# TIMEOUT after {elapsed:.1f}s — process group killed.\n")
            return Result(case, "TIMEOUT", None, elapsed, log_path)

    elapsed = time.monotonic() - started
    status = "PASS" if rc == 0 else "FAIL"
    return Result(case, status, rc, elapsed, log_path)


COLORS = {
    "PASS":    "\033[32m",  # green
    "FAIL":    "\033[31m",  # red
    "TIMEOUT": "\033[33m",  # yellow
    "ERROR":   "\033[35m",  # magenta
}
RESET = "\033[0m"


def color(status: str) -> str:
    if not sys.stdout.isatty():
        return ""
    return COLORS.get(status, "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--timeout", type=float, default=60.0,
                    help="per-test hard timeout in seconds (default: 60). "
                         "Use 30 to match the user's requested threshold.")
    ap.add_argument("--jobs", type=int, default=2,
                    help="parallel workers (default: 2). flutter test is heavy; "
                         "going above 4 on a laptop usually backfires.")
    ap.add_argument("--filter", default=None,
                    help="only run tests whose name contains this substring")
    ap.add_argument("--names-from", type=Path, default=None,
                    help="only run tests whose name appears (verbatim) on a line "
                         "of this file. Blank lines and lines starting with '#' "
                         "are ignored. Useful for rerunning prior TIMEOUT/FAIL "
                         "sets, e.g. tools/scripts/flutter-test-timeout.txt.")
    ap.add_argument("--list", action="store_true",
                    help="print the discovered test list and exit")
    ap.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR,
                    help=f"directory for per-test logs (default: {DEFAULT_LOG_DIR})")
    ap.add_argument("--with-pub", action="store_true",
                    help="pass without --no-pub (default uses --no-pub for speed; "
                         "first time you may need --with-pub if deps changed)")
    ap.add_argument("--flutter", default=shutil.which("flutter") or "flutter",
                    help="path to the flutter binary")
    args = ap.parse_args()

    test_file = FLUTTER_DIR / TEST_FILE_REL
    if not test_file.exists():
        print(f"FATAL: test file not found: {test_file}", file=sys.stderr)
        return 2
    if not Path(args.flutter).exists() and not shutil.which(args.flutter):
        print(f"FATAL: flutter not found at {args.flutter!r}", file=sys.stderr)
        return 2

    cases = parse_tests(test_file)
    if args.filter:
        cases = [c for c in cases if args.filter in c.name]
    if args.names_from:
        try:
            raw = args.names_from.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"FATAL: cannot read --names-from {args.names_from}: {exc}",
                  file=sys.stderr)
            return 2
        wanted = {
            line.strip()
            for line in raw.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        if not wanted:
            print(f"FATAL: --names-from {args.names_from} has no usable names",
                  file=sys.stderr)
            return 2
        by_name = {c.name: c for c in cases}
        missing = sorted(n for n in wanted if n not in by_name)
        if missing:
            print("WARNING: these names from --names-from did not match any test "
                  "(skipped):", file=sys.stderr)
            for n in missing:
                print(f"  - {n}", file=sys.stderr)
        cases = [by_name[n] for n in wanted if n in by_name]

    if args.list:
        for c in cases:
            print(f"{c.line:5d}  {c.kind:12s}  {c.name}")
        print(f"\n{len(cases)} test(s).")
        return 0

    args.log_dir.mkdir(parents=True, exist_ok=True)

    print(f"Discovered {len(cases)} test(s) in {test_file.relative_to(REPO_ROOT)}")
    print(f"Timeout: {args.timeout:g}s   Jobs: {args.jobs}   Logs: {args.log_dir}")
    print(f"flutter: {args.flutter}")
    print()

    results: list[Result] = []
    started_all = time.monotonic()

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {
            pool.submit(
                run_one,
                args.flutter,
                c,
                args.timeout,
                args.log_dir,
                not args.with_pub,
            ): c
            for c in cases
        }
        for i, fut in enumerate(as_completed(futures), 1):
            r = fut.result()
            results.append(r)
            col = color(r.status)
            print(
                f"[{i:3d}/{len(cases)}] {col}{r.status:7s}{RESET if col else ''} "
                f"{r.elapsed:6.1f}s  L{r.case.line:<5d} {r.case.name}"
            )

    total = time.monotonic() - started_all
    by_status: dict[str, list[Result]] = {}
    for r in results:
        by_status.setdefault(r.status, []).append(r)

    print()
    print("=" * 72)
    print(f"Done in {total:.1f}s.  ", end="")
    for s in ("PASS", "FAIL", "TIMEOUT", "ERROR"):
        n = len(by_status.get(s, []))
        if n:
            col = color(s)
            print(f"{col}{s}={n}{RESET if col else ''}  ", end="")
    print("\n")

    for s in ("TIMEOUT", "FAIL", "ERROR"):
        items = by_status.get(s, [])
        if not items:
            continue
        col = color(s)
        print(f"{col}{s}{RESET if col else ''} ({len(items)}):")
        for r in sorted(items, key=lambda r: r.case.line):
            print(f"  L{r.case.line:<5d} {r.case.name}")
            print(f"          log: {r.log_path}")
        print()

    # CSV summary for easy machine consumption
    summary = args.log_dir / "_summary.csv"
    with summary.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["line", "kind", "status", "rc", "elapsed_s", "name", "log"])
        for r in sorted(results, key=lambda r: r.case.line):
            w.writerow([
                r.case.line, r.case.kind, r.status,
                "" if r.rc is None else r.rc,
                f"{r.elapsed:.2f}",
                r.case.name, str(r.log_path),
            ])
    print(f"Summary CSV: {summary}")

    # exit non-zero if anything looks broken, so CI/wrappers can act on it
    return 0 if not (by_status.get("FAIL") or by_status.get("TIMEOUT") or by_status.get("ERROR")) else 1


if __name__ == "__main__":
    sys.exit(main())
