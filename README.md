# DXUI V2 — MTA:SA UI Framework (Lua 5.1)

DXUI is a client-side UI library for MTA:SA (Multi Theft Auto: San Andreas):
a retained-mode widget tree with a dirty-driven render pipeline, a
state-matrix theme system, and a plugin API. Rewritten from legacy with a
readable, extensible, testable core.

## Quick start

    local ui = DXUI.createContext()          -- or: exports.dxui:getUI()
    ui:setScreenSize(1280, 720)

    local btn = ui:button({ x = 100, y = 100, text = "Click me" })
    btn:on("click", function()
        print("clicked!")
    end)

> Rendering and input are bridged automatically: the resource's init.lua
> renders every live context in `onClientRender` and forwards cursor/click/
> key/character events. Do NOT add your own `onClientRender` loop on top
> (it would draw twice). Mouse events need a visible cursor
> (`showCursor(true)`) — the framework never changes cursor state itself.
> Running a standalone copy without init.lua? Then render manually:
> `addEventHandler("onClientRender", root, function() ui:renderFrame() end)`.

## Cross-resource use (M21)

    local ui = exports.dxui:getUI()          -- per-resource cached Context
    local w = ui:window({ title = "Hello", draggable = true, modal = true })

> Note: calling getUI at resource start may misbehave — use setTimer.

## Architecture (short)

- **AoS Node** — public API is plain Lua tables (node.x, node.width, node.color).
- **Property system** — __newindex/__index converge in one `_set()` that
  validates (type + min/max, see M23) and invalidates subsystems.
- **Dirty categories** — named flags (LAYOUT, RENDER, INPUT, STYLE, CHILDREN,
  VISIBILITY); idle frames do zero work.
- **Flat lists** — interactive/render lists are derived on demand, the tree is
  not walked every frame.
- **State matrix** — theme { Class = { default = { ..., hover/pressed/focused/
  disabled = {...} } } } with priority disabled > pressed > hover > focused >
  normal; `_userSet` guards manual properties (M22).
- **Isolated contexts** — each createContext() is an independent world.

## Structure

    .
    ├── client/
    │   ├── api/          -- Context, UI coordinator, export (getUI)
    │   ├── core/         -- Node, Widget (property system, lifecycle, DnD)
    │   ├── input/        -- Dispatcher, hit-test, events
    │   ├── layout/       -- absolute/relative/anchor/center/stretch/autosize
    │   ├── render/       -- Renderer, RenderList, state cache, RT groups, backend
    │   ├── resources/    -- Texture/font/shader cache
    │   ├── animation/    -- Tween manager + easing
    │   ├── style/        -- Theme, applyThemeDefaults, applyStyle
    │   ├── text/         -- Text.measure, wrap, ellipsis
    │   ├── utils/        -- color resolution
    │   ├── widgets/      -- 23 widgets + builders registry
    │   ├── translation.lua -- locales, setTextKey
    │   └── export.lua    -- exports.dxui:getUI()
    ├── tests/            -- Python + lupa (Lua 5.1) suite, 15 files (419 asserts)
    ├── examples/         -- demo resource (consumer-style, exports.dxui:getUI())
    ├── docs/adr/         -- Architecture Decision Records (001–011)
    ├── docs/             -- RELEASE-REPORT.md (audit + release prep)
    ├── ROADMAP.md        -- milestone plan M21–M25
    ├── ARCHITECTURE.md   -- full architecture description
    └── meta.xml          -- MTA resource manifest

## Widgets (23)

Registered widgets: panel, label, image, button, checkbox, radiobutton,
switchbutton, slider, progressbar, edit, memo, scrollpanel, gridlist,
tabpanel, combobox, contextmenu, menu, selector, popup, window, layout
(LayoutBox), scalepane, line.

`toggle` is an internal base class of checkbox/radiobutton (not registered),
and tooltips are a node method, not a widget:

    btn:setTooltip("Help text")

## Plugins (M23)

    -- custom widget: class with .build(context, props) + render(renderer)
    DXUI.registerWidget("mywidget", MyWidget)
    local w = ui:mywidget({ ... })          -- context builder
    local c = host:mywidget({ ... })        -- parent-scoped builder

    DXUI.registerEffect("vignette", function(node) return { shader = s, params = {...} } end)
    local img = ui:image({ effect = "vignette", ... })

## Translation (M25)

    DXUI.addLocale("ru", { ["menu.open"] = "Открыть" })
    DXUI.setLocale("ru")
    label:setTextKey("menu.open")           -- label.text = "Открыть"

## Drag & drop (M25)

    src:setDraggable(true):setDragData({ item = "X" })
    tgt:setDropTarget(true)
    tgt:on("drop", function(e) print(e.node, e.data.item) end)

## Widget contract

To add a widget:

1. Create `client/widgets/mywidget.lua`
2. Describe properties with defaults and invalidates (validation optional)
3. Implement `:render(renderer)`
4. Register via `DXUI.registerWidget("mywidget", MyWidget)` (builders.lua)

Details: see ARCHITECTURE.md (the Widget contract section).

## Tests

Tests use Python + lupa (embedded Lua 5.1) with a mock backend:

    python tests/run.py          # all 15 test files
    python tests/run.py test_m25.lua

Coverage: core (lifecycle, properties, dirty), input (dispatcher, hit-test,
focus, events, drag), layout (anchors, stretch, autosize), render (primitives,
clip, state cache, RT groups), widgets, animation, style, translation,
validation, plugins.

## License

MIT (keep attribution on forks).
