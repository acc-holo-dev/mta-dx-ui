# DXUI V3 — Architecture

DXUI V3 is a retained-mode, two-pass-layout, pooled-render UI framework for
MTA:SA (Lua 5.1 / DirectX 9). This document maps the code layout and the
design decisions that make it fast, deterministic and themeable.

```
source/client/
├── settings.lua                  runtime + resource policy defaults
├── core/
│   ├── values.lua                colors, color proxies, resolveColor
│   ├── node.lua                  base tree node + property system (_set layer)
│   ├── widget.lua                widget base: theme apply, states, measure
│   └── part.lua                  named child nodes (header/content/…)
├── translation.lua               `T(key)` — translation dict (utf8)
├── text/
│   └── text.lua                  injected measurer, wrap/ellipsis, layout cache
├── style/
│   ├── tokens.lua                design tokens (@color.accent, …)
│   ├── theme.lua                 themes, component styles, variants, states
│   └── defaults.lua              Fluent-Lite default theme (auto-activates)
├── animation/
│   ├── easing.lua                linear/in/out/inout/back/elastic/bounce/spring
│   └── animation.lua             Anim manager + chained AnimHandle
├── resources/
│   └── manager.lua               texture/font cache + theme ownership sweep
├── layout/
│   ├── dimension.lua             px / pct / auto / fill + box()
│   ├── flex.lua                  flex rows/columns (weights, wrap)
│   └── layout.lua                two-pass layout: root pass + child pass
├── render/
│   ├── render_list.lua           flat pooled item list (id of last item)
│   ├── state.lua                 per-frame draw state (blend, clip, groups)
│   ├── renderer.lua              Canvas – draw entry for widgets
│   ├── effects.lua               clipMode rt/mask/blur — RT group manager
│   ├── backend_mta.lua           ONLY MTA dx* entry point (injectable)
│   └── pass.lua                  collect → sort → emit
├── input/
│   ├── events.lua                Events.on/emit with bubbling + DXUI.STOP
│   ├── hit_test.lua              flag-based interactive scan (topAt reverse)
│   └── dispatcher.lua            hover/focus/pressed/modal/popups/drag
├── api/
│   ├── runtime.lua               UI instance: tick() pipeline + stats
│   ├── ui.lua                    `ui:*` builders (panel/button/… shortcuts)
│   ├── exports.lua               exports.getUI / DXUI.getUI singleton
│   └── diagnostics.lua           snapshot/describe/report/zeroWork/idleRatio
├── widgets/                      one file per widget; registered via Builders
└── init.lua                      MTA glue: bootstrap + event wiring (resource)
```

## The property system (core/node.lua)

Every state lives in `node._data` behind one mutation layer:

- `Node:_set(key, value, owner)` — the single write path. Owner is
  `"user"` (API/script), `"theme"` (style apply), `"system"` (engine:
  layout sizes, viewport mapping). Owner `"theme"` sets `_themeApplied[key]`;
  any OTHER owner write revokes it.
- Property specs: `{ default, type, min, max, validate, transform,
  invalidates = { DIRTY.* }, onSet }`. Writes go through min/max clamping,
  transform, then the dirty flags (category → instance dirty flag).
- Value objects: colors read as proxies; arithmetic on them returns plain
  values. Proxies are live references to the node's current value.

## Dirty system

Nodes invalidate by CATEGORY; the instance maps categories to four flags:

```
layoutDirty  (sizes/positions)        renderDirty  (paint output)
orderDirty   (z-order / siblings)     interactiveDirty (hit-test buckets)
```

`Runtime:tick()` runs the pipeline **only when its flag says so**:

```
anim:update() → Layout.update (if layoutDirty) → rebuild flat item list
(if renderDirty|orderDirty) → rebuild interactive list (if interactiveDirty)
→ draw() paints the pooled list every frame (idle = zero rebuild, not zero draw)
```

The render list is a persistent flat array rebuilt only on dirty; painting
caches it. Sort on rebuild: `(effLayer, zIndex, _id)` — stable and cheap.

## Layout

- `Dimension`: `ui:px(10)` → `{k="px",v=10}`; `ui:pct(50)`; `ui:auto()`;
  `ui:fill()`. `layoutWidth/layoutHeight` accept any of these.
- `layoutMode`: `"relative"` — x/y are FRACTIONS of the parent content box
  (0..1); `"absolute"` — pixels.
- `resolveSize` shares ONE `_measureContent()` call for both axes; autoSize
  measures only when a dimension is *free* (no explicit owner + nil/0 raw
  value) — explicit props and layout dims always win.
- Two passes: root pass resolves the UI box; the child walk resolves each
  node and recurses. Engine-computed sizes are written as `_set(...,"system")`
  with a same-value guard → no invalidation loops.

## Rendering

- `Canvas` (renderer) provides `rect/roundedRect/image/text/line`; widgets
  call it from `Widget:render(renderer)` — no direct dx* calls anywhere.
- Item pooling: group arrays recycled AFTER draw via the per-frame state
  cache; `render_list.lua` tracks pooled item count (`list.count`, used for
  `stats.items`).
- RT groups exist ONLY for `clipMode="rt"`, blur, and mask; everything else
  is plain draw calls with dxSetBlendMode state tracking.
- Screen culling (settings.performance.screenCulling) skips items fully
  outside the viewport at collect time.

## Theme

Chain: **variant (`node.style`) → component base → fallback theme → class
defaults.** Compiled ONCE per (theme, component, styleKey):

- `_applyStyleState()` reads the compiled map; `enabled == false` forces
  `"disabled"` over hover/pressed; sparse overrides are applied with the
  owner guard — user-set props are never overwritten.
- `Theme.activate()` clears the compile cache, sweeps obsolete theme assets
  via `releaseObsolete(Theme._keep)`, then `reapplyAll()` walks every mounted
  UI tree. Detached nodes re-apply when re-attached (or manually).
- Tokens resolve iteratively with a depth cap + cycle guard (always
  terminates); unresolved props are dropped → deterministic fallback.

## Input

Events bubble target → ancestors (snapshot per level); a handler returning
`DXUI.STOP` halts. Hit-testing is flag-based (`interactive/focusable` reset
the interactive cache). The Dispatcher owns hover / focus / pressed / drag
(threshold 6px) / modal depth / popup registry, maps screen→design coords,
and click emits `(button, x, y, pressedOrigin)`.

## Diagnostics

`DXUI.Diagnostics`: `snapshot/ui/stats`, `describe` (one-line), `report`
(multi-line), `idleRatio` (1 − active frames / frames), and
`enableZeroWork(ui, true)` — asserts inside `tick()` that layout and rebuild
never run without their dirty flag (the idle-frame contract).

## Boot

`DXUI.bootstrap(opts)` (init.lua) is the MTA entry: `addEventHandler
onClientRender` frame loop, `guiGetScreenSize → setViewport`, and mouse /
click / scroll / key glue that translates screen coords into design coords
before dispatch. Resource stop destroys the instance and releases resources.

Everything MTA-specific lives in `init.lua` + `render/backend_mta.lua`; the
rest is plain Lua 5.1 and runs under lupa with a table backend (see
`readme/tests/run.py`).