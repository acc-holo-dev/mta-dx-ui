---BackendMTA — the ONLY entry point to the external dx* API in the whole
---engine (every direct dx* call lives here; tests inject a mock table
---instead).
---
---Responsibilities:
--- draw primitives (rect / rounded / image / text / line);
--- global state: blend mode (deduped by RenderState),
--- blur/mask shader params (deduped by effect-table identity),
--- rounded-rect shader params (deduped by shadow compare);
--- RT-groups (beginGroup/endGroup with the pooled allocator);
--- measurement hooks: dxGetTextSize wired into Text.setMeasurer,
--- dxGetMaterialSize exposed as materialSize (image section culling).
---
---interface (mirrored by the test mock):
---    setBlendMode(mode)
---    drawRect(x,y,w,h,color)
---    drawRoundedRect(x,y,w,h, rtl,rtr,rbr,rbl, fill, border, borderWidth)
---    drawImage(x,y,w,h,texture,color,effect,section[,rotation,rotCX,rotCY])
---    drawText(text,x,y,w,h,color,font,align,valign,scaleX,scaleY)
---    drawLine(x1,y1,x2,y2,color,width)
---    beginGroup(x,y,w,h)  -> bool
---    endGroup(x,y,w,h,effect,alpha)
---    beginPersistentGroup(key,w,h,ox,oy) -> bool
---    endPersistentGroup()
---    compositePersistentGroup(key,x,y,w,h,sx,sy,sw,sh) -> bool
---    materialSize(tex)    -> w,h

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
    -- base-texture binds are for shaders that SAMPLE their input
    -- (blur/mask); the gradient ignores its input, and its "texture"
    -- IS the shader element itself — never bind that
    if base and base ~= "" and base ~= effect.shader then
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

-- Persistent RT registry (cacheContent containers; NOT the pool): keyed
-- render targets that survive frames, released via destroyPersistentRT.
-- { key = { rt, w, h } }
local persistentRTs = {}

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

    --- Draws an image (full or section), optionally through an effect
    --- shader. `rotation` (deg, optional) turns the quad around
    --- (rotCX, rotCY) — ABSOLUTE screen coords (the Renderer scales
    --- them); nil = the quad's own center.
    drawImage = function(x, y, w, h, texture, color, effect, section, rotation, rotCX, rotCY)
        x, y = adjust(x, y)
        local shader = applyEffect(effect, texture)
        local material = shader or texture
        local rot = rotation or 0
        if rot ~= 0 then
            if rotCX == nil or rotCY == nil then
                rotCX, rotCY = x + w / 2, y + h / 2
            else
                -- same RT-group local space as the position
                rotCX, rotCY = adjust(rotCX, rotCY)
            end
        end
        if section then
            dxDrawImageSection(x, y, w, h,
                section[1], section[2], section[3], section[4],
                material, rot, rotCX or 0, rotCY or 0, color)
        else
            dxDrawImage(x, y, w, h, material, rot, rotCX or 0, rotCY or 0, color)
        end
    end,

    --- Draws text with alignment and scale. `colorCoded` (11th arg,
    --- optional) renders #RRGGBB codes embedded in the text (Label.rich).
    drawText = function(text, x, y, w, h, color, font, align, valign, scaleX, scaleY, colorCoded)
        x, y = adjust(x, y)
        dxDrawText(text, x, y, x + w, y + h, color,
            scaleX or 1, scaleY or 1, font or "default",
            align or "left", valign or "top", true, false, false,
            colorCoded and true or false)
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

    -- Persistent RT content cache (cacheContent; see state.lua) --------

    --- Begins a persistent group: creates/resizes the keyed RT ONCE and
    --- redirects draws into it. (ox, oy) = the RT origin in screen space
    --- so children with absolute coords land correctly (groupStack
    --- adjust()). NO composite here — compositePersistentGroup draws the
    --- RT, possibly many frames later.
    beginPersistentGroup = function(key, w, h, ox, oy)
        local e = persistentRTs[key]
        if e and e.rt and (e.w ~= w or e.h ~= h) then
            dxDestroyRenderTarget(e.rt)
            e.rt = nil
        end
        if not e or not e.rt then
            local rt = dxCreateRenderTarget(w, h, true)
            if not rt then return false end
            persistentRTs[key] = { rt = rt, w = w, h = h }
            e = persistentRTs[key]
        end
        local n = #groupStack
        local prevTarget = (n > 0) and groupStack[n].rt or nil
        if not dxSetRenderTarget(e.rt, true) then return false end
        groupStack[#groupStack + 1] = { rt = e.rt, offX = ox, offY = oy, prevTarget = prevTarget }
        return true
    end,

    --- Ends a persistent group (restores the previous target; the RT
    --- stays alive in the registry until destroyPersistentRT).
    endPersistentGroup = function()
        local g = table.remove(groupStack)
        if g then
            dxSetRenderTarget(g.prevTarget)
        else
            dxSetRenderTarget(nil)
        end
    end,

    --- Composites a section of a persistent RT (idle frames: ONE draw).
    compositePersistentGroup = function(key, x, y, w, h, sx, sy, sw, sh)
        local e = persistentRTs[key]
        if not e or not e.rt then return false end
        x, y = adjust(x, y)
        dxDrawImageSection(x, y, w, h, sx, sy, sw, sh, e.rt, 0, 0, 0, 0xFFFFFFFF)
        return true
    end,
}

--- Releases a persistent RT (node destroyed/detached; cacheContent).
function DXUI.BackendMTA.destroyPersistentRT(key)
    local e = persistentRTs[key]
    if e and e.rt then dxDestroyRenderTarget(e.rt) end
    persistentRTs[key] = nil
end

--- Wires the MTA measurement backend into the text engine (called once at
-- bootstrap; safe to call repeatedly).
function DXUI.backendInitMTA()
    if DXUI.Text and dxGetTextSize then
        DXUI.Text.setMeasurer(function(text, scale, font)
            -- fontless measures fall back to the system font, matching
            -- the renderer's text draw path
            local f = font or (DXUI.systemFont and DXUI.systemFont()) or "default"
            return dxGetTextSize(text, scale or 1, f)
        end)
    end
end