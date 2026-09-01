# DXUI V3 — Code Comment Style

This document is the single source of truth for how comments are written
across the DXUI V3 codebase. It is derived from `PROMT.md` (§74 "No Magic",
§75 "Comments", §85 "Final Quality Bar", §86 "The Final Rule") and applies
to every Lua file under `source/client/`.

The goal is **readable outside, engineered inside**: a comment must tell a
human *what* a piece of code is for and *why* it exists, never *how* it
works line by line (the code already says how).

---

## 1. Language

All comments are written in **English**. No Russian, no mixed-language
comments, no abbreviations that are not universally understood.

## 2. File header

Every file starts with a `--[[ ... ]]` block that states, in plain English:

- the file's **responsibility** (one or two sentences);
- the **key concepts / invariants** it owns, when non-obvious;
- a short **usage example** when the file exposes a public API.

The header must NOT contain:

- section markers (`§42`, `§53-54`, `§71`, …);
- milestone / ADR references (`M1`, `M20`, `ADR-19`, …);
- implementation-history notes ("the V2 flaw was…", "v1 did X").

The product name "DXUI V3" is allowed in the header title (it is the
project identity, not a version marker).

```lua
--[[
    node.lua — DXUI V3

    BaseNode — the public UI object. A plain Lua table with one metatable
    that funnels every property write through a single mutation layer
    (validation + transform + owner tracking + invalidation).

    Pure Lua 5.1 — no MTA API (testable outside the game).
]]
```

## 3. Function documentation

Every function (including local helpers) gets a `---` LuaDoc block placed
**directly above** the function. The block contains:

- a one-line **summary** of what the function does;
- `@param` lines for non-obvious parameters;
- `@return` lines for non-obvious return values.

The summary describes *what* and *why*, not a restatement of the signature.

```lua
--- Marks the node dirty for the given categories and propagates the
-- category -> instance frame flags (see CATEGORY_FLAGS above).
function Node:_invalidate(categories)
```

One-line functions may use a single `---` summary line without `@param` /
`@return` when the signature is self-evident.

## 4. Inline comments

Inline comments sit on their **own line, above** the code they explain.
They explain **why** (a decision, an invariant, a non-obvious constraint),
not what the next line obviously does.

```lua
-- rounded corners need the SDF shader; nil degrades to a flat rect
if it.radius > 0 and DXUI.Effects then
```

## 5. Forbidden patterns

- **No trailing / side-by-side comments** (`local x = 1 -- the value`).
  Move the explanation to its own line above.
- **No section markers** (`§N`), milestone markers (`M1`), or ADR
  references in implementation code.
- **No version-history comments** ("V2 flaw", "v1 did", "was X, now Y").
- **No magic numbers without explanation** — a bare literal that is not
  self-evident must be named or explained (§74).
- **No stale or garbled comments** — a comment that contradicts the code
  is worse than no comment; fix or delete it.

## 6. Consistency

- Use the same vocabulary across files (e.g. "node", "widget", "part",
  "render list", "dirty flag", "owner").
- Prefer short, declarative sentences. Avoid filler ("This function is
  used to…").
- Keep comments close to the code they describe; do not duplicate the
  file header's responsibility inside a function.

---

## Checklist (for review)

- [ ] Header is a `--[[ ]]` block with responsibility, no `§N`/`M1`/`ADR`.
- [ ] Every function has a `---` block above it.
- [ ] No trailing comments anywhere.
- [ ] Inline comments explain *why*, on their own line.
- [ ] English only.
- [ ] No version-history or milestone references.
