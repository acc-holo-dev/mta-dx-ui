--[[
    events.lua — DXUI V2

    Event system: target → bubble (up the parent chain). No capture phase
    (no DOM clone is built). The event is handled on the target node, then
    travels up the parent chain, stoppable via event:stopPropagation().

    EventBus is stateless: listeners live on the node itself (node._listeners,
    see Widget:on), and emit simply walks the parent chain. So bubbling stays
    inside the context tree (parent never crosses contexts) — context
    isolation is free.
]]

DXUI = DXUI or {}

local EventBus = {}

--- Deliver event eventName starting at target, bubbling up.
-- eventData — arbitrary data table (x, y, button, ...). It receives
-- type/target/currentTarget/stopPropagation/preventDefault.
-- bubble = false — target event without bubbling (focus/blur/key/text).
-- Returns the event (so the caller can check defaultPrevented).
function EventBus.emit(target, eventName, eventData, bubble)
    -- A destroyed node gets no events: destroy removes subscriptions,
    -- emit on a dead reference is a predictable no-op.
    if target._destroyed then
        local event = eventData or {}
        event.type = eventName
        event.target = target
        return event
    end
    bubble = bubble ~= false -- bubbles by default
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
                    -- dev mode: a listener error doesn't break the chain
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
