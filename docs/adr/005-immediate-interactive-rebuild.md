# ADR-005: Immediate Interactive List Rebuild on Node Destroy

## Context
When a node was destroyed, the interactiveList was rebuilt only via the dirty flag in the next frame. If events (mousedown) fired between destroy and the next renderFrame, the destroyed node with nil width/height stayed in the list, breaking hit-test (arithmetic on nil).

## Decision
Context:_onNodeDestroyed() immediately calls self:_rebuildInteractiveList(). This guarantees that interactiveList is always consistent with the live tree.

## Consequences
+ Stale entries in interactiveList are eliminated.
+ Hit-test no longer fails on destroyed nodes.
− O(N) rebuild on every destroy (cold path, acceptable).

## Status
Accepted, implemented.
