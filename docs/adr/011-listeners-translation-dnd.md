# ADR-011: Property Listeners, Translation, Drag & Drop (M25)

## Context
Remaining DGS-derived features: reacting to property changes, localization, and
generic drag & drop. Custom cursor was dropped (decision #11).

## Decision
1) Property listeners: `Node:onProperty(key, fn)` / `offProperty`; fired from
   `Node._set` with (value, old, node) after the change, before the spec
   onSet hook. Fire for ANY write (props, theme, animation).
2) Translation: `translation.lua` — `addLocale/setLocale/tr(key, ...)` with
   %1..%N substitution, and `Widget:setTextKey(key, target)` binding a text
   property to a key; bound nodes re-apply on locale switch (weak registry).
3) Drag & drop: `Widget:setDraggable/setDropTarget/setDragData`. Drag starts
   on mousedown (dispatcher capture, like window title bars); the dispatcher
   tracks drop targets under the cursor (dragenter/dragleave) and on release
   emits `drop` on the target ({node, data, x, y}) and `dragend` on the
   source ({dropTarget}).

## Consequences
+ Property listeners cover themes/animations uniformly; event field `target`
  stays reserved for the event origin (payload uses `dropTarget`).
+ Translation is a registry, not per-widget copy — setLocale() re-translates.
+ Drag & drop reuses the existing capture pipeline; no new event loops.

## Status
Accepted, implemented.
