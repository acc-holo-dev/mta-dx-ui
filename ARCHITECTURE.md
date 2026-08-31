# DXUI V2 — Architecture

> **Principle:** SIMPLE OUTSIDE, ENGINEERED INSIDE.
> The public API is plain object-oriented Lua. Inside — controlled optimizations,
> isolated from the user.

This document is the result of Stage 0 (legacy audit) and Stage 1 (architectural
redesign). Legacy (client/, docs/adr/, tests/) remains the reference
implementation: we keep its **behavior**, not its **implementation**.

---

## 1. Why redesign, not rewrite

Legacy reached functional completeness (M20, ~300 tests), but its architecture
is optimized for the internal data representation, not for people:

| Legacy problem | Consequence |
|---|---|
| SoA + slot + id indirection | widgets read s.worldX[slot], s.w[slot] — the widget author must know SoA |
| No property-style API | only setPosition(...), no button.x = 100 |
| ui.lua = 2929 lines | all 16 widgets in one file |
| _parts, _win, _sp, etc. | a parallel state system outside Storage, manual cleanup |
| 10+ near-identical makeXxxMt | duplicated metatable logic |

V2 solves these problems **without** throwing away what legacy got right:
dirty invalidation, zero-work idle, centralized input, data-driven
animation, RT-clip, the composite concept, layer architecture.

---

## 2. Layers

PUBLIC API          (ui.*, node.*, context.*)
    ↓
UI OBJECTS          (Node, Widget, composite)
    ↓
UI RUNTIME          (Context: layout / input / render / style / resources)
    ↓
MTA DX              (backend_mta)

Dependencies only go downward. Core knows nothing about specific widgets.
The renderer knows nothing about the internal state of complex widgets.

---

## 3. Node — the public object (AoS)

Node is an **ordinary Lua table** held by the user. It is the source of
truth of the node's state. No slot/id/SoA in the public representation.

    node = {
        id        = number,
        x = 0, y = 0,
        width = 0, height = 0,
        visible = true,
        enabled = true,
        opacity = 1,
        parent = nil,
        children = {},
        zIndex = 0,
        layer = LAYER_BASE,
        style = nil,
        userData = nil,
    }

### 3.1 Property system (single mutation layer)

Node's metatable intercepts writes via __newindex and reads via
__index. **Both styles** — property and method — converge into one internal
layer node:_set(prop, value):

    button.x = 100            -- __newindex -> _set("x", 100)
    button:setPosition(100, 0) -- method -> _set("x", 100) + _set("y", 0)

_set does exactly three things:
1. value validation (in dev mode);
2. write to the field;
3. invalidation of exactly the subsystems that depend on the property.

Properties are declared **declaratively** (see Widget contract), so
_set contains no giant if/elseif — the property table generates
getter/setter/invalidation once when the widget is defined.

### 3.2 Invalidation (readable categories)

Instead of 0x091 — named categories. Boolean flags are fine internally,
but they never leak out:

    DIRTY_LAYOUT      -- position/size/parent/anchor/margin/padding
    DIRTY_RENDER      -- color/text/texture/opacity/geometry
    DIRTY_INPUT       -- hit geometry/visibility/enabled/z-order
    DIRTY_STYLE       -- style resolution
    DIRTY_CHILDREN    -- children composition
    DIRTY_VISIBILITY  -- visibility/culling

Each property knows which categories it invalidates (declared in its
description). Changing x -> DIRTY_LAYOUT; changing color -> DIRTY_RENDER.

### 3.3 Lifecycle (explicit)

    created → mounted → updated → hidden → detached → destroyed

- **created** — ui.panel(...) / context:create(...).
- **mounted** — the node (or one of its ancestors) is attached to the context root.
- **updated** — a property changed (via _set).
- **hidden** — visible = false (the node is alive, not drawn, not hit-tested).
- **detached** — parent = nil (the node is alive, outside the tree).
- **destroyed** — node:destroy(); recursively tears down children, removes
  subscriptions, frees node-owned resources.

Ownership: **the parent owns its children**. Destroying a parent destroys the subtree.
The node's events/resources/animations are released in destroy.

---

## 4. Context

    local hud  = ui.createContext()
    local menu = ui.createContext()

Each context owns:
- its own root (root node);
- its own focus manager;
- its own layers;
- its own lifecycle (renderFrame).

The global coordinator (screen size, input bridge) lives in api/ui.lua.
Contexts are isolated: one context's focus/layers/tree don't affect another's.

---

## 5. Rendering

### 5.1 Model: per-node emit (Stage 0–11)

In the current implementation the renderer keeps no persistent derived flat
cache at the context level. Instead, renderFrame walks dirty nodes and
calls node:render(renderer) — the widget itself emits primitives into the
RenderList. That is O(N) in the worst case, but sufficient for the current scope.

A full flat render list (a persistent derived cache with partial update)
is planned for the next stage; the current approach provides zero-work idle
(only dirty nodes are rendered) and readability.

### 5.2 Frame pipeline

    renderFrame
      → processDirty           (layout, style, render)
      → rebuildInteractiveList   (if dirtyCount > 0)
      → clearDirty
      → drawRenderList           (flat items → backend)

Each stage is **conditional**: if nothing changed, the stage is skipped.

### 5.3 Ordering

Render items and interactive nodes are sorted by (_effLayer, zIndex, id).
_effLayer is computed recursively at collection time (ADR-003), not
mutated via setParent.

### 5.4 Clipping: cheap path

- **Cheap path (implemented, Stage 7/9)** — geometric clip: a node with clip=true
  defines a clip region; the renderer intersects primitives with the region, fully
  invisible ones are skipped. No RT.
- **Expensive path (effects)** — effects.lua contains stubs for
  blur/mask/RT groups, but a full RT-compositing pipeline is future work.

### 5.5 Opacity

opacity is a float 0..1 on any visual node, **inherited multiplicatively**
(parent 0.5 × child 0.5 → 0.25): layout computes effectiveOpacity,
the renderer modulates the color's alpha channel.

---

## 6. Input

A centralized dispatcher (one per context), **not** per-node MTA handlers.

    MTA events (bootstrap bridge)
      → Context.dispatcher
        → hit test (flat interactive list)
        → target
        → event dispatch (bubble)

States: hovered, focused, pressed, captured.

Hit-test uses a **flat list of interactive nodes** (a derived cache,
rebuilt on DIRTY_INPUT and **immediately on destroy** (ADR-005)).
A plain rectangular node is a cheap AABB test.

### 6.1 Event model

target → bubble (up the parent chain). event:stopPropagation(),
event:preventDefault().

### 6.2 Focus

A single focus manager per context (focusedNode). Used by Edit, keyboard,
modal, popup. Escape resets focus (nil).

---

## 7. Layout

The layout subsystem computes world coords from local descriptions.
It is invalidated on changes to position/size/parent/layoutMode.

Supported modes:
- absolute — x/y in pixels;
- relative — x/y as a 0..1 fraction of the parent;
- anchor — 9 anchor points;
- center — centering within the parent;
- stretch — stretching along axes;
- autosize — size from content.

### 7.1 Design resolution

    DXUI.setDesignResolution(1920, 1080)

Implemented (Stage 8): the UI is designed in design space; the renderer
scales primitives (scale+offset at rebuild). The dispatcher
converts screen coords into design space (toLocal) — hit-test and events
stay consistent.

---

## 8. Widget contract

Each widget is its own file widgets/<name>.lua. The contract:

    local Widget = require("core.widget")
    local Button = Widget:extend("Button")
    Button.properties = {
        text  = { default = "", invalidates = { DIRTY.RENDER } },
        color = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER } },
    }
    function Button:render(renderer)
        renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    end

A new widget is written **without changing** core/kernel — only through
existing interfaces.

### 8.1 Inheritance (Lua 5.1 prototype)

    Widget → Node
    Button → Widget

Simple prototype inheritance via setmetatable.

### 8.2 Composite widgets

A composite is logically one object for the user. Internally it owns
hidden child nodes (frame, title bar, close button...).

---

## 9. Style / Theme

    DXUI.setTheme(theme)
    button.style = "primary"

Style resolution (Stage 11):

1. **Build-time**: applyThemeDefaults applies
   theme[Class][style or "default"] to empty properties at mount time.
2. **Runtime**: applyStyle(name) or node.style = name recomputes
   values but **does not overwrite** fields explicitly set by the user
   (_userSet guard, ADR-004).

Parent style inheritance and state-driven style chains (hover/pressed/focused
as first-class styles) are **not implemented**; hover is handled via
mouseenter/mouseleave events inside the widget (dynamic hover color).

---

## 10. Resources

A single Resource Manager (resources/manager.lua) caches textures/fonts.
Ownership is global: resources live until releaseResources (resource stop);
node destroy does not touch them.

---

## 11. Text engine

The subsystem (text/text.lua, Stage 8):
- **measurement** — measuring (cache keyed by text+font+scale+wrap);
  outside MTA — monospace estimate (fallback for tests);
- **layout** — word-wrap, ellipsis, splitting on \n;
- **rendering** — align/valign via dxDrawText parameters.

**Edit** (Stage 11): multiline implemented, vertical navigation with goal column,
drag-select, clipboard (internal + MTA bridge), cursor/selection positioned via
Text.measure.

---

## 12. Animation

A centralized manager (animation/animation.lua): animate, easing
(linear/in/out), stop, isAnimating. Timeline chains (:after) —
not implemented in the current scope.

---

## 13. File structure (actual)

    dxui/
    ├── meta.xml
    ├── README.md
    ├── ARCHITECTURE.md
    ├── ROADMAP.md
    ├── docs/adr/
    │   ├── 001-aos-public-nodes.md
    │   ├── 002-named-dirty-categories.md
    │   ├── 003-efflayer-collect-time.md
    │   ├── 004-style-ownership-guards.md
    │   ├── 005-immediate-interactive-rebuild.md
    │   ├── 006-zindex-modal-reset.md
    │   ├── 007-export-getui.md
    │   ├── 008-state-matrix-theme.md
    │   ├── 009-property-validation-plugins.md
    │   ├── 010-widget-set-extension.md
    │   └── 011-listeners-translation-dnd.md
    ├── client/
    │   ├── init.lua          -- MTA event bridge (render/input/character)
    │   ├── export.lua        -- exports.dxui:getUI()
    │   ├── translation.lua   -- locales, setTextKey
    │   ├── api/
    │   │   ├── ui.lua        -- createContext, design resolution
    │   │   └── context.lua   -- Context: frames, layout, render lists, input passthrough
    │   ├── core/
    │   │   ├── node.lua      -- Node + property system (mutation layer)
    │   │   └── widget.lua    -- Widget: events, DnD, translation binding
    │   ├── input/
    │   │   ├── dispatcher.lua -- hover/focus/pressed/drag/modal/popup + key/text
    │   │   ├── events.lua     -- EventBus (bubble)
    │   │   └── hit_test.lua   -- AABB pick on the flat interactive list
    │   ├── layout/
    │   │   └── layout.lua     -- absolute/relative/center/stretch/autosize
    │   ├── render/
    │   │   ├── renderer.lua   -- primitives (rect/text/image/roundedRect/line)
    │   │   ├── render_list.lua
    │   │   ├── state.lua      -- state cache (blend mode dedup)
    │   │   ├── effects.lua    -- SDF rounded / blur / mask shaders, RT pool
    │   │   └── backend_mta.lua -- dxDraw* adapter (the only dx* entry point)
    │   ├── resources/
    │   │   └── manager.lua    -- texture/font/shader cache
    │   ├── animation/
    │   │   ├── animation.lua  -- tween manager + chains
    │   │   └── easing.lua
    │   ├── style/
    │   │   └── theme.lua      -- state-matrix theme
    │   ├── text/
    │   │   └── text.lua       -- measure / wrap / ellipsis
    │   ├── utils/
    │   │   └── color.lua
    │   └── widgets/
    │       ├── builders.lua   -- registerWidget + registrations
    │       ├── button.lua, checkbox.lua, combobox.lua, contextmenu.lua,
    │       ├── edit.lua, gridlist.lua, image.lua, label.lua, layout.lua,
    │       ├── line.lua, memo.lua, menu.lua, panel.lua, popup.lua,
    │       ├── progressbar.lua, radiobutton.lua, scalepane.lua,
    │       ├── scrollpanel.lua, selector.lua, slider.lua, switchbutton.lua,
    │       ├── tabpanel.lua, toggle.lua (base), tooltip.lua (setTooltip),
    │       └── window.lua
    └── tests/
        ├── run.py            -- python tests/run.py [test_name.lua ...]
        ├── loader.lua        -- loads all client modules (meta.xml order)
        ├── test_core.lua, test_input.lua, test_layout.lua, test_render.lua,
        ├── test_widgets.lua, test_advanced.lua, test_stage7b.lua,
        ├── test_stage8.lua, test_stage9.lua, test_stage10.lua,
        ├── test_stage11.lua, test_stage12.lua,
        └── test_m23.lua, test_m24.lua, test_m25.lua

---

## 14. What we carry over / redesign / remove

### Carry over (behavior + decisions)
- dirty invalidation (with readable names);
- zero-work idle;
- centralized input dispatcher;
- flat interactive list for hit-test;
- bubble event model (+ stopPropagation/preventDefault);
- data-driven animation (single tick);
- composite concept;
- layer architecture;
- modal focus lock / input trap;
- popup dismiss-on-outside-click.

### Redesign
- Node: SoA+slot+id → a readable object (AoS) + isolated runtime;
- property system: property-style added, single mutation layer;
- widget: one file per widget, contract;
- text: measurement/layout/render + font API + cache;
- style/theme: build-time defaults + runtime applyStyle with ownership guards;
- multi-context: createContext();
- layout: anchor/center/stretch/autosize + design resolution;
- opacity: 0..1 float;
- color: string/number/table at the property level.

### Remove
- 10+ makeXxxMt factories → a single inheritance mechanism;
- repeated destroy-overrides → a lifecycle contract;
- packed margin/padding bit-math → plain fields.

---

## 15. Performance target

The architecture is designed for **100–1000+ nodes** without degradation for
obvious reasons. Priorities (in order): readability → API quality → extensibility
→ predictable runtime → CPU → memory → GPU.

An idle frame = zero work: layout, render-list, and hit-test are
not recomputed without invalidation.

---

## 16. Review gate (Stage 6 → 7)

After core + renderer + input + layout + basic widgets — stop and
review: is Node, the API, lifecycle, rendering, widget addition understandable,
is the code readable. Only after it passes — advanced widgets.
