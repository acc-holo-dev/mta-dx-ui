# ADR-008: State-Matrix Theme & Minimal Style Manager (M22)

## Context
v1 used scattered hardcoded colors and per-widget styling. The proposal was a
full DGS-style style manager with packs and per-resource styles; that was cut.

## Decision
Minimal manager: `DXUI.setTheme({ Class = { style = { base, hover, pressed,
focused, disabled } } })`. `node.style` switches styles. `_applyStyleState`
reverts style-managed props to class defaults, applies base (skipping state
keys), then the state override. State priority: disabled > pressed > hover >
focused > normal, tracked centrally by the dispatcher (`Node:setState`).
Shared textures/fonts via the resource manager's caches.

## Consequences
+ Themes are declarative and state-aware; node state just flips `_state`.
+ `_userSet` guard: manual properties are never overwritten by themes.
+ Packs/per-resource styles deferred; `setTheme` re-applies to all contexts.

## Status
Accepted, implemented.
