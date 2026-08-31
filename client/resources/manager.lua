--[[
    manager.lua — DXUI V2

    Resource Manager: textures, fonts, shaders — with automatic caching.
    Identical resources are never re-created (no "font per label").

        local tex  = ui.texture("icons/inventory.png")  -- cached
        local font = ui.font("Roboto", 12)               -- cached
        local sh   = ui.shader(code)                     -- cached

    Ownership:
      - GLOBAL — resources created here are shared; they live until release-
        Resources (resource stop) or end of resource. Node destroy does NOT touch
        (node-owned resources — future RTs for clip/blur).
      - Outside MTA (tests, lupa): texture returns path as a placeholder-handle
        (pass-through), font/shader — nil (default MTA font).
]]

DXUI = DXUI or {}

local textureCache = {}
local fontCache = {}
local shaderCache = {}

--- Loads a texture, cached by path.
function DXUI.texture(path)
    if textureCache[path] then return textureCache[path] end
    local tex = nil
    if dxCreateTexture then
        local ok, result = pcall(dxCreateTexture, path)
        if ok then tex = result end
    end
    if tex == nil then tex = path end -- outside MTA: pass-through placeholder
    textureCache[path] = tex
    return tex
end

--- Creates a font, cached by (name, size). nil = default MTA font.
function DXUI.font(name, size)
    local key = tostring(name) .. ":" .. tostring(size)
    if fontCache[key] then return fontCache[key] end
    local font = nil
    if dxCreateFont then
        local ok, result = pcall(dxCreateFont, name, size)
        if ok then font = result end
    end
    fontCache[key] = font
    return font
end

--- Compiles a shader, cached by code (extensibility point).
function DXUI.shader(code)
    if shaderCache[code] then return shaderCache[code] end
    local sh = nil
    if dxCreateShader then
        local ok, result = pcall(dxCreateShader, code)
        if ok then sh = result end
    end
    shaderCache[code] = sh
    return sh
end

--- Releases all cached resources (onClientResourceStop).
function DXUI.releaseResources()
    if isElement and destroyElement then
        for _, tex in pairs(textureCache) do
            if isElement(tex) then destroyElement(tex) end
        end
        for _, font in pairs(fontCache) do
            if isElement(font) then destroyElement(font) end
        end
        for _, sh in pairs(shaderCache) do
            if isElement(sh) then destroyElement(sh) end
        end
    end
    textureCache, fontCache, shaderCache = {}, {}, {}
    -- text engine measurement cache
    if DXUI.Text and DXUI.Text.clearCache then
        DXUI.Text.clearCache()
    end
    -- effects RT-pool: destroy all offscreen targets
    if DXUI.Effects and DXUI.Effects.releasePool then
        DXUI.Effects.releasePool()
    end
end