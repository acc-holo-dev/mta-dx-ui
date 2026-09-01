--[[
    animation.lua — DXUI V3

    Animation engine: ONE centralized manager per UI instance, ONE tick per
    frame (the instance frame loop calls anim:update()). No per-animation
    timers, MTA handlers or coroutines.

    Animations write REAL node properties through the normal mutation layer
    (_set with owner "system") — no duplicated state; invalidation is
    automatic. Explicit animation > automatic theme transition.

        local anim = button:animate({ x = 100 }, 300, "out")
        anim:after({ opacity = 0.5 }, 200):onDone(function() ... end)
        anim:pause() / anim:resume() / anim:cancel()
]]

DXUI = DXUI or {}

local AnimationManager = {}
AnimationManager.__index = AnimationManager

local AnimHandle = {}
AnimHandle.__index = AnimHandle
DXUI.AnimHandle = AnimHandle

--- Resolves an ease name/function to a callable easing function.
local function resolveEase(ease)
    if type(ease) == "function" then return ease end
    local name = ease or DXUI.Settings and DXUI.Settings.defaults.animationEasing or "inout"
    return DXUI.EASING[name] or DXUI.EASING.inout
end

--- Creates an animation manager bound to an instance context.
function AnimationManager.new(context)
    local self = setmetatable({}, AnimationManager)
    self.context = context
    -- { {node, prop, from, to, start, dur, ease, token}, ... }
    self.active = {}
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

--- Interrupts a node property's animations (before starting a new one).
-- Cancel != complete: onDone is NOT called.
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

--- Removes only the entries owned by one handle (AnimHandle:cancel).
-- Other handles on the same node keep running.
function AnimationManager:_removeHandle(handle)
    local i = 1
    while i <= self.activeCount do
        local a = self.active[i]
        local tok = a.token
        if tok and tok.owner == handle then
            tok.cancelled = true
            removeAt(self, i)
        else
            i = i + 1
        end
    end
end

--- One animation step: a set of props + token (step completion -> onDone).
function AnimationManager:_startStep(node, props, duration, ease, onDone, owner)
    duration = duration or (DXUI.Settings and DXUI.Settings.defaults.animationDuration) or 250
    if duration <= 0 then duration = 1 end
    local token = { remaining = 0, onDone = onDone, cancelled = false, owner = owner }
    for prop, target in pairs(props) do
        local spec = node._spec[prop]
        local current = node._data[prop]
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

--- Public entry: node:animate(...) -> chained handle.
function AnimationManager:animate(node, props, duration, ease)
    local handle = setmetatable({
        manager = self, node = node,
        queue = {}, doneCbs = {},
        cancelled = false,
    }, AnimHandle)
    handle:_run(props, duration, ease)
    return handle
end

--- Stops all animations of a node (values stay current).
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

--- Whether the node has any running animation.
function AnimationManager:isAnimating(node)
    for i = 1, self.activeCount do
        if self.active[i].node == node then return true end
    end
    return false
end

--- Decrements a token's remaining count and fires onDone when it reaches zero.
local function finishEntry(entry)
    local token = entry.token
    if not token then return end
    token.remaining = token.remaining - 1
    if token.remaining <= 0 and not token.cancelled and token.onDone then
        token.onDone()
    end
end

--- Single tick (instance frame loop, BEFORE layout/render). Writes via
-- node:_set(prop, value, "system") — normal mutation layer, automatic
-- invalidation. Paused chains freeze (timestamps shift on resume).
function AnimationManager:update()
    -- zero-work idle
    if self.activeCount == 0 then return end
    local now = self.context.clock()
    local i = 1
    while i <= self.activeCount do
        local a = self.active[i]
        local owner = a.token and a.token.owner
        if owner and owner.paused then
            i = i + 1
        else
            local node = a.node
            if node._destroyed then
                a.token = nil
                finishEntry(a)
                removeAt(self, i)
            else
                local t = (now - a.start) / a.dur
                if t >= 1 then
                    node:_set(a.prop, a.to, "system")
                    -- remove FIRST (callbacks may chain)
                    removeAt(self, i)
                    finishEntry(a)
                else
                    if t < 0 then t = 0 end
                    node:_set(a.prop, a.from + (a.to - a.from) * a.ease(t), "system")
                    i = i + 1
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- AnimHandle: step chain (timeline/sequence)
-- ---------------------------------------------------------------------

--- Runs a step; on completion — the next from the queue or done callbacks.
function AnimHandle:_run(props, duration, ease)
    local node = self.node
    self.manager:_startStep(node, props, duration, resolveEase(ease), function()
        if self.cancelled or not node:isAlive() then return end
        local next_ = table.remove(self.queue, 1)
        if next_ then
            self:_run(next_[1], next_[2], next_[3])
        else
            local cbs = self.doneCbs
            for i = 1, #cbs do cbs[i]() end
        end
    end, self)
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

--- Cancels THIS chain only; onDone is not called.
function AnimHandle:cancel()
    self.cancelled = true
    self.queue = {}
    self.doneCbs = {}
    self.manager:_removeHandle(self)
    return self
end

--- Pauses THIS chain (running steps freeze; queued steps wait).
function AnimHandle:pause()
    if self.paused then return self end
    self.paused = true
    self._pauseStart = self.manager.context.clock()
    return self
end

--- Resumes a paused chain: paused duration is added to every running
-- step's start timestamp.
function AnimHandle:resume()
    if not self.paused then return self end
    local dt = self.manager.context.clock() - self._pauseStart
    self.paused = false
    local active = self.manager.active
    for i = 1, self.manager.activeCount do
        local a = active[i]
        if a.token and a.token.owner == self then
            a.start = a.start + dt
        end
    end
    return self
end

DXUI.Anim = AnimationManager