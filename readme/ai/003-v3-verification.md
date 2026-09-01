# V3 verification — round 7 (implementation log + change log)

PROMT.md §79–81 response shape: this file is the **implementation log**
(§83 change log) for the live rewrite. Rounds 1–6 completed the engine:
audit → design → structure → contracts → core → rendering/input/layout/
theme → widgets → integration. This round: **integration boot, tests/perf
resource, docs, and the self-review gates (§82/§85/§86).**

## What round 7 delivered

1. **Runtime diagnostics** — `stats` counters (frames/layoutRuns/rebuilds/
   hitRebuilds/items/draws) accumulate always + `perf.zeroWork` asserts
   inside `tick()` (layout/rebuild never run without their dirty flag);
   `draw()` counts painted items. Module: `source/client/api/diagnostics.lua`
   (`snapshot/describe/report/enableZeroWork/idleRatio`), wired into
   `meta.xml` after `exports.lua`.

2. **MTA boot integration verified** — `init.lua` bootstrap (onClientRender
   frame loop, guiGetScreenSize → setViewport, mouse/click/scroll/key glue,
   resource-stop cleanup) exercised under a faked MTA environment:
   click routed through the glue at 3× scaling (screen (240,180) →
   design (100,100)), zero-work idle contract on real frame ticks, single
   mutation → exactly one rebuild, resource stop destroys + releases.

3. **Test resource** — `readme/tests/`: python runner (lupa, no MTA) with
   five suites (core 42 / style 16 / basic 21 / composite 33 / boot 14 =
   **126 assertions green**). Runner mirrors meta.xml load order; the boot
   suite loads init.lua under fake MTA globals.

4. **Engine bugs found & fixed by the tests**
   - `resources/manager.lua`: `local _themeKeep` declared AFTER the
     functions using it → compiled as a global → nil-index crash on
     `markTextureUsed`; declaration moved before use.
   - `layout/layout.lua`: autoSize measured dimensions clobbering EXPLICIT
     `width`/`height` props (wrap labels 40→77). New `freeDim` gate: measure
     only when the dimension has NO explicit owner AND the raw value is
     nil/0. Props and layout dims always win.
   - `widgets/tooltip.lua`: `refresh()` computed WORLD coords but the
     tooltip is parented to its target → `setPosition` stored LOCAL coords →
     double offset (top-anchored tooltip appeared below the target at
     `anchor.y + (anchor.y - th - 6)`); now converted back through the
     parent's world position.
   - Widget content-sizing defaults: `autoSize = true` on Label, Checkbox,
     RadioButton, Tooltip (they measure intrinsic content; the freeDim gate
     keeps explicit sizes authoritative).
   - Test-side (not engine) corrections only: `_themeApplied` guard, `#`
     on counter vs list, reapply scope for detached nodes, proxy liveness in
     value copies, `Token.resolve(name, "@path")` signature, EASING table
     keys, Anim `animate(node, props, dur, ease)` chain, user/system owner
     semantics, STOP = the stopping handler runs, higher ancestors halt.

5. **Docs round** — `readme/documents/ARCHITECTURE.md` (full V3 map),
   `readme/documents/ADR.md` (ADR-001…009), `readme/examples/demo.lua`,
   `readme/tests/README.md`; top-level `README.md` + `ARCHITECTURE.md`
   rewritten for V3.

## Change log (§83) — key decisions consolidated

| R | module | change |
|---|--------|--------|
| 7 | api/diagnostics.lua | NEW: stats/zero-work/idleRatio |
| 7 | api/runtime.lua | stats counters + zeroWork asserts + draws counting |
| 7 | resources/manager.lua | fix `_themeKeep` scope shadowing |
| 7 | layout/layout.lua | autoSize free-dimension gate |
| 7 | widgets/tooltip.lua | world→local anchor fix; content autoSize |
| 6 | (prior) | viewStyle spawn, combobox fix, scrollpanel local extent |
| 5–4 | (prior) | renderer/effects/backend; theme reapply; widget set |

## Self-review gates (§82/§85/§86)

- **§82 review**: all 48 modules load in meta.xml order (verified by the
  runner AND the fake-MTA boot load); Lua 5.1-compatible (no `goto`, bare
  `X and Y()` or generic-for writes; compile-checked under Lua 5.5 load).
- **§85 quality**: every unit backward-referenced in this file; bugs found
  by tests were FIXED in the engine, not papered over in tests (manager
  scope, autoSize gate, tooltip anchor — three genuine engine defects).
- **§86 no code for code's sake**: no speculative modules added this round;
  every new file serves tests, docs or the idle contract.

Remaining (next milestones): MTA in-game sweep (real dx* backend), and the
example resource (`meta.xml` demo pattern hardened against live MTA).