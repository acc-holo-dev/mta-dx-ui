--[[
    animation.lua — DXUI V2

    Animation engine: a centralized manager, ONE tick per frame
    (Context:renderFrame → update). No per-node timers/handlers.

    Animation changes REAL node properties through the normal mutation layer
    (node:_set) — no duplicated node.x / animation.x / render.x values
    Invalidation is automatic: value change → DIRTY.

        local anim = button:animate({ x = 100 }, 300)        -- 300ms
        anim:after({ opacity = 0.5 }, 200)                   -- chained step
        anim:onDone(function() print("done") end)
        anim:cancel()

    Chaining: `:after(...)` (not `:then` — Lua reserved word).
    Each step = a set of properties (entries in a shared list) + token; the token
    completes when all props of the step reached their targets → the next
    queue step starts. Interrupting (cancel/re-animate) does NOT call
    onDone (cancel ≠ complete).
]]

DXUI = DXUI or {}

local AnimationManager = {}
AnimationManager.__index = AnimationManager

local AnimHandle = {}
AnimHandle.__index = AnimHandle
DXUI.AnimHandle = AnimHandle

function AnimationManager.new(context)
    local self = setmetatable({}, AnimationManager)
    self.context = context
    self.active = {}       -- { {node, prop, from, to, start, dur, ease, token}, ... }
    self.activeCount = 0
    return self
end

--- Removes entry at position (swap-with-last, O(1)). Decrements token.
local function removeAt(self, i)
    local n = self.activeCount
    local entry = self.active[i]
    self.active[i] = self.active[n]
    self.active[n] = nil
    self.activeCount = n - 1
    return entry
end

--- Interrupts a node property's animations (before starting a new one). Token
--- (cancel ≠ complete: onDone is NOT called).
function AnimationManager:_removeFor(node, prop)
    local i = 1
    while i <= self.activeCount do
        local a = self.active[i]
        if a.node == node and a.prop == prop then
            if a.token then a.token.cancelled = true end
            removeAt(self, i)
        else
            i = i + 1
        end
    end
end

--- One animation step: a set of props + token (step completion → onDone).
function AnimationManager:_startStep(node, props, duration, easeName, onDone)
    local ease = DXUI.EASING[easeName or "inout"] or DXUI.EASING.inout
    duration = duration or 300
    if duration <= 0 then duration = 1 end

    local token = { remaining = 0, onDone = onDone, cancelled = false }
    for prop, target in pairs(props) do
        local spec = node._spec[prop]
        local current = node[prop]
        if spec and type(target) == "number" and type(current) == "number" then
            self:_removeFor(node, prop)
            token.remaining = token.remaining + 1
            self.activeCount = self.activeCount + 1
            self.active[self.activeCount] = {
                node = node, prop = prop,
                from = current, to = target,
                start = self.context.clock(),
                dur = duration, ease = ease, token = token,
            }
        else
            DXUI._warn("animate: property not animatable: " .. tostring(prop))
        end
    end
    if token.remaining == 0 and onDone then onDone() end
end

--- Public entry: node:animate(...) → chained handle.
function AnimationManager:animate(node, props, duration, easeName)
    local handle = setmetatable({
        manager = self, node = node,
        queue = {}, doneCbs = {},
        cancelled = false,
    }, AnimHandle)
    handle:_run(props, duration, easeName)
    return handle
end

--- Stops all animations of a node (value stays current).
function AnimationManager:stop(node)
    local i = 1
    while i <= self.activeCount do
        local a = self.active[i]
        if a.node == node then
            if a.token then a.token.cancelled = true end
            removeAt(self, i)
        else
            i = i + 1
        end
    end
end

function AnimationManager:isAnimating(node)
    for i = 1, self.activeCount do
        if self.active[i].node == node then return true end
    end
    return false
end

--- Finishes an entry: decrement token; zero and not cancelled → onDone (next step).
local function finishEntry(entry)
    local token = entry.token
    if not token then return end
    token.remaining = token.remaining - 1
    if token.remaining <= 0 and not token.cancelled and token.onDone then
        token.onDone()
    end
end

--- Single tick (called by Context:renderFrame BEFORE layout/render).
-- Writes intermediate values via node:_set — normal mutation layer.
function AnimationManager:update()
    if self.activeCount == 0 then return end -- zero-work idle
    local now = self.context.clock()
    local i = 1
    while i <= self.activeCount do
        local a = self.active[i]
        local node = a.node
        if node._destroyed then
            a.token = nil -- dead node: do not continue the chain
            finishEntry(removeAt(self, i))
        else
            local t = (now - a.start) / a.dur
            if t >= 1 then
                node:_set(a.prop, a.to) -- exact snap to end
                local entry = removeAt(self, i)
                entry.token = a.token
                finishEntry(entry)
            else
                if t < 0 then t = 0 end
                node:_set(a.prop, a.from + (a.to - a.from) * a.ease(t))
                i = i + 1
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- AnimHandle: step chain (timeline/sequence)
-- ---------------------------------------------------------------------

--- Runs a step; on completion — next from the queue or done callbacks.
function AnimHandle:_run(props, duration, easeName)
    local node, self_ = self.node, self
    self.manager:_startStep(node, props, duration, easeName, function()
        if self_.cancelled or not node:isAlive() then return end
        local next_ = table.remove(self_.queue, 1)
        if next_ then
            self_:_run(next_[1], next_[2], next_[3])
        else
            local cbs = self_.doneCbs
            for i = 1, #cbs do cbs[i]() end
        end
    end)
end

--- Adds a step to the chain queue (runs after the current one).
function AnimHandle:after(props, duration, easeName)
    self.queue[#self.queue + 1] = { props, duration, easeName }
    return self
end

--- Callback when the WHOLE chain finishes.
function AnimHandle:onDone(fn)
    self.doneCbs[#self.doneCbs + 1] = fn
    return self
end

--- Cancels the chain (current animations stop, onDone is not called).
function AnimHandle:cancel()
    self.cancelled = true
    self.queue = {}
    self.doneCbs = {}
    self.manager:stop(self.node)
    return self
end

DXUI.AnimationManager = AnimationManager