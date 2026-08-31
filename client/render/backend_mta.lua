--[[
    backend_mta.lua — DXUI V2

    Backend implementation on top of MTA DX9 (dxDraw*/dxSetBlendMode).

    This is the only entry point for the external dx* dependency in the
    whole engine. Tests use a mock instead (see tests/).

    Stage 9: drawRoundedRect (SDF shader, fallback — flat rect), drawImage
    with effect (shader: blur/mask) and section (crop via
    dxDrawImageSection — without distorting proportions).

    Stage 10: RT-groups (effect layer). beginGroup switches rendering to an
    offscreen RT and sets an offset; draw functions subtract the offset
    (coords inside the RT are local); endGroup restores the target and draws
    the RT with the effect (blur/mask). Node-level effects thus get
    pixel-perfect composition without changing the items model.
]]

DXUI = DXUI or {}

--- Applies effect params to the shader. Returns the shader or nil.
local function applyEffect(effect)
    if not effect or not effect.shader then return nil end
    if effect.params then
        for k, v in pairs(effect.params) do
            dxSetShaderValue(effect.shader, k, v)
        end
    end
    return effect.shader
end

-- Stack of active RT-groups: { { rt, offX, offY }, ... }. Empty — draw to screen.
local groupStack = {}

--- Subtracts the current group offset (world → local RT coords).
local function adjust(x, y)
    local n = #groupStack
    if n > 0 then
        local g = groupStack[n]
        return x - g.offX, y - g.offY
    end
    return x, y
end

DXUI.MtaBackend = {
    setBlendMode = function(mode)
        dxSetBlendMode(mode)
    end,

    drawRect = function(x, y, w, h, color)
        x, y = adjust(x, y)
        dxDrawRectangle(x, y, w, h, color)
    end,

    --- Rounded rect: white quad with SDF shader; color via tint
    -- dxDrawImage (shader outputs white + corner alpha). Without shader — flat rect.
    drawRoundedRect = function(x, y, w, h, radius, color, effect)
        x, y = adjust(x, y)
        local shader = applyEffect(effect)
        if shader and effect.texture then
            dxDrawImage(x, y, w, h, effect.texture, 0, 0, 0, color, shader)
        else
            dxDrawRectangle(x, y, w, h, color) -- fallback (no shader)
        end
    end,

    drawImage = function(x, y, w, h, texture, color, effect, section)
        x, y = adjust(x, y)
        local shader = applyEffect(effect)
        if section then
            -- crop: draw the visible texture SECTION into the clipped quad
            dxDrawImageSection(x, y, w, h,
                section[1], section[2], section[3], section[4],
                texture, 0, 0, 0, color, shader)
        else
            dxDrawImage(x, y, w, h, texture, 0, 0, 0, color, shader)
        end
    end,

    drawText = function(text, x, y, w, h, color, font, align, valign, scaleX, scaleY)
        x, y = adjust(x, y)
        dxDrawText(text, x, y, x + w, y + h, color,
            scaleX or 1, scaleY or 1, font or "default",
            align or "left", valign or "top")
    end,

    drawLine = function(x1, y1, x2, y2, color, width)
        x1, y1 = adjust(x1, y1)
        x2, y2 = adjust(x2, y2)
        dxDrawLine(x1, y1, x2, y2, color, width)
    end,

    -- -----------------------------------------------------------------
    -- RT-groups (expensive path / effect layer)
    -- -----------------------------------------------------------------

    --- Switches rendering to an offscreen RT (w×h) with origin (x, y).
    -- Returns true on success; false — RT unavailable (draw directly).
    beginGroup = function(x, y, w, h)
        local rt = DXUI.Effects and DXUI.Effects.acquireRT(w, h)
        if not rt then return false end
        dxSetRenderTarget(rt, true)
        groupStack[#groupStack + 1] = { rt = rt, offX = x, offY = y }
        return true
    end,

    --- Restores the target, draws the RT with the effect (blur/mask) in place.
    -- alpha (0..1) — TRUE group-opacity: the whole composite as one quad,
    -- interior intersections never blend twice.
    endGroup = function(x, y, w, h, effect, alpha)
        local g = table.remove(groupStack)
        if not g then return end
        dxSetRenderTarget(nil)
        local shader = applyEffect(effect)
        local a = alpha
        if a == nil or a >= 1 then a = 1 elseif a < 0 then a = 0 end
        local quadColor = math.floor(255 * a) * 0x1000000 + 0xFFFFFF -- 0xAAFFFFFF
        dxDrawImage(x, y, w, h, g.rt, 0, 0, 0, quadColor, shader)
        if DXUI.Effects then DXUI.Effects.releaseRT(g.rt) end
    end,
}