# ADR-001: AoS Public Node Objects (vs SoA Internal Storage)

## Context
Legacy DXUI used SoA (structure-of-arrays) plus slot indexing: widgets read data from central arrays (s.worldX[slot], s.w[slot]). This optimized cache locality but made the API unreadable and required widget authors to know the internal representation.

## Decision
V2 moved to AoS (array-of-structures): the public API is a plain Lua table (node.x, node.width, node.color). Internal state is stored in node._data (a field table) and controlled by a single mutation layer _set(). The runtime (layout, render, input) works with public fields through a metatable or direct access.

## Consequences
+ The API is understandable without knowing internals.
+ Property-style and method-style converge in a single _set().
+ Widget authors write plain Lua.
− Slightly more memory per object (acceptable for Lua tables).
− Potentially lower cache locality during bulk processing (offset by flat lists for render/input).

## Status
Accepted, implemented.
