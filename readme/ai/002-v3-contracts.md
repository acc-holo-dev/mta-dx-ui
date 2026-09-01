# DXUI V3 — Internal Contracts (source of truth for implementation)

Status: LOCKED by the main agent after the V2 audit (readme/ai/001-v2-audit.md).
Load order (meta.xml): settings → values → node → widget → part → translation → text → tokens → theme →
defaults → easing → animation → resources(manager) → layout(dimension/flex/layout) → render(list/effects/
backend_mta/renderer/state/pass) → input(events/hit_test/dispatcher) → runtime → ui → exports → diagnostics →
builders → widgets(…) → init.

## 1. Globals & module convention
- `DXUI = DXUI or {}` in each file; each subsystem publishes ONE table: `DXUI.Values, DXUI.Node, DXUI.Widget,
  DXUI.Part, DXUI.Settings, DXUI.Text, DXUI.Color, DXUI.Resources, DXUI.Tokens, DXUI.Theme, DXUI.Layout,
  DXUI.Dimension, DXUI.RenderList, DXUI.RenderState, DXUI.RenderPass, DXUI.Renderer, DXUI.Effects,
  DXUI.BackendMTA, DXUI.EventBus, DXUI.HitTest, DXUI.Dispatcher, DXUI.Easing, DXUI.Anim, DXUI.Runtime,
  DXUI.UI, DXUI.<WidgetClass>…`.
- Pure Lua 5.1: no MTA API in core/ (core = values, node, widget, part, settings). MTA touches only:
  backend_mta, resources/manager, text (dxGetTextSize via backend callback), init (bridge), exports.

## 2. Property spec (declared per class; inherited)
```lua
{ default = v, type = "number"|"string"|"boolean"|"table"|"function", min, max,
  validate = fn(v)->bool, transform = fn(v)->v,
  invalidates = { DIRTY.LAYOUT, DIRTY.STYLE, DIRTY.RENDER, DIRTY.INPUT, DIRTY.CONTENT, DIRTY.VISIBILITY },
  readOnly = true, -- managed by the engine (worldX/worldY/parts/…)
  alias = { "position", "size" } } -- value-object hosts
```
- ALL writes go through one mutation layer `Node:_set(key, value, owner)` (user|system|theme — the "system"
  owner is used by layout/animation/lifecycle). Same-value guard → no invalidation.
- Validation runs in dev mode always, prod mode on user writes; `DXUI.Settings.dev`.
- theme writes happen with owner="theme" (flag `_applyingTheme`); any non-theme write revokes theme ownership
  of that property (`_owner` map + `_themeApplied` set).

## 3. Dirty model (consumed, not just collected)
DIRTY categories (per node): LAYOUT, STYLE, RENDER, INPUT, CONTENT, VISIBILITY.
UI instance frame flags (derived from node mutations): `layoutDirty, orderDirty, renderDirty, interactiveDirty`.
Mapping (property → instance flags):
- x/y/width/height/parent/margin/padding/anchor/layoutMode → layout+render+order+interactive
- zIndex/layer → render+order+interactive
- visible/enabled → render+interactive
- color/text/texture/font/opacity/radius/… → render
- style → style+render
- children (add/remove) → layout+render+order+interactive
Frame: `layoutDirty → layout pass; (renderDirty or orderDirty) → collect+rebuild items (sort ONLY if orderDirty);
interactiveDirty → rebuild hit list; style: state/style changes re-resolve per affected node (not a tree pass)`;
then DRAIN all per-node dirty flags. Idle frame (no flags): animation tick + draw only.

## 4. Value objects (cold-path proxies, cached per node, `values.lua`)
- `Color`: packed 0xAARRGGBB int; `c.r/c.g/c.b/c.a` read 0-255, writes repack via node:_set(key, packed, owner).
- `Point` (position: .x .y), `Size` (width .height), `Vec2` (theme-level).
- Node exposes `node.color` (Color), `node.position` (Point), `node.size` (Size) plus direct aliases
  `node.x/y/width/height` — SAME storage (`_data`), dual access. `node.color.r = 255` == `node:setColor(…)`.
- Creating/reading a value object NEVER allocates: one cached table per (node,key), reused.

## 5. Node lifecycle (explicit states)
created → mounted (context assigned; hook `_onMount(ctx)` after children) → updated (per-node dirty handled
by its category passes) → hidden (`visible=false`; hook `_onVisibleChanged(v)`) → detached (removed from live
context; hook `_onDetached()`) → destroyed (hook `_onDestroy()`; children first; unqueue; clear state).
Ownership: parent owns children (`destroy()` cascades). UI instance owns its tree root; runtime owns instances.

## 6. Parts (§14-17)
- A widget class may declare `Class.parts = { ["header"] = true, ["content"] = true, … }`.
- `node:setPart(name, partNode)` replaces deterministically: detach old → destroy it (it was owned) → attach
  new → fix `node._parts[name]`. `node:getPart(name)`. Property-style `node.header = x` and read `node.header`
  work through the metatable when the name is in `_partKeys`.
- Parts are real Nodes/Widgets with their own visual state/layout/input; they receive theme sections by role
  name (`components.Window.parts.closeButton.states.hover…`).
- `node:removePart(name)` destroys the part and clears the slot (nullable parts only).

## 7. Theme (§45-61)
Data shape (portable, JSON-shaped):
```lua
theme = {
  tokens = { colors={…}, fonts={…}, spacing={…}, sizes={…}, radii={…}, durations={…} },
  components = { [ClassName] = {
      [styleName or "default"] = {
        props = { color="#", … },               -- flat component props (may reference tokens)
        states = { hover={…}, pressed={…}, focused={…}, selected={…}, disabled={…} },
        parts  = { [roleName] = { props=…, states=… } },
        transitions = { [prop] = { duration=ms, easing="out" } },  -- or false to disable
      } } },
  fonts = { body="…", title="…", mono="…" },
  textures = { … }, icons = { … },
}
```
- Resolution is COLD: `Theme.compile(name) → ComponentStyle` (tokens resolved, states merged, parts resolved)
  — happens at theme load/switch and per component on first use; cached.
- Fallback order (deterministic): engine defaults (settings + defaults.lua) → global theme → resource theme →
  component → part role → state → instance override (_owner=user) → explicit runtime override.
- Sparse overrides: only the changed property is overridden (user owner guard; nothing copied wholesale).
- Live switch `ui:setTheme(theme)`: load → validate (shape/refs) → compile → activate → invalidate styled
  props of all mounted widgets (STATE+STYLE, not a tree walk when possible — see 3).
- Transitions: automatic on state/style switches where declared; **explicit `node:animate` wins** (§52).
- Assets (fonts/textures) owned by the ACTIVE theme set; switching releases obsolete, keeps shared.

## 8. Layout (§28-31)
- Dimension values (cold-path compiled): `ui.percent(50)`, `ui.auto()`, `ui.fill()`, and plain numbers;
  internal compiled form: `{k="px",v=n} | {k="pct",v=n} | {k="auto"} | {k="fill"}`. Strings like "50%"
  accepted at cold path only.
- Two passes: measure (compute intrinsic sizes: auto/flex) → place (world coords). Modes: absolute/corner
  anchor(9)/center/stretch/auto/fill; flex: row|column, gap, align (start|center|end|stretch), justify
  (start|center|end|spaceBetween|spaceAround|spaceEvenly), grow/shrink (weights), wrap.
- Auto-relayout triggers: child create/destroy, any geometry/font/text/padding/margin/layout change,
  parent resize, screen/design resolution change. No manual `relayout()` in normal use.
- Design resolution PER UI INSTANCE (`ui:setDesignResolution(w,h,mode)`), mode stretch|fit; inputs mapped
  screen↔design via instance scale/offset; events delivered in design coords (worldX/worldY), hit-test in
  the same space.

## 9. Render (§21-26, §34-37)
- Persistent flat item list (kind: rect|rrect|image|text|line|rtgroup), rebuilt on (renderDirty|orderDirty),
  drawn every frame; idle = draw only. Items are plain tables, reused via pool (no per-rebuild alloc churn).
- Renderer = widget-facing primitive API only (rect/roundedRect/image/text/line/outline + clip + opacity
  modulation). Widgets NEVER call DX or manage global state; hit-test-friendly draw order (layer→z→insertion).
- RenderState: real state cache — blend mode, current texture/font/shader + params, dedup by IDENTITY with
  correct invalidation (fx tables cached by inputs, shared; no per-use clones).
- RenderPass: collect (visibility + ancestor clip + SCREEN culling) → sort (only on orderDirty) → emit;
  RT-groups ONLY for clipMode="rt"/effects; ordinary clip = cheap rectangle intersection; opacity = alpha
  modulation (no RT); blur/mask via shader/group; blur is EXTENSIBLE, not core scope.
- backend_mta = the ONLY dx* entry point (absorbs dxGetTextSize/dxGetMaterialSize behind interface).

## 10. Input (§39-43)
- One Dispatcher per UI instance; pipeline: MTA bridge → instance → dispatcher → HitTest (indexed: buckets
  by layer, per-bucket scan; no O(scene) per move; solved stale-world staleness by hit-testing current worldX)
  → EventBus (capture→target→bubble; stopPropagation/preventDefault/consume; `on/off`; prod-safe isolated
  listener errors).
- Pointer capture contract: mousedown→capture→move delivered to captured node→mouseup→release.
- Focus system: hovered/focused/pressed/captured/active; keyboard events to focused node; keyboard-nav
  foundation (focusable set + moveNext/movePrev) used by widgets later.
- Modal stack (focus lock + input trap) & popup stack (dismiss on outside click) per instance.

## 11. Text (§38)
- Subsystem: measure (cached per text+font+scale), layout (wrap/ellipsis/align/color-code carry/autosize),
  render (via renderer; align/valign native), cache bounded; selection/caret foundation (metrics API usable
  by Edit). Measurement callback injected from backend (MTA dxGetTextSize / tests monospace). UTF-8:
  byte-level documented limitation (same as V2).

## 12. Animation (§44, §52)
- One manager per instance, single tick in frame; `node:animate(props, durMs, ease)`; handle:
  `:after/:onDone/:pause/:resume/:cancel`; easing set: linear/in/out/inout/back/elastic/bounce/spring;
  writes through `_set(...,"system")` (so explicit animation > theme transition). No timers/handlers/
  coroutines per animation.

## 13. Settings (§47, §32, §31)
`source/client/settings.lua`: dev(bool)/errorPolicy/designResolution{width,height,mode}/scaling(quality
preset)/defaults{font,colors}/animation{defaultDuration,defaultEasing}/resourcePolicy{autoRelease},
quality strategy for supersampling configurable later. Appearance NEVER lives here.

## 14. Widget contract (§18-20, §14-16)
```lua
local Button = DXUI.Widget:extend("Button", { props…, parts = {…} })
function Button:render(renderer) … end           -- primitives only
function Button:onMount(ctx) … end               -- parts that need context
function Button.build(ui, props) → node          -- constructor (ui instance)
```
- Registration `DXUI.Builders.register("Button", Button)` → `ui:button(props)` (mounts to root or parent
  builder `parent:button(props)`). New widgets never touch kernel.
- Widget props that are functions (`onClick`, `render`) are consumed by builders explicitly; method-named
  props are rejected loudly in dev (no silent skip).

## 15. Errors (§71)
- dev: clear errors + warnings + validation on every write; prod: predictable, low overhead, safe —
  guards on destroyed access; listener isolation cost off in prod; no hidden corruption on destroyed objects
  (destroy clears subscriptions and queues).

## 16. Ownership & runtime (§8-9)
- `exports.dxui:getUI()` ONCE per consumer resource at init; NEVER in onClientRender. One global Runtime
  (bridge, frame loop, settings, resources); each UI instance = one tree + dispatcher + render/anim/layout +
  theme scope; destroyed on the consumer resource stop (nodes/listeners/animations/theme-scoped assets freed).