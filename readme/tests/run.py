#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run.py — DXUI V3 lupa test runner (headless; no MTA needed).

Usage:
    python readme/tests/run.py            # run all suites
    python readme/tests/run.py basic boot  # run named suites

Each suite gets a FRESH LuaRuntime with the engine loaded in meta.xml
dependency order (minus init.lua — the MTA glue — except the "boot"
suite, which loads it under a faked MTA environment).

Suite files are plain Lua chunks run inside the runtime; the harness
exposes: DXUI, eq(got, want, name), ok(fn-got, want-name) truthiness,
expect(cond, name), Backend (a fresh observable test backend factory,
call DXUI.Runtime.backend = Backend()), ui (a pre-made UI handle).
Exit code is 0 iff every suite passes.

Requires: pip install lupa  (Python >= 3.8)
"""

import pathlib
import sys

try:
    import lupa
except ImportError:
    sys.stderr.write("lupa is required:  pip install lupa\n")
    sys.exit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

# meta.xml dependency order (identical list; init.lua handled separately)
LOAD_ORDER = [
    "source/client/settings.lua",
    "source/client/core/values.lua",
    "source/client/core/node.lua",
    "source/client/core/widget.lua",
    "source/client/core/part.lua",
    "source/client/translation.lua",
    "source/client/text/text.lua",
    "source/client/style/tokens.lua",
    "source/client/style/theme.lua",
    "source/client/style/defaults.lua",
    "source/client/animation/easing.lua",
    "source/client/animation/animation.lua",
    "source/client/resources/manager.lua",
    "source/client/layout/dimension.lua",
    "source/client/layout/flex.lua",
    "source/client/layout/layout.lua",
    "source/client/render/render_list.lua",
    "source/client/render/effects.lua",
    "source/client/render/backend_mta.lua",
    "source/client/render/renderer.lua",
    "source/client/render/state.lua",
    "source/client/render/pass.lua",
    "source/client/input/events.lua",
    "source/client/input/hit_test.lua",
    "source/client/input/dispatcher.lua",
    "source/client/api/runtime.lua",
    "source/client/api/ui.lua",
    "source/client/api/exports.lua",
    "source/client/api/diagnostics.lua",
    "source/client/widgets/builders.lua",
    "source/client/widgets/panel.lua",
    "source/client/widgets/label.lua",
    "source/client/widgets/button.lua",
    "source/client/widgets/image.lua",
    "source/client/widgets/window.lua",
    "source/client/widgets/checkbox.lua",
    "source/client/widgets/radiobutton.lua",
    "source/client/widgets/progressbar.lua",
    "source/client/widgets/slider.lua",
    "source/client/widgets/scrollpanel.lua",
    "source/client/widgets/edit.lua",
    "source/client/widgets/combobox.lua",
    "source/client/widgets/tabpanel.lua",
    "source/client/widgets/gridlist.lua",
    "source/client/widgets/popup.lua",
    "source/client/widgets/contextmenu.lua",
    "source/client/widgets/modal.lua",
    "source/client/widgets/tooltip.lua",
]

# faked MTA globals needed by init.lua (boot suite loads it explicitly)
MTA_PRELUDE = r"""
local mta = { handlers = {}, screenW = 1920, screenH = 1080, now = 0 }
function addEventHandler(name, el, fn, ...)
    mta.handlers[name] = mta.handlers[name] or {}
    mta.handlers[name][#mta.handlers[name] + 1] = fn
end
function removeEventHandler(name, el, fn) end
resourceRoot = setmetatable({}, {})
function guiGetScreenSize() return mta.screenW, mta.screenH end
function getTickCount() return mta.now end
function setTimer() return {} end
function dxGetTextSize(text, scale, font) return #text * 7 * (scale or 1), 15 * (scale or 1) end
__MTA = mta
"""

# engines re-used across all suites
HARNESS = r"""
local okCount, failCount = 0, 0
function eq(got, want, name)
    if got == want then okCount = okCount + 1
    else
        failCount = failCount + 1
        print(("FAIL: %s (got %s, want %s)"):format(name, tostring(got), tostring(want)))
    end
end
function expect(cond, name)
    if cond then okCount = okCount + 1
    else failCount = failCount + 1; print("FAIL: " .. name) end
end
function Backend()
    local b = { rects = 0, texts = 0, images = 0, lines = 0 }
    function b.setBlendMode() end
    function b.drawRect() b.rects = b.rects + 1 end
    function b.drawRoundedRect() b.rects = b.rects + 1 end
    function b.drawImage() b.images = b.images + 1 end
    function b.drawText() b.texts = b.texts + 1 end
    function b.drawLine() b.lines = b.lines + 1 end
    function b.beginGroup() return false end
    function b.endGroup() end
    function b.materialSize() return nil end
    return b
end
function _suiteResult()
    return okCount, failCount, (okCount + failCount)
end
"""


def load_engine(L, include_init=False):
    for rel in LOAD_ORDER:
        L.execute('assert(loadfile(%r))()' % str(ROOT / rel))
    if include_init:
        L.execute('assert(loadfile(%r))()' % str(ROOT / "source/client/init.lua"))


def run_suite(name, prelude=None):
    path = ROOT / "readme" / "tests" / ("smoke_%s.lua" % name)
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    try:
        if prelude:
            L.execute(prelude)
        load_engine(L, include_init=(name == "boot"))
        L.execute(HARNESS)
        L.execute("loadfile(%r)()" % str(path))
        ok, failed, total = L.globals()._suiteResult()
    except lupa.LuaError as e:
        print("  %-10s ERROR: %s" % (name, e))
        return 0, 1, 1
    if failed == 0:
        print("  %-10s ok=%d" % (name, total))
    else:
        print("  %-10s ok=%d failed=%d" % (name, ok, failed))
    return ok, failed, total


def main():
    names = sys.argv[1:] or ["core", "style", "basic", "composite", "boot"]
    total_ok = total_fail = 0
    print("DXUI V3 test runner (%s)" % ROOT)
    for name in names:
        prelude = MTA_PRELUDE if name == "boot" else None
        ok, failed, _ = run_suite(name, prelude)
        total_ok += ok
        total_fail += failed
    print("---")
    print("total: %d passed, %d failed" % (total_ok, total_fail))
    sys.exit(1 if total_fail else 0)


if __name__ == "__main__":
    main()