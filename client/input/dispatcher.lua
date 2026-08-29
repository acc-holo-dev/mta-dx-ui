--[[
    dispatcher.lua

    §25 ТЗ: "Не создавать десятки MTA event handlers на каждый элемент...
    Предпочтительно: one global input dispatcher". Реализовано здесь —
    ровно 3 входные точки (move/down/up), вызываемые из bootstrap.lua на
    ДВА глобальных MTA-события (onClientCursorMove, onClientClick), а не
    на события отдельных узлов.

    §28 ТЗ: глобальная модель hoveredId/pressedId/focusedId вместо
    локального состояния в каждом виджете.
]]

DXUI = DXUI or {}
local C = DXUI.Constants
local HitTest = DXUI.HitTest

DXUI.Dispatcher = {}
local Dispatcher = DXUI.Dispatcher

--- Создаёт объект состояния диспетчера, привязанный к конкретному Kernel'у
-- (через storage + eventBus). Отдельный от Kernel класс — чтобы Input
-- оставался независимой подсистемой (§5 обзор архитектуры), а не методами,
-- вклиненными прямо в Kernel.
function Dispatcher.new(storage, eventBus)
    local self = setmetatable({}, { __index = Dispatcher })
    self.storage = storage
    self.eventBus = eventBus

    self.hoveredId  = C.NIL_ID
    self.pressedId  = C.NIL_ID
    self.focusedId  = C.NIL_ID

    return self
end

function Dispatcher:onCursorMove(px, py)
    local hit = HitTest.pick(self.storage, px, py)

    if hit ~= self.hoveredId then
        if self.hoveredId ~= C.NIL_ID then
            self.eventBus:emit(self.hoveredId, C.EVENT_MOUSELEAVE, {})
        end
        self.hoveredId = hit
        if hit ~= C.NIL_ID then
            self.eventBus:emit(hit, C.EVENT_MOUSEENTER, {})
        end
    end
end

function Dispatcher:onMouseDown(px, py, button)
    local hit = HitTest.pick(self.storage, px, py)
    self.pressedId = hit
    self.focusedId = hit -- M3: простейшая модель — клик мимо снимает фокус (hit == NIL_ID)

    if hit ~= C.NIL_ID then
        self.eventBus:emit(hit, C.EVENT_MOUSEDOWN, { button = button })
    end
end

function Dispatcher:onMouseUp(px, py, button)
    local hit = HitTest.pick(self.storage, px, py)

    if hit ~= C.NIL_ID then
        self.eventBus:emit(hit, C.EVENT_MOUSEUP, { button = button })
    end

    -- click засчитывается только если mouseup произошёл над ТЕМ ЖЕ узлом,
    -- на котором было mousedown (стандартное поведение кнопок в UI-тулкитах:
    -- увести курсор с кнопки перед отпусканием -> клик не засчитывается)
    if hit ~= C.NIL_ID and hit == self.pressedId then
        self.eventBus:emit(hit, C.EVENT_CLICK, { button = button })
    end

    self.pressedId = C.NIL_ID
end
