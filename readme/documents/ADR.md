# DXUI V3 — Architecture Decision Records

Short decision log for the V3 rewrite. Each entry: context, decision,
consequences (what we gave up / gained).

---

## ADR-001 — Retained mode with a pooled paint list

**Context.** MTA:SA DX drawing is immediate-mode and expensive per call;
naive per-frame widget iteration allocates and re-sorts constantly.

**Decision.** Widgets declare state; `Runtime:tick()` rebuilds a persistent
FLAT item list only when dirty flags say so, and `draw()` paints that cached
list every frame. Rebuild sorts by `(effLayer, zIndex, id)` once.

**Consequences.** Idle frames are O(draws), not O(tree). Gains: predictable
frame cost, easy stats. Costs: mutations must invalidate correctly (dirty
category system), and any node edit must go through `_set`.

---

## ADR-002 — One mutation layer with owner bookkeeping

**Context.** Theme application, engine sizing and user scripts all write the
same properties; we must never clobber a user's explicit value with a theme
default (or with an engine-computed size).

**Decision.** `Node:_set(key, value, owner)` with owners `user` / `theme` /
`system`. Theme writes record `_themeApplied[key]`; any non-theme write
revokes it; style apply skips user/system-owned props.

**Consequences.** Deterministic precedence: user > system > theme > class
default. Costs: every write path must declare its owner (enforced at the
API boundary).

---

## ADR-003 — Theme as compiled maps, resolved once

**Context.** V2 resolved tokens inside render; V3 needs theme switches at
runtime without per-frame token chasing.

**Decision.** `Theme.compile → { props, states }` per (theme, component,
styleKey), cached; components use the variant chain
`node.style > component base > fallback theme > class defaults`; tokens
resolve iteratively with depth cap + cycle guard (always terminates).

**Consequences.** switch/apply = plain table reads. Costs: edits to theme
tables need `Theme.activate()` (or cache clear) to take effect — documented
cold path.

---

## ADR-004 — Dirty flags by category, not by node

**Context.** Fine-grained per-node dirty lists kept V2 correct but slow and
leaky (missed invalidations = stale UI).

**Decision.** Nodes invalidate by CATEGORY (layout/render/order/interactive);
the instance folds them into four booleans. `tick()`'s zero-work assertion
(enabled via Diagnostics) proves no pass runs without its flag.

**Consequences.** Simpler and leak-proof; slightly more work per mutation
than the theoretical minimum. Tests pin "idle = zero rebuilds".

---

## ADR-005 — Widgets are plain registered extensions, not core

**Context.** V2 grew widget code into the core loop; the theme/state/render
contracts were implicit.

**Decision.** A widget is `Widget:extend` + `Builders.register + a declared
prop spec + optional `_build` / `_measureContent` / `render`. Core never
mentions a widget; the kernel (node/layout/render/input) is agnostic.

**Consequences.** Adding a widget touches one file. Guarantees: every widget
inherits owner guards, dirty flags, states, themes and diagnostics.

---

## ADR-006 — Content-sized widgets measure via their own autoSize contract

**Context.** Labels, checkbox rows and tooltips need intrinsic sizes, but
auto-measure must never override an explicit `width`/`height` or a
`layoutWidth/layoutHeight` dimension.

**Decision.** `autoSize = true` by default on content widgets; layout
`resolveSize` measures only a *free* dimension (no explicit owner AND raw
value nil/0). Explicit props and layout dims win; engine writes resolved
sizes back as `system`.

**Consequences.** `ui:label{text="…"}` sizes itself; `width=40` is honored
for wrapping. Costs: none observed — the rule is stated once in
`layout.lua` and pinned by tests.

---

## ADR-007 — MTA isolation: one glue module, injectable backend

**Context.** Testing requires running the engine without MTA; V2 mixed
`dx*` calls into widgets.

**Decision.** All MTA-only code lives in `init.lua` (bootstrap + events)
and `render/backend_mta.lua` (dx* calls). `Runtime.backend` and the text
measurer are injectable; the test suite runs the full engine under lupa
with a table backend (fake MTA for the boot suite).

**Consequences.** The whole framework is verifiable headless (126
assertions, see readme/tests). Costs: two small adapters.

---

## ADR-008 — Stats first; zero-work is a testable contract

**Context.** “Fast idle frames” was a V2 claim, not a measured property.

**Decision.** `Runtime.stats` (frames/layoutRuns/rebuilds/hitRebuilds/
items/draws) accumulates ALWAYS; `Diagnostics.enableZeroWork` turns the
idle contract into asserts inside `tick()`; `idleRatio` reports it.

**Consequences.** Perf regressions fail tests. Costs: two counters and an
optional assert branch per frame.

---

## ADR-009 — Screen culling, RT groups only where needed

**Context.** Post-V2 measurements (hypothesis) point at overdraw and RT
switches as the main cost.

**Decision.** Items fully outside the viewport are dropped at collect time
(settings.performance.screenCulling, on by default). Render-target groups
exist ONLY for `clipMode="rt"`, blur and mask; plain clipped content uses
the cheaper transform-free path.

**Consequences.** Off-screen panels cost nothing to paint. Costs: culling
needs the viewport mapped before collect (done by tick pipeline).

---

*Log: all decisions above ratified during the V3 rewrite (rounds 1–7).*
*Change log for the implementation itself: readme/ai/003-v3-verification.md.*