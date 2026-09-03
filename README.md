# DXUI — V4

Retained-mode UI framework for **MTA:SA** (Lua 5.1 / DirectX 9): a full
widget library, a real theme engine, live translations, pooled
retained-mode rendering and a headless assert-locked test suite.

## Quick start

1. Add the `dxui` resource to your server, start it, and declare it in
   your resource:

   ```xml
   <include resource="dxui" />
   ```

2. In your client script — that is the ENTIRE setup:

```lua
local ui = exports.dxui:getUI("app", { design = { width = 800, height = 600 } })

local win = ui:window({ title = "Hello", x = 40, y = 40, width = 360, height = 300 })
ui:add(win)
win:on("close", function(n) n.visible = false end)
win:container():addChild(ui:button({ x = 10, y = 10, width = 100, height = 28, text = "OK" }))
```

The engine owns the frame loop, the input glue, the design→screen mapping
and per-resource cleanup. A runnable showcase lives in
[`demo/`](demo/).

## Deploy

The **repository root is the engine resource** — there is no nested
`dxui/` folder. Copy the whole repository folder into your server's
`resources/` and name that folder **`dxui`**: MTA treats the folder name
as the resource name, and everything here (`exports.dxui`,
`<include resource="dxui">`) expects exactly that name. Then start
`dxui`, and start `demo` alongside it for the showcase.

## Feature highlights

- **Widgets** — panel, label, button, image, window (draggable header,
  close button), checkbox, radiobutton + group, progressbar, slider,
  scrollpanel, edit, combobox, tabpanel, gridlist, popup, contextmenu,
  modal, tooltip.
- **Edit V4** — caret modes (blink/solid/off), shift-selection,
  maxLength/readOnly/masked, alignment, placeholder that hides on focus;
  the caret is a per-frame overlay — blinking never invalidates the
  render cache.
- **Themes** — design tokens, 9 built-in themes (light/dark/green ×
  normal/compact/full), custom themes with `extends` from ANY resource,
  per-state styles with opt-in transitions, live switching.
- **Translate** — per-resource locale tables, `setTextKey` bindings,
  live locale switching (`ui:setLocale`), `%1..%N` substitution.
- **Settings** — every key consumed by the engine; default theme,
  caret blink interval, frame priority, culling, hit-test caps.
- **Performance** — one mutation layer with ownership guards; category
  dirty flags; persistent pooled paint list (idle frames = zero
  rebuild/layout/hit-rebuild work — assert-locked); screen culling; one
  shared SDF rounded-rect shader (border + fill in a single draw,
  per-corner radii).
- **Input** — bubbling events, hover/focus/press/drag/modal/popup
  dispatcher, click-to-position caret editing, clamped window drag.
- **Testability** — the whole engine runs headless under a table
  backend; the demo resource is executed end-to-end by the suite.

## Documentation

| doc | what |
|-----|------|
| [`documents/`](documents/) | **local wiki site** — open `documents/index.html` in a browser; every method documented (what it takes, what it returns); widget property tables are reflected from the live engine specs by `documents/gen.lua` |
| [`readme/ARCHITECTURE.md`](readme/ARCHITECTURE.md) | layer map, frame pipeline, invariants, file responsibilities |
| [`readme/CODE_STYLE.md`](readme/CODE_STYLE.md) | LuaCATS doc conventions, formatting, naming |
| [`demo/`](demo/) | standalone showcase resource (public API only) |

## Migration V3 → V4

V4 is a breaking release. The full change list:

- **Edit**: `cursor` property renamed to **`caret`**; new `caretWidth`,
  `caretMode` ("blink"|"solid"|"off"), `caretBlinkInterval`,
  `selectionFrom`/`selectionColor`, `alignment`, `maxLength`,
  `readOnly`, `masked`/`maskChar`, `placeholderVisibleWhenFocused`.
  Click positions the caret (was: focus always moved it to the end).
  Escape blurs; Enter submits keeping focus; Delete added; overflow
  scrolls to keep the caret visible.
- **Naming**: `DXUI.EASING` → **`DXUI.Easing`**; the key event's second
  parameter `pressed2` → **`isDown`** (init.lua appends the shift
  modifier); removed dead API: `DXUI.Values`, `Part.themeRole`,
  `Part.replace` (use `node:setPart`).
- **Themes**: built-in theme `"default"` renamed to **`"light"`**
  (`Settings.defaultTheme` default); 9 built-ins via density presets
  (`dark-compact`, `green-full`, ...); `ui:defineTheme` /
  `ui:setTheme(name|table)`; themed components may carry asset prefixes
  and opt-in `transition` blocks.
- **Factories**: `ui:<widget>()` factories are synthesized from the
  widget registry — every registered class gains one automatically
  (`ui:radiogroup()` appeared); the hardcoded list is gone.
- **Window**: new `closeButton` part + `closeButtonVisible` (click emits
  `"close"`); the header drags the window (clamped on-screen, `draggable`
  gates); pages of a TabPanel parent to the content part.
- **Render**: `drawRoundedRect(x, y, w, h, rtl, rtr, rbr, rbl, fill,
  border, borderWidth)` (new signature); render-list `rrect` items carry
  per-corner radii + border fields; removed `Effects.round`,
  `Effects.whiteTexture`, the renderer's `resolveEffect`.
- **Runtime**: `visible` now invalidates the input set too (hidden
  interactive nodes leave the hit-test list); `DXUI.setRenderPriority`
  re-registers the frame loop; the wheel falls back to the screen center
  when the cursor is disabled.
- **Comments**: source documentation is LuaCATS-only
  ([`readme/CODE_STYLE.md`](readme/CODE_STYLE.md)).

## Building & verifying

DXUI is pure Lua 5.1 — no compilation step is needed to deploy it. To
verify a change (any Lua 5.1 interpreter works):

- **Syntax gate.** Every file must parse as Lua 5.1:
  `luac -p source/settings.lua && luac -p source/client/core/node.lua`
  (repeat for every `source/`, `demo/` and `documents/gen.lua` file).
- **Wiki regeneration.** `lua documents/gen.lua` loads the whole engine
  headless (meta.xml order, no MTA backend), reflects the live widget
  specs and rewrites `documents/`. Keep the regenerated files in your
  commit.
- **Engine load smoke.** Running `documents/gen.lua` at all proves the
  engine boots headless (the same guarantee the owner's test suite
  asserts). CI runs the syntax gate, this engine load and a wiki-freshness
  check on every push.

The full test suite (`tests/`) is maintained locally by the owner and not
shipped (see PROMT.md) — CI covers what is reproducible from a clean
checkout.

## Repository layout

```
source/          the engine (meta.xml order = dependency order)
demo/            standalone showcase resource
documents/       local wiki site (+ gen.lua, regenerated from the engine)
readme/          ARCHITECTURE + CODE_STYLE
CHANGELOG.md     version history
tests/           headless suites + notes (owner-local; gitignored, not shipped)
```