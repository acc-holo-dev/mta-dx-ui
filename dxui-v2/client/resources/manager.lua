--[[
    manager.lua — DXUI V2

    Resource Manager (§54/§55): textures, fonts, shaders — с automatic caching.
    Одинаковые ресурсы не создаются повторно (§87: не «font per label»).

        local tex  = ui.texture("icons/inventory.png")  -- cached
        local font = ui.font("Roboto", 12)               -- cached
        local sh   = ui.shader(code)                     -- cached

    Ownership (§55):
      - GLOBAL — ресурсы, созданные здесь, разделяемые; живут до release-
        Resources (resource stop) или конца ресурса. Node destroy их НЕ трогает
        (node-owned ресурсы — будущие RT для clip/blur).
      - Вне MTA (тесты, lupa): texture возвращает path как placeholder-handle
        (pass-through), font/shader — nil (дефолтный шрифт MTA).
]]

DXUI = DXUI or {}

local textureCache = {}
local fontCache = {}
local shaderCache = {}

--- Загружает текстуру с кэшированием по пути.
function DXUI.texture(path)
    if textureCache[path] then return textureCache[path] end
    local tex = nil
    if dxCreateTexture then
        local ok, result = pcall(dxCreateTexture, path)
        if ok then tex = result end
    end
    if tex == nil then tex = path end -- вне MTA: pass-through placeholder
    textureCache[path] = tex
    return tex
end

--- Создаёт шрифт с кэшированием по (имя, размер). nil = дефолтный шрифт MTA.
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

--- Компилирует шейдер с кэшированием по коду (extensibility point, §40).
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

--- Освобождает все кэшированные ресурсы (onClientResourceStop).
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
    -- кэш измерений text engine (§43)
    if DXUI.Text and DXUI.Text.clearCache then
        DXUI.Text.clearCache()
    end
    -- RT-пул эффектов (§35): уничтожить все offscreen-таргеты
    if DXUI.Effects and DXUI.Effects.releasePool then
        DXUI.Effects.releasePool()
    end
end