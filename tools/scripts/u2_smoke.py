#!/usr/bin/env python3
"""u2 equivalent of examples/flutter/.maestro/smoke_chat_launch.yaml.

Mirrors the maestro flow step-for-step EXCEPT launchApp.clearState, which is
deliberately omitted (red line: no app-data clearing). The app is stopped and
restarted instead, which is what launchApp does apart from the state wipe.

Usage: u2_smoke.py <serial>
"""
import sys
import traceback

import uiautomator2 as u2

PKG = "com.napa.app.test"
TEXT_NAPAXI = ("Napaxi",)
# strings.dart: messageHint zh/en; later zh/en. Accept either locale so the
# probe never needs clearState (red line: no app-data clearing).
TEXT_COMPOSER = ("给 napaxi 发消息", "Message napaxi")
TEXT_ENGINE = ("Codex(beta)",)
TEXT_LATER = ("稍后", "Later")
TEXT_TYPED = ("冒烟测试 hello",)


def _sel(d, variants):
    """Flutter exposes semantics via content-desc/hint, not text; maestro's
    text selector matches all of them, so try each attribute in order."""
    for text in variants:
        for kw in ("text", "description"):
            el = d(**{kw: text})
            if el.exists:
                return el
        # Flutter TextField hints land in the `hint` attribute, which u2's
        # Selector rejects; xpath is the supported escape hatch.
        el = d.xpath('//*[@hint="%s"]' % text)
        if el.exists:
            return el
    return None


def _wait_sel(d, variants, timeout):
    import time as _t
    deadline = _t.time() + timeout
    while _t.time() < deadline:
        el = _sel(d, variants)
        if el is not None:
            return el
        _t.sleep(0.5)
    return None


def fail(d, msg):
    print("FAIL:", msg, flush=True)
    try:
        xml = d.dump_hierarchy()
        print("--- dump_hierarchy first 50 lines ---", flush=True)
        for line in xml.splitlines()[:50]:
            print(line, flush=True)
    except Exception as e2:  # noqa: BLE001
        print("dump_hierarchy also failed:", type(e2).__name__, e2, flush=True)
    raise SystemExit(1)


def assert_visible(d, variants, timeout=30):
    if _wait_sel(d, variants, timeout) is None:
        fail(d, "assertVisible %r timed out after %ss" % (variants, timeout))
    print("  assertVisible %r ok" % (variants,), flush=True)


def tap(d, variants, timeout=15):
    el = _wait_sel(d, variants, timeout)
    if el is None:
        fail(d, "tapOn %r not found within %ss" % (variants, timeout))
    el.click()


def main():
    serial = sys.argv[1] if len(sys.argv) > 1 else "7e78be85"
    d = u2.connect(serial)
    print("connected:", d.serial, flush=True)

    # launchApp (without clearState): stop then start
    print("[1] app_stop+app_start", PKG, flush=True)
    d.app_stop(PKG)
    d.app_start(PKG, wait=True)
    # Guard against launcher false-positives: wait until OUR package is foreground.
    import time as _t
    deadline = _t.time() + 60
    cur = None
    am_fired = False
    t_start = _t.time()
    while _t.time() < deadline:
        cur = (d.app_current() or {}).get("package")
        if cur == PKG:
            break
        if not am_fired and (_t.time() - t_start) > 10:
            # u2 app_start no-op on some devices: resolve launcher activity and
            # start it explicitly (same thing maestro launchApp does internally).
            out = d.shell("cmd package resolve-activity --brief " + PKG).output
            act = out.strip().splitlines()[-1].strip()
            print("  am start fallback:", act, flush=True)
            d.shell("am start -n " + act)
            am_fired = True
        _t.sleep(1)
    if cur != PKG:
        fail(d, "app not in foreground after 60s, current=%r" % cur)
    print("  foreground:", cur, flush=True)

    # optional in-app update dialog dismissal
    later = _wait_sel(d, TEXT_LATER, 3)
    if later is not None:
        later.click()
        print("[2] tapped optional dialog", TEXT_LATER, flush=True)
    else:
        print("[2] optional dialog", TEXT_LATER, "not present (ok)", flush=True)

    # extendedWaitUntil visible Napaxi (30s)
    print("[3] wait ready", TEXT_NAPAXI, flush=True)
    assert_visible(d, TEXT_NAPAXI, timeout=30)

    # assertVisible composer hint
    print("[4] assert composer hint", flush=True)
    assert_visible(d, TEXT_COMPOSER, timeout=15)

    # engine-selector popup: tap Napaxi, assert Codex(beta), back
    print("[5] tap", TEXT_NAPAXI, flush=True)
    tap(d, TEXT_NAPAXI)
    print("[6] assert", TEXT_ENGINE, flush=True)
    assert_visible(d, TEXT_ENGINE, timeout=10)
    print("[7] back", flush=True)
    d.press("back")
    print("[8] assert composer hint again", flush=True)
    assert_visible(d, TEXT_COMPOSER, timeout=15)

    # type into composer and assert the typed text
    print("[9] tap composer", flush=True)
    tap(d, TEXT_COMPOSER)
    d.sleep(1.0)
    print("[10] set_text", TEXT_TYPED, flush=True)
    typed = False
    focused = d(focused=True)
    if focused.wait(timeout=5):
        try:
            focused.set_text(TEXT_TYPED[0])
            typed = True
        except Exception as e:  # noqa: BLE001
            print("  focused.set_text failed:", type(e).__name__, e, flush=True)
    if not typed:
        try:
            d.xpath("//android.widget.EditText").set_text(TEXT_TYPED[0])
            typed = True
        except Exception as e:  # noqa: BLE001
            print("  xpath EditText set_text failed:", type(e).__name__, e, flush=True)
    if not typed:
        d.send_keys(TEXT_TYPED[0])
    print("[11] assert typed text", flush=True)
    assert_visible(d, TEXT_TYPED, timeout=10)

    # hideKeyboard (KEYCODE_ESCAPE)
    print("[12] hideKeyboard", flush=True)
    d.shell("input keyevent 111")

    print("FULLFLOW PASS on", serial, flush=True)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:  # noqa: BLE101
        traceback.print_exc()
        raise SystemExit(1)
