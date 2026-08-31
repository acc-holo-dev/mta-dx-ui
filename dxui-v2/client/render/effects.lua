--[[
    effects.lua — DXUI V2

    Shader-эффекты (§36–§40): rounded rects (SDF-шейдер), blur, mask.
    Extensibility point: любой item может нести effect = { shader, params,
    texture } — backend применяет params и рисует с шейдером.

    §37: «Не создавать лишний resource per node» — шейдеры кэшируются
    (DXUI.shader, один на вид), white-пиксель — один RT на процесс.
    §36: mask — специальный path ТОЛЬКО для узлов с mask; обычные узлы идут
    по fast path без шейдеров.
    §39: blur для изображений (прямой шейдер, без RT — как legacy M8);
    rect/text blur (RT-проход) — future extension point.

    Вне MTA (тесты): dx-функции отсутствуют → эффекты возвращают nil,
    виджеты деградируют на плоский rect / эффект без шейдера. Тесты могут
    подставить фейковые dx-функции ДО первого использования (lazy init).
]]

DXUI = DXUI or {}

local Effects = {}

-- ---------------------------------------------------------------------
-- Шейдерные коды (HLSL, ps_2_0)
-- ---------------------------------------------------------------------

-- Rounded rectangle через signed distance field: точные скруглённые углы
-- любого радиуса, AA через smoothstep, разрешение-независимо.
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

-- 5-tap Gaussian blur (тот же, что legacy M8 — проверен в игре).
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

-- Маска: альфа базовой текстуры умножается на альфу маски (та же UV-развёртка).
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
-- White-пиксель (1×1 RT, заполняется белым) — база для rounded-квада.
-- Создаётся один раз, лениво (первое использование rounded).
-- ---------------------------------------------------------------------

local whiteTexture = nil

function Effects.whiteTexture()
    if whiteTexture ~= nil then return whiteTexture end
    whiteTexture = false -- nil-детектор: не ретраить каждый кадр
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
    return DXUI.shader(code) -- кэш по коду (§40: shader cache)
end

-- ---------------------------------------------------------------------
-- Публичные эффекты: каждый возвращает { shader, params, texture? } или nil
-- (недоступно — виджет деградирует на плоский путь).
-- ---------------------------------------------------------------------

--- Rounded rect. w/h/radius — в ЭКРАННЫХ пикселях (renderer уже отскейлил).
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

--- Blur для изображения (прямой шейдер на текстуру, без RT).
function Effects.blur(w, h, strength)
    local sh = shaderFor(BLUR_CODE)
    if not sh then return nil end
    return {
        shader = sh,
        params = { gBlur = strength, gTexelSize = { 1 / math.max(w, 1), 1 / math.max(h, 1) } },
    }
end

--- Маска (§36): maskTexture — текстура-маска (альфа управляет видимостью).
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
-- RT-пул (§35 expensive path / §39 effect layer): offscreen-композитинг
-- для node-level blur/mask. Пул по размеру — RT переиспользуются, не
-- создаётся per draw (§87: не RT per node).
-- ---------------------------------------------------------------------

local rtPool = {}     -- [key] = { rt1, rt2, ... }
local rtKey = {}      -- [rt] = key (для release)

--- Берёт RT из пула (или создаёт). nil если RT недоступны (вне MTA).
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

--- Возвращает RT в пул.
function Effects.releaseRT(rt)
    if not rt then return end
    local key = rtKey[rt]
    if not key then return end
    rtPool[key] = rtPool[key] or {}
    rtPool[key][#rtPool[key] + 1] = rt
end

--- Доступен ли RT-путь (для node-level эффектов): нужны шейдер И рендер-таргет.
function Effects.canGroup()
    return dxCreateShader ~= nil and dxCreateRenderTarget ~= nil
end

--- Уничтожает все RT из пула (releaseResources / смена разрешения).
function Effects.releasePool()
    if isElement and destroyElement then
        for _, list in pairs(rtPool) do
            for i = 1, #list do
                if isElement(list[i]) then destroyElement(list[i]) end
            end
        end
    end
    rtPool, rtKey = {}, {}
    whiteTexture = nil -- white-пиксель тоже RT — пересоздадится лениво
end