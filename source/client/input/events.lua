---Events — namespaced node events with BUBBLING (child first, then
---ancestors), run against a SNAPSHOT so handlers may add/remove/destroy
---during dispatch without corrupting iteration (prod-safe). Node:on/off/emit
---delegate here; EventBus is also used for UI-level channels later.
---
---Event signature: emit(node, name, ...); each handler fn(node, ...).
---stopPropagation: handlers may return the constant STOP to halt bubbling
---(checked after every handler call).

DXUI = DXUI or {}

local Events = {}

-- sentinel: return this from a handler to stop propagation
DXUI.STOP = {}

--- Returns the index of fn in list, or nil.
local function listIndex(list, fn)
    for i = 1, #list do
        if list[i] == fn then return i end
    end
end

--- Attaches fn to node's event. id: tag used by removeForOwner.
function Events.add(node, eventName, fn, id)
    local map = node._events
    if not map then
        map = {}
        node._events = map
    end
    local list = map[eventName]
    if not list then
        list = {}
        map[eventName] = list
    end
    -- idempotent for identical {fn,id}
    for i = 1, #list do
        if list[i].fn == fn and list[i].id == id then return fn end
    end
    list[#list + 1] = { fn = fn, id = id }
    return fn
end

--- Detaches fn from node's event; nil fn removes every handler for the name.
function Events.remove(node, eventName, fn)
    local map = node._events
    if not map then return end
    local list = map[eventName]
    if not list then return end
    if fn == nil then
        -- remove every handler for the name (node:off(name))
        map[eventName] = nil
        return
    end
    local idx = listIndex(list, fn)
    if idx then
        table.remove(list, idx)
        if #list == 0 then map[eventName] = nil end
    end
end

--- Removes every handler for the event registered under the given owner id.
-- Mirrors removeForOwner but scoped to one event name (node:off with an id).
function Events.removeId(node, eventName, id)
    local map = node._events
    if not map then return end
    local list = map[eventName]
    if not list then return end
    local j = 1
    while j <= #list do
        if list[j].id == id then
            table.remove(list, j)
        else
            j = j + 1
        end
    end
    if #list == 0 then map[eventName] = nil end
    if not next(map) then node._events = nil end
end

--- Removes every handler registered under the given owner id.
function Events.removeForOwner(node, id)
    local map = node._events
    if not map then return end
    for name, list in pairs(map) do
        local j = 1
        while j <= #list do
            if list[j].id == id then
                table.remove(list, j)
            else
                j = j + 1
            end
        end
        if #list == 0 then map[name] = nil end
    end
    if not next(map) then node._events = nil end
end

--- Removes all event handlers from the node.
function Events.clear(node)
    node._events = nil
end

--- Whether the node has at least one handler for the event.
function Events.has(node, eventName)
    local map = node._events
    return map ~= nil and map[eventName] ~= nil and #map[eventName] > 0
end

--- Invokes one handler with error isolation. Returns true when the handler
-- returned DXUI.STOP (stop propagation).
local function callHandler(h, current, eventName, ...)
    if not (h and h.fn) then return false end
    local ok, r = pcall(h.fn, current, ...)
    if not ok then
        -- one bad listener must never abort the frame;
        -- the policy decides how loud the failure is
        local policy = (DXUI.Settings and DXUI.Settings.errorPolicy) or "warn"
        if policy == "error" then
            error(r, 0)
        elseif policy == "warn" then
            DXUI.Debug.warn("EVENT", "event handler error (" .. tostring(eventName) .. "): " .. tostring(r))
        end
    elseif r == DXUI.STOP then
        return true
    end
    return false
end

--- Emits on node and bubbles through ancestors (snapshot per level).
-- Returns true if a handler stopped propagation. A throwing handler is
-- isolated: rethrown in dev mode, warned-and-skipped in production, so one
-- bad listener can never abort the frame.
function Events.bc(node, eventName, ...)
    if not node or node._destroyed then return false end
    local current = node
    while current do
        local map = current._events
        if map then
            local list = map[eventName]
            if list and #list > 0 then
                if #list == 1 then
                    -- fast path: no snapshot allocation for the common
                    -- single-handler case
                    if callHandler(list[1], current, eventName, ...) then return true end
                else
                    local snap = {}
                    for i = 1, #list do snap[i] = list[i] end
                    for i = 1, #snap do
                        if callHandler(snap[i], current, eventName, ...) then return true end
                    end
                end
            end
        end
        local parent = current._parent
        if parent == nil or parent._destroyed then return false end
        current = parent
    end
    return false
end

DXUI.Events = Events