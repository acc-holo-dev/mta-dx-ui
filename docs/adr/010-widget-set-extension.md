# ADR-010: Widget Set Extension (M24)

## Context
Missing widgets from the DGS comparison: memo, menu, selector, switchbutton,
layout, scalepane, line.

## Decision
Implemented in priority order. Notes:
- memo extends Label (wrap + wheel-scroll + clip).
- menu / selector are item-row composites (click → `select` event).
- switchbutton extends Toggle (track + knob, rounded rects).
- line draws `dxDrawLine` with thickness (renderer/state/backend extended).
- layout: class **LayoutBox** (registered as `ui:layout`) because
  `DXUI.Layout` is the layout subsystem.
- scalepane scales its whole subtree via an RT group (clipMode="rt"): children
  render into an offscreen RT at 1x, the RT quad is drawn stretched by
  scaleX/scaleY (rtgroup item carries scale factors; state cache stretches).

## Consequences
+ Each new widget reuses existing subsystems (text engine, RT groups, builder
  registry) — no pipeline forks except the small RT-scale extension.
+ ScalePane hit-testing is only accurate at scale == 1 (documented).

## Status
Accepted, implemented.
