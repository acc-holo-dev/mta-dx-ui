--[[
    effects.lua — DXUI V3

    Shader effects: rounded rects (SDF), blur, mask + a pooled render-target
    allocator for expensive paths (RT groups, effects).

    Identity rule (state cache contract): effects are SHARED tables keyed by
    inputs — identical items use the same table, so the backend's
    shader-parameter dedup works by pointer identity. Texel sizes are baked
    at CREATION (no per-item clones — the V2 fitBlurTexel flaw is gone).

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

function Effects.whiteTexture()
    if whiteTexture ~= nil then return whiteTexture end
    whiteTexture = false -- nil-detector
    if dxCreateRenderTarget and dxGetRenderTarget and dxSetRenderTarget then
        local ok, rt = pcall(dxCreateRenderTarget, 2, 2)
        if ok and rt then
            local prev = dxGetRenderTarget()
            dxSetRenderTarget(rt)
            dxDrawRectangle(0, 0, 2, 2, 0xFFFFFFFF)
            dxSetRenderTarget(prev)
            whiteTexture = rt
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
                    gTexelSize = { 1 / w, 1 / h }, -- baked once, shared
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

local rtPool, rtCap = {}, 0

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
        local ok, rt = pcall(dxCreateRenderTarget, w, h)
        if ok and rt then return rt end
    end
    return nil
end

--- Returns an RT to the pool with its size key (bounded; overflow destroys
-- the RT instead of pooling). Re-acquire is an exact-size match.
function Effects.releaseRT(rt, key)
    if rtCap >= 64 then
        if isElement and isElement(rt) then destroyElement(rt) end
        return
    end
    rtCap = rtCap + 1
    rtPool[#rtPool + 1] = { rt = rt, key = key }
end

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
    rtCap = 0
    whiteTexture = nil
end

DXUI.Effects = Effects