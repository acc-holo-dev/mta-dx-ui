--[[
    dispatcher.lua

    §25 ТЗ: "Не создавать десятки MTA event handlers на каждый элемент...
    Предпочтительно: one global input dispatcher". Реализовано здесь --
    ровно 3 входные точки (move/down/up), вызываемые из bootstrap.lua на
    ДВА глобальных MTA-события (onClientCursorMove, onClientClick), а не
    на события отдельных узлов.

    §28 ТЗ: глобальная модель hoveredId/pressedId/focusedId вместо
    локального состояния в каждом виджете.

    M12 (ADR-016): DRAG-CAPTURE. beginDrag(fnMove, fnEnd) захватывает
    курсор для перетаскивания окна: fnMove(px, py) вызывается на каждый
    onCursorMove, drag завершается на первый mouseup ГДЕ УГОДНО (fnEnd).
    Пока drag активен, hover-события (mouseenter/mouseleave) подавлены --
    под курсором "виртуально" висит захвативший узел. В M18 этот же
    механизм расширится до modal input trap (focus lock).
]]

DXUI = DXUI or {}
local C = DXUI.Constants
local HitTest = DXUI.HitTest

DXUI.Dispatcher = {}
local Dispatcher = DXUI.Dispatcher

--- Создаёт объект состояния диспетчера, привязанный к конкретному Kernel'у
-- (через storage + eventBus). Отдельный от Kernel класс -- чтобы Input
-- оставался независимой подсистемой (§5 обзор архитектуры), а не методами,
-- вклиненными прямо в Kernel.
function Dispatcher.new(storage, eventBus)
    local self = setmetatable({}, { __index = Dispatcher })
    self.storage = storage
    self.eventBus = eventBus

    self.hoveredId  = C.NIL_ID
    self.pressedId  = C.NIL_ID
    self.focusedId  = C.NIL_ID

    -- M12: активный drag (nil = нет захвата)
    self.dragMove = nil
    self.dragEnd  = nil

    -- M16 (ADR-020): стек активных modal-окон (focus lock + input trap).
    -- Каждый элемент: { windowId, overlayId }. Верхний — последний.
    self.modalStack = {}

    -- M17 (ADR-021): стек открытых popup/contextmenu (dismiss по клику вне).
    -- Каждый элемент: { id, dismissFn }. Верхний — последний.
    self.popupStack = {}

    return self
end

-- =======================================================================
-- M16 (ADR-020): modal — focus lock + input trap
-- =======================================================================

--- Зарегистрировать modal-окно. Возвращает новую глубину стека (1-based).
function Dispatcher:pushModal(windowId, overlayId)
    self.modalStack[#self.modalStack + 1] = {
        windowId = windowId,
        overlayId = overlayId or C.NIL_ID,
    }
    return #self.modalStack
end

--- Снять modal-окно со стека (по windowId).
function Dispatcher:popModal(windowId)
    for i = #self.modalStack, 1, -1 do
        if self.modalStack[i].windowId == windowId then
            table.remove(self.modalStack, i)
            break
        end
    end
end

--- Верхний modal (или nil).
function Dispatcher:getTopModal()
    local n = #self.modalStack
    if n == 0 then return nil end
    return self.modalStack[n]
end

--- Есть ли активный modal.
function Dispatcher:isModalActive()
    return #self.modalStack > 0
end

--- id — потомок ancestorId (или равен ему). Обход parent-цепочки.
function Dispatcher:isDescendant(id, ancestorId)
    local s = self.storage
    local cur = id
    while cur ~= C.NIL_ID do
        if cur == ancestorId then return true end
        local slot = s.idToSlot[cur]
        if not slot then return false end
        cur = s.parent[slot]
    end
    return false
end

--- id внутри верхнего modal (окно / потомок / overlay). Без modal — всё разрешено.
function Dispatcher:isInsideModal(id)
    local top = self:getTopModal()
    if not top then return true end
    if id == C.NIL_ID then return false end
    if id == top.overlayId then return true end
    return self:isDescendant(id, top.windowId)
end

--- M16: resize overlay'ев при смене разрешения (Kernel:setScreenSize).
function Dispatcher:resizeModalOverlays(w, h)
    for i = 1, #self.modalStack do
        local m = self.modalStack[i]
        if m.overlayId ~= C.NIL_ID then
            local slot = self.storage.idToSlot[m.overlayId]
            if slot then
                self.storage.w[slot] = w
                self.storage.h[slot] = h
                self.storage:markDirty(m.overlayId, C.DIRTY_POS)
            end
        end
    end
end

-- =======================================================================
-- M17 (ADR-021): popup / contextmenu — dismiss по клику вне
-- =======================================================================

--- Открыть popup. dismissFn вызывается при клике вне popup (закрыть).
function Dispatcher:pushPopup(id, dismissFn)
    self.popupStack[#self.popupStack + 1] = { id = id, dismissFn = dismissFn }
end

--- Снять popup со стека (по id). Идемпотентно.
function Dispatcher:popPopup(id)
    for i = #self.popupStack, 1, -1 do
        if self.popupStack[i].id == id then
            table.remove(self.popupStack, i)
            break
        end
    end
end

--- Верхний popup (или nil).
function Dispatcher:getTopPopup()
    local n = #self.popupStack
    if n == 0 then return nil end
    return self.popupStack[n]
end

--- id внутри верхнего popup (или равен ему).
function Dispatcher:isInsidePopup(id)
    local top = self:getTopPopup()
    if not top then return false end
    if id == C.NIL_ID then return false end
    return self:isDescendant(id, top.id)
end

--- M14 (ADR-018): клавиатура. key -- имя клавиши (MTA key map, строка,
-- напр. "a", "backspace", "arrow_l"), state -- "down"/"up", mods -- строка
-- модификаторов ("ctrl", "shift", "ctrl+shift", "" / nil), text -- символ.
-- Ctrl-комбо НЕ эмитят EVENT_TEXT (событие text только для обычного ввода).
-- M15 (ADR-019): mods передаются в EVENT_KEY для ctrl-шорткатов (copy/paste).
function Dispatcher:onKeyDown(key, state, mods, text)
    if self.focusedId ~= C.NIL_ID then
        local isCtrl = mods and mods:find("ctrl") ~= nil
        if not isCtrl and text and text ~= "" then
            self.eventBus:emit(self.focusedId, C.EVENT_TEXT, { text = text })
        end
        self.eventBus:emit(self.focusedId, C.EVENT_KEY, {
            key = key, state = state, mods = mods or "", text = text
        })
    end
end

--- M14: установить фокус (emit blur на старый + focus на новый).
-- M16 (ADR-020): focus lock — при активном modal фокус только внутри окна;
-- клик вне окна (пусто/overlay) НЕ трогает фокус (не снимает с поля ввода).
function Dispatcher:setFocus(id)
    if id == self.focusedId then return end
    if self:isModalActive() then
        local top = self:getTopModal()
        if id == C.NIL_ID or id == top.overlayId then
            return -- вне окна: фокус не меняется
        end
        if not self:isDescendant(id, top.windowId) then
            return -- focus lock: только внутри modal
        end
    end
    if self.focusedId ~= C.NIL_ID then
        self.eventBus:emit(self.focusedId, C.EVENT_BLUR, {})
    end
    self.focusedId = id
    if id ~= C.NIL_ID then
        self.eventBus:emit(id, C.EVENT_FOCUS, {})
    end
end

--- M14: получить текущий focusedId (или NIL_ID).
function Dispatcher:getFocus()
    return self.focusedId
end

--- M12: захват курсора для перетаскивания. fnMove(px, py) -- на каждый
-- onCursorMove; fnEnd() -- на первый mouseup (в любой точке экрана).
-- Повторный beginDrag без завершения заменяет предыдущий захват.
function Dispatcher:beginDrag(fnMove, fnEnd)
    self.dragMove = fnMove
    self.dragEnd = fnEnd
end

--- M12: немедленно прекратить drag (без mouseup). Вызывает fnEnd.
function Dispatcher:endDrag()
    local f = self.dragEnd
    self.dragMove = nil
    self.dragEnd = nil
    if f then f() end
end

function Dispatcher:onCursorMove(px, py)
    -- M12: активный drag съедает движение; hover заморожен до mouseup
    if self.dragMove then
        self.dragMove(px, py)
        return
    end

    local hit = HitTest.pick(self.storage, px, py)

    -- M16: hover вне modal подавлен (фон под overlay не получает enter/leave)
    if self:isModalActive() and not self:isInsideModal(hit) then
        hit = C.NIL_ID
    end

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

    -- M17: popup dismiss — клик вне верхнего popup закрывает его (съедает клик)
    local topPopup = self:getTopPopup()
    if topPopup and not self:isInsidePopup(hit) then
        self:popPopup(topPopup.id)
        if topPopup.dismissFn then topPopup.dismissFn() end
        self.pressedId = C.NIL_ID
        return
    end

    -- M16: input trap — при modal события вне окна блокируются
    if self:isModalActive() and not self:isInsideModal(hit) then
        self.pressedId = C.NIL_ID
        return
    end

    self.pressedId = hit
    -- M14: фокус через setFocus (emit blur/focus); клик мимо снимает фокус
    self:setFocus(hit)

    if hit ~= C.NIL_ID then
        self.eventBus:emit(hit, C.EVENT_MOUSEDOWN, { button = button, x = px, y = py })
    end
end

--- M13 (ADR-017): колесо мыши. dz = +1 (вверх) / -1 (вниз). Событие
-- EVENT_WHEEL эмитится на узел под курсором и бабблится -- ScrollPanel
-- ловит его через обычного подписчика (в т.ч. для детей контента).
-- Во время активного drag колесо игнорируется.
function Dispatcher:onMouseWheel(px, py, dz)
    if self.dragMove then return end

    local hit = HitTest.pick(self.storage, px, py)

    -- M16: input trap — колесо вне modal игнорируется
    if self:isModalActive() and not self:isInsideModal(hit) then return end

    if hit ~= C.NIL_ID then
        self.eventBus:emit(hit, C.EVENT_WHEEL, { dz = dz, x = px, y = py })
    end
end

function Dispatcher:onMouseUp(px, py, button)
    -- M12: drag заканчивается на mouseup в любой точке
    if self.dragMove then
        self:endDrag()
    end

    local hit = HitTest.pick(self.storage, px, py)

    -- M16: input trap — mouseup/click вне modal блокируются
    if self:isModalActive() and not self:isInsideModal(hit) then
        self.pressedId = C.NIL_ID
        return
    end

    if hit ~= C.NIL_ID then
        self.eventBus:emit(hit, C.EVENT_MOUSEUP, { button = button, x = px, y = py })
    end

    -- click засчитывается только если mouseup произошёл над ТЕМ ЖЕ узлом,
    -- на котором было mousedown (стандартное поведение кнопок в UI-тулкитах:
    -- увести курсор с кнопки перед отпусканием -> клик не засчитывается)
    if hit ~= C.NIL_ID and hit == self.pressedId then
        self.eventBus:emit(hit, C.EVENT_CLICK, { button = button, x = px, y = py })
    end

    self.pressedId = C.NIL_ID
end
