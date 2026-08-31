--[[
    events.lua — DXUI V2

    Event system (§47/§48): target → bubble (вверх по parent). Без capture-фазы
    (не строим DOM-клон). Событие обрабатывается на целевом узле, затем
    поднимается по parent-цепочке, с остановкой через event:stopPropagation().

    EventBus — stateless: слушатели хранятся на самом узле (node._listeners,
    см. Widget:on), а emit просто идёт по parent-цепочке. Поэтому бабблинг
    естественно остаётся внутри дерева контекста (parent не пересекает
    контексты) — изоляция контекстов бесплатна (§57).
]]

DXUI = DXUI or {}

local EventBus = {}

--- Доставляет событие eventName, начиная с target, с бабблингом вверх.
-- eventData — произвольная таблица с данными события (x, y, button, ...).
-- В неё добавляются type/target/currentTarget/stopPropagation/preventDefault.
-- bubble = false — целевое событие без всплытия (focus/blur/key/text).
-- Возвращает event (для проверки defaultPrevented вызывающей стороной).
function EventBus.emit(target, eventName, eventData, bubble)
    -- Уничтоженный узел не получает событий (§70): destroy снимает подписки,
    -- emit по мёртвой ссылке — предсказуемый no-op.
    if target._destroyed then
        local event = eventData or {}
        event.type = eventName
        event.target = target
        return event
    end
    bubble = bubble ~= false -- по умолчанию бабблит
    local event = eventData or {}
    event.type = eventName
    event.target = target
    event.stopped = false
    event.defaultPrevented = false
    event.stopPropagation = function() event.stopped = true end
    event.preventDefault = function() event.defaultPrevented = true end

    local current = target
    while current do
        event.currentTarget = current
        local listeners = current._listeners
        if listeners then
            local list = listeners[eventName]
            if list then
                for i = 1, #list do
                    -- dev-режим (§69): ошибка слушателя не рвёт цепочку
                    if DXUI.config.debug then
                        local ok, err = pcall(list[i], event)
                        if not ok then
                            DXUI._warn("listener error on '" .. eventName .. "': " .. tostring(err))
                        end
                    else
                        list[i](event)
                    end
                    if event.stopped then break end
                end
            end
        end
        if event.stopped or not bubble then break end
        current = current._parent
    end
    return event
end

DXUI.EventBus = EventBus
