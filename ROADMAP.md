# DXUI v2 Roadmap (M21–M25)

> Working plan. Locked decisions from the planning session. Follow this, not the chat.

Status: **ALL MILESTONES DONE** — code (M21–M25), tests (15 files, ~380 asserts, green on Lua 5.1 via lupa),
docs (README, ARCHITECTURE translated; ADR-007..011 added), comment rework (all ~64 .lua files → concise
English, §-references removed, 0 syntax errors, tests still green). Optional leftovers: translate the 6
legacy ADRs (001–006) and an examples/ folder (short demo was deleted by decision #3).

## Locked decisions (all implemented)
- Single codebase: v2 promoted to repo root. Resource name "dxui". DELETE v1 (done).
- Keep v2: docs/adr/ (6 ADRs), tests/ (v2 + new test_m23/24/25).
- Export (M21): Variant A — exports.dxui:getUI() per-resource cached Context. ⚠ OPEN: verify in MTA that
  tables pass by reference cross-resource (fallback: numeric handle + flat functions); first getUI call
  preferably via setTimer (MTA wiki note).
- Style (M22): state-matrix theme; setTheme re-applies; shared textures/fonts (manager dedup). Deferred: packs.
- Property (M23): type + min/max + transform in spec, validator cached.
- Plugins (M23): DXUI.registerWidget(name, class) + DXUI.registerEffect(name, fn) + named "effect" property.
- Widgets (M24): memo, menu, selector, switchbutton, line (thickness), layout (LayoutBox), scalepane (RT scale).
- M25: Node:onProperty/offProperty, translation (addLocale/setLocale/tr/setTextKey), drag&drop
  (setDraggable/setDropTarget/setDragData; dragenter/dragleave/drop/dragend). No custom cursor.
- Comments: English, brief, no §-refs — DONE across the whole tree (subagent fan-out + verification).

## Milestones
0. Cleanup ✅   1. M21 Export ✅   2. M22 Style ✅   3. M23 Property+Plugins ✅
4. M24 Widgets ✅   5. M25 Events/Translation/DnD ✅   6. Final (tests ✅ ADR ✅ wiki ✅ comments ✅)
