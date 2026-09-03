# Changelog

All notable changes to DXUI are documented here. Versions follow
[major].[minor].[patch]; the resource manifest (`meta.xml`) is the source
of truth for the current version.

## [4.0.0] — 2026-09-01

V4 is a **breaking release** — see `README.md` → *Migration V3 → V4* for
the full list of renames and behaviour changes.

### Added
- **Settings V4** — `source/settings.lua`: every key is consumed by the
  engine (default theme, caret blink, frame priority, culling, hit-test
  cap, auto-release). `DXUI.applySettings(t)` merges overrides at any time.
- **Translate V4** — per-resource locale tables (`ui:addLocale`), the
  `textKey` property + `setTextKey(key, prop)`, per-UI locale
  (`ui:setLocale`), fallback chain (`ru-RU` → `ru` → key), `%1..%N`
  substitution, live re-translation on switch and on mount.
- **Theme V4** — real `extends` (deep merge), 9 built-in themes
  (light/dark/green × normal/compact/full), `ui:defineTheme` /
  `ui:setTheme(name|table)`, asset prefixes (`texture:`, `font:path:size`),
  opt-in state transitions, live re-apply to every mounted widget
  (mount-fix included).
- **Edit V4** — caret modes (blink/solid/off), caret overlay (frame-clock
  repaint, zero-work idle preserved), click-to-position caret, shift
  selection, `maxLength`/`readOnly`/`masked`, alignment,
  `placeholderVisibleWhenFocused`.
- **Window V4** — `draggable` header drag (clamped on-screen), themable
  `closeButton` part (click → `"close"`), mid-stack modal close fix.
- **Render V4** — one shared SDF rounded-rect shader (per-corner radii,
  border + fill in a single draw, 1px AA), square corners decompose to
  plain rects, `borderWidth` as a property.
- Registry-synthesized widget factories (`ui:radiogroup()` appeared).
- `documents/` local wiki (static HTML, reflects live engine specs via
  `documents/gen.lua`), `readme/ARCHITECTURE.md`, `readme/CODE_STYLE.md`.

### Changed
- `DXUI.EASING` → `DXUI.Easing`.
- Key event second param `pressed2` → `isDown` (shift modifier appended
  by `init.lua`).
- `drawRoundedRect` new signature; render-list `rrect` items carry
  per-corner radii + border fields.
- Removed dead API: `DXUI.Values`, `Part.themeRole`, `Part.replace`
  (use `node:setPart`), `Effects.round`, `Effects.whiteTexture`,
  `Renderer.resolveEffect`.

### Deprecated
- None.

### Removed
- Built-in theme `"default"` → renamed to `"light"`
  (`Settings.defaultTheme` default).

### Fixed
- `visible` now also invalidates the input set (hidden interactive nodes
  leave the hit-test list).
- `DXUI.setRenderPriority` re-registers the frame loop; wheel falls back
  to the screen center when the cursor is disabled.
- `Node:on` now flags `interactiveDirty` when attaching a handler turns a
  previously non-interactive node clickable.
- Human-readable dimensions (`"50%"`, `"auto"`, `"fill"`, numbers) are
  compiled for `layoutWidth`/`layoutHeight` (previously only the
  `ui:percent/auto/fill()` objects worked).
- `Tooltip:showAt` treats coordinates as world (matching `Tooltip:refresh`).
- `GridList` wheel scroll no longer drifts when the content fits.
- `settings.lua` no longer depends on `node.lua` having loaded before
  `applySettings` runs.

### Security
- None.
