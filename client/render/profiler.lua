--[[
    profiler.lua

    M10 (Production): профилирование рендер-кадра. §50 ТЗ: "production:
    minimal overhead" — Profiler ОТКЛЮЧЁН по умолчанию (enabled = false),
    его стоимость в проде = 0 (один if-чек в renderFrame). Включение —
    только вручную: DXUI.instance.profiler.enabled = true (или DXUI.toggleProfile()).

    Что меряется (в мс, через getRealTime()/os.clock):
      - total: полный renderFrame
      - anim: AnimationPool:update
      - culling: Culling.update
      - layout: Layout.update
      - clip: Clip.update
      - builder: Builder.update
      - batcher: Batcher.getDrawOrder
      - execute: StateCache:executeOrder (draw calls)
      - flushClip: StateCache:flushClip

    История: ring buffer на HISTORY=120 кадров (≈2 секунды @60fps).
    Без аллокаций в hot path (все таблицы переиспользуются).

    ADR-012: M9-оптимизации замеряются через этот Profiler (bench/bench.lua —
    внешний harness, Profiler — внутренний, для в-игре).
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.Profiler = {}
local Profiler = DXUI.Profiler
Profiler.__index = Profiler

-- Ring buffer: 120 кадров (≈2 сек @60fps). Каждая запись — таблица с
-- таймстампами фаз (переиспользуется, не аллоцируется).
local HISTORY = 120
local PHASES = {
    "total", "anim", "culling", "layout", "clip",
    "builder", "batcher", "execute", "flushClip",
}

-- Функция времени (мс). В MTA: getTickCount() — мс с момента старта.
-- В тестах (lupa): os.clock()*1000 (фоллбэк).
local function clockFn()
    if getTickCount then
        return getTickCount()
    end
    return os.clock() * 1000
end

function Profiler.new()
    local self = setmetatable({}, Profiler)
    self.enabled = false -- M10: OFF by default (§50 — zero overhead в проде)
    self.history = {}    -- ring buffer: [1..HISTORY]
    self.head = 0        -- индекс последней записи (0 = пусто)
    self.clock = clockFn
    -- Текущий кадр (переиспользуется, не аллоцируется).
    self.frame = {}
    for i = 1, #PHASES do
        self.frame[PHASES[i]] = 0
    end
    self.frame.frameNum = 0
    self.frame.commandCount = 0
    self.frame.rebuiltOrder = false
    self.frame.dirtyCount = 0
    -- Статистика (среднее за историю).
    self.avg = {}
    for i = 1, #PHASES do
        self.avg[PHASES[i]] = 0
    end
    return self
end

--- Включает/выключает профилирование.
function Profiler:setEnabled(v)
    self.enabled = v
end

function Profiler:toggle()
    self.enabled = not self.enabled
    return self.enabled
end

--- Начало кадра (вызывается Kernel:renderFrame при enabled).
-- Запоминает время старта и нольрует frame.
function Profiler:begin()
    local f = self.frame
    f.frameNum = f.frameNum + 1
    f._t0 = self.clock()
    for i = 1, #PHASES do
        f[PHASES[i]] = 0
    end
    f._phaseStart = f._t0
    f._phaseIdx = 1 -- указатель на текущую фазу (для mark)
end

--- Отметка завершения фазы (вызывается после каждой фазы при enabled).
-- Фаза определяется порядком вызовов: anim -> culling -> layout -> clip ->
-- builder -> batcher -> execute -> flushClip.
function Profiler:mark()
    local f = self.frame
    local now = self.clock()
    local idx = f._phaseIdx
    if idx <= #PHASES then
        f[PHASES[idx]] = now - f._phaseStart
        f._phaseStart = now
        f._phaseIdx = idx + 1
    end
end

--- Конец кадра: сохраняет frame в ring buffer, пересчитывает avg.
function Profiler:finish()
    local f = self.frame
    -- Последняя фаза (flushClip) — если не отмечена, отмечаем.
    local idx = f._phaseIdx
    if idx <= #PHASES then
        local now = self.clock()
        f[PHASES[idx]] = now - f._phaseStart
        f._phaseIdx = idx + 1
    end
    -- total = всё время кадра
    local tEnd = self.clock()
    f.total = tEnd - f._t0

    -- Сохраняем в ring buffer (переиспользуем слот).
    self.head = (self.head % HISTORY) + 1
    local slot = self.history[self.head]
    if not slot then
        slot = {}
        self.history[self.head] = slot
    end
    for i = 1, #PHASES do
        slot[PHASES[i]] = f[PHASES[i]]
    end
    slot.frameNum = f.frameNum
    slot.commandCount = f.commandCount
    slot.rebuiltOrder = f.rebuiltOrder
    slot.dirtyCount = f.dirtyCount

    -- Пересчитываем avg (O(HISTORY) — только при enabled, не в hot path).
    local filled = 0
    for j = 1, HISTORY do
        if self.history[j] then filled = filled + 1 end
    end
    for i = 1, #PHASES do
        local sum = 0
        for j = 1, HISTORY do
            local h = self.history[j]
            if h then sum = sum + (h[PHASES[i]] or 0) end
        end
        self.avg[PHASES[i]] = filled > 0 and sum / filled or 0
    end
end

--- Устанавливает метаданные кадра (commandCount, rebuiltOrder, dirtyCount).
-- Вызывается Kernel после compute, перед end().
function Profiler:setFrameMeta(commandCount, rebuiltOrder, dirtyCount)
    local f = self.frame
    f.commandCount = commandCount
    f.rebuiltOrder = rebuiltOrder
    f.dirtyCount = dirtyCount
end

--- Возвращает avg-статистику (для overlay/отладки).
function Profiler:getAvg()
    return self.avg
end

--- Возвращает последнюю запись ring buffer.
function Profiler:getLast()
    return self.history[self.head]
end

--- Форматирует avg-статистику строкой (для overlay/debug-вывода).
-- Cold path: вызывается только при включённом overlay, не каждый кадр.
function Profiler:format()
    local avg = self.avg
    local lines = {}
    lines[#lines + 1] = string.format("DXUI Profiler (avg over %d frames):", HISTORY)
    for i = 1, #PHASES do
        lines[#lines + 1] = string.format("  %-10s %8.4f ms", PHASES[i], avg[PHASES[i]])
    end
    return table.concat(lines, "\n")
end