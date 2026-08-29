--[[
    backend_mta.lua

    Реализация драйвера рендера поверх MTA DX9 (dxDraw*/dxSetBlendMode).

    M8 (ADR-011): RT-based clip + real opacity + blur-шейдер.
      - clip: pushClip/popClip через RTManager (dxCreateRenderTarget).
      - opacity: модуляция альфа-канала packed 0xAARRGGBB через bitReplace.
      - blur: 5-tap Gaussian blur shader. Image — напрямую (dxDrawImage+shader).
        Rect/Text (M10) — blur-fallback: рендер в RT, затем draw RT с шейдером.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

-- M8: 5-tap Gaussian blur shader (pass-through если gBlur=0).
local BLUR_SHADER_CODE = [[
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

technique simple
{
    pass P0
    {
        PixelShader = compile ps_2_0 PS();
    }
}
]]

local function applyOpacity(color, opacity)
    if opacity >= 255 then return color end
    if opacity <= 0 then
        -- Полностью прозрачный: обнуляем альфа
        return bitReplace(color, 0, 24, 8)
    end
    local a = bitExtract(color, 24, 8)
    local newA = math.floor(a * opacity / 255)
    return bitReplace(color, newA, 24, 8)
end

DXUI.MtaDriver = {
    rtManager = nil, -- инициализируется ниже
    blurShader = nil,
    currentOpacity = 255,
    currentBlur = 0,

    setBlendMode = function(mode)
        dxSetBlendMode(mode)
    end,

    -- M8: clip-стек управляется RT Manager
    pushClip = function(x, y, w, h)
        DXUI.MtaDriver.rtManager:pushClip(x, y, w, h)
    end,

    popClip = function()
        DXUI.MtaDriver.rtManager:popClip()
    end,

    setOpacity = function(opacity)
        DXUI.MtaDriver.currentOpacity = opacity
    end,

    setBlur = function(blur)
        DXUI.MtaDriver.currentBlur = blur
    end,

    drawRect = function(x, y, w, h, color)
        local c = applyOpacity(color, DXUI.MtaDriver.currentOpacity)
        local blur = DXUI.MtaDriver.currentBlur
        local rm = DXUI.MtaDriver.rtManager
        if blur and blur > 0 and DXUI.MtaDriver.blurShader then
            -- M10: blur-fallback — рендер rect в RT, затем draw RT с шейдером.
            local prevRT = rm:getCurrentRT()
            local rt = rm:acquire(w, h)
            dxSetRenderTarget(rt, true)
            dxDrawRectangle(0, 0, w, h, c)
            dxSetRenderTarget(prevRT)
            dxSetShaderValue(DXUI.MtaDriver.blurShader, "gBlur", blur)
            dxSetShaderValue(DXUI.MtaDriver.blurShader, "gTexelSize", 1/w, 1/h)
            dxDrawImage(x - rm.offsetX, y - rm.offsetY, w, h, rt, 0, 0, 0, 0xFFFFFFFF, DXUI.MtaDriver.blurShader)
            rm:release(rt)
        else
            dxDrawRectangle(x - rm.offsetX, y - rm.offsetY, w, h, c)
        end
    end,

    drawImage = function(x, y, w, h, texture, color)
        local c = applyOpacity(color, DXUI.MtaDriver.currentOpacity)
        local blur = DXUI.MtaDriver.currentBlur
        local shader = nil
        if blur and blur > 0 and DXUI.MtaDriver.blurShader then
            dxSetShaderValue(DXUI.MtaDriver.blurShader, "gBlur", blur)
            dxSetShaderValue(DXUI.MtaDriver.blurShader, "gTexelSize", 1/w, 1/h)
            shader = DXUI.MtaDriver.blurShader
        end
        dxDrawImage(x - DXUI.MtaDriver.rtManager.offsetX,
                    y - DXUI.MtaDriver.rtManager.offsetY,
                    w, h, texture, 0, 0, 0, c, shader)
    end,

    drawText = function(text, x, y, w, h, color)
        local c = applyOpacity(color, DXUI.MtaDriver.currentOpacity)
        local blur = DXUI.MtaDriver.currentBlur
        local rm = DXUI.MtaDriver.rtManager
        if blur and blur > 0 and DXUI.MtaDriver.blurShader then
            -- M10: blur-fallback — рендер text в RT, затем draw RT с шейдером.
            local prevRT = rm:getCurrentRT()
            local rt = rm:acquire(w, h)
            dxSetRenderTarget(rt, true)
            dxDrawText(text, 0, 0, w, h, c)
            dxSetRenderTarget(prevRT)
            dxSetShaderValue(DXUI.MtaDriver.blurShader, "gBlur", blur)
            dxSetShaderValue(DXUI.MtaDriver.blurShader, "gTexelSize", 1/w, 1/h)
            dxDrawImage(x - rm.offsetX, y - rm.offsetY, w, h, rt, 0, 0, 0, 0xFFFFFFFF, DXUI.MtaDriver.blurShader)
            rm:release(rt)
        else
            dxDrawText(text,
                       x - rm.offsetX,
                       y - rm.offsetY,
                       x + w - rm.offsetX,
                       y + h - rm.offsetY,
                       c)
        end
    end,
}

-- M8: lazy init RTManager + blur shader. В tests/вне MTA этот init не вызывается,
-- но если backend_mta.lua загружен, создаём пустые объекты только при наличии dxCreateRenderTarget.
if dxCreateRenderTarget then
    DXUI.MtaDriver.rtManager = DXUI.RTManager.new()
    local ok, shader = pcall(dxCreateShader, BLUR_SHADER_CODE)
    if ok and shader then
        DXUI.MtaDriver.blurShader = shader
    end
end
