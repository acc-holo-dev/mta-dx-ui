---Theme engine: named themes with tokens, component styles, inheritance
---and live activation (DXUI.Theme).
---
---    Theme.define("flat", {
---        extends = "light",                    -- optional parent theme
---        tokens  = { color = { primary = 0xFF... } },
---        components = {
---            button = {
---                base    = { color = "@color.primary", radius = "@radius.md" },
---                variants = { secondary = {...} },  -- keyed by node.style
---                states   = { hover = {...}, pressed = {...} },
---                transition = { duration = 120, easing = "out" },
---            },
---        },
---    })
---    Theme.activate("flat")  -- switches live; restyles every mounted widget
---
---`extends` deep-merges the child over the parent (tokens, components,
---variants, states): the child overrides pointwise and keeps everything it
---does not mention. Define parents before children.
---
---Component values may reference tokens ("@color.primary"). Asset
---prefixes load through the resource cache at compile time:
---    "texture:path/file.png"        -> DXUI.texture(path)
---    "font:path/file.ttf:12"         -> DXUI.font(path, 12)
---    "font:path/file.ttf:12:cleartype" -> DXUI.font(path, 12, {quality})
---
---Lookup chain (Widget:_applyStyleState): widget.style variant > component
---base > widget class default. getComponentStyle returns COMPILED maps
---(tokens resolved once, cached per (theme, component, styleKey)) — runtime
---style apply is a plain table read, never token chasing per frame.
---
---Switching themes re-applies styles to every mounted widget (sparse
---overrides, owner guard: user-set props are never overwritten). A
---component may declare `transition` to animate VISUAL-STATE changes
---(hover/press/focus) over the given duration; construction and theme
---switches stay instant.

DXUI = DXUI or {}

local Theme = {}

Theme.themes = {}
Theme._currentName = nil

-- compiled cache: key "name\1component\1style" -> { props, states }
local compiledCache = {}
local compiledCount = 0
local CACHE_CAP = 512

---Deep-merges src into dst (tables merge recursively, scalars overwrite).
---Returns dst.
local function deepMerge(dst, src)
    for k, v in pairs(src) do
        local dv = dst[k]
        if type(dv) == "table" and type(v) == "table" then
            deepMerge(dv, v)
        else
            dst[k] = v
        end
    end
    return dst
end

---Returns a deep copy of tbl.
local function deepCopy(tbl)
    local out = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            out[k] = deepCopy(v)
        else
            out[k] = v
        end
    end
    return out
end

---Materializes a theme: when `tbl.extends` names a registered theme, the
---parent's materialized table is deep-copied and `tbl` merges over it.
---The `extends` key itself is consumed (never stored).
local function materialize(tbl)
    tbl = tbl or {}
    local parentName = tbl.extends
    if not parentName then return tbl end
    local parent = Theme.themes[parentName]
    if not parent then
        if DXUI._warn then
            DXUI._warn("theme: extends unknown theme '" .. tostring(parentName) .. "' (ignored)")
        end
        tbl.extends = nil
        return tbl
    end
    local merged = deepCopy(parent)
    tbl.extends = nil
    return deepMerge(merged, tbl)
end

---Registers a theme table. With `tbl.extends = "parent"`, the theme
---inherits the parent's tokens/components and overrides pointwise.
function Theme.define(name, tbl)
    tbl = materialize(tbl)
    Theme.themes[name] = tbl
    if tbl.tokens then
        DXUI.Tokens.define(name, tbl.tokens)
    end
    -- a redefinition must not serve stale compiled styles
    compiledCache = {}
    compiledCount = 0
end

---Resolves token references and asset prefixes in a props table, dropping
---unresolved keys (deterministic fallback to the widget class default).
local function resolveProps(themeName, props)
    local out = {}
    for k, v in pairs(props) do
        local r = DXUI.Tokens.resolve(themeName, v)
        if type(r) == "string" then
            local texPath = r:match("^texture:(.+)$")
            if texPath then
                local loaded = DXUI.texture and DXUI.texture(texPath)
                if loaded == false then
                    -- failed load (cached false marker): drop the key
                    r = nil
                else
                    Theme.keepTexture(texPath)
                    r = loaded
                end
            else
                local fontPath, fontSz, quality =
                    r:match("^font:([^:]+):(%d+):(%a[%w_]*)$")
                if not fontPath then
                    fontPath, fontSz = r:match("^font:([^:]+):(%d+)$")
                end
                if fontPath then
                    fontSz = tonumber(fontSz)
                    local opts = quality and { quality = quality } or nil
                    local loaded = DXUI.font and DXUI.font(fontPath, fontSz, opts)
                    if loaded == false then
                        r = nil
                    else
                        Theme.keepFont(fontPath, fontSz, quality)
                        r = loaded
                    end
                end
            end
        end
        if r ~= nil then out[k] = r end
    end
    return out
end

---Compiles (tokens resolved) + caches the component style for one
---(theme, component, styleKey). Returns { props, states, transition }.
local function compileComponent(themeName, componentName, styleKey)
    local theme = Theme.themes[themeName]
    if not theme then return nil end
    local def = theme.components and theme.components[componentName]
    -- class names are capitalized ("Button"); theme components lowercase
    if not def then
        def = theme.components and theme.components[componentName:lower()]
    end
    if not def then return nil end

    -- variant merge over base (sparse). `props` is a top-level alias for
    -- base; with inheritance a child `base` must win over a parent `props`,
    -- so the alias merges FIRST and `base` second.
    local chosen = {}
    if def.props then
        for k, v in pairs(def.props) do chosen[k] = v end
    end
    if def.base then
        for k, v in pairs(def.base) do chosen[k] = v end
    end
    if styleKey and def.variants and def.variants[styleKey] then
        for k, v in pairs(def.variants[styleKey]) do chosen[k] = v end
    end

    local styles = { props = resolveProps(themeName, chosen), states = {} }
    if def.states then
        for stateName, map in pairs(def.states) do
            styles.states[stateName] = resolveProps(themeName, map)
        end
    end
    if def.transition then
        styles.transition = {
            duration = tonumber(def.transition.duration) or 0,
            easing = def.transition.easing or "out",
        }
    end
    return styles
end

---Returns the compiled style for (theme, component, styleKey), caching it.
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

---Public lookup used by Widget:_applyStyleState. Deterministic fallback
---chain: current theme component > fallback theme component >
---widget class default (nil here).
function Theme.getComponentStyle(componentName, styleKey)
    local cur = Theme._currentName
    if not cur then return nil end
    local hit = cached(cur, componentName, styleKey)
    if hit == nil and Theme._fallback and Theme._fallback ~= cur then
        return cached(Theme._fallback, componentName, styleKey)
    end
    return hit
end

---Returns the ACTIVE theme's name (nil before the first activation).
function Theme.getCurrent()
    return Theme._currentName
end

---Returns the registered names of every theme (sorted for display).
function Theme.list()
    local names = {}
    for name in pairs(Theme.themes) do names[#names + 1] = name end
    table.sort(names)
    return names
end

---Fallback theme (opt-in): consulted when the active theme lacks a
---component (theme -> fallback -> widget defaults).
function Theme.setFallback(name)
    Theme._fallback = name
end

---Activates a theme by name, or by an INLINE table (registered under an
---auto-generated name, then activated). Re-styles every mounted widget
---live. Alias for the UI method `ui:setTheme`.
---@param nameOrTable string|table registered name or theme table
---@return boolean true when a theme was activated
function Theme.setTheme(nameOrTable)
    if type(nameOrTable) == "table" then
        Theme._inlineCount = (Theme._inlineCount or 0) + 1
        local name = "__inline_theme_" .. Theme._inlineCount
        Theme.define(name, nameOrTable)
        return Theme.activate(name)
    end
    if nameOrTable ~= nil then
        return Theme.activate(nameOrTable)
    end
    return false
end

---Activates a theme: compiles switch, re-styles every mounted widget.
---An unknown name keeps the current theme (warn only).
function Theme.activate(name)
    local theme = Theme.themes[name]
    if not theme then
        if DXUI._warn then DXUI._warn("theme: unknown theme '" .. tostring(name) .. "'") end
        return false
    end
    Theme._currentName = name
    compiledCache = {}
    compiledCount = 0
    -- sweep assets owned by the old theme. Only runs when the old theme
    -- kept assets (theme-asset prefixes during compile); with an empty
    -- keep-set this is a no-op — releasing with an empty set would free
    -- assets loaded by CONSUMERS (not the theme).
    if DXUI.releaseObsolete and Theme._keep and next(Theme._keep) then
        DXUI.releaseObsolete(Theme._keep)
    end
    Theme._keep = {}
    -- re-style all live widgets
    Theme.reapplyAll()
    return true
end

---Marks a texture path as kept by the active theme (the switch sweep
---releases obsolete cached assets; kept ones survive).
function Theme.keepTexture(path)
    if Theme._keep and path then Theme._keep["t:" .. path] = true end
end

---Marks a font (path, size[, quality]) as kept by the active theme. The
---key is built by DXUI.fontCacheKey (the same validation it applies in
---DXUI.font), so the keep entry always matches the key the font was
---actually cached under — including the invalid-quality fallback.
function Theme.keepFont(path, size, quality)
    if Theme._keep and path then
        local key
        if DXUI.fontCacheKey then
            key = DXUI.fontCacheKey(path, size,
                quality and { quality = quality } or nil)
        else
            key = tostring(path) .. ":" .. tostring(size)
        end
        Theme._keep["f:" .. key] = true
    end
end

---Re-applies the current style to every mounted widget (tree walks).
function Theme.reapplyAll()
    if not (DXUI._uis and DXUI.Widget) then return end
    --- Re-applies the style to a node and recurses into its children.
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