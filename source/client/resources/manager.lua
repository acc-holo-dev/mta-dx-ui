--[[
    manager.lua — DXUI V3

    Resource Manager: textures, fonts, shaders — with automatic caching
    (identical resources created once: no "font per label").

        local tex  = ui:texture("icons/x.png")   -- cached
        local font = ui:font("Roboto", 12)        -- cached
        local sh   = ui:shader(code)              -- cached

    Ownership (§59): caches are SHARED process-wide. The ACTIVE theme owns
    the set of assets it references; switching themes sweeps obsolete assets
    (released) while shared ones remain. Hard release happens on the
    runtime resource stop (releaseResources).

    Outside MTA (tests): textures pass through as path placeholders, fonts/
    shaders return nil (default font) — deterministic and testable.
]]

DXUI = DXUI or {}

local textureCache = {}
local fontCache = {}
local shaderCache = {}

--- Loads a texture, cached by path. Failed loads cached as `false` (marker;
-- a nil value cannot be stored) and returned as nil — no retry thrash.
function DXUI.texture(path)
    local cached = textureCache[path]
    if cached ~= nil then return cached ~= false and cached or nil end
    local tex
    if dxCreateTexture then
        local ok, result = pcall(dxCreateTexture, path)
        tex = ok and result or false
    else
        tex = path -- outside MTA: pass-through placeholder
    end
    textureCache[path] = tex
    return tex ~= false and tex or nil
end

--- Creates a font, cached by (name, size). nil = default MTA font.
function DXUI.font(name, size)
    local key = tostring(name) .. ":" .. tostring(size)
    local cached = fontCache[key]
    if cached ~= nil then return cached ~= false and cached or nil end
    local font
    if dxCreateFont then
        local ok, result = pcall(dxCreateFont, name, size)
        font = ok and result or false
    end
    fontCache[key] = font
    return font ~= false and font or nil
end

--- Compiles a shader, cached by code.
function DXUI.shader(code)
    local cached = shaderCache[code]
    if cached ~= nil then return cached ~= false and cached or nil end
    local sh
    if dxCreateShader then
        local ok, result = pcall(dxCreateShader, code)
        sh = ok and result or false
    end
    shaderCache[code] = sh
    return sh ~= false and sh or nil
end

-- ---------------------------------------------------------------------
-- Theme-asset ownership (§59): the active theme references a keep-set;
-- sweeping releases obsolete cached assets, shared ones survive.
-- ---------------------------------------------------------------------

local function destroyIfElement(_, v)
    if type(v) == "userdata" and isElement and isElement(v) then
        destroyElement(v)
    end
end

--- Releases every cached texture/font NOT in keep (string keys). The
-- keep-set is built by the theme while it compiles (Resources.markUsed).
-- Returns the number of released assets (diagnostics).
function DXUI.releaseObsolete(keep)
    local freed = 0
    if keep then
        for k, tex in pairs(textureCache) do
            if tex ~= false and not keep["t:" .. k] then
                destroyIfElement(k, tex)
                textureCache[k] = nil
                freed = freed + 1
            end
        end
        for k, font in pairs(fontCache) do
            if font ~= false and not keep["f:" .. k] then
                destroyIfElement(k, font)
                fontCache[k] = nil
                freed = freed + 1
            end
        end
    end
    return freed
end

--- Marks an asset key as used by the active theme (during compile).
local _themeKeep = {} -- must be in scope BEFORE the functions below (Lua)
function DXUI.markTextureUsed(path)    _themeKeep["t:" .. path] = true end
function DXUI.markFontUsed(name, size) _themeKeep["f:" .. tostring(name) .. ":" .. tostring(size)] = true end
function DXUI._themeKeepStart() _themeKeep = {} end

--- Fully release everything (runtime resource stop).
function DXUI.releaseResources()
    if isElement and destroyElement then
        for _, tex in pairs(textureCache) do destroyIfElement(nil, tex) end
        for _, font in pairs(fontCache) do destroyIfElement(nil, font) end
        for _, sh in pairs(shaderCache) do destroyIfElement(nil, sh) end
    end
    textureCache, fontCache, shaderCache = {}, {}, {}
    _themeKeep = {}
    if DXUI.Text and DXUI.Text.clearCache then DXUI.Text.clearCache() end
    if DXUI.Effects and DXUI.Effects.releasePool then DXUI.Effects.releasePool() end
end