# ADR-002: Named Dirty Categories (vs Legacy Bitmask)

## Context
Legacy used bitmasks (0x091) for dirty flags. This is compact but unreadable and fragile when adding new categories.

## Decision
V2 uses named string categories (DIRTY_LAYOUT, DIRTY_RENDER, DIRTY_INPUT, DIRTY_STYLE, DIRTY_CHILDREN, DIRTY_VISIBILITY). Inside Context they are stored in boolean flags node._dirty[name]; the external API never sees numeric constants.

## Consequences
+ Readability: _set() invalidates exactly the categories declared in spec.invalidates.
+ Extensibility: a new category is added with a single string.
− The _dirty array is slightly heavier than a bitmask (insignificant for Lua).

## Status
Accepted, implemented.
