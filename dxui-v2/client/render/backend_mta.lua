--[[
    backend_mta.lua — DXUI V2

    Реализация backend поверх MTA DX9 (dxDraw*/dxSetBlendMode).

    Это единственная точка входа внешней зависимости от dx*-функций во всём
    движке. В тестах вместо него используется мок (см. tests/test_render.lua).
]]

DXUI = DXUI or {}

DXUI.MtaBackend = {
    setBlendMode = function(mode)
        dxSetBlendMode(mode)
    end,

    drawRect = function(x, y, w, h, color)
        dxDrawRectangle(x, y, w, h, color)
    end,

    drawImage = function(x, y, w, h, texture, color)
        dxDrawImage(x, y, w, h, texture, 0, 0, 0, color)
    end,

    drawText = function(text, x, y, w, h, color)
        dxDrawText(text, x, y, x + w, y + h, color)
    end,

    drawLine = function(x1, y1, x2, y2, color)
        dxDrawLine(x1, y1, x2, y2, color)
    end,
}
