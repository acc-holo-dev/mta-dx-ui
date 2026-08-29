--[[
    kernel.lua

    M1: Kernel. Публичная поверхность на этом этапе — только создание/
    уничтожение/иерархия/dirty-система. Никакого рендера (M2), layout-правил
    (M4) или виджетов (M7) здесь ещё нет — согласно Quality Gate (§9 ADR),
    веха не смешивает ответственность разных стадий плана.
]]

DXUI = DXUI or {}
local Storage = DXUI.Storage
local Proxy = DXUI.Proxy
local C = DXUI.Constants

local Kernel = {}
Kernel.__index = Kernel
DXUI.Kernel = Kernel

function Kernel.new(driver)
    local self = setmetatable({}, Kernel)
    self.driver = driver -- M6: храним для доступа из tests/инспекции (stateCache тоже владеет ссылкой)
    -- M8: rtManager живёт в MTA-драйвере (backend_mta.lua); у мок-драйверов/без драйвера nil.
    self.rtManager = driver and driver.rtManager or nil
    self.storage = Storage.new()

    -- M3: EventBus создаётся до Proxy, т.к. proxy:on() нужна ссылка на него.
    self.eventBus = DXUI.EventBus.new(self.storage)

    -- M6: clock — время в мс. В MTA bootstrap подменит на getRealTime()*1000;
    -- по умолчанию статичный 0, пока clock не задан через setClock (тесты).
    local clockFn
    if getRealTime then
        clockFn = function() return getRealTime() * 1000 end
    else
        clockFn = function() return 0 end
    end

    local animPool = DXUI.AnimationPool.new(self.storage, clockFn)
    self.animPool = animPool

    self.proxy = Proxy.new(self.storage, self.eventBus, animPool)
    self.dispatcher = DXUI.Dispatcher.new(self.storage, self.eventBus)

    -- M2: render pipeline. driver — реальный DXUI.MtaDriver в игре,
    -- либо мок в тестах (см. tests/test_render.lua) — это единственная
    -- точка входа внешней зависимости от dx*-функций во всём Kernel.
    self.cmdPool = DXUI.RenderCmdPool.new()
    self.stateCache = DXUI.StateCache.new(driver)
    self.drawOrder = nil -- закэшированный порядок, пересобирается Batcher'ом по требованию

    -- M10: Profiler — OFF by default (§50 — zero overhead в проде).
    -- Включение: DXUI.instance.profiler.enabled = true (или DXUI.toggleProfile()).
    self.profiler = DXUI.Profiler.new()
    self.profiler.clock = clockFn

    -- Renderer владеет cmdPool-слотами узлов, но НЕ знает о destroy напрямую —
    -- подписывается на Storage-событие, получая cmdSlot, захваченный ДО
    -- компакции (см. Storage:onNodeDestroyed).
    local cmdPool = self.cmdPool
    self.storage:onNodeDestroyed(function(id, cmdSlot)
        DXUI.Builder.onNodeDestroyed(self.storage, cmdPool, id, cmdSlot)
        self.animPool:releaseNode(id) -- M6: чистим активные анимации узла
    end)

    return self
end

--- Создаёt узел заданного числового типа (C.NODE_*) с опциональным родителем
-- (proxy или сырой id). Возвращает proxy-handle.
function Kernel:create(nodeType, parentHandle)
    local parentId = C.NIL_ID
    if parentHandle ~= nil then
        parentId = type(parentHandle) == "table" and parentHandle.id or parentHandle
    end
    local id = self.storage:createNode(nodeType, parentId)
    return self.proxy:acquire(id)
end

--- Уничтожает узел по handle и возвращает proxy-таблицу в пул.
function Kernel:destroy(handle)
    handle:destroy()
    self.proxy:release(handle)
end

--- Вызывается в конце обработки кадра рендер-конвейером (в M1 — заглушка,
-- реальный вызов будет частью Core frame loop, добавляемого в M2 вместе
-- с onClientRender интеграцией).
function Kernel:endFrame()
    self.storage:clearFrameDirty()
end

--- Полный render pass за кадр (§E pipeline). Порядок фиксирован:
--   Culling (effectiveVisible) -> Layout (world-координаты) -> Clip (M5,
--   clipDepth) -> Builder (cmd-пул) -> Batcher (draw order) -> StateCache
--   (dedup state + draw calls) -> endFrame (clearFrameDirty).
-- Каждый шаг работает только по dirty-узлам; idle-кадр = zero work (§8 ТЗ).
function Kernel:renderFrame()
    local prof = self.profiler
    local profiling = prof.enabled
    if profiling then prof:begin() end

    self.animPool:update() -- M6: ПЕРВЫМ — сдвиг позиции прошёл layout в этом же кадре
    if profiling then prof:mark() end
    DXUI.Culling.update(self.storage)
    if profiling then prof:mark() end
    DXUI.Layout.update(self.storage)
    if profiling then prof:mark() end
    DXUI.Clip.update(self.storage)
    if profiling then prof:mark() end

    local compositionChanged = DXUI.Builder.update(self.storage, self.cmdPool)
    if compositionChanged then
        self.storage.orderDirty = true
    end
    if profiling then prof:mark() end

    local order, rebuilt = DXUI.Batcher.getDrawOrder(self.storage, self.cmdPool, self.drawOrder)
    self.drawOrder = order
    if profiling then prof:mark() end

    self.stateCache:executeOrder(self.cmdPool, order)
    if profiling then prof:mark() end
    self.stateCache:flushClip() -- M8: RT-стек не переживает кадр
    if profiling then prof:mark() end

    self:endFrame()

    if profiling then
        prof:setFrameMeta(#order, rebuilt, self.storage.dirtyCount)
        prof:finish()
    end

    return { rebuiltOrder = rebuilt, commandCount = #order }
end

--- M4: устанавливает размер экрана для корневых узлов в LAY_REL/LAY_CENTER.
-- Вызывается один раз при инициализации (bootstrap.lua) и при смене
-- разрешения игры (onClientResolutionChange, M8).
function Kernel:setScreenSize(w, h)
    self.screenW = w
    self.screenH = h
    DXUI.Layout.setScreenSize(self.storage, w, h)
end

--- M6: подмена источника времени (мс). MTA: getRealTime()*1000 (bootstrap);
-- тесты — фейковый clock с ручным advance.
function Kernel:setClock(fn)
    self.animPool.clock = fn
end

function Kernel:stats()
    return self.storage:stats()
end

-- M3: тонкие проброс-методы к Dispatcher — единственная точка входа для
-- bootstrap.lua, чтобы вызывающий код не знал о существовании Dispatcher
-- как отдельного объекта (§42 "simple outside, complex inside").
function Kernel:onCursorMove(px, py)
    self.dispatcher:onCursorMove(px, py)
end

function Kernel:onMouseDown(px, py, button)
    self.dispatcher:onMouseDown(px, py, button)
end

function Kernel:onMouseUp(px, py, button)
    self.dispatcher:onMouseUp(px, py, button)
end
