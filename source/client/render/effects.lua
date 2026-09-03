---Shader effects (DXUI.Effects): the rounded-rect SDF shader, blur, mask
---and a pooled render-target allocator for expensive paths.
---
---Rounded rectangles (V4): ONE shared shader instance for every rounded
---draw in the process. The shader does border + fill with PER-CORNER radii
---in a single pass; the backend dedupes parameter sets before uploading
---(shadow compare — there are no per-size effect tables, no param churn).
---The shader ignores its input texture (pure uv-space SDF), so no base
---texture is bound for rrect draws.
---
---Blur/mask stay input-cached (identity-stable shared tables keyed by
---their inputs) — they are per-container/per-image effects.
---
---Outside MTA (tests): dx functions are absent; roundedShader() returns
---nil and widgets degrade to flat draws. Suites that need the shader path
---stub fake dx functions BEFORE first use.

DXUI = DXUI or {}

local Effects = {}

-- ---------------------------------------------------------------------
-- Shader code (HLSL, ps_2_0)
-- ---------------------------------------------------------------------

---Rounded rect: one-draw border + fill with per-corner radii.
---gRadii = (TL, TR, BR, BL); ring pixels take gBorderColor, inner
---pixels gFillColor; the outer edge is 1px antialiased.
local ROUNDED_CODE = [[
float2 gSize;
float4 gRadii;
float gBorder;
float4 gFillColor;
float4 gBorderColor;
float4 PS(float2 uv : TEXCOORD0) : COLOR0
{
    float2 hc = gSize * 0.5;
    float2 p = uv * gSize;
    float r;
    if (p.x < hc.x)
    {
        if (p.y < hc.y) { r = gRadii.x; } else { r = gRadii.w; }
    }
    else
    {
        if (p.y < hc.y) { r = gRadii.y; } else { r = gRadii.z; }
    }
    float2 q = abs(p - hc) - (hc - r);
    float dist = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    // ring = dist + border: negative inside the fill zone
    float ring = dist + gBorder;
    float4 col;
    if (ring < 0.0) { col = gFillColor; } else { col = gBorderColor; }
    col.a = col.a * (1.0 - smoothstep(-1.0, 0.0, dist));
    return col;
}
technique rounded
{
    pass P0 { PixelShader = compile ps_2_0 PS(); }
}
]]

local BLUR_CODE = [[
texture gTexture0;
float gBlur;
float2 gTexelSize;
sampler2D Samp0 = sampler_state
{
    Texture = <gTexture0>;
    AddressU = Clamp;
    AddressV = Clamp;
};
float4 PS(float2 uv : TEXCOORD0) : COLOR0
{
    float4 c = tex2D(Samp0, uv) * 0.5;
    float2 off = gTexelSize * gBlur;
    c += tex2D(Samp0, uv + float2(off.x, 0)) * 0.125;
    c += tex2D(Samp0, uv - float2(off.x, 0)) * 0.125;
    c += tex2D(Samp0, uv + float2(0, off.y)) * 0.125;
    c += tex2D(Samp0, uv - float2(0, off.y)) * 0.125;
    return c;
}
technique blur
{
    pass P0 { PixelShader = compile ps_2_0 PS(); }
}
]]

local MASK_CODE = [[
texture gTexture0;
texture gMask;
sampler2D Samp0 = sampler_state { Texture = <gTexture0>; };
sampler2D MaskSamp = sampler_state { Texture = <gMask>; };
float4 PS(float2 uv : TEXCOORD0) : COLOR0
{
    float4 c = tex2D(Samp0, uv);
    float m = tex2D(MaskSamp, uv).a;
    return float4(c.rgb, c.a * m);
}
technique mask
{
    pass P0 { PixelShader = compile ps_2_0 PS(); }
}
]]

---Linear gradient (E6): pure uv-space lerp between two colors along an
---angle (0° = left→right, 90° = top→bottom in screen space). gDir is the
---normalized axis, gSpan the min/max corner projections onto it — both
---precomputed in Lua so the pixel shader stays a dot product + lerp.
local GRADIENT_CODE = [[
float2 gSize;
float2 gDir;
float2 gSpan;
float4 gFrom;
float4 gTo;
float4 PS(float2 uv : TEXCOORD0) : COLOR0
{
    float2 p = uv * gSize;
    float t = saturate((dot(p, gDir) - gSpan.x) / gSpan.y);
    return lerp(gFrom, gTo, t);
}
technique gradient
{
    pass P0 { PixelShader = compile ps_2_0 PS(); }
}
]]

-- ---------------------------------------------------------------------
-- Shared effect caches (identity-stable, bounded; whole-cache reset on
-- overflow — a couple of redundant param sets, then convergence)
-- ---------------------------------------------------------------------

local blurCache, blurCount = {}, 0
local maskCache, maskCount = {}, 0
local gradCache, gradCount = {}, 0
local EFFECT_CAP = 512

---Inserts a value into a cache, resetting that cache when it overflows.
-- The reset clears the SAME table in place (not a reassignment) so the
-- caller's `cache` reference and the module-level cache stay consistent.
-- Returns the new entry count (the caller owns the count variable).
local function cacheInsert(cache, count, key, value)
    if count >= EFFECT_CAP then
        for k in pairs(cache) do cache[k] = nil end
        count = 0
    end
    cache[key] = value
    return count + 1
end

-- The single shared rounded-rect shader instance (nil until first use,
-- false after a failed attempt — no retry thrash).
local roundedShader = nil

-- The single shared linear-gradient shader instance (same lifecycle).
local gradientShader = nil

---Returns the process-wide rounded-rect SDF shader element, or nil when
---shaders are unavailable (headless/tests; callers degrade gracefully).
function Effects.roundedShader()
    if roundedShader ~= nil then return roundedShader ~= false and roundedShader or nil end
    roundedShader = false
    if dxCreateShader then
        local sh = DXUI.shader and DXUI.shader(ROUNDED_CODE)
        if sh then roundedShader = sh end
    end
    return roundedShader ~= false and roundedShader or nil
end

---Returns the process-wide linear-gradient shader element, or nil when
---shaders are unavailable.
function Effects.gradientShader()
    if gradientShader ~= nil then return gradientShader ~= false and gradientShader or nil end
    gradientShader = false
    if dxCreateShader then
        local sh = DXUI.shader and DXUI.shader(GRADIENT_CODE)
        if sh then gradientShader = sh end
    end
    return gradientShader ~= false and gradientShader or nil
end

--- 0xAARRGGBB → {r, g, b, a} floats (dxSetShaderValue float4).
local function colorFloats(c)
    return {
        math.floor(c / 0x10000) % 0x100 / 255,
        math.floor(c / 0x100) % 0x100 / 255,
        c % 0x100 / 255,
        math.floor(c / 0x1000000) % 0x100 / 255,
    }
end

---Shared linear-gradient effect (E6): ONE shader instance for every
---node; the param-set TABLE is cached per (size, angle, colors) so the
---backend's identity dedup skips re-uploads between equal gradients.
---spec = { from = 0xAARRGGBB, to = 0xAARRGGBB, angle = degrees }.
---The shader ignores its input texture — callers draw the shader element
---itself as the quad material (see Panel/Button/Image `gradient`).
function Effects.gradient(w, h, spec)
    if w <= 0 or h <= 0 then return nil end
    local from = spec.from or 0xFFFFFFFF
    local to = spec.to or 0xFF000000
    local angle = spec.angle or 0
    local key = w .. "x" .. h .. "a" .. angle .. ":" .. from .. ":" .. to
    local cached = gradCache[key]
    if cached then return cached end
    local sh = Effects.gradientShader()
    if not sh then return nil end
    -- axis in screen space (y grows down); the span maps the rect's
    -- corner projections onto the axis → t = 0..1 across the quad
    local rad = math.rad(angle)
    local dxr, dyr = math.cos(rad), math.sin(rad)
    local pmin = math.min(0, w * dxr) + math.min(0, h * dyr)
    local pmax = math.max(0, w * dxr) + math.max(0, h * dyr)
    local fx = {
        shader = sh,
        params = {
            gSize = { w, h },
            gDir = { dxr, dyr },
            gSpan = { pmin, math.max(pmax - pmin, 0.0001) },
            gFrom = colorFloats(from),
            gTo = colorFloats(to),
        },
    }
    gradCount = cacheInsert(gradCache, gradCount, key, fx)
    return fx
end

---Shared blur effect (identity per w×h×strength; texel baked).
function Effects.blur(w, h, strength)
    local key = "b" .. w .. "x" .. h .. "s" .. strength
    local cached = blurCache[key]
    if cached then return cached end
    local fx
    if dxCreateShader then
        local sh = DXUI.shader and DXUI.shader(BLUR_CODE)
        if sh then
            fx = {
                shader = sh,
                params = {
                    gBlur = strength,
                    -- baked once, shared by every item with this size
                    gTexelSize = { 1 / w, 1 / h },
                },
            }
        end
    end
    if not fx then return nil end
    blurCount = cacheInsert(blurCache, blurCount, key, fx)
    return fx
end

---Shared mask effect (identity per mask texture).
function Effects.mask(maskTexture)
    local cached = maskCache[maskTexture]
    if cached then return cached end
    local fx
    if dxCreateShader then
        local sh = DXUI.shader and DXUI.shader(MASK_CODE)
        if sh then fx = { shader = sh, params = { gMask = maskTexture } } end
    end
    if not fx then return nil end
    maskCount = cacheInsert(maskCache, maskCount, maskTexture, fx)
    return fx
end

-- ---------------------------------------------------------------------
-- Backdrop source (E5: frosted-glass windows)
-- ---------------------------------------------------------------------

local screenSource = nil
local screenSourceW, screenSourceH = 0, 0
local screenSourceFrame = nil

---Lazy global screen source at HALF resolution (cheaper capture and
---blur). Updated ONCE per frame and only in frames where a backdrop
---node actually drew (frame stamp from the caller: runtime.stats.frames)
---— the world of the PREVIOUS frame. No visible backdrop node anywhere
---→ the source is never created nor updated (zero-work idle contract).
function Effects.backdropSource(frameStamp)
    if not dxCreateScreenSource then return nil end
    if not screenSource then
        local sw, sh = 0, 0
        if guiGetScreenSize then sw, sh = guiGetScreenSize() end
        if sw <= 0 or sh <= 0 then return nil end
        local w = math.max(1, math.floor(sw / 2))
        local h = math.max(1, math.floor(sh / 2))
        local ok, src = pcall(dxCreateScreenSource, w, h)
        if not ok or not src then return nil end
        screenSource, screenSourceW, screenSourceH = src, w, h
    end
    if frameStamp ~= screenSourceFrame then
        screenSourceFrame = frameStamp
        if dxUpdateScreenSource then
            pcall(dxUpdateScreenSource, screenSource, false)
        end
    end
    return screenSource
end

---Backdrop source pixel size (0, 0 when not created).
function Effects.backdropSourceSize()
    return screenSourceW, screenSourceH
end

---Draws the frosted backdrop of a node rect (E5): the half-res screen
---source through the shared blur shader, cropped to the node's screen
---rect. Call from the node's render() BEFORE its surface. Nothing draws
---when no source (headless), a degenerate crop or no shaders.
function Effects.renderBackdrop(renderer, node, strength)
    local ctx = node._context
    if not ctx then return end
    local src = Effects.backdropSource(ctx.stats and ctx.stats.frames or 0)
    if not src then return end
    local sw, sh = Effects.backdropSourceSize()
    local msx, msy = ctx._mapScaleX or 1, ctx._mapScaleY or 1
    local mox, moy = ctx._mapOffX or 0, ctx._mapOffY or 0
    -- the node's screen rect (the same mapping the pass applies at emit)
    local x = node.worldX * msx + mox
    local y = node.worldY * msy + moy
    local w = node.width * msx
    local h = node.height * msy
    -- crop in SOURCE pixels (half-res), clamped to the source bounds
    local cx, cy, cw, ch = x / 2, y / 2, w / 2, h / 2
    if cx < 0 then cx = 0 end
    if cy < 0 then cy = 0 end
    if cx + cw > sw then cw = sw - cx end
    if cy + ch > sh then ch = sh - cy end
    if cw <= 0 or ch <= 0 then return end
    local fx = Effects.blur(cw, ch, strength)
    if not fx then return end
    -- texture = the SOURCE (the backend binds it as gTexture0), the
    -- drawn material = the blur shader, section = the source crop;
    -- a rect clamped at the screen edge stretches the rest — fine for
    -- a frosted look
    renderer.fx = fx
    renderer:image(src, node.worldX, node.worldY, node.width, node.height,
        0xFFFFFFFF, { cx, cy, cw, ch })
    renderer.fx = nil
end

-- ---------------------------------------------------------------------
-- Node effect resolution (the pass reads these for RT groups / images)
-- ---------------------------------------------------------------------

---The image-path effect for a node carrying blur/mask (mask wins for
---images; combining both happens via an RT group in the pass).
function Effects.effectForImage(node)
    if node.mask then return Effects.mask(node.mask) end
    if node.blur and node.blur > 0 then
        return Effects.blur(node.width, node.height, node.blur)
    end
    return nil
end

---Whether the node needs an RT group (non-image effects: blur/mask on
---containers, or clipMode="rt").
function Effects.needsGroup(node)
    if node.clipMode == "rt" then return true end
    local hasFx = (node.blur and node.blur > 0) or (node.mask ~= nil)
    -- images draw effects with a direct shader (cheaper, see image.lua)
    local isImage = node._class ~= nil and node._class._name == "Image"
    return hasFx and not isImage
end

---Whether the RT path is available.
function Effects.canGroup()
    return dxCreateShader ~= nil and dxCreateRenderTarget ~= nil
end

-- ---------------------------------------------------------------------
-- Render-target pool
-- ---------------------------------------------------------------------

local rtPool = {}
local RT_POOL_CAP = 64

---Acquires an RT of exactly w×h (pooled by exact size key; miss = create).
function Effects.acquireRT(w, h)
    local key = w .. "x" .. h
    local reuseAt, reuseEntry = nil, nil
    for i = 1, #rtPool do
        local e = rtPool[i]
        if e.key == key then
            reuseAt, reuseEntry = i, e
            break
        end
    end
    if reuseEntry then
        table.remove(rtPool, reuseAt)
        return reuseEntry.rt
    end
    if dxCreateRenderTarget then
        -- withAlpha=true keeps transparency inside the group (rounded
        -- corners, faded children); false would render opaque black.
        local ok, rt = pcall(dxCreateRenderTarget, w, h, true)
        if ok and rt then return rt end
    end
    return nil
end

---Returns an RT to the pool with its size key (bounded; overflow destroys
---the RT instead of pooling). Re-acquire is an exact-size match.
function Effects.releaseRT(rt, key)
    if #rtPool >= RT_POOL_CAP then
        if isElement and isElement(rt) then destroyElement(rt) end
        return
    end
    rtPool[#rtPool + 1] = { rt = rt, key = key }
end

---Destroys every pooled RT (full teardown).
function Effects.releasePool()
    if isElement and destroyElement then
        for i = 1, #rtPool do
            local e = rtPool[i]
            if e and e.rt and isElement(e.rt) then destroyElement(e.rt) end
        end
    end
    rtPool = {}
end

---Destroys every cached shader (called by releaseResources on stop; the
---rounded shader is re-created lazily on next use).
function Effects.clearCaches()
    if isElement and destroyElement then
        for _, fx in pairs(blurCache) do
            if fx.shader and isElement(fx.shader) then destroyElement(fx.shader) end
        end
        for _, fx in pairs(maskCache) do
            if fx.shader and isElement(fx.shader) then destroyElement(fx.shader) end
        end
        if type(roundedShader) == "userdata" and isElement(roundedShader) then
            destroyElement(roundedShader)
        end
        if type(gradientShader) == "userdata" and isElement(gradientShader) then
            destroyElement(gradientShader)
        end
        if screenSource and isElement(screenSource) then
            destroyElement(screenSource)
        end
    end
    blurCache, blurCount = {}, 0
    maskCache, maskCount = {}, 0
    gradCache, gradCount = {}, 0
    roundedShader = nil
    gradientShader = nil
    screenSource, screenSourceW, screenSourceH = nil, 0, 0
    screenSourceFrame = nil
end

DXUI.Effects = Effects