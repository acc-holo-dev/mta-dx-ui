--[[
    backend_mta.lua — DXUI V2

    Реализация backend поверх MTA DX9 (dxDraw*/dxSetBlendMode).

    Это единственная точка входа внешней зависимости от dx*-функций во всём
    движке. В тестах вместо него используется мок (см. tests/).

    Stage 9 (§36–§40): drawRoundedRect (SDF-шейдер, fallback — плоский rect),
    drawImage с effect (шейдер: blur/mask) и section (кроп через
    dxDrawImageSection — без искажения пропорций).

    Stage 10 (§35/§39): RT-группы (effect layer). beginGroup переключает
    рендер в offscreen RT и задаёт offset; draw-функции вычитают offset
    (координаты внутри RT — локальные); endGroup возвращает target и рисует
    RT с эффектом (blur/mask). Так node-level эффекты получают pixel-perfect
    композицию без изменения модели items.
]]

DXUI = DXUI or {}

--- Применяет params эффекта к шейдеру. Возвращает shader или nil.
local function applyEffect(effect)
    if not effect or not effect.shader then return nil end
    if effect.params then
        for k, v in pairs(effect.params) do
            dxSetShaderValue(effect.shader, k, v)
        end
    end
    return effect.shader
end

-- Стек активных RT-групп: { { rt, offX, offY }, ... }. Пуст — рисуем на экран.
local groupStack = {}

--- Вычитает текущий group-offset (world → локальные координаты RT).
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

    --- Rounded rect (§37): white-квад с SDF-шейдером; цвет — через tint
    -- dxDrawImage (шейдер выводит белый + альфу углов). Без шейдера — плоский rect.
    drawRoundedRect = function(x, y, w, h, radius, color, effect)
        x, y = adjust(x, y)
        local shader = applyEffect(effect)
        if shader and effect.texture then
            dxDrawImage(x, y, w, h, effect.texture, 0, 0, 0, color, shader)
        else
            dxDrawRectangle(x, y, w, h, color) -- деградация (нет шейдера)
        end
    end,

    drawImage = function(x, y, w, h, texture, color, effect, section)
        x, y = adjust(x, y)
        local shader = applyEffect(effect)
        if section then
            -- кроп: рисуем видимую СЕКЦИЮ текстуры в обрезанный квад
            dxDrawImageSection(x, y, w, h,
                section[1], section[2], section[3], section[4],
                texture, 0, 0, 0, color, shader)
        else
            dxDrawImage(x, y, w, h, texture, 0, 0, 0, color, shader)
        end
    end,

    drawText = function(text, x, y, w, h, color, font, align, valign, scaleX, scaleY)
        x, y = adjust(x, y)
        dxDrawText(text, x, y, x + w, y + h, color,
            scaleX or 1, scaleY or 1, font or "default",
            align or "left", valign or "top")
    end,

    drawLine = function(x1, y1, x2, y2, color)
        x1, y1 = adjust(x1, y1)
        x2, y2 = adjust(x2, y2)
        dxDrawLine(x1, y1, x2, y2, color)
    end,

    -- -----------------------------------------------------------------
    -- RT-группы (§35 expensive path / §39 effect layer)
    -- -----------------------------------------------------------------

    --- Переключает рендер в offscreen RT (w×h) с origin (x, y).
    -- Возвращает true при успехе; false — RT недоступен (рисуем напрямую).
    beginGroup = function(x, y, w, h)
        local rt = DXUI.Effects and DXUI.Effects.acquireRT(w, h)
        if not rt then return false end
        dxSetRenderTarget(rt, true)
        groupStack[#groupStack + 1] = { rt = rt, offX = x, offY = y }
        return true
    end,

    --- Возвращает target и рисует RT с эффектом (blur/mask) на месте группы.
    -- alpha (0..1) — TRUE group-opacity (§34): весь композит одним квадом,
    -- пересечения внутри не блендятся дважды.
    endGroup = function(x, y, w, h, effect, alpha)
        local g = table.remove(groupStack)
        if not g then return end
        dxSetRenderTarget(nil)
        local shader = applyEffect(effect)
        local a = alpha
        if a == nil or a >= 1 then a = 1 elseif a < 0 then a = 0 end
        local quadColor = math.floor(255 * a) * 0x1000000 + 0xFFFFFF -- 0xAAFFFFFF
        dxDrawImage(x, y, w, h, g.rt, 0, 0, 0, quadColor, shader)
        if DXUI.Effects then DXUI.Effects.releaseRT(g.rt) end
    end,
}