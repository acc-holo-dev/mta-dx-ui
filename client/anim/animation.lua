--[[
    animation.lua (M6)

    ADR-010: анимация = ДАННЫЕ, а не таймеры.

    Запрет (архитектура ТЗ): никаких setTimer на узел, никаких per-node
    обработчиков рендера. Единственный механизм времени — единый тик:

        Kernel:renderFrame() -> AnimationPool:update(now)

    before Culling/Layout/Builder, чтобы сдвиг позиции в этом же кадре
    прошёл через layout и отрисовался.

    Структура (SoA, тот же паттерн, что cmdPool/storage):
      - пул активных анимаций: field/from/to/start/dur/ease/nodeId
      - activeList + activeIndexOf — O(1) swap-with-last удаление
      - freelist переиспользования слотов (no alloc в hot path)
      - storage.animX/animY/animW/animH[slot] = pool-слот узла по свойству
        (O(1) прерывание и cleanup при destroy)

    Idle-кадр без активных анимаций = zero work: update() проходит по
    activeList, а он пуст (activeCount == 0 -> немедленный return).

    Easing — чистые численные функции без аллокаций.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

local EASE = {
    [C.EASE_LINEAR] = function(t) return t end,
    [C.EASE_IN]     = function(t) return t * t * t end,
    [C.EASE_OUT]    = function(t) local u = 1 - t return 1 - u * u * u end,
    [C.EASE_IN_OUT] = function(t) return t * t * (3 - 2 * t) end,
}

local AnimationPool = {}
AnimationPool.__index = AnimationPool
DXUI.AnimationPool = AnimationPool

--- storage — SoA узлов; clock — функция, возвращающая текущее время в мс
-- (в MTA: getRealTime()*1000, в тестах — фейк).
function AnimationPool.new(storage, clock)
    local self = setmetatable({}, AnimationPool)
    self.storage = storage
    self.clock = clock or function() return 0 end

    self.field   = {}  -- C.ANIM_X/Y/W/H
    self.from    = {}
    self.to      = {}
    self.startTime = {} -- ms (НЕ "start": имя метода, shadowing!)
    self.dur     = {}  -- ms
    self.ease    = {}  -- C.EASE_*
    self.nodeId  = {}  -- id целевого узла

    self.freeSlots = {}
    self.freeCount = 0
    self.nextFreshSlot = 1

    self.activeList = {}
    self.activeCount = 0
    self.activeIndexOf = {}
    return self
end

function AnimationPool:_alloc()
    local slot
    if self.freeCount > 0 then
        slot = self.freeSlots[self.freeCount]
        self.freeSlots[self.freeCount] = nil
        self.freeCount = self.freeCount - 1
    else
        slot = self.nextFreshSlot
        self.nextFreshSlot = slot + 1
    end
    return slot
end

function AnimationPool:_free(slot)
    self.nodeId[slot] = nil
    self.field[slot] = nil
    self.from[slot] = nil
    self.to[slot] = nil
    self.startTime[slot] = nil
    self.dur[slot] = nil
    self.ease[slot] = nil
    self.freeSlots[self.freeCount + 1] = slot
    self.freeCount = self.freeCount + 1
end

--- Убирает активную анимацию по позиции в activeList (swap-with-last).
-- Вызывается из update() (комплит) и releaseNode/stop (прерывание).
function AnimationPool:_removeActiveAt(i)
    local slot = self.activeList[i]
    local last = self.activeList[self.activeCount]
    self.activeList[i] = last
    self.activeIndexOf[last] = i
    self.activeList[self.activeCount] = nil
    self.activeIndexOf[slot] = nil
    self.activeCount = self.activeCount - 1
    return slot
end

--- Запускает анимацию свойства узла. Прерывает уже идущую анимацию
-- того же свойства (from берётся из ТЕКУЩЕГО значения).
-- props: field — C.ANIM_*; to, durMs, ease.
function AnimationPool:start(nodeId, field, to, durMs, ease)
    local s = self.storage
    local slot = s.idToSlot[nodeId]
    if not slot then return nil end

    -- прерывание: освобождаем старый слот этого свойства
    local col
    if field == C.ANIM_X then col = s.animX
    elseif field == C.ANIM_Y then col = s.animY
    elseif field == C.ANIM_W then col = s.animW
    else col = s.animH end

    local oldSlot = col[slot]
    if oldSlot ~= C.NO_ANIM_SLOT then
        -- oldSlot обязательно в activeList
        local idx = self.activeIndexOf[oldSlot]
        if idx then self:_removeActiveAt(idx) end
        self:_free(oldSlot)
    end

    local from
    if field == C.ANIM_X then from = s.x[slot]
    elseif field == C.ANIM_Y then from = s.y[slot]
    elseif field == C.ANIM_W then from = s.w[slot]
    else from = s.h[slot] end

    if durMs <= 0 then
        -- дегенерация: мгновенный snap без записи в пул
        if field == C.ANIM_X then s.x[slot] = to
        elseif field == C.ANIM_Y then s.y[slot] = to
        elseif field == C.ANIM_W then s.w[slot] = to
        else s.h[slot] = to end
        s:markDirty(nodeId, C.DIRTY_POS) -- M9: единый бит
        return nil
    end

    local pslot = self:_alloc()
    self.field[pslot] = field
    self.from[pslot] = from
    self.to[pslot] = to
    self.startTime[pslot] = self.clock()
    self.dur[pslot] = durMs
    self.ease[pslot] = ease or C.EASE_DEFAULT
    self.nodeId[pslot] = nodeId

    self.activeCount = self.activeCount + 1
    self.activeList[self.activeCount] = pslot
    self.activeIndexOf[pslot] = self.activeCount
    col[slot] = pslot
    return pslot
end

--- Простановка/остановка всех анимаций узла (без snap на конец).
function AnimationPool:stop(nodeId)
    local s = self.storage
    local slot = s.idToSlot[nodeId]
    if not slot then return end
    for _, col in ipairs({ s.animX, s.animY, s.animW, s.animH }) do
        local pslot = col[slot]
        if pslot ~= C.NO_ANIM_SLOT then
            col[slot] = C.NO_ANIM_SLOT
            local idx = self.activeIndexOf[pslot]
            if idx then self:_removeActiveAt(idx) end
            self:_free(pslot)
        end
    end
end

--- Вызывается Storage-хуком destroy: чистим все активные анимации узла.
-- Слоты storage.anim* к этому моменту уже стёрты компакцией, поэтому
-- ищем по пулу (activeList короткий; destroy — редкий cold path).
function AnimationPool:releaseNode(nodeId)
    local i = 1
    while i <= self.activeCount do
        if self.nodeId[self.activeList[i]] == nodeId then
            local pslot = self:_removeActiveAt(i)
            self:_free(pslot)
        else
            i = i + 1
        end
    end
end

--- Единый тик анимаций. Вызывается Kernel:renderFrame() ДО layout.
-- Пишет промежуточные значения в storage.x/y/w/h + DIRTY_LAYOUT|RENDER.
function AnimationPool:update()
    local s = self.storage
    local n = self.activeCount
    if n == 0 then return end -- zero-work idle

    local now = self.clock()
    local i = 1
    while i <= n do
        local pslot = self.activeList[i]
        local t = (now - self.startTime[pslot]) / self.dur[pslot]

        if t >= 1 then
            -- комплит: точный snap на to, чистим column узла, убираем из пула
            local id = self.nodeId[pslot]
            local slot = s.idToSlot[id]
            if slot then
                local f = self.field[pslot]
                if f == C.ANIM_X then s.x[slot] = self.to[pslot]; s.animX[slot] = C.NO_ANIM_SLOT
                elseif f == C.ANIM_Y then s.y[slot] = self.to[pslot]; s.animY[slot] = C.NO_ANIM_SLOT
                elseif f == C.ANIM_W then s.w[slot] = self.to[pslot]; s.animW[slot] = C.NO_ANIM_SLOT
                else s.h[slot] = self.to[pslot]; s.animH[slot] = C.NO_ANIM_SLOT end
                s:markSlotDirty(slot, C.DIRTY_POS) -- M9: hot-вариант
            end
            self:_removeActiveAt(i)
            self:_free(pslot)
            n = n - 1 -- НЕ i=i+1: на место i поднят последний элемент
        else
            if t < 0 then t = 0 end
            local id = self.nodeId[pslot]
            local slot = s.idToSlot[id]
            if slot then
                local v = self.from[pslot] + (self.to[pslot] - self.from[pslot]) * EASE[self.ease[pslot]](t)
                local f = self.field[pslot]
                if f == C.ANIM_X then s.x[slot] = v
                elseif f == C.ANIM_Y then s.y[slot] = v
                elseif f == C.ANIM_W then s.w[slot] = v
                else s.h[slot] = v end
                s:markSlotDirty(slot, C.DIRTY_POS) -- M9: hot-вариант
            end
            i = i + 1
        end
    end
end
