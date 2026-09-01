--[[
    effects.lua — DXUI V3

    Shader effects: rounded rects (SDF), blur, mask + a pooled render-target
    allocator for expensive paths (RT groups, effects).

    Identity rule (state cache contract): effects are SHARED tables keyed by
    inputs — identical items use the same table, so the backend's
    shader-parameter dedup works by pointer identity. Texel sizes are baked
    at creation, so identical items share one table.

    Outside MTA (tests): dx functions absent → effects return nil, widgets
    degrade to flat draws. Tests stub fake dx functions BEFORE first use.
]]

DXUI = DXUI or {}

local Effects = {}

-- ---------------------------------------------------------------------
-- Shader code (HLSL, ps_2_0)
-- ---------------------------------------------------------------------

local ROUNDED_CODE = [[
texture gTexture0;
float2 gSize;
float gRadius;
sampler2D Samp0 = sampler_state { Texture = <gTexture0>; };
float4 PS(float2 uv : TEXCOORD0) : COLOR0
{
    float2 q = abs(uv * gSize - gSize * 0.5) - (gSize * 0.5 - gRadius);
    float dist = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - gRadius;
    float alpha = 1.0 - smoothstep(-1.0, 0.0, dist);
    return float4(1.0, 1.0, 1.0, alpha);
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

local roundCache, roundCount = {}, 0
local blurCache, blurCount = {}, 0
local maskCache, maskCount = {}, 0
local EFFECT_CAP = 512

--- Inserts a value into a cache, resetting that cache when it overflows.
local function cacheInsert(cache, capName, key, value)
    if capName >= EFFECT_CAP then
        if cache == roundCache then roundCache, roundCount = {}, 0
        elseif cache == blurCache then blurCache, blurCount = {}, 0
        else maskCache, maskCount = {}, 0 end
    end
    cache[key] = value
    if cache == roundCache then roundCount = roundCount + 1
    elseif cache == blurCache then blurCount = blurCount + 1
    else maskCount = maskCount + 1 end
    return value
end

-- White pixel (1x1 RT filled white) — basis for the rounded quad.
local whiteTexture = nil

--- Returns the shared 1x1 white texture, creating it lazily on first use.
function Effects.whiteTexture()
    if whiteTexture ~= nil then return whiteTexture ~= false and whiteTexture or nil end
    -- false marks "dx unavailable" (no retry); nil means "not yet attempted"
    whiteTexture = false
    if dxCreateRenderTarget and dxGetRenderTarget and dxSetRenderTarget then
        local ok, rt = pcall(dxCreateRenderTarget, 2, 2, true)
        if ok and rt then
            local prev = dxGetRenderTarget()
            dxSetRenderTarget(rt)
            dxDrawRectangle(0, 0, 2, 2, 0xFFFFFFFF)
            dxSetRenderTarget(prev)
            whiteTexture = rt
        else
            -- transient failure: allow a retry on the next call
            whiteTexture = nil
        end
    end
    return whiteTexture ~= false and whiteTexture or nil
end

--- Shared rounded-rect effect (identity per w×h×radius).
function Effects.round(w, h, radius)
    local key = "r" .. w .. "x" .. h .. "r" .. radius
    local cached = roundCache[key]
    if cached then return cached end
    local fx
    if dxCreateShader then
        local sh = DXUI.shader and DXUI.shader(ROUNDED_CODE)
        if sh then
            fx = {
                shader = sh,
                texture = Effects.whiteTexture(),
                params = { gSize = { w, h }, gRadius = radius },
            }
        end
    end
    if not fx then return nil end
    return cacheInsert(roundCache, roundCount, key, fx)
end

--- Shared blur effect (identity per w×h×strength; texel baked).
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

--- Shared mask effect (identity per mask texture).
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
-- Node effect resolution (the renderer's resolveEffect hook)
-- ---------------------------------------------------------------------

--- The image-path effect for a node carrying blur/mask (mask wins for
-- images; combining both happens via an RT group in the pass).
function Effects.effectForImage(node)
    if node.mask then return Effects.mask(node.mask) end
    if node.blur and node.blur > 0 then
        return Effects.blur(node.width, node.height, node.blur)
    end
    return nil
end

--- Whether the node needs an RT group (non-image effects: blur/mask on
-- containers, or clipMode="rt").
function Effects.needsGroup(node, engine)
    if node.clipMode == "rt" then return true end
    local hasFx = (node.blur and node.blur > 0) or (node.mask ~= nil)
    -- images draw effects with a direct shader (cheaper, see image.lua)
    local isImage = node._class ~= nil and node._class._name == "Image"
    return hasFx and not isImage
end

--- Whether the RT path is available.
function Effects.canGroup()
    return dxCreateShader ~= nil and dxCreateRenderTarget ~= nil
end

-- ---------------------------------------------------------------------
-- Render-target pool
-- ---------------------------------------------------------------------

local rtPool = {}
local RT_POOL_CAP = 64

--- Acquires an RT of at least w×h (exact match first). Creation on miss.
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

--- Returns an RT to the pool with its size key (bounded; overflow destroys
-- the RT instead of pooling). Re-acquire is an exact-size match.
function Effects.releaseRT(rt, key)
    if #rtPool >= RT_POOL_CAP then
        if isElement and isElement(rt) then destroyElement(rt) end
        return
    end
    rtPool[#rtPool + 1] = { rt = rt, key = key }
end

--- Destroys every pooled RT and the white texture (full teardown).
function Effects.releasePool()
    if isElement and destroyElement then
        for i = 1, #rtPool do
            local e = rtPool[i]
            if e and e.rt and isElement(e.rt) then destroyElement(e.rt) end
        end
        if whiteTexture and isElement(whiteTexture) then
            destroyElement(whiteTexture)
        end
    end
    rtPool = {}
    whiteTexture = nil
end

--- Destroys every cached shader/RT (called by releaseResources on stop).
function Effects.clearCaches()
    if isElement and destroyElement then
        for key, fx in pairs(roundCache) do
            if fx.shader and isElement(fx.shader) then destroyElement(fx.shader) end
        end
        for key, fx in pairs(blurCache) do
            if fx.shader and isElement(fx.shader) then destroyElement(fx.shader) end
        end
        for key, fx in pairs(maskCache) do
            if fx.shader and isElement(fx.shader) then destroyElement(fx.shader) end
        end
    end
    roundCache, roundCount = {}, 0
    blurCache, blurCount = {}, 0
    maskCache, maskCount = {}, 0
end

DXUI.Effects = Effects