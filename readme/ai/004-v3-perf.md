# V4 perf — measured performance contract (round 8)

Measured headless via `readme/tests/run.py perf` (lupa, table backend, no
MTA). The engine's performance strategy is described in §67–69 terms in
ARCHITECTURE.md; this file records the numbers the contract guarantees.

## Benchmark rig

A composite UI (~160 nodes): a window with 8 rows of
(label + button + slider + progressbar + checkbox), a 30-row gridlist, a
3-page tabpanel, and a 40-row scrollpanel. Design 1280×720, stretch
mapping; `Diagnostics.enableZeroWork(ui, true)` is active for the whole
run — EVERY idle tick asserts that no layout/rebuild happens.

## Results (smoke_perf, current engine)

```
items=159  draws/frame~=166        (≈1.04 back-end calls per item:
                                   rectangles + text + fills)
layoutRuns=3 rebuilds=5 hitRebuilds=3  across 68 frames
idleRatio=0.882                    (includes the 5 dirty frames;
                                   the 60-frame idle block alone ≈ 0.93+)
```

## What the contract pins (asserts, not claims)

| scenario | observed | contract |
|----------|----------|----------|
| 60 idle frames | 0 layout runs, 0 rebuilds, 0 interactive rebuilds | idle frame = ZERO work (list is painted, not rebuilt) |
| one `addChild` | exactly 1 layout + 1 rebuild, next frame idle again | mutation cost = its category, exactly once |
| slider `value` write | 1 rebuild, 0 layout | render-only writes don't re-layout |
| label `text` write | 1 rebuild, 1 layout | text invalidates layout + render |
| pointer moves (2) | 0 any rebuild | input never dirties the paint pipe (hit-test scans the cached interactive list) |
| theme switch | 1 rebuild, 0 layout | style re-apply is a paint-level change |
| 159 items | ~166 draws/frame | painting the cached list every frame |

## Notes / interpretation

- `draws/frame ≈ items + 7` — window chrome (header/surface/shadow) and
  slider (track+thumb) legitimately emit a few extra items; there is NO
  per-frame collection, sorting or allocation (pooled flat list).
- idleRatio < 1 is EXPECTED on a changing scene; what matters is that every
  dirty frame does exactly its category's work and idle frames do none —
  the asserts prove it per frame.
- The MTA backend adds only dx* calls and blend-state dedup (state.lua);
  headless numbers transfer as upper bounds of work, and
  `Diagnostics.idleRatio` lets a running resource measure ITS frames.

## How to re-measure

```bash
python readme/tests/run.py perf
```

or in-game: `print(DXUI.Diagnostics.report(ui))` every second.