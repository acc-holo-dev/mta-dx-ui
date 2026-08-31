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

--- Applies effect params to the shader and returns it (or nil).
-- baseTexture feeds the shader's gTexture0 source sample: the effect's
-- own texture (e.g. the rounded-rect white quad) or the drawn texture.
local function applyEffect(effect, baseTexture)
    if not effect or not effect.shader then return nil end
    if effect.params then
        for k, v in pairs(effect.params) do
            dxSetShaderValue(effect.shader, k, v)
        end
    end
    local base = effect.texture or baseTexture
    if base and base ~= "" then
        dxSetShaderValue(effect.shader, "gTexture0", base)
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

    --- Rounded rect: the SDF shader IS the draw material (MTA has no
    -- shader argument — dxDrawImage's 10th param is postGUI). Without
    -- shader — flat rect fallback.
    drawRoundedRect = function(x, y, w, h, radius, color, effect)
        x, y = adjust(x, y)
        local shader = applyEffect(effect)
        if shader then
            dxDrawImage(x, y, w, h, shader, 0, 0, 0, color)
        else
            dxDrawRectangle(x, y, w, h, color) -- fallback (no shader)
        end
    end,

    drawImage = function(x, y, w, h, texture, color, effect, section)
        x, y = adjust(x, y)
        local shader = applyEffect(effect, texture)
        local material = shader or texture
        if section then
            -- crop: draw the visible texture SECTION into the clipped quad
            dxDrawImageSection(x, y, w, h,
                section[1], section[2], section[3], section[4],
                material, 0, 0, 0, color)
        else
            dxDrawImage(x, y, w, h, material, 0, 0, 0, color)
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
    -- Nested groups: the enclosing target (screen or an outer group's RT)
    -- is remembered so endGroup can restore it.
    beginGroup = function(x, y, w, h)
        local rt = DXUI.Effects and DXUI.Effects.acquireRT(w, h)
        if not rt then return false end
        local n = #groupStack
        local prevTarget = (n > 0) and groupStack[n].rt or nil
        dxSetRenderTarget(rt, true)
        groupStack[#groupStack + 1] = { rt = rt, offX = x, offY = y, prevTarget = prevTarget }
        return true
    end,

    --- Restores the enclosing target, draws the RT with the effect
    -- (blur/mask) in the current target's coordinate space.
    -- alpha (0..1) — TRUE group-opacity: the whole composite as one quad,
    -- interior intersections never blend twice.
    endGroup = function(x, y, w, h, effect, alpha)
        local g = table.remove(groupStack)
        if not g then return end
        -- restore the target we were rendering into before this group
        -- (screen at top level, the outer group's RT when nested)
        dxSetRenderTarget(g.prevTarget)
        -- the composite lands in that target's coordinate space: subtract
        -- the (enclosing) group's offset, identity when top-level
        local ax, ay = adjust(x, y)
        -- the RT is the shader's source sample (blur/mask over the composite)
        local shader = applyEffect(effect, g.rt)
        local a = alpha
        if a == nil or a >= 1 then a = 1 elseif a < 0 then a = 0 end
        local quadColor = math.floor(255 * a) * 0x1000000 + 0xFFFFFF -- 0xAAFFFFFF
        dxDrawImage(ax, ay, w, h, shader or g.rt, 0, 0, 0, quadColor)
        if DXUI.Effects then DXUI.Effects.releaseRT(g.rt) end
    end,
}