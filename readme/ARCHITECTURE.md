# ARCHITECTURE

DXUI V4 is a retained-mode UI engine for MTA:SA. This document maps the
layers, the frame pipeline, the invariants the engine is built around, and
where every responsibility lives.

## Layers

```
init.lua (MTA glue; loads LAST)
   └─ wires BackendMTA, registers the frame loop + input events
Runtime (api/runtime.lua)
   └─ owns: frame loop, dirty flags, dispatcher, animations, overlays,
      design→screen mapping, the pooled render list, diagnostics
      UI handle (api/ui.lua) is Runtime + consumer-facing methods
Dispatcher (input/dispatcher.lua)
   └─ correlates raw input into: hover, focus, press, click, drag,
      wheel, keys, modal stack, popup chain
Node (core/node.lua)
   └─ the mutation layer: EVERY property write funnels through Node:_set
Widget (core/widget.lua)
   └─ render contract, states, theme application, translation, autoSize
Layout (layout/)          sizes + positions (runs only when layoutDirty)
RenderPass (render/pass)  tree → flat item list (runs only when renderDirty)
Renderer (render/renderer)primitives; knows nothing about the backend
BackendMTA (render/backend_mta)  the ONLY dx* calls in the engine
```

Everything above BackendMTA is pure Lua 5.1 — the test harness runs the
whole engine with an injected table backend and a fake MTA environment.

## The frame pipeline (Runtime:tick)

```
anim:update()                    -- early-out when no animation is active
if layoutDirty     → Layout.update     (walks the tree, writes via _set "system")
if renderDirty/orderDirty → RenderPass.build
                       collect  visibility/opacity/layer/clip/culling
                       sort     (effLayer, zIndex, insertion id)
                       emit     every node renders its own primitives
if interactiveDirty → HitTest.rebuild  (mirrors painter order)
draw the CACHED list            -- zero rebuild on idle frames
overlays                        -- frame-clock repaints (Edit caret), direct
```

**Zero-work idle contract**: an idle frame performs no layout, no rebuild,
no hit-test rebuild — it only draws the cached list. This is assert-locked
in the perf suite and by `Diagnostics.enableZeroWork`.

## The mutation layer (Node:_set)

Every property write — `node.x = 10`, a setter, an animation tick, the
layout engine, the theme re-apply — goes through one function:

1. validate (spec `type`/`min`/`max`/`validate`);
2. transform (e.g. `DXUI.resolveColor`, compiled dimensions);
3. if `old == value` → early out (this makes onSet write-backs and
   engine writes recursion-safe and free);
4. ownership bookkeeping (`user` > `system` > `theme`): a themed value
   never overwrites a user/system value; a non-theme write revokes the
   theme's ownership of that property;
5. category invalidation (DIRTY.LAYOUT/RENDER/ORDER/VISIBILITY/INPUT)
   coalesces into instance-level flags, drained once per frame.

## Themes (style/)

- **Tokens** (`tokens.lua`): nested tables; theme components reference
  them as `"@color.primary"`. Resolution is iterative with a depth cap
  and cycle guard; a missing token drops the property (deterministic
  fallback to the class default).
- **Theme.define** (`theme.lua`): `extends` deep-merges the child over the
  parent (parents must be defined first). Component styles compile once
  per (theme, component, styleKey) into `props` + `states`; `props`/`base`
  are aliases (child `base` wins over parent `props`).
- **Asset prefixes** in theme values (`"texture:…"`, `"font:path:size"`)
  load through the shared resource cache; failed loads drop the key.
- **Switching** (`Theme.activate` / `ui:setTheme`): re-applies to every
  live widget, then mounted-later widgets adopt the active theme on
  mount. Opt-in `transition = {duration, easing}` animates state changes
  (colors lerp per channel via the animation layer, owner "theme").
- Built-ins (`defaults.lua`, `themes.lua`): light/dark/green ×
  normal/compact/full = 9 registered themes.

## Render data flow

```
node:render(renderer)      -- design space, primitives only
  Renderer:rect/roundedRect/borderedRect/text/image/line
      clip intersect, opacity modulate, design→screen map
      → RenderList item (pooled table)
RenderList                 -- persistent, the derived cache of the tree
StateCache (render/state)  -- dedupes native state (blend, shader params)
BackendMTA                 -- draws; rounded rects ride ONE shared SDF
                              shader (border+fill single draw, per-corner
                              radii, 1px AA); square corners decompose to
                              plain rects (no shader round-trip)
```

Rounded-rect shader params dedupe via shadow-compare; blur/mask effects
dedupe by table identity (the Effects cache returns the same table for
identical inputs).

## Input model (dispatcher)

- Input arrives in DESIGN space (Runtime converts screen px).
- Hit-testing walks the interactive list (rebuilt on interactiveDirty,
  mirrors painter order: last = topmost).
- Press → focus set (focus event) → release → click (click-to-position
  wins after the focus handler); movement beyond 6px turns the press into
  a drag (click suppressed).
- The modal stack blocks everything outside the topmost modal; closing a
  mid-stack modal removes only THAT modal. Open popups close on outside
  clicks.
- `visible` invalidates INPUT as well — hidden interactive nodes leave the
  hit-test list on the next collect.

## Overlays

Widgets that must repaint every frame from the clock (the Edit caret
blink) implement `node:overlay(renderer)` and register on the instance.
`Runtime:draw` sets the renderer to direct mode and re-emits overlays
through the backend WITHOUT touching the cached list — blinking stays
free under the idle contract.

## Translation

Per-resource locale tables (`ui:addLocale`), bindings
(`node:setTextKey(key, target?)`), re-applied on `ui:setLocale` and on
mount (a binding made while detached resolves against the instance locale
once the node mounts). The instance locale overrides the engine locale.

## File responsibility map

| file | responsibility |
|------|----------------|
| `source/settings.lua` | engine behavior keys (consumed, not decorative) |
| `source/client/core/values.lua` | color/point/size value objects, packed colors |
| `source/client/core/node.lua` | tree, mutation layer, dirty model |
| `source/client/core/widget.lua` | widget contract, states, theme/translation |
| `source/client/core/part.lua` | named child slots of composites |
| `source/client/text/text.lua` | measurement + text layout (injected measurer) |
| `source/client/style/tokens.lua` | design-token registry + resolution |
| `source/client/style/theme.lua` | define/compile/activate/reapply, transitions |
| `source/client/style/defaults.lua` | the "light" base theme |
| `source/client/style/themes.lua` | dark/green palettes + density presets |
| `source/client/animation/animation.lua` | one manager, property animations |
| `source/client/animation/easing.lua` | easing library (`DXUI.Easing`) |
| `source/client/resources/manager.lua` | cached textures/fonts/shaders |
| `source/client/layout/dimension.lua` | px/pct/auto/fill compile + resolve |
| `source/client/layout/layout.lua` | the layout walk |
| `source/client/layout/flex.lua` | flex rows/columns |
| `source/client/render/render_list.lua` | pooled persistent item list |
| `source/client/render/renderer.lua` | primitives (backend-agnostic) |
| `source/client/render/pass.lua` | collect/sort/emit |
| `source/client/render/state.lua` | native state dedupe |
| `source/client/render/backend_mta.lua` | ALL dx* calls, SDF rounded shader |
| `source/client/render/effects.lua` | blur/mask shader cache, RT pool |
| `source/client/input/events.lua` | bubbling event bus (snapshot-safe) |
| `source/client/input/dispatcher.lua` | input correlation state machine |
| `source/client/input/hit_test.lua` | topmost-node lookup |
| `source/client/api/runtime.lua` | frame loop, caches, lifecycle |
| `source/client/api/ui.lua` | the consumer handle + synthesized factories |
| `source/client/api/exports.lua` | `getUI` + per-resource ownership |
| `source/client/api/diagnostics.lua` | counters, zero-work assertion |
| `source/client/widgets/*.lua` | the widget library |
| `source/client/init.lua` | MTA bootstrap + event glue (loads last) |

`meta.xml` script order is the dependency order — init.lua MUST load last.