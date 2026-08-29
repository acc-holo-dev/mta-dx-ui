--[[
    events.lua

    Реализует ADR-005: только всплытие (bubble), без фазы захвата (capture).
    Событие обрабатывается сначала на целевом узле (найденном hit-test'ом),
    затем поднимается по цепочке parent через storage.parent до C.NIL_ID,
    с возможностью остановки через event.stopPropagation().

    Публичный API регистрации (proxy:on("click", fn)) принимает строки —
    это cold path (вызывается один раз при настройке UI, не каждый кадр),
    поэтому строка -> числовая константа мапится один раз здесь и хранится
    уже в числовом виде (ADR-006: строк в hot path диспетчеризации нет).
]]

DXUI = DXUI or {}
local C = DXUI.Constants

local NAME_TO_EVENT = {
    click      = C.EVENT_CLICK,
    mousedown  = C.EVENT_MOUSEDOWN,
    mouseup    = C.EVENT_MOUSEUP,
    mouseenter = C.EVENT_MOUSEENTER,
    mouseleave = C.EVENT_MOUSELEAVE,
}

local EventBus = {}
EventBus.__index = EventBus
DXUI.EventBus = EventBus

function EventBus.new(storage)
    local self = setmetatable({}, EventBus)
    self.storage = storage
    -- listeners[id] = { [numericEventType] = { fn1, fn2, ... } }
    self.listeners = {}

    -- Слушатели узла больше не нужны после его уничтожения — используем тот
    -- же generic destroy-hook, что и Renderer (Storage не знает о EventBus,
    -- разделение ответственности сохраняется).
    storage:onNodeDestroyed(function(id)
        self.listeners[id] = nil
    end)

    return self
end

--- Регистрирует обработчик. eventName — строка публичного API ("click" и т.п.).
function EventBus:on(id, eventName, fn)
    local eventType = NAME_TO_EVENT[eventName]
    assert(eventType, "EventBus:on: unknown event name '" .. tostring(eventName) .. "'")

    local nodeListeners = self.listeners[id]
    if not nodeListeners then
        nodeListeners = {}
        self.listeners[id] = nodeListeners
    end
    local typeListeners = nodeListeners[eventType]
    if not typeListeners then
        typeListeners = {}
        nodeListeners[eventType] = typeListeners
    end
    typeListeners[#typeListeners + 1] = fn
end

--- Доставляет событие численного типа eventType, начиная с targetId, с
-- бабблингом вверх по родителям. eventData — произвольная таблица, в неё
-- добавляются target/currentTarget/stopPropagation.
function EventBus:emit(targetId, eventType, eventData)
    eventData = eventData or {}
    eventData.target = targetId
    eventData.stopped = false
    eventData.stopPropagation = function() eventData.stopped = true end

    local storage = self.storage
    local currentId = targetId

    while currentId ~= C.NIL_ID and currentId ~= nil do
        if not storage:isAlive(currentId) then break end -- узел мог быть уничтожен обработчиком выше по цепочке

        eventData.currentTarget = currentId
        local nodeListeners = self.listeners[currentId]
        if nodeListeners then
            local typeListeners = nodeListeners[eventType]
            if typeListeners then
                for i = 1, #typeListeners do
                    typeListeners[i](eventData)
                    if eventData.stopped then break end
                end
            end
        end

        if eventData.stopped then break end

        local slot = storage.idToSlot[currentId]
        currentId = slot and storage.parent[slot] or C.NIL_ID
    end
end
