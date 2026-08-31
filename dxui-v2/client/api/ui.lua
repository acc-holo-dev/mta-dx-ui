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

--- Устанавливает design resolution (§32). UI проектируется в design-пространстве;
-- render масштабирует его на экран (renderer mapping), события ввода
-- конвертируются обратно (event.x/y — design-координаты, согласованы с worldX).
-- mode: "stretch" (default — независимые оси) | "fit" (равномерно + letterbox).
function DXUI.setDesignResolution(w, h, mode)
    DXUI.designW, DXUI.designH = w, h
    DXUI.designScaleMode = mode or "stretch"
end

-- Цвет (DXUI.color / DXUI.resolveColor) — в utils/color.lua.
