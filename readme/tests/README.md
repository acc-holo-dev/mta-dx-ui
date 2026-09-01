# Tests

Headless verification of the whole DXUI V3 engine. Requires `lupa`
(Lua 5.5 embed for Python) — **no MTA needed**; the MTA surface is faked
for the boot suite.

```bash
pip install lupa
python readme/tests/run.py            # all suites
python readme/tests/run.py boot basic # named suites
```

## Suites

| suite           | file                 | covers |
|-----------------|----------------------|--------|
| core            | smoke_core.lua       | values/proxies, `_set` owners, tree ops, events + STOP, parts, settings, easing, animation |
| style           | smoke_style.lua      | tokens (alias/cycle guard), custom theme, variants, states, switch-back, fallback chain |
| basic           | smoke_basic.lua      | panel/label (wrap, padding measure)/button (states, disabled)/image/window parts |
| composite       | smoke_composite.lua  | checkbox, radio group, slider, edit, gridlist, scrollpanel, tabpanel, combobox, contextmenu, modal, tooltip |
| api             | smoke_api.lua        | public API surface: all 18 factories, value factories, node lifecycle, events+ids, parts, translation, diagnostics, theme/tokens statics |
| perf            | smoke_perf.lua       | performance contract on ~160 nodes: idle frames do ZERO work, category-exact mutation cost, pointer input never rebuilds, theme switch = 1 rebuild |
| boot            | smoke_boot.lua       | `DXUI.bootstrap` under fake MTA: frame loop, input glue (screen→design), diagnostics zero-work, resource-stop cleanup |

Engine modules load in `meta.xml` dependency order; `init.lua` loads only
in the boot suite (it needs the fake MTA globals). Every suite gets a fresh
runtime and observable backend (draw counters).

## What the tests pin down

- Idle frames perform **zero rebuilds** (zero-work assertion inside `tick()`)
  and a single mutation produces **exactly one** rebuild.
- `autoSize` never overrides an explicit `width/height` (free-dimension
  gate in layout).
- Dispatcher reality: clicks, drags, wheel, typing, modal blocking,
  popup-outside-close, and the screen→design coordinate mapping — all
  through real (`ui:mouse*`, `ui:key`) calls.
- Theme switch re-application and the owner guard (user props survive).

Exit code 0 = all suites green (current: **260 assertions, 0 failed**).