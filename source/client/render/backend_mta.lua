--[[
    backend_mta.lua — DXUI V4

    The ONLY entry point to the external dx* API in the whole engine
    (every direct dx* call lives here; tests inject a mock table instead).

    Responsibilities:
      - draw primitives (rect / rounded / image / text / line);
      - global state: blend mode (deduped by RenderState),
        blur/mask shader params (deduped by effect-table identity),
        rounded-rect shader params (deduped by shadow compare);
      - RT-groups (beginGroup/endGroup with the pooled allocator);
      - measurement hooks: dxGetTextSize wired into Text.setMeasurer,
        dxGetMaterialSize exposed as materialSize (image section culling).

    interface (mirrored by the test mock):
        setBlendMode(mode)
        drawRect(x,y,w,h,color)
        drawRoundedRect(x,y,w,h, rtl,rtr,rbr,rbl, fill, border, borderWidth)
        drawImage(x,y,w,h,texture,color,effect,section)
        drawText(text,x,y,w,h,color,font,align,valign,scaleX,scaleY)
        drawLine(x1,y1,x2,y2,color,width)
        beginGroup(x,y,w,h)  -> bool
        endGroup(x,y,w,h,effect,alpha)
        materialSize(tex)    -> w,h
]]

DXUI = DXUI or {}

-- Last applied effect (table identity) + its base texture: the SAME shared
-- effect table with the same base is never re-applied (identity dedup —
-- blur/mask effects are cached by inputs, so identity is stable).
local lastFx, lastFxBase = nil, nil

---Applies a blur/mask effect's shader params, skipping re-application
---when the effect and base texture are unchanged (identity dedup).
local function applyEffect(effect, baseTexture)
    if not effect or not effect.shader then
        lastFx, lastFxBase = nil, nil
        return nil
    end
    local base = effect.texture or baseTexture
    if effect == lastFx and base == lastFxBase then
        -- unchanged — shader already has these params
        return effect.shader
    end
    lastFx, lastFxBase = effect, base
    if effect.params then
        for k, v in pairs(effect.params) do
            dxSetShaderValue(effect.shader, k, v)
        end
    end
    if base and base ~= "" then
        dxSetShaderValue(effect.shader, "gTexture0", base)
    end
    return effect.shader
end

-- ---------------------------------------------------------------------
-- Rounded-rect path (V4): ONE shared SDF shader, per-corner radii,
-- border + fill in a single draw. Parameter uploads are deduped by a
-- shadow compare (only CHANGED params reach dxSetShaderValue) — there
-- are no per-size effect tables.
-- ---------------------------------------------------------------------

-- Shadow state for the rounded shader (allocated once, mutated in place).
local rrShadow = nil

---Splits a packed 0xAARRGGBB color into 0..1 floats (r, g, b, a).
local function colorFloats(packed)
    local a = (math.floor(packed / 0x1000000) % 256) / 255
    local r = (math.floor(packed / 0x10000) % 256) / 255
    local g = (math.floor(packed / 0x100) % 256) / 255
    local b = (packed % 256) / 255
    return r, g, b, a
end

---Draws a rounded rect through the shared SDF shader. Falls back to
---square-corner native rects when shaders are unavailable (headless).
local function drawRounded(x, y, w, h, rtl, rtr, rbr, rbl, fill, border, borderWidth)
    local shader = DXUI.Effects and DXUI.Effects.roundedShader()
    if not shader then
        -- fallback: square corners, border rect + inset fill rect
        local bw = (border and borderWidth and borderWidth > 0) and borderWidth or 0
        if bw > 0 then
            dxDrawRectangle(x, y, w, h, border)
        end
        local iw, ih = w - 2 * bw, h - 2 * bw
        if iw > 0 and ih > 0 then
            dxDrawRectangle(x + bw, y + bw, iw, ih, fill)
        elseif bw <= 0 then
            dxDrawRectangle(x, y, w, h, fill)
        end
        return
    end
    -- clamp radii so a radius never exceeds half the smaller side
    local halfMin = (w < h and w or h) * 0.5
    if rtl > halfMin then rtl = halfMin end
    if rtr > halfMin then rtr = halfMin end
    if rbr > halfMin then rbr = halfMin end
    if rbl > halfMin then rbl = halfMin end
    -- shadow-compare params; upload only what changed
    local s = rrShadow
    if s == nil or s.shader ~= shader then
        s = { shader = shader }
        rrShadow = s
    end
    if s.w ~= w or s.h ~= h then
        dxSetShaderValue(shader, "gSize", w, h)
        s.w, s.h = w, h
    end
    if s.rtl ~= rtl or s.rtr ~= rtr or s.rbr ~= rbr or s.rbl ~= rbl then
        dxSetShaderValue(shader, "gRadii", rtl, rtr, rbr, rbl)
        s.rtl, s.rtr, s.rbr, s.rbl = rtl, rtr, rbr, rbl
    end
    local bw = borderWidth or 0
    if s.bw ~= bw then
        dxSetShaderValue(shader, "gBorder", bw)
        s.bw = bw
    end
    if s.fill ~= fill then
        dxSetShaderValue(shader, "gFillColor", colorFloats(fill))
        s.fill = fill
    end
    local bcol = border or fill
    if s.border ~= bcol then
        dxSetShaderValue(shader, "gBorderColor", colorFloats(bcol))
        s.border = bcol
    end
    -- white multiplier: colors come from the shader params
    dxDrawImage(x, y, w, h, shader, 0, 0, 0, 0xFFFFFFFF)
end

-- Active RT-group stack: { { rt, offX, offY, prevTarget }, ... }.
local groupStack = {}

--- Translates a point into the active RT group's local space.
local function adjust(x, y)
    local n = #groupStack
    if n > 0 then
        local g = groupStack[n]
        return x - g.offX, y - g.offY
    end
    return x, y
end

DXUI.BackendMTA = {
    --- Sets the native blend mode.
    setBlendMode = function(mode)
        dxSetBlendMode(mode)
    end,

    --- Draws a filled rectangle.
    drawRect = function(x, y, w, h, color)
        x, y = adjust(x, y)
        dxDrawRectangle(x, y, w, h, color)
    end,

    --- Draws a rounded rectangle: single SDF draw with per-corner radii
    --- (TL, TR, BR, BL) and optional border ring; flat-rect fallback when
    --- shaders are unavailable.
    drawRoundedRect = function(x, y, w, h, rtl, rtr, rbr, rbl, fill, border, borderWidth)
        x, y = adjust(x, y)
        drawRounded(x, y, w, h, rtl, rtr, rbr, rbl, fill, border, borderWidth)
    end,

    --- Draws an image (full or section), optionally through an effect shader.
    drawImage = function(x, y, w, h, texture, color, effect, section)
        x, y = adjust(x, y)
        local shader = applyEffect(effect, texture)
        local material = shader or texture
        if section then
            dxDrawImageSection(x, y, w, h,
                section[1], section[2], section[3], section[4],
                material, 0, 0, 0, color)
        else
            dxDrawImage(x, y, w, h, material, 0, 0, 0, color)
        end
    end,

    --- Draws text with alignment and scale.
    drawText = function(text, x, y, w, h, color, font, align, valign, scaleX, scaleY)
        x, y = adjust(x, y)
        dxDrawText(text, x, y, x + w, y + h, color,
            scaleX or 1, scaleY or 1, font or "default",
            align or "left", valign or "top", true, false, false, false)
    end,

    --- Draws a line segment.
    drawLine = function(x1, y1, x2, y2, color, width)
        x1, y1 = adjust(x1, y1)
        x2, y2 = adjust(x2, y2)
        dxDrawLine(x1, y1, x2, y2, color, width)
    end,

    --- Texture pixel size (dxGetMaterialSize; nil when unavailable).
    materialSize = function(tex)
        if tex and dxGetMaterialSize then
            local ok, w, h = pcall(dxGetMaterialSize, tex)
            if ok and w then return w, h end
        end
        return nil
    end,

    -- RT-groups (expensive path / effect layer) -------------------------

    --- Begins an RT group, redirecting draws into a pooled render target.
    beginGroup = function(x, y, w, h)
        local rt = DXUI.Effects and DXUI.Effects.acquireRT(w, h)
        if not rt then return false end
        local n = #groupStack
        local prevTarget = (n > 0) and groupStack[n].rt or nil
        dxSetRenderTarget(rt, true)
        groupStack[#groupStack + 1] = { rt = rt, offX = x, offY = y, prevTarget = prevTarget }
        return true
    end,

    --- Ends the RT group and composites it back with effect and alpha.
    endGroup = function(x, y, w, h, effect, alpha)
        local g = table.remove(groupStack)
        if not g then return end
        dxSetRenderTarget(g.prevTarget)
        local ax, ay = adjust(x, y)
        local shader = applyEffect(effect, g.rt)
        local a = alpha
        if a == nil or a >= 1 then a = 1 elseif a < 0 then a = 0 end
        local quadColor = math.floor(255 * a) * 0x1000000 + 0xFFFFFF
        dxDrawImage(ax, ay, w, h, shader or g.rt, 0, 0, 0, quadColor)
        if DXUI.Effects then DXUI.Effects.releaseRT(g.rt, w .. "x" .. h) end
    end,
}

--- Wires the MTA measurement backend into the text engine (called once at
-- bootstrap; safe to call repeatedly).
function DXUI.backendInitMTA()
    if DXUI.Text and dxGetTextSize then
        DXUI.Text.setMeasurer(function(text, scale, font)
            return dxGetTextSize(text, scale or 1, font or "default")
        end)
    end
end