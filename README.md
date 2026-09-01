# DXUI — V3

Retained-mode UI framework for **MTA:SA** (Lua 5.1 / DirectX 9): widgets,
a real theme engine, pooled rendering and headless tests.

## Quick start (MTA resource)

1. Add this resource to your server, then declare it as a client dependency
   of your resource (`<include resource="dxui" />`). The engine exports
   `getUI` (see `meta.xml`).
2. In your client script:

```lua
local ui = exports.dxui:getUI("app", { design = { width = 800, height = 600 } })

local win = ui:window({ title = "Hello", x = 0.3, y = 0.3, width = 200, height = 120 })
ui:add(win)
win:container():addChild(ui:button({ x = 10, y = 10, width = 90, height = 28, text = "OK" }))
```

That's the whole setup: the engine owns the frame loop, input glue, viewport
mapping (`guiGetScreenSize`), and per-resource cleanup. Each consumer
resource gets its own UI instance (keyed by its resource root), released
automatically when that resource stops.

## Feature highlights

- **Widgets** — panel, label (wrap/ellipsis), button, image, window,
  checkbox, radiobutton (+group), progressbar, slider, scrollpanel, edit,
  combobox, tabpanel, gridlist, popup, contextmenu, modal, tooltip.
- **Theme system** — design tokens (`@color.accent`), named themes,
  component styles, variants (`node.style`) and states (hover/pressed/
  focused/selected/disabled); compiled once per (theme, component,
  styleKey); swappable at runtime (`DXUI.Theme.activate`).
- **Layout** — two-pass resolve, `px`/`pct`/`auto`/`fill` dimensions,
  relative (fractional) and absolute modes, flex rows/columns,
  auto-sized content widgets.
- **Performance** — one mutation layer with owner guards; category dirty
  flags; a persistent pooled paint list (idle frames = zero rebuild, not
  zero draws); screen culling; RT groups only for clip/mask/blur.
- **Input** — bubbling events, hover/focus/pressed/drag/modal/popup
  dispatcher, screen→design mapping.
- **Diagnostics** — `DXUI.Diagnostics.{snapshot, describe, report,
  idleRatio, enableZeroWork}` — the idle contract is assert-tested.
- **Testability** — the whole engine runs under lupa with a table backend;
  `python readme/tests/run.py` → **260 assertions, 0 failed**.

## Bootstrap vs. roll-your-own

`DXUI.bootstrap(opts)` is the all-in-one MTA entry (init.lua). If you drive
the frame loop yourself, call `ui:tick()` every `onClientRender` and feed
the dispatcher via `ui:mouseMove/mouseDown/mouseUp/scroll/key`.

## Documentation

| doc | what |
|-----|------|
| [`readme/documents/ARCHITECTURE.md`](readme/documents/ARCHITECTURE.md) | full V3 architecture map + decisions |
| [`readme/documents/ADR.md`](readme/documents/ADR.md) | architecture decision records (ADR-001…009) |
| [`readme/documents/CODE_STYLE.md`](readme/documents/CODE_STYLE.md) | unified code comment style |
| [`readme/examples/demo.lua`](readme/examples/demo.lua) | runnable usage example |
| [`readme/tests/`](readme/tests/) | headless test runner + suites |
| [`readme/ai/001-v2-audit.md`](readme/ai/001-v2-audit.md) | V2 audit that motivated the rewrite |
| [`readme/ai/002-v3-contracts.md`](readme/ai/002-v3-contracts.md) | locked V3 contracts |
| [`readme/ai/003-v3-verification.md`](readme/ai/003-v3-verification.md) | implementation log + change log |

The engine lives in `source/client/`; `meta.xml` is the MTA manifest.