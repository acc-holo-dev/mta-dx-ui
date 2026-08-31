--[[
    dispatcher.lua — DXUI V2

    Централизованный input dispatcher (§44): один на контекст, НЕ per-node
    MTA-обработчики. Глобальный bridge (init.lua) вызывает эти методы.

    Состояния (§45): hovered / focused / pressed / captured (drag).
    Глобальная модель вместо локального состояния в каждом виджете.

    Stage 7 добавляет:
      - drag-capture (beginDrag/endDrag) — перетаскивание окна/thumb/выделения;
      - modal-стек — focus lock + input trap (§60);
      - popup-стек — dismiss по клику вне (§59).

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

    -- Stage 7: drag-capture
    self.dragMove = nil
    self.dragEnd = nil

    -- Stage 7: modal-стек (focus lock + input trap)
    self.modalStack = {}

    -- Stage 7: popup-стек (dismiss по клику вне)
    self.popupStack = {}

    return self
end

-- =======================================================================
-- Drag-capture (Stage 7)
-- =======================================================================

--- Захват курсора для перетаскивания. fnMove(x, y) — на каждый onCursorMove;
-- fnEnd() — на первый mouseup (в любой точке). Повторный beginDrag заменяет.
function Dispatcher:beginDrag(fnMove, fnEnd)
    self.dragMove = fnMove
    self.dragEnd = fnEnd
end

--- Немедленно прекратить drag (без mouseup). Вызывает fnEnd.
function Dispatcher:endDrag()
    local f = self.dragEnd
    self.dragMove = nil
    self.dragEnd = nil
    if f then f() end
end

-- =======================================================================
-- Modal (Stage 7): focus lock + input trap
-- Стек хранит NODE REFERENCES (V2 — объектная модель, не числовые id).
-- =======================================================================

function Dispatcher:pushModal(window, overlay)
    self.modalStack[#self.modalStack + 1] = { window = window, overlay = overlay }
end

function Dispatcher:popModal(window)
    for i = #self.modalStack, 1, -1 do
        if self.modalStack[i].window == window then
            table.remove(self.modalStack, i)
            break
        end
    end
end

function Dispatcher:getTopModal()
    return self.modalStack[#self.modalStack]
end

function Dispatcher:isModalActive()
    return #self.modalStack > 0
end

--- node — потомок ancestor (или равен ему). Обход parent-цепочки.
function Dispatcher:isDescendant(node, ancestor)
    local cur = node
    while cur do
        if cur == ancestor then return true end
        cur = cur._parent
    end
    return false
end

--- node внутри верхнего modal (окно / потомок / overlay). Без modal — всё разрешено.
function Dispatcher:isInsideModal(node)
    local top = self:getTopModal()
    if not top then return true end
    if node == nil then return false end
    if node == top.overlay then return true end
    return self:isDescendant(node, top.window)
end

-- =======================================================================
-- Popup (Stage 7): dismiss по клику вне. Стек хранит node references.
-- =======================================================================

function Dispatcher:pushPopup(node, dismissFn)
    self.popupStack[#self.popupStack + 1] = { node = node, dismissFn = dismissFn }
end

function Dispatcher:popPopup(node)
    for i = #self.popupStack, 1, -1 do
        if self.popupStack[i].node == node then
            table.remove(self.popupStack, i)
            break
        end
    end
end

function Dispatcher:getTopPopup()
    return self.popupStack[#self.popupStack]
end

function Dispatcher:isInsidePopup(node)
    local top = self:getTopPopup()
    if not top then return false end
    if node == nil then return false end
    return self:isDescendant(node, top.node)
end

-- =======================================================================
-- Mouse
-- =======================================================================

function Dispatcher:onCursorMove(x, y)
    x, y = self.context:toLocal(x, y) -- screen → design (§31–§33)
    -- drag съедает движение; hover заморожен до mouseup
    if self.dragMove then
        self.dragMove(x, y)
        return
    end

    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- modal: hover вне окна подавлен
    if self:isModalActive() and not self:isInsideModal(hit) then
        hit = nil
    end

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
    x, y = self.context:toLocal(x, y) -- screen → design (§31–§33)
    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- popup dismiss: клик вне верхнего popup закрывает его (съедает клик)
    local topPopup = self:getTopPopup()
    if topPopup and not self:isInsidePopup(hit) then
        self:popPopup(topPopup.node)
        if topPopup.dismissFn then topPopup.dismissFn() end
        self.pressedNode = nil
        return
    end

    -- modal: input trap — события вне окна блокируются
    if self:isModalActive() and not self:isInsideModal(hit) then
        self.pressedNode = nil
        return
    end

    self.pressedNode = hit
    self:setFocus(hit)
    if hit then
        DXUI.EventBus.emit(hit, "mousedown", { x = x, y = y, button = button })
    end
end

function Dispatcher:onMouseUp(x, y, button)
    x, y = self.context:toLocal(x, y) -- screen → design (§31–§33)
    -- drag заканчивается на mouseup в любой точке
    if self.dragMove then
        self:endDrag()
    end

    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- modal: input trap
    if self:isModalActive() and not self:isInsideModal(hit) then
        self.pressedNode = nil
        return
    end

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
    x, y = self.context:toLocal(x, y) -- screen → design (§31–§33)
    if self.dragMove then return end

    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- modal: input trap — колесо вне окна игнорируется
    if self:isModalActive() and not self:isInsideModal(hit) then return end

    if hit then
        DXUI.EventBus.emit(hit, "wheel", { x = x, y = y, dz = dz })
    end
end

-- =======================================================================
-- Keyboard / Focus
-- =======================================================================

--- Клавиатура (§50 foundation): key/text события на сфокусированный узел.
-- key — имя клавиши (MTA key map), state — "down"/"up", mods — "ctrl"/"shift",
-- text — символ (для text-события). Целевые события (без бабблинга).
function Dispatcher:onKeyDown(key, state, mods, text)
    if not self.focusedNode then return end
    if state == "down" and text and text ~= "" then
        DXUI.EventBus.emit(self.focusedNode, "text", { text = text }, false)
    end
    DXUI.EventBus.emit(self.focusedNode, "key", {
        key = key, state = state, mods = mods or "", text = text,
    }, false)
end

--- Установить фокус (emit blur на старый + focus на новый). Целевые события
-- (без бабблинга — focus/blur не всплывают, как в DOM). Modal: focus lock.
-- Клик по overlay НЕ меняет фокус (поле ввода под overlay не теряет его).
function Dispatcher:setFocus(node)
    if node == self.focusedNode then return end
    if self:isModalActive() then
        local top = self:getTopModal()
        if node == top.overlay then return end
        if node == nil or not self:isInsideModal(node) then
            return -- focus lock: только внутри modal
        end
    end
    if self.focusedNode then
        DXUI.EventBus.emit(self.focusedNode, "blur", {}, false)
    end
    self.focusedNode = node
    if node then
        DXUI.EventBus.emit(node, "focus", {}, false)
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
    -- Stage 7: чистим modal/popup-стеки (страховка; виджеты чистят себя сами)
    for i = #self.modalStack, 1, -1 do
        local m = self.modalStack[i]
        if m.window == node or m.overlay == node then
            table.remove(self.modalStack, i)
        end
    end
    for i = #self.popupStack, 1, -1 do
        if self.popupStack[i].node == node then
            table.remove(self.popupStack, i)
        end
    end
end

DXUI.Dispatcher = Dispatcher
