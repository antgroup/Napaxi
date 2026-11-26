#!/usr/bin/env python3
"""Standalone, dependency-free self-check for u2_runner.py.

Does NOT import uiautomator2 (u2 import is deferred to connect() in u2_runner,
and resolve_selector no longer imports u2 at function scope after the fix).
Imports u2_runner's pure functions directly, monkeypatches `_bind` with a fake
so no device is needed, and asserts:
  1. `key:` selector resolves to `description_prefix`, regex matches the actual
     `dk.<key>\n<label>` content-desc format.
  2. `textContains` / `descriptionContains` branches resolve to the right kind.
  3. `_require_or_skip` with optional=True + element not found returns None and
     does NOT raise ProductError.

Prints SELF_CHECK_OK on success; exits 1 on any failure.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import u2_runner as u  # noqa: E402


def _assert(cond, msg):
    if not cond:
        print("SELF_CHECK_FAIL: %s" % msg, file=sys.stderr)
        sys.exit(1)


def main():
    keys = {"chat_engine_entry": "dk.chat.engineEntry"}

    # (1) key -> description_prefix, regex matches `dk(<dk>\n<label>`.
    spec, desc = u.resolve_selector({"key": "chat_engine_entry"}, keys, "x")
    _assert(spec.get("kind") == "description_prefix",
            "key should resolve to description_prefix, got %r" % spec)
    _assert(spec.get("value") == "dk.chat.engineEntry",
            "description_prefix value should be the dk string, got %r" % spec)
    pat = r"^%s(\n.*)?$" % re.escape(spec["value"])
    _assert(re.match(pat, "dk.chat.engineEntry\nNapaxi") is not None,
            "regex %r should match 'dk.chat.engineEntry\\nNapaxi'" % pat)
    _assert("descriptionMatches" in desc,
            "spec desc should mention descriptionMatches, got %r" % desc)

    # (2) textContains / descriptionContains resolution.
    sc, _ = u.resolve_selector({"textContains": "Codex"}, {}, "x")
    _assert(sc.get("kind") == "textContains",
            "textContains should resolve to kind=textContains, got %r" % sc)
    _assert(sc.get("value") == "Codex",
            "textContains value should be Codex, got %r" % sc)
    dc, _ = u.resolve_selector({"descriptionContains": "dk.engine.popup.item.codex"}, {}, "x")
    _assert(dc.get("kind") == "descriptionContains",
            "descriptionContains should resolve to kind=descriptionContains, got %r" % dc)
    _assert(dc.get("value") == "dk.engine.popup.item.codex",
            "descriptionContains value should be preserved, got %r" % dc)

    # (2b) `_bind` for a key must also resolve when the dk lives in the `hint`
    # attribute (Flutter text fields) instead of content-desc.
    class _Missing:
        exists = False

        def wait(self, timeout=0):
            return False

    class _Found:
        exists = True

        def wait(self, timeout=0):
            return True

    class HintOnlyD:
        def __call__(self, **kwargs):
            return _Missing()

        def xpath(self, q):
            return _Found() if "hint" in q else _Missing()

    el = u._bind(HintOnlyD(), {"kind": "description_prefix",
                               "value": "dk.chat.composer"}, 0.5)
    _assert(el is not None,
            "description_prefix should fall back to //*[@hint=...] when the dk "
            "is a Flutter hint (composer case)")

    # (3) optional skip: _require_or_skip with optional=True, no element found,
    # must return None and not raise.
    class _NoEl:
        def wait(self, timeout=0):
            return False

        exists = False

    class FakeD:
        def __call__(self, **kwargs):
            return _NoEl()

    # Monkeypatch _bind to always return None (element not found).
    orig_bind = u._bind
    u._bind = lambda d, spec, timeout: None
    try:
        try:
            r = u._require_or_skip(FakeD(), {"kind": "textContains", "value": "x"},
                                   "tap", "x", 0.1, optional=True)
        except Exception as e:  # noqa: BLE001
            _assert(False, "optional=True should not raise, got %s: %s"
                    % (type(e).__name__, e))
        _assert(r is None, "optional=True with no element should return None, got %r" % r)

        # Non-optional _require_or_skip should raise ProductError.
        try:
            u._require_or_skip(FakeD(), {"kind": "textContains", "value": "x"},
                               "tap", "x", 0.1, optional=False)
            _assert(False, "optional=False with no element should raise ProductError")
        except u.ProductError:
            pass  # expected
    finally:
        u._bind = orig_bind

    print("SELF_CHECK_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
