--[[
    ui.lua — DXUI V2

    Публичная точка входа. Глобальный coordinator (§57): создание контекстов,
    тема, design resolution, утилиты цвета.

        local ui = DXUI.createContext()
        local win = ui:window({ ... })   -- Stage 6

    Публичный API не импортирует внутреннюю реализацию виджетов напрямую —
    только через Context (§20).
]]

DXUI = DXUI or {}

-- ---------------------------------------------------------------------
-- Создание контекста
-- ---------------------------------------------------------------------

-- Реестр активных контекстов (глобальный coordinator рендерит их все).
DXUI._contexts = DXUI._contexts or {}

--- Создаёт изолированный UI-контекст. backend — опционально (тесты).
function DXUI.createContext(backend)
    local ctx = DXUI.Context.new(backend)
    DXUI._contexts[#DXUI._contexts + 1] = ctx
    return ctx
end

-- ---------------------------------------------------------------------
-- Тема / design resolution (глобальные, Stage 5/9)
-- ---------------------------------------------------------------------

--- Устанавливает глобальную тему (Stage 9).
function DXUI.setTheme(theme)
    DXUI.theme = theme
end

--- Устанавливает design resolution (Stage 5).
function DXUI.setDesignResolution(w, h)
    DXUI.designW = w
    DXUI.designH = h
end

-- ---------------------------------------------------------------------
-- Цвет (§6: number | "#RRGGBB[AA]" | {r,g,b,a})
-- ---------------------------------------------------------------------

--- ui.color(r, g, b, a) -> packed 0xAARRGGBB (MTA tocolor).
function DXUI.color(r, g, b, a)
    return (a or 255) * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

--- Разрешает цвет: number (packed) | "#RRGGBB[AA]" | {r,g,b,a}.
-- Cold path: строки и аллокации допустимы.
function DXUI.resolveColor(c)
    if c == nil then return nil end
    if type(c) == "number" then return c end
    if type(c) == "string" then
        local hex = c:match("^#(.*)$") or c
        local r = tonumber(hex:sub(1, 2), 16) or 0
        local g = tonumber(hex:sub(3, 4), 16) or 0
        local b = tonumber(hex:sub(5, 6), 16) or 0
        local a = #hex >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    if type(c) == "table" then
        local r, g, b = c.r or 0, c.g or 0, c.b or 0
        local a = c.a or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    error("resolveColor: unsupported color type: " .. type(c))
end
