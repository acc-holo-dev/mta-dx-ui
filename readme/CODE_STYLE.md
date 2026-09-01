# CODE STYLE

Comments and documentation follow ONE convention: [LuaCATS][luacats] /
lua-language-server annotations. No other doc-block style appears in
`source/`.

## Doc comments

A doc comment is a `---` block placed directly above the symbol it
documents. Continuation lines start with `---` at the same column; blank
separator lines are `---` alone. Code examples are indented by 4 spaces
after the marker:

```lua
---Window — Panel + header + content container.
---
---    local w = ui:window({ title = "Settings", width = 320, height = 220 })
---
---title is a declarative shorthand routed to the header part.
```

Annotations for parameters, returns and fields:

```lua
---Moves the caret.
---@param pos number byte index into `text`
---@param extend boolean shift held: anchor/extend the selection
function Edit:_moveCaret(pos, extend) end
```

Available markers: `@param`, `@return`, `@field`, `@class`,
`@type`, `@alias`, `@see`, `@usage`, `@vararg`, `@private`, `@deprecated`.

## Rules

1. **No block comments.** `--[[ ... ]]` never appears in `source/`;
   everything is `---` (doc) or `--` (short inline note).
2. **No file-identity lines.** Doc comments never state the file name,
   the resource name or a version. The first line names the SYMBOL and
   what it is for.
3. **One doc block per public symbol**: every exported function and
   property table carries `@param`/`@return` (or a prose contract for
   tables/specs).
4. Inline `--` notes explain WHY, never restate WHAT the code does.
5. Files begin with a module-level `---` block describing the module's
   contract, then `DXUI = DXUI or {}`.

## Formatting

- Lua 5.1 syntax only (no `goto`, no integer division `//`).
- 4 spaces per indent level, no tabs.
- Double quotes for strings.
- Up to ~100 columns; wrap long calls with aligned indents.
- Locals first: `local` declarations above use; forward-declare when
  functions are mutually recursive (`local rebuildRows`).

## Naming

- Classes: `PascalCase` (`Panel`, `GridList`). Instances: `camelCase`.
- Module tables: `PascalCase` (`Renderer`, `HitTest`).
- Functions/methods: `camelCase`; predicates read as questions
  (`isVisible`, `needsGroup`).
- Properties (public): `camelCase` (`borderColor`, `rowHeight`).
- Internal fields: underscore prefix (`_scrollX`, `_hoverRow`) — never
  set directly by consumers.
- Constants: `UPPER_SNAKE` (`DRAG_THRESHOLD`, `POOL_CAP`).
- Events: `kebab-case` (`hover-start`, `drag-move`, `popup-close`).

## Property specs

Widget properties are declared as specs — never bare assignments:

```lua
caretWidth = {
    default = 1,
    type = "number", min = 1,
    invalidates = { DXUI.DIRTY.RENDER },
},
```

- `default`, `type`, `min`/`max`, `validate`, `transform`,
  `invalidates`, `onSet` — in that order.
- Nilable props must NOT declare `type` (the validator would reject
  nil); write a nil-tolerant `validate` instead.
- `onSet` handlers may write back through the same property
  (clamping) — the mutation layer's same-value guard keeps it
  recursion-safe.

[luacats]: https://luals.github.io/wiki/annotations/