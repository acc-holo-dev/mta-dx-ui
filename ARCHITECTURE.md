# Architecture (V3) — entry

DXUI V3 is a retained-mode, two-pass-layout, pooled-render UI framework for
MTA:SA. The full map lives in [`readme/documents/ARCHITECTURE.md`](readme/documents/ARCHITECTURE.md);
the short version:

```
settings.lua → core/ (values node widget part)
              → translation, text/
              → style/ (tokens theme defaults)
              → animation/, resources/
              → layout/  render/  input/
              → api/ (runtime ui exports diagnostics)
              → widgets/  → init.lua (MTA glue, LAST)
```

**Key contracts** (each a testable property, pinned by readme/tests):

1. One mutation layer: `Node:_set(key, value, owner)` — owners
   `user / theme / system`; theme writes are revoked by any other owner;
   style apply never overwrites a user/system property.
2. Category dirty flags (layout/render/order/interactive) folded into four
   booleans; `tick()` runs each pass only when its flag is set — verified by
   the optional zero-work assertion in `Diagnostics`.
3. Persistent pooled paint list rebuilt only on dirty; painting is cached
   every frame (idle = zero rebuild, not zero draws). Sort on rebuild:
   `(effLayer, zIndex, id)`.
4. Theme = compiled maps per (theme, component, styleKey); chain
   `node.style variant > component base > fallback theme > class defaults`;
   tokens resolve iteratively with cycle guard; `activate()` re-applies to
   all mounted trees.
5. Layout: one shared `_measureContent()` per node; `autoSize` measures only
   FREE dimensions (no explicit owner + nil/0 raw) — props always win;
   engine sizes are `_set(...,"system")` with a same-value guard.
6. Input: bubbling events (snapshot per level, `DXUI.STOP`), flag-based
   hit-testing, dispatcher owning hover/focus/pressed/drag/modal/popups;
   click emits `(button, x, y, origin)`.
7. MTA isolation: only `init.lua` (bootstrap + events) and
   `render/backend_mta.lua` touch MTA; backend + text measurer injectable.

Design decisions are recorded in [`readme/documents/ADR.md`](readme/documents/ADR.md).
The `readme/ai/` docs describe the rewrite process itself.