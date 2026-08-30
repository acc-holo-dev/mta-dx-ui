--[[
    dispatcher.lua — DXUI V2

    Централизованный input dispatcher (§44): один на контекст, НЕ per-node
    MTA-обработчики. Глобальный bridge (init.lua) вызывает эти методы.

    Состояния (§45): hovered / focused / pressed. Глобальная модель вместо
    локального состояния в каждом виджете.

    Поток: MTA event → Context:onXxx → Dispatcher → HitTest → target →
    EventBus.emit (bubble).
]]

DXUI = DXUI or {}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

function Dispatcher.new(context)
    local self = setmetatable({}, Dispatcher)
    self.context = context
    self.hoveredNode = nil
    self.pressedNode = nil
    self.focusedNode = nil
    return self
end

function Dispatcher:onCursorMove(x, y)
    local hit = DXUI.HitTest.pick(self.context, x, y)
    if hit ~= self.hoveredNode then
        if self.hoveredNode then
            DXUI.EventBus.emit(self.hoveredNode, "mouseleave", { x = x, y = y })
        end
        self.hoveredNode = hit
        if hit then
            DXUI.EventBus.emit(hit, "mouseenter", { x = x, y = y })
        end
    end
end

function Dispatcher:onMouseDown(x, y, button)
    local hit = DXUI.HitTest.pick(self.context, x, y)
    self.pressedNode = hit
    self:setFocus(hit) -- клик фокусирует узел (клик мимо снимает фокус)
    if hit then
        DXUI.EventBus.emit(hit, "mousedown", { x = x, y = y, button = button })
    end
end

function Dispatcher:onMouseUp(x, y, button)
    local hit = DXUI.HitTest.pick(self.context, x, y)
    if hit then
        DXUI.EventBus.emit(hit, "mouseup", { x = x, y = y, button = button })
    end
    -- click засчитывается только если mouseup над ТЕМ ЖЕ узлом, что mousedown
    if hit and hit == self.pressedNode then
        DXUI.EventBus.emit(hit, "click", { x = x, y = y, button = button })
    end
    self.pressedNode = nil
end

function Dispatcher:onMouseWheel(x, y, dz)
    local hit = DXUI.HitTest.pick(self.context, x, y)
    if hit then
        DXUI.EventBus.emit(hit, "wheel", { x = x, y = y, dz = dz })
    end
end

--- Клавиатура (§50 foundation): key/text события на сфокусированный узел.
-- key — имя клавиши (MTA key map), state — "down"/"up", mods — "ctrl"/"shift",
-- text — символ (для text-события).
function Dispatcher:onKeyDown(key, state, mods, text)
    if not self.focusedNode then return end
    if state == "down" and text and text ~= "" then
        DXUI.EventBus.emit(self.focusedNode, "text", { text = text })
    end
    DXUI.EventBus.emit(self.focusedNode, "key", {
        key = key, state = state, mods = mods or "", text = text,
    })
end

--- Установить фокус (emit blur на старый + focus на новый).
function Dispatcher:setFocus(node)
    if node == self.focusedNode then return end
    if self.focusedNode then
        DXUI.EventBus.emit(self.focusedNode, "blur", {})
    end
    self.focusedNode = node
    if node then
        DXUI.EventBus.emit(node, "focus", {})
    end
end

function Dispatcher:getFocus()
    return self.focusedNode
end

--- Очистка ссылок на уничтоженный узел (вызывается Context:_onNodeDestroyed).
function Dispatcher:_onNodeDestroyed(node)
    if self.hoveredNode == node then self.hoveredNode = nil end
    if self.pressedNode == node then self.pressedNode = nil end
    if self.focusedNode == node then self.focusedNode = nil end
end

DXUI.Dispatcher = Dispatcher
