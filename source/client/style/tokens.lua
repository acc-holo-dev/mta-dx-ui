--[[
    tokens.lua — DXUI V3

    Design-token registry: named values (colors, radii, etc.)
    referenced from theme components as "@category.name" (dotted paths).
    Tokens are plain nested tables; a theme defines its own token set and
    may reference tokens from a parent theme (fallback chain).

        tokens.define("flat", { color = { primary = 0xFF... }, radius = { md = 8 } })
        tokens.get("color.primary")   --> value or nil (deterministic)

    Resolution is iterative ("@a.b" and nested "@") with a depth cap and
    cycle guard — always terminates. A missing token resolves to nil, and
    the theme compile step DROPS the property (deterministic fallback to
    the widget class default).
]]

DXUI = DXUI or {}

local Tokens = {}

--- Registry: theme name -> token table (later defines merge deeper scopes).
Tokens.registry = {}
local MAX_DEPTH = 8

--- Registers (or merges into) a named token table; later defines merge
-- deeper scopes into the existing table.
function Tokens.define(name, tbl)
    local cur = Tokens.registry[name]
    if not cur then
        cur = {}
        Tokens.registry[name] = cur
    end
    --- Recursively merges src into dst (tables merge, scalars overwrite).
    local function deepMerge(dst, src)
        for k, v in pairs(src) do
            local dv = dst[k]
            if type(dv) == "table" and type(v) == "table" then
                deepMerge(dv, v)
            else
                dst[k] = v
            end
        end
    end
    deepMerge(cur, tbl)
end

--- Token table lookup ("color.primary" with dotted path).
function Tokens.get(name, path)
    local tbl = Tokens.registry[name]
    if not tbl then return nil end
    local cur = tbl
    for part in path:gmatch("[^.]+") do
        if type(cur) ~= "table" or cur[part] == nil then return nil end
        cur = cur[part]
    end
    return cur
end

--- Resolves a themed value: plain values pass through; "@path" strings are
-- looked up (recursively, cycle-guarded) in the given token set.
-- Returns nil when unresolvable (deterministic fallback to defaults).
function Tokens.resolve(name, value, seen)
    if type(value) ~= "string" then return value end
    if value:sub(1, 1) ~= "@" then return value end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local depth = 0
    local current = value
    while depth < MAX_DEPTH do
        local v = Tokens.get(name, current:sub(2))
        if v == nil then return nil end
        if type(v) ~= "string" or v:sub(1, 1) ~= "@" then return v end
        if seen[v] then return nil end
        seen[v] = true
        current = v
        depth = depth + 1
    end
    return nil
end

DXUI.Tokens = Tokens