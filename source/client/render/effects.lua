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

-- ---------------------------------------------------------------------
-- Shared effect caches (identity-stable, bounded; whole-cache reset on
-- overflow — a couple of redundant param sets, then convergence)
-- ---------------------------------------------------------------------

local blurCache, blurCount = {}, 0
local maskCache, maskCount = {}, 0
local EFFECT_CAP = 512

---Inserts a value into a cache, resetting that cache when it overflows.
local function cacheInsert(cache, count, key, value)
    if count >= EFFECT_CAP then
        if cache == blurCache then blurCache, blurCount = {}, 0
        else maskCache, maskCount = {}, 0 end
        count = 0
    end
    cache[key] = value
    if cache == blurCache then blurCount = count + 1
    else maskCount = count + 1 end
    return value
end

-- The single shared rounded-rect shader instance (nil until first use,
-- false after a failed attempt — no retry thrash).
local roundedShader = nil

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
    return cacheInsert(blurCache, blurCount, key, fx)
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
    return cacheInsert(maskCache, maskCount, maskTexture, fx)
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

---Acquires an RT of at least w×h (exact match first). Creation on miss.
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
    end
    blurCache, blurCount = {}, 0
    maskCache, maskCount = {}, 0
    roundedShader = nil
end

DXUI.Effects = Effects