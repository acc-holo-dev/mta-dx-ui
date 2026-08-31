# ADR-009: Property Validation & Plugin API (M23)

## Context
Widgets need cheap validation (typos, wrong types) and external resources need
to add widgets/effects without editing the core.

## Decision
1) Property validation: specs gain `type` + `min`/`max` + existing
   `transform`. `getValidator(spec)` builds a cached validator from these;
   `Node._set` runs it before transform.
2) Plugins: `DXUI.registerWidget(name, class)` generates Context and Node
   builders from a class with `.build`; `DXUI.registerEffect(name, fn)`
   registers a named effect used via the `effect` property (render-path
   integrated, RT groups included).

## Consequences
+ Impossible values fail at the mutation layer with a clear error.
+ External widgets use exactly the same builder path as internal ones.
− Cross-resource registration still depends on the table-by-reference question
  (see ADR-007).

## Status
Accepted, implemented.
