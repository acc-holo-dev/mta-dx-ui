# V2 Audit — DXUI (feeds the V3 rewrite)

Full audit delivered as the first PROMT.md response (kept here for reference).
Repo state audited: V2 **2.1.0** (client/ tree, 48 Lua files, ~7k lines) + one new widget `custom.lua`.
All old docs/tests/examples deleted from the working tree (still in git HEAD). `meta.xml` references
missing `README.md`/`ARCHITECTURE.md`.

## Verdicts in one line each

| Area | Verdict |
|---|---|
| Mutation layer `_set`, property+method convergence | KEEP (carried into V3 node.lua) |
| Named dirty categories | KEEP as flags, but CONSUME them (V3: category→frame-flag mapping) |
| Zero-work idle frame | KEEP (V2 already good) |
| Persistent render list + draw-only idle | KEEP concept |
| Renderer-primitive API; backend_mta only dx entry | KEEP (move the 2 dxGet* leaks into backend) |
| Central dispatcher, modal/popup stacks, drag capture | KEEP |
| Bubble events + stop/prevent | KEEP (+ add off, prod-safe isolation) |
| Central animation tick + chains | KEEP (+ richer easing) |
| owner guard (user/system/theme) | KEEP (V3 widget.lua) |
| Resource caches + false-marker failure caching | KEEP (+ theme asset ownership) |
| Text measure/wrap/ellipsis + bounded caches | KEEP |
| exports.dxui:getUI() per-resource | KEEP |
| Node:extend + registerWidget extensibility | KEEP |
| Theme (59-line state-matrix) | REWRITE into full engine (tokens/components/states/transitions/fallback/live switch) |
| Layout single-pass | REWRITE into two-pass measure/layout + flex |
| Dirty granularity (full collect+2 sorts on any change) | REWRITE (content-scoped consumption, screen culling) |
| Hit-test O(scene) + drag staleness | REWRITE (buckets by layer, current-worldX) |
| Widget parts as ad-hoc rawset internals | REWRITE (real Parts, §14-17) |
| Global design resolution | REWRITE (per-instance) |
| meta.xml 53-script manifest, missing files | REPLACE for V3 |
| Node backdoors (arbitrary __newindex fields, silent prop skips) | REWRITE (explicit, dev-loud) |
| Global-load-order wiring | REPLACE (docs-only ordering; late binding only across subsystems) |

## Top problems fixed in V3 (ranked)
1. Any dirty node → full scene rebuild + 2 full sorts (typing in one Edit rebuilds everything).
2. Per-rebuild allocation churn (item tables, clip tables, fx clones).
3. O(scene) hit-test per move; one-frame worldX staleness during drag.
4. No screen culling / virtualization (GridList renders all rows).
5. Theme is a 59-line stub; no default theme installed; no tokens/parts/states/transitions.
6. Parts inconsistent: real nodes (close button/scrollbars) vs render-drawn (slider thumb/title bar).
7. Global design resolution; per-context impossible.
8. Node metatable: dead `_hasDirty`, fictional "updated" lifecycle, `props.children` warn noise.
9. Events: no `off`, prod listener errors break the frame.
10. Repo not in §63 shape (missing referenced files, version 2.1.0, deleted tests/docs still referenced).

## V3 decisions (locked in readme/ai/002-v3-contracts.md)
Structure per §62 (`source/client/…` + `readme/{ai,documents,examples,tests}` + root meta/README).
Deviations (recorded): `api/exports.lua`+`api/runtime.lua` split; `render/pass.lua`; `style/defaults.lua`;
`core/values.lua`; `core/part.lua`; `layout/{dimension,flex}.lua`. Reason: contract-driven separation,
ships a default theme, single RenderPass home for RT-groups.