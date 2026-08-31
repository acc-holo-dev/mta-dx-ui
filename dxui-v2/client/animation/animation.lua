--[[
    animation.lua — DXUI V2

    Animation engine (§51–§53): централизованный manager, ОДИН тик в кадре
    (Context:renderFrame → update). Никаких per-node таймеров/handler'ов.

    Анимация изменяет РЕАЛЬНЫЕ свойства узла через нормальный mutation layer
    (node:_set) — нет дублирующих значений node.x / animation.x / render.x
    (§53). Инвалидация работает автоматически: value change → DIRTY.

        local anim = button:animate({ x = 100 }, 300)        -- 300ms
        anim:after({ opacity = 0.5 }, 200)                   -- цепочка (§52)
        anim:onDone(function() print("готово") end)
        anim:cancel()

    Цепочка: `:after(...)` (не `:then` — «then» зарезервированное слово Lua).
    Каждый шаг = набор свойств (записи в общем списке) + token; token
    завершается, когда все свойства шага дошли до цели → запускается
    следующий шаг очереди. Прерывание (cancel/re-animate) НЕ вызывает
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

--- Убирает запись по позиции (swap-with-last, O(1)). Декремент token.
local function removeAt(self, i)
    local n = self.activeCount
    local entry = self.active[i]
    self.active[i] = self.active[n]
    self.active[n] = nil
    self.activeCount = n - 1
    return entry
end

--- Прерывает анимации свойства узла (перед запуском новой). Token отменяется
--- (cancel ≠ complete: onDone НЕ вызывается).
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

--- Один шаг анимации: набор свойств + token (завершение шага → onDone).
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

--- Публичный вход: node:animate(...) → handle с цепочкой (§52).
function AnimationManager:animate(node, props, duration, easeName)
    local handle = setmetatable({
        manager = self, node = node,
        queue = {}, doneCbs = {},
        cancelled = false,
    }, AnimHandle)
    handle:_run(props, duration, easeName)
    return handle
end

--- Останавливает все анимации узла (значение остаётся текущим).
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

--- Завершение записи: декремент token; 0 и не отменён → onDone (следующий шаг).
local function finishEntry(entry)
    local token = entry.token
    if not token then return end
    token.remaining = token.remaining - 1
    if token.remaining <= 0 and not token.cancelled and token.onDone then
        token.onDone()
    end
end

--- Единый тик (вызывается Context:renderFrame ДО layout/render).
-- Пишет промежуточные значения через node:_set — нормальный mutation layer.
function AnimationManager:update()
    if self.activeCount == 0 then return end -- zero-work idle
    local now = self.context.clock()
    local i = 1
    while i <= self.activeCount do
        local a = self.active[i]
        local node = a.node
        if node._destroyed then
            a.token = nil -- мёртвый узел: цепочку не продолжаем
            finishEntry(removeAt(self, i))
        else
            local t = (now - a.start) / a.dur
            if t >= 1 then
                node:_set(a.prop, a.to) -- точный snap на конец
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
-- AnimHandle: цепочка шагов (§52 timeline/sequence)
-- ---------------------------------------------------------------------

--- Запускает шаг; по завершении — следующий из очереди или done-колбэки.
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

--- Добавляет шаг в очередь цепочки (выполняется после текущего).
function AnimHandle:after(props, duration, easeName)
    self.queue[#self.queue + 1] = { props, duration, easeName }
    return self
end

--- Колбэк по завершении ВСЕЙ цепочки.
function AnimHandle:onDone(fn)
    self.doneCbs[#self.doneCbs + 1] = fn
    return self
end

--- Отменяет цепочку (текущие анимации останавливаются, onDone не вызывается).
function AnimHandle:cancel()
    self.cancelled = true
    self.queue = {}
    self.doneCbs = {}
    self.manager:stop(self.node)
    return self
end

DXUI.AnimationManager = AnimationManager