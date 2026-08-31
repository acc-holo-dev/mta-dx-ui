# ADR-006: zIndex Reset on Modal Disable

## Context
Window:setModal(true) set node.zIndex = 1 to raise the window above the overlay inside the MODAL layer. When setModal(false) was called, zIndex was not reset, and the window "jumped" above all BASE neighbors.

## Decision
setModal(false) now adds self.zIndex = 0 (reset to default).

## Consequences
+ After disabling modal, the window is sorted by id together with other BASE nodes.
+ No unexpected overlapping of neighboring widgets.

## Status
Accepted, implemented.
