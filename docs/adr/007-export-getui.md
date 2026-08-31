# ADR-007: Cross-Resource Export — getUI() Shared Context (M21)

## Context
External resources need UI built on dxui. MTA supports client exports with
hidden variables sourceResource / sourceResourceRoot. Two designs were possible:
(A) return the live Context table; (B) return a numeric handle + flat functions.

## Decision
Variant A: `exports.dxui:getUI()` returns the calling resource's default
Context, created lazily and cached per resource (`contextsByResource`), so a
resource's widgets are isolated and cleaned up on resource stop
(`onClientResourceStop` → `ctx:destroy()`). The render loop stays inside dxui.

## Consequences
+ Natural API: `local ui = exports.dxui:getUI()`, then `ui:button(...)`.
+ Per-resource isolation and cleanup (Lua tables are not GC'd on resource stop).
− Depends on MTA passing tables by reference between resources (EMPIRICAL, must
  be verified; fallback is Variant B with numeric handles).
− `getUI` called at resource start may misbehave — use setTimer (MTA wiki).

## Status
Accepted, implemented (verification in MTA pending).
