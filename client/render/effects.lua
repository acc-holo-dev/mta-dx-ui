--[[
    effects.lua — DXUI V2

    Shader effects: rounded rects (SDF shader), blur, mask.
    Extensibility point: any item can carry effect = { shader, params,
    texture } — the backend applies params and draws with the shader.

    Shaders are cached (DXUI.shader, one per widget); the white pixel is
    one RT per process. Mask: a special path ONLY for nodes with mask;
    regular nodes take the fast path without shaders.
    Blur for images (direct shader, without RT — like legacy M8);
    rect/text blur (RT pass) — future extension point.

    Outside MTA (tests): dx functions are absent → effects return nil,
    widgets degrade to a flat rect / an effect without shader. Tests may
    stub fake dx functions BEFORE first use (lazy init).
]]

DXUI = DXUI or {}

local Effects = {}

-- ---------------------------------------------------------------------
-- Shader code (HLSL, ps_2_0)
-- ---------------------------------------------------------------------

-- Rounded rectangle via signed distance field: exact rounded corners at
-- any radius, AA via smoothstep, resolution-independent.
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

-- 5-tap Gaussian blur (same as legacy M8 — proven in-game).
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

-- Mask: base texture alpha multiplied by mask alpha (same UV layout).
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
-- White pixel (1x1 RT filled with white) — basis for the rounded quad.
-- Created once, lazily (on first rounded use).
-- ---------------------------------------------------------------------

local whiteTexture = nil

function Effects.whiteTexture()
    if whiteTexture ~= nil then return whiteTexture end
    whiteTexture = false -- nil-detector: don't retry every frame
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
    return whiteTexture
end

local function shaderFor(code)
    if not dxCreateShader then return nil end
    return DXUI.shader(code) -- cached by code
end

-- ---------------------------------------------------------------------
-- Public effects: each returns { shader, params, texture? } or nil
-- (unavailable — widget degrades to the flat path).
-- ---------------------------------------------------------------------

--- Rounded rect. w/h/radius in SCREEN pixels (renderer already scaled).
function Effects.rounded(w, h, radius)
    local sh = shaderFor(ROUNDED_CODE)
    local tex = sh and Effects.whiteTexture()
    if not sh or not tex then return nil end
    return {
        shader = sh,
        texture = tex,
        params = { gSize = { w, h }, gRadius = radius },
    }
end

--- Blur for an image (direct shader on the texture, no RT).
function Effects.blur(w, h, strength)
    local sh = shaderFor(BLUR_CODE)
    if not sh then return nil end
    return {
        shader = sh,
        params = { gBlur = strength, gTexelSize = { 1 / math.max(w, 1), 1 / math.max(h, 1) } },
    }
end

--- Mask: maskTexture — the mask texture (alpha controls visibility).
function Effects.mask(maskTexture)
    if not maskTexture then return nil end
    local sh = shaderFor(MASK_CODE)
    if not sh then return nil end
    return {
        shader = sh,
        params = { gMask = maskTexture },
    }
end

DXUI.Effects = Effects

-- ---------------------------------------------------------------------
-- Named effect registry (M23): external plugins register custom effects.
-- ---------------------------------------------------------------------

DXUI._effects = DXUI._effects or {}

--- Registers a named effect. fn(node) returns { shader, params, texture }
-- or nil (unavailable — widget degrades to the flat path).
function DXUI.registerEffect(name, fn)
    DXUI._effects[name] = fn
end

--- Resolves a named effect for a node. Returns { shader, params, texture }
-- or nil.
function DXUI.getEffect(name, node)
    local fn = DXUI._effects and DXUI._effects[name]
    if not fn then return nil end
    return fn(node)
end

-- ---------------------------------------------------------------------
-- RT pool (expensive path / effect layer): offscreen compositing for
-- node-level blur/mask. Pooled by size — RTs are reused, not created
-- per draw (no RT per node).
-- ---------------------------------------------------------------------

local rtPool = {}     -- [key] = { rt1, rt2, ... }
local rtKey = {}      -- [rt] = key (for release)

--- Takes an RT from the pool (or creates one). nil if RTs unavailable (outside MTA).
function Effects.acquireRT(w, h)
    w = math.max(1, math.floor(w or 1))
    h = math.max(1, math.floor(h or 1))
    local key = w .. "x" .. h
    local list = rtPool[key]
    if list and #list > 0 then
        local rt = list[#list]
        list[#list] = nil
        return rt
    end
    if not dxCreateRenderTarget then return nil end
    local ok, rt = pcall(dxCreateRenderTarget, w, h)
    if ok and rt then
        rtKey[rt] = key
        return rt
    end
    return nil
end

--- Sets the effect's gTexelSize to match a SCREEN-space quad.
-- Effects.blur is created with design-space size; when the design resolution
-- scales the quad, the blur offset (in texels of the sampled target) must use
-- 1/(drawn px), not 1/(design px). Returns a shallow clone (params copied) so
-- shared/named effects are never mutated.
function Effects.fitBlurTexel(effect, qw, qh)
    if not effect or not effect.params or not effect.params.gTexelSize then
        return effect
    end
    local p = effect.params
    return {
        shader = effect.shader, texture = effect.texture,
        params = {
            gBlur = p.gBlur,
            gTexelSize = { 1 / math.max(qw, 1), 1 / math.max(qh, 1) },
        },
    }
end

--- Returns an RT to the pool.
function Effects.releaseRT(rt)
    if not rt then return end
    local key = rtKey[rt]
    if not key then return end
    rtPool[key] = rtPool[key] or {}
    rtPool[key][#rtPool[key] + 1] = rt
end

--- Whether the RT path is available (node-level effects): needs shader AND render target.
function Effects.canGroup()
    return dxCreateShader ~= nil and dxCreateRenderTarget ~= nil
end

--- Destroys all pooled RTs (releaseResources / resolution change).
function Effects.releasePool()
    if isElement and destroyElement then
        for _, list in pairs(rtPool) do
            for i = 1, #list do
                if isElement(list[i]) then destroyElement(list[i]) end
            end
        end
        -- the white pixel is an RT too — destroy, not just drop the ref
        if whiteTexture and isElement(whiteTexture) then
            destroyElement(whiteTexture)
        end
    end
    rtPool, rtKey = {}, {}
    whiteTexture = nil -- white pixel is an RT too — re-created lazily
end