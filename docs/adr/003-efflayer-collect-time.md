# ADR-003: _effLayer Computed at Collect Time (vs Child Mutation)

## Context
When a parent changed, the child's layer was inherited from the parent by mutating child.layer in setParent(). This caused layer "sticking": when modal was disabled on a Window, its children stayed in MODAL because their layer was never reset.

## Decision
V2 dropped the child.layer mutation in setParent(). Instead, _effLayer is computed recursively in _collectInteractive()/_collectRenderable() and written via rawset(node, "_effLayer", effLayer). Sorting uses _effLayer, not layer.

## Consequences
+ A parent can change its layer (modal, popup) and children automatically receive the effective layer without side effects on their own layer.
+ No risk of getting "stuck" in MODAL after setModal(false).
− A small O(N) overhead computing _effLayer on every list rebuild.

## Status
Accepted, implemented.
