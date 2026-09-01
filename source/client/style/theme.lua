--[[
    theme.lua — DXUI V3

    Theme engine (§45-59): named themes with token sets + component styles.

        Theme.define("flat", { tokens = {...}, components = {
            button = {
                base    = { color = "@color.primary", radius = "@radius.md" },
                variants = { secondary = {...}, danger = {...} },   -- keyed by node.style
                states   = { hover = {...}, pressed = {...}, disabled = {...} },
            },
        }})

        Theme.activate("flat")   -- switches live; re-styles mounted widgets

    Lookup (deterministic fallback chain §51):
        widget.style variant > component base > widget class default.
    getComponentStyle(name, styleKey) returns COMPILED maps (tokens resolved
    once, cached per (theme, component, styleKey)) — runtime style apply is
    a plain table read, never token chasing per frame.

    Widgets consume only compiled maps: { props = {...}, states = { name = {...} } }
    (the exact shape Widget:_applyStyleState expects). Unknown properties in
    a component are skipped by the widget layer (spec guard).

    Switching themes re-applies styles to every mounted widget (sparse
    overrides, owner guard: user-set props are never overwritten, §54).
]]

DXUI = DXUI or {}

local Theme = {}

Theme.themes = {}
Theme.current = nil
Theme._currentName = nil

-- compiled cache: key "name\1component\1style" -> { props, states }
local compiledCache = {}
local compiledCount = 0
local CACHE_CAP = 512

--- Registers a theme table (tokens define/merge into their own scope).
function Theme.define(name, tbl)
    Theme.themes[name] = tbl
    if tbl.tokens then
        DXUI.Tokens.define(name, tbl.tokens)
    end
end

local function resolveProps(themeName, props)
    local out = {}
    for k, v in pairs(props) do
        local r = DXUI.Tokens.resolve(themeName, v)
        if r ~= nil then out[k] = r end
    end
    return out
end

--- Compiles (tokens resolved) + caches the component style for one
-- (theme, component, styleKey). Returns { props = {...}, states = {...} }.
local function compileComponent(themeName, componentName, styleKey)
    local theme = Theme.themes[themeName]
    if not theme then return nil end
    local def = theme.components and theme.components[componentName]
    -- class names are capitalized ("Button"); theme components lowercase
    if not def then
        def = theme.components and theme.components[componentName:lower()]
    end
    if not def then return nil end

    -- variant merge over base (sparse)
    local chosen = {}
    if def.base then
        for k, v in pairs(def.base) do chosen[k] = v end
    end
    if styleKey and def.variants and def.variants[styleKey] then
        for k, v in pairs(def.variants[styleKey]) do chosen[k] = v end
    end
    if def.props then -- `props` top-level alias for base
        for k, v in pairs(def.props) do chosen[k] = v end
    end

    local styles = { props = resolveProps(themeName, chosen), states = {} }
    if def.states then
        for stateName, map in pairs(def.states) do
            styles.states[stateName] = resolveProps(themeName, map)
        end
    end
    return styles
end

local function cached(themeName, componentName, styleKey)
    local key = themeName .. "\1" .. componentName .. "\1" .. tostring(styleKey or "")
    local hit = compiledCache[key]
    if hit ~= nil then return hit end
    local compiled = compileComponent(themeName, componentName, styleKey)
    if compiledCount >= CACHE_CAP then
        compiledCache = {}
        compiledCount = 0
    end
    compiledCount = compiledCount + 1
    compiledCache[key] = compiled
    return compiled
end

--- Public lookup used by Widget:_applyStyleState. Deterministic fallback
-- chain (§51): current theme component > fallback theme component >
-- widget class default (nil here).
function Theme.getComponentStyle(componentName, styleKey)
    local cur = Theme._currentName
    if not cur then return nil end
    local hit = cached(cur, componentName, styleKey)
    if hit == nil and Theme._fallback and Theme._fallback ~= cur then
        return cached(Theme._fallback, componentName, styleKey)
    end
    return hit
end

--- Fallback file (opt-in): "lighter" defaults theme when the chosen theme
-- lacks a component (theme -> fallback -> widget defaults).
function Theme.setFallback(name)
    Theme._fallback = name
end

--- Activates a theme: compiles switch, re-styles every mounted widget.
function Theme.activate(name)
    local theme = Theme.themes[name]
    if not theme then
        if DXUI._warn then DXUI._warn("theme: unknown theme '" .. tostring(name) .. "'") end
        return
    end
    Theme._currentName = name
    Theme.current = theme
    compiledCache = {}
    -- sweep assets owned by the old theme before the new one marks its own
    if DXUI.releaseObsolete then DXUI.releaseObsolete(Theme._keep) end
    Theme._keep = {}
    -- re-style all live widgets
    Theme.reapplyAll()
end

--- Marks an asset path/desc as used by the active theme (component compile
-- can call this when a token resolves to an asset path). Reserved for the
-- resource-ownership sweep (§59).
function Theme.markAssetUsed(path)
    if DXUI.markTextureUsed and path then DXUI.markTextureUsed(path) end
    if Theme._keep then Theme._keep["t:" .. path] = true end
end

--- Re-applies the current style to every mounted widget (tree walks).
function Theme.reapplyAll()
    if not (DXUI._uis and DXUI.Widget) then return end
    local function walk(node)
        local cls = node._class
        if cls and cls ~= DXUI.Node and cls._applyStyleState then
            node:_applyStyleState()
        end
        local children = node._children
        for i = 1, #children do
            if not children[i]._destroyed then walk(children[i]) end
        end
    end
    for _, ui in pairs(DXUI._uis) do
        if ui.root and not ui.root._destroyed then
            local children = ui.root._children
            for i = 1, #children do walk(children[i]) end
        end
    end
end

DXUI.Theme = Theme