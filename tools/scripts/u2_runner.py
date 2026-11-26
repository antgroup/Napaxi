#!/usr/bin/env python3
"""Declarative device-test runner on top of uiautomator2.

Replaces the hardcoded u2_smoke.py with a cases/<suite>/<id>.yaml driven
executor. Top-level does NOT import uiautomator2 — the import is deferred to
connect() so that --help / --list-cases / py_compile work without the u2 venv.

Usage:
    u2_runner.py --serial <serial> --suite L0|L1|all [--cases id,id,...]
                 [--run-id <str>] [--out-dir <dir>] [--keys-yaml <path>]
                 [--cases-dir <dir>] [--quarantine <path>] [--list-cases]

Reuses u2_smoke.py's connect / launch (app_stop+app_start, 60s foreground
guard with am-start fallback at +10s) / set_text three-tier fallback /
KEYCODE_ESCAPE keyboard-hide. Adds: declarative case loading, per-case
timeout + failure_class + screenshot-on-fail + per-case JSON + summary.json.
"""
import argparse
import glob
import json
import os
import re
import signal
import sys
import time
import traceback

PKG = "com.napa.app.test"

# --- keys.yaml resolution -------------------------------------------------

def _repo_root():
    """The napaxi repo root (parent of tools/)."""
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def default_keys_yaml():
    """Search order (plan 裁断 1):
    1. tests/device/keys.yaml            (future canonical, reserved)
    2. examples/flutter/tests/device/keys.yaml  (PR#150 landed here)
    First hit wins; returns None if neither exists."""
    root = _repo_root()
    for cand in (
        os.path.join(root, "tests", "device", "keys.yaml"),
        os.path.join(root, "examples", "flutter", "tests", "device", "keys.yaml"),
    ):
        if os.path.isfile(cand):
            return cand
    return None


def default_cases_dir():
    return os.path.join(_repo_root(), "tests", "device", "cases")


def default_quarantine():
    return os.path.join(_repo_root(), "tests", "device", "quarantine.yaml")


# --- loaders ---------------------------------------------------------------

def load_keys(keys_path):
    """Parse keys.yaml -> {logical_name: dk}. Returns {} if path is None."""
    if not keys_path:
        return {}
    try:
        import yaml
    except ImportError as e:
        raise SystemExit("PyYAML required: %s" % e)
    with open(keys_path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    out = {}
    for entry in data.get("keys", []) or []:
        name = entry.get("logical_name")
        dk = entry.get("dk")
        if name and dk:
            out[name] = dk
    return out


def load_quarantine(path):
    """Parse quarantine.yaml -> set of case ids. Returns set() if missing/empty.

    Supports both layouts:
      - quarantined: [<id>, ...]   (canonical, per plan 交付物 3)
      - - <id>                      (legacy bare-list)
    """
    if not path or not os.path.isfile(path):
        return set()
    try:
        import yaml
    except ImportError as e:
        raise SystemExit("PyYAML required: %s" % e)
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if data is None:
        return set()
    if isinstance(data, dict):
        items = data.get("quarantined", []) or []
    elif isinstance(data, list):
        items = data
    else:
        items = []
    return {str(x) for x in items}


def load_cases(cases_dir, suite, ids=None):
    """Walk cases/<suite>/*.yaml (or all suites when suite=='all') and return
    a list of case dicts ordered by suite then id. If ids is given (a set),
    filter to those ids only."""
    suites = ["L0", "L1"] if suite == "all" else [suite]
    cases = []
    for s in suites:
        pat = os.path.join(cases_dir, s, "*.yaml")
        for path in sorted(glob.glob(pat)):
            try:
                import yaml
            except ImportError as e:
                raise SystemExit("PyYAML required: %s" % e)
            with open(path, "r", encoding="utf-8") as fh:
                c = yaml.safe_load(fh) or {}
            if not c.get("id"):
                continue
            c.setdefault("suite", s)
            c["_path"] = path
            cases.append(c)
    if ids:
        ids = {str(x) for x in ids}
        cases = [c for c in cases if str(c["id"]) in ids]
    return cases


# --- selector resolution ----------------------------------------------------

def _interp(s, run_id):
    if isinstance(s, str):
        return s.replace("{RUN_ID}", run_id)
    if isinstance(s, (list, tuple)):
        return [_interp(x, run_id) for x in s]
    return s


def resolve_selector(selector, keys, run_id):
    """Resolve a case selector dict to a u2 Selector/UiObject.

    Priority (plan §1):
      1. key:           -> lookup keys[key] -> d(description=dk) ; on miss, KeyError (case error)
      2. text|description (string or bilingual array) -> try d(text|description=v) per variant
         per kw, then xpath //*[@hint=v] (ports u2_smoke._sel L25-38)
      3. xpath:         -> d.xpath(...)

    Returns the bound element (calling .wait(timeout) is the caller's job) and
    a small spec string for error messages.
    """
    # selector is a dict like {"key": "..."} / {"text": ["a","b"]} / {"xpath": "..."}
    if not isinstance(selector, dict):
        raise CaseError("selector must be a dict, got %r" % type(selector).__name__)

    if "key" in selector and selector["key"]:
        name = selector["key"]
        if name not in keys:
            raise CaseError("unknown key %r (not in keys.yaml)" % name)
        dk = keys[name]
        return ({"kind": "description_prefix", "value": dk},
                "key=%s->descriptionMatches=^%s(\\n.*)?$" % (name, dk))

    if "textContains" in selector and selector["textContains"] is not None:
        v = _interp(selector["textContains"], run_id)
        return {"kind": "textContains", "value": v}, "textContains=%r" % v

    if "descriptionContains" in selector and selector["descriptionContains"] is not None:
        v = _interp(selector["descriptionContains"], run_id)
        return {"kind": "descriptionContains", "value": v}, "descriptionContains=%r" % v

    if "text" in selector or "description" in selector:
        variants = []
        for kw in ("text", "description"):
            v = selector.get(kw)
            if v is None:
                continue
            if isinstance(v, str):
                variants.append((kw, v))
            elif isinstance(v, (list, tuple)):
                for item in v:
                    variants.append((kw, item))
        variants = [(kw, _interp(val, run_id)) for kw, val in variants]
        return {"kind": "text_or_desc", "variants": variants}, "text/desc=%r" % variants

    if "xpath" in selector and selector["xpath"]:
        xq = _interp(selector["xpath"], run_id)
        return {"kind": "xpath", "value": xq}, "xpath=%s" % xq

    raise CaseError("selector must define key | text | description | "
                    "textContains | descriptionContains | xpath")


# --- error types -----------------------------------------------------------

class CaseError(Exception):
    """A YAML/selector/case-definition problem. failure_class=case."""


class ProductError(Exception):
    """An assertion or element-not-found against the running UI. failure_class=product."""


class EnvError(Exception):
    """Connection / foreground-guard / per-case timeout / device-level. failure_class=env."""


# --- step primitives -------------------------------------------------------

def _xpath_literal(s):
    """Quote `s` as an XPath 1.0 string literal (no escaping exists, so pick
    a delimiter that does not appear, else concat the parts)."""
    if '"' not in s:
        return '"%s"' % s
    if "'" not in s:
        return "'%s'" % s
    return "concat(%s)" % ", '\"', ".join('"%s"' % p for p in s.split('"'))


def _bind(d, spec, timeout):
    """Translate a resolve_selector() result into a waited UiObject, or None."""
    kind = spec["kind"]
    if kind == "description":
        el = d(description=spec["value"])
        if el.wait(timeout=timeout):
            return el
        return None
    if kind == "description_prefix":
        # `dk.<key>` lands in two different places depending on the widget:
        #   * plain Semantics widgets -> content-desc `dk.<key>\n<label>`
        #   * Flutter text fields      -> the `hint` attribute (content-desc
        #     empty), e.g. hint=`dk.chat.composer\n给 napaxi 发消息`
        # u2's Selector has no `hint` kw, so xpath is the escape hatch (same
        # trick as text_or_desc below). Probe every candidate inside one
        # deadline, so a miss costs a single timeout instead of one per probe.
        dk = spec["value"]
        pat = r"^%s(\n.*)?$" % re.escape(dk)
        hint_q = "//*[starts-with(@hint, %s)]" % _xpath_literal(dk)
        desc_q = "//*[starts-with(@content-desc, %s)]" % _xpath_literal(dk)
        deadline = time.time() + timeout
        while True:
            for probe in (
                lambda: d(descriptionMatches=pat),
                lambda: d(descriptionContains=dk),
                lambda: d(description=dk),
                lambda: d.xpath(hint_q),
                lambda: d.xpath(desc_q),
            ):
                try:
                    el = probe()
                    if el.exists:
                        return el
                except Exception:  # noqa: BLE001 — unsupported kw/selector, next probe
                    continue
            if time.time() >= deadline:
                return None
            time.sleep(0.3)
    if kind == "textContains":
        el = d(textContains=spec["value"])
        return el if el.wait(timeout=timeout) else None
    if kind == "descriptionContains":
        el = d(descriptionContains=spec["value"])
        return el if el.wait(timeout=timeout) else None
    if kind == "text_or_desc":
        deadline = time.time() + timeout
        while time.time() < deadline:
            for kw, val in spec["variants"]:
                el = d(**{kw: val})
                if el.exists:
                    return el
                # Flutter TextField hints land in `hint`, which u2 Selector
                # rejects; xpath is the supported escape hatch (u2_smoke L35).
                x = d.xpath("//*[@hint=%s]" % _xpath_literal(val))
                if x.exists:
                    return x
            time.sleep(0.5)
        return None
    if kind == "xpath":
        x = d.xpath(spec["value"])
        try:
            if x.wait(timeout):
                return x
        except AttributeError:
            # older u2 xpath objects: poll manually
            deadline = time.time() + timeout
            while time.time() < deadline:
                if x.exists:
                    return x
                time.sleep(0.5)
        return None
    return None


def _screenshot(d, out_dir, case_id):
    path = os.path.join(out_dir, "cases", "%s.png" % case_id)
    try:
        d.screenshot(path)
        return os.path.relpath(path, out_dir)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write("screenshot failed: %s: %s\n" % (type(e).__name__, e))
        return None


def _dump_hierarchy(d, out_dir, case_id):
    path = os.path.join(out_dir, "cases", "%s.hierarchy.xml" % case_id)
    try:
        xml = d.dump_hierarchy()
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(xml)
        return os.path.relpath(path, out_dir)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write("dump_hierarchy failed: %s: %s\n" % (type(e).__name__, e))
        return None


def step_launch(d, step, ctx):
    """app_stop + app_start + 60s foreground guard with am-start fallback at +10s.
    Ports u2_smoke.py L82-107. No clearState (red line)."""
    pkg = step.get("pkg") or PKG
    timeout = step.get("timeout", 60)
    print("  [launch] app_stop+app_start %s" % pkg, flush=True)
    d.app_stop(pkg)
    d.app_start(pkg, wait=True)
    deadline = time.time() + timeout
    am_fired = False
    t_start = time.time()
    cur = None
    while time.time() < deadline:
        cur = (d.app_current() or {}).get("package")
        if cur == pkg:
            break
        if not am_fired and (time.time() - t_start) > 10:
            out = d.shell("cmd package resolve-activity --brief " + pkg).output
            act = out.strip().splitlines()[-1].strip()
            print("  [launch] am start fallback:", act, flush=True)
            d.shell("am start -n " + act)
            am_fired = True
        time.sleep(1)
    if cur != pkg:
        raise EnvError("app not in foreground after %ss, current=%r" % (timeout, cur))
    print("  [launch] foreground=%s" % cur, flush=True)


def _require_or_skip(d, sel_spec, label, sel_desc, timeout, optional=False):
    """Bind via _bind and either return the element or skip / raise.

    optional=True and element not found within timeout → log a skip line and
    return None (caller must check for None and treat as no-op). optional=False
    (default) preserves the old ProductError behavior.
    """
    el = _bind(d, sel_spec, timeout)
    if el is None:
        if optional:
            print("  [%s] optional step skipped (not found within %ss)"
                   % (label, timeout), flush=True)
            return None
        raise ProductError("%s selector(%s) not found within %ss"
                           % (label, sel_desc, timeout))
    return el


def step_tap(d, step, ctx):
    optional = step.get("optional", False)
    sel = step.get("selector") or {}
    timeout = step.get("timeout", 15)
    spec, desc = resolve_selector(sel, ctx["keys"], ctx["run_id"])
    el = _require_or_skip(d, spec, "tap", desc, timeout, optional=optional)
    if el is None:
        return  # optional skip — no click
    el.click()


def step_set_text(d, step, ctx):
    optional = step.get("optional", False)
    sel = step.get("selector") or {}
    timeout = step.get("timeout", 15)
    text = _interp(step.get("text", ""), ctx["run_id"])
    spec, desc = resolve_selector(sel, ctx["keys"], ctx["run_id"])
    el = _require_or_skip(d, spec, "set_text", desc, timeout, optional=optional)
    if el is None:
        return  # optional skip — no text typed
    # Three-tier fallback from u2_smoke.py L140-155:
    # 1. if el has set_text, try focused.set_text; 2. xpath //EditText; 3. d.send_keys
    typed = False
    try:
        el.click()
    except Exception:  # noqa: BLE001
        pass
    d.sleep(0.8)
    try:
        focused = d(focused=True)
        if focused.wait(timeout=3):
            try:
                focused.set_text(text)
                typed = True
            except Exception as e:  # noqa: BLE001
                print("  [set_text] focused.set_text failed: %s" % e, flush=True)
    except Exception:  # noqa: BLE001
        pass
    if not typed:
        try:
            d.xpath("//android.widget.EditText").set_text(text)
            typed = True
        except Exception as e:  # noqa: BLE001
            print("  [set_text] xpath EditText set_text failed: %s" % e, flush=True)
    if not typed:
        d.send_keys(text)


def step_assert_visible(d, step, ctx):
    optional = step.get("optional", False)
    sel = step.get("selector") or {}
    timeout = step.get("timeout", 30)
    spec, desc = resolve_selector(sel, ctx["keys"], ctx["run_id"])
    if optional:
        # optional visible-not-found = skip (not a product fail)
        el = _bind(d, spec, timeout)
        if el is None:
            print("  [assert_visible] optional step skipped (not found within %ss)"
                   % timeout, flush=True)
            return
        return
    el = _bind(d, spec, timeout)
    if el is None:
        raise ProductError("assert_visible selector(%s) not found within %ss" % (desc, timeout))


def step_assert_absent(d, step, ctx):
    # optional has no direction meaning on assert_absent (still see-is-fail);
    # 4 cases never use optional on absent; preserve old raise semantics.
    sel = step.get("selector") or {}
    timeout = step.get("timeout", 10)
    spec, desc = resolve_selector(sel, ctx["keys"], ctx["run_id"])
    deadline = time.time() + timeout
    while time.time() < deadline:
        if _bind(d, spec, 0.5) is not None:
            raise ProductError("assert_absent selector(%s) still present within %ss" % (desc, timeout))
        time.sleep(0.3)
    return


def step_wait(d, step, ctx):
    optional = step.get("optional", False)
    sel = step.get("selector") or {}
    timeout = step.get("timeout", 30)
    if not sel:
        time.sleep(timeout)
        return
    spec, desc = resolve_selector(sel, ctx["keys"], ctx["run_id"])
    el = _bind(d, spec, timeout)
    if optional and el is None:
        print("  [wait] optional step skipped (not found within %ss)" % timeout, flush=True)
        return
    # even non-optional wait is not an assertion; swallow not-found (old behavior)
    return


def step_back(d, step, ctx):
    d.press("back")


def step_press_key(d, step, ctx):
    keycode = step.get("keycode", 111)
    d.shell("input keyevent %s" % keycode)


def step_screenshot(d, step, ctx):
    name = step.get("name")
    label = name if name else ctx["current_step_label"]
    path = os.path.join(ctx["out_dir"], "cases", "%s.%s.png" % (ctx["case_id"], label))
    try:
        d.screenshot(path)
    except Exception as e:  # noqa: BLE001
        print("  [screenshot] failed: %s" % e, flush=True)


STEP_TABLE = {
    "launch": step_launch,
    "tap": step_tap,
    "set_text": step_set_text,
    "assert_visible": step_assert_visible,
    "assert_absent": step_assert_absent,
    "wait": step_wait,
    "back": step_back,
    "press_key": step_press_key,
    "screenshot": step_screenshot,
}


# --- per-case runner -------------------------------------------------------

def _format_step_label(step):
    for k in ("launch", "tap", "set_text", "assert_visible", "assert_absent",
              "wait", "back", "press_key", "screenshot"):
        if k in step:
            return k
    return "?"


def run_case(case, d, keys, run_id, out_dir, per_case_timeout_override=None):
    case_id = str(case["id"])
    suite = case.get("suite", "?")
    title = case.get("title", "")
    timeout = per_case_timeout_override or case.get("timeout", 240)
    cases_dir = os.path.join(out_dir, "cases")
    os.makedirs(cases_dir, exist_ok=True)
    ctx = {
        "case_id": case_id,
        "keys": keys,
        "run_id": run_id,
        "out_dir": out_dir,
        "current_step_label": "?",
    }
    print("== case %s [%s] %s timeout=%ss" % (case_id, suite, title, timeout), flush=True)
    rec = {
        "id": case_id,
        "suite": suite,
        "title": title,
        "verdict": "running",
        "duration": 0.0,
        "error": None,
        "failure_class": None,
        "quarantined": False,
        "screenshot": None,
        "hierarchy": None,
    }
    started = time.time()

    def _timeout_handler(signum, frame):
        raise EnvError("case timeout after %ss" % timeout)

    use_sigalrm = hasattr(signal, "SIGALRM") and os.name != "nt"
    if use_sigalrm:
        old = signal.signal(signal.SIGALRM, _timeout_handler)
        signal.setitimer(signal.ITIMER_REAL, timeout)
    try:
        steps = case.get("steps") or []
        if not isinstance(steps, list):
            raise CaseError("steps must be a list")
        for i, step in enumerate(steps, start=1):
            if not isinstance(step, dict):
                raise CaseError("step #%d must be a dict" % i)
            label = _format_step_label(step)
            if label == "?":
                raise CaseError("step #%d has no known action: %r" % (i, list(step.keys())))
            ctx["current_step_label"] = "%02d_%s" % (i, label)
            fn = STEP_TABLE[label]
            print("  [%s] %s" % (ctx["current_step_label"], label), flush=True)
            try:
                fn(d, step.get(label) or {}, ctx)
            except (ProductError, CaseError, EnvError):
                raise
            except Exception as e:  # noqa: BLE001
                # Unexpected python/usb error -> env
                raise EnvError("step %s raised %s: %s" % (label, type(e).__name__, e))
        rec["verdict"] = "passed"
    except ProductError as e:
        rec["verdict"] = "failed"
        rec["failure_class"] = "product"
        rec["error"] = str(e)
        rec["screenshot"] = _screenshot(d, out_dir, case_id)
        rec["hierarchy"] = _dump_hierarchy(d, out_dir, case_id)
    except CaseError as e:
        rec["verdict"] = "failed"
        rec["failure_class"] = "case"
        rec["error"] = str(e)
        rec["screenshot"] = _screenshot(d, out_dir, case_id)
    except EnvError as e:
        rec["verdict"] = "failed"
        rec["failure_class"] = "env"
        rec["error"] = str(e)
        rec["screenshot"] = _screenshot(d, out_dir, case_id)
    except Exception as e:  # noqa: BLE001
        rec["verdict"] = "failed"
        rec["failure_class"] = "env"
        rec["error"] = "%s: %s" % (type(e).__name__, e)
        rec["screenshot"] = _screenshot(d, out_dir, case_id)
    finally:
        if use_sigalrm:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old)
    rec["duration"] = round(time.time() - started, 3)
    per_case_path = os.path.join(cases_dir, "%s.json" % case_id)
    with open(per_case_path, "w", encoding="utf-8") as fh:
        json.dump(rec, fh, ensure_ascii=False, indent=2)
    print("  -> %s (%.2fs, %s)" % (rec["verdict"], rec["duration"], rec["failure_class"]), flush=True)
    return rec


# --- connect (deferred u2 import) ------------------------------------------

def connect(serial):
    import uiautomator2 as u2
    print("u2 connect(%s) ..." % serial, flush=True)
    d = u2.connect(serial)
    print("connected:", d.serial, flush=True)
    return d


# --- main ------------------------------------------------------------------

def _default_run_id():
    full = os.environ.get("DEVPOOL_JOB_ID") or "local"
    return full[-8:] if len(full) >= 8 else full


def _screens_runtime_id():
    return os.environ.get("DEVPOOL_JOB_ID", "local")


def _short_run_id(run_id):
    return run_id[-8:] if len(run_id) >= 8 else run_id


def build_parser():
    p = argparse.ArgumentParser(
        prog="u2_runner.py",
        description="Declarative uiautomator2 device-test executor.",
    )
    p.add_argument("--serial", required=True,
                   help="device serial (passed to u2.connect)")
    p.add_argument("--suite", choices=["L0", "L1", "all"], default="L0",
                   help="which suite to run; L0 by default")
    p.add_argument("--cases", default=None,
                   help="explicit comma-separated case ids; mutually exclusive with --suite "
                        "in that it overrides the suite scope")
    p.add_argument("--run-id", default=None,
                   help="run id (defaults to last-8 of DEVPOOL_JOB_ID or 'local')")
    p.add_argument("--out-dir", default=None,
                   help="output dir (defaults to DEVPOOL_RESULT_DIR or '.')")
    p.add_argument("--keys-yaml", default=None,
                   help="keys.yaml path (default: search tests/device then examples/flutter/tests/device)")
    p.add_argument("--cases-dir", default=None,
                   help="cases root (default: <repo>/tests/device/cases)")
    p.add_argument("--quarantine", default=None,
                   help="quarantine.yaml path (default: <repo>/tests/device/quarantine.yaml)")
    p.add_argument("--list-cases", action="store_true",
                   help="dry mode: do not connect to device; print JSON "
                        "{case_ids, quarantined, suite} and exit 0")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    run_id = args.run_id or _short_run_id(_screens_runtime_id())
    out_dir = args.out_dir or os.environ.get("DEVPOOL_RESULT_DIR", ".")
    out_dir = os.path.abspath(out_dir)
    cases_dir = args.cases_dir or default_cases_dir()
    keys_yaml = args.keys_yaml or default_keys_yaml()

    if not os.path.isdir(cases_dir):
        sys.stderr.write("cases dir missing: %s\n" % cases_dir)
        if args.list_cases:
            print(json.dumps({"case_ids": [], "quarantined": [],
                              "suite": args.suite, "error": "cases dir missing"}))
            return 0
        return 2

    keys = load_keys(keys_yaml)
    quarantine = load_quarantine(args.quarantine or default_quarantine())

    if args.cases:
        id_list = [s.strip() for s in args.cases.split(",") if s.strip()]
        all_cases = load_cases(cases_dir, "all", ids=set(id_list))
    else:
        all_cases = load_cases(cases_dir, args.suite)

    case_ids = [str(c["id"]) for c in all_cases]
    quarantined_in_suite = sorted([i for i in case_ids if i in quarantine])

    if args.list_cases:
        print(json.dumps({
            "case_ids": case_ids,
            "quarantined": quarantined_in_suite,
            "suite": args.suite,
            "cases_dir": cases_dir,
            "keys_yaml": keys_yaml,
        }, ensure_ascii=False))
        return 0

    if not all_cases:
        sys.stderr.write("no cases resolved for suite=%s ids=%s in %s\n"
                         % (args.suite, args.cases, cases_dir))
        return 2

    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(os.path.join(out_dir, "cases"), exist_ok=True)

    d = connect(args.serial)
    records = []
    for c in all_cases:
        cid = str(c["id"])
        if cid in quarantine:
            print("== case %s [%s] QUARANTINED (skipped)" % (cid, c.get("suite", "?")), flush=True)
            rec = {
                "id": cid,
                "suite": c.get("suite", "?"),
                "title": c.get("title", ""),
                "verdict": "skipped",
                "duration": 0.0,
                "error": None,
                "failure_class": None,
                "quarantined": True,
                "screenshot": None,
                "hierarchy": None,
            }
            with open(os.path.join(out_dir, "cases", "%s.json" % cid), "w",
                      encoding="utf-8") as fh:
                json.dump(rec, fh, ensure_ascii=False, indent=2)
            records.append(rec)
            continue
        rec = run_case(c, d, keys, run_id, out_dir)
        records.append(rec)

    passed = sum(1 for r in records if r["verdict"] == "passed")
    failed = sum(1 for r in records if r["verdict"] == "failed")
    quarantined = sum(1 for r in records if r["quarantined"])
    if failed > 0:
        verdict = "failed"
        exit_code = 1
    elif passed == 0 and quarantined == len(records):
        verdict = "blocked"
        exit_code = 1
    else:
        verdict = "passed"
        exit_code = 0

    summary = {
        "run_id": run_id,
        "suite": args.suite,
        "cases": records,
        "verdict": verdict,
        "exit_code": exit_code,
        "keys_yaml": keys_yaml,
        "cases_dir": cases_dir,
    }
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=2)
    print("SUMMARY " + json.dumps({
        "run_id": run_id,
        "suite": args.suite,
        "verdict": verdict,
        "exit_code": exit_code,
        "passed": passed,
        "failed": failed,
        "quarantined": quarantined,
        "cases": case_ids,
    }, ensure_ascii=False), flush=True)
    return exit_code


if __name__ == "__main__":
    try:
        rc = main()
        raise SystemExit(rc)
    except SystemExit:
        raise
    except Exception:  # noqa: BLE001
        traceback.print_exc()
        raise SystemExit(1)
