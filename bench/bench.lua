--[[
    bench/bench.lua (M9)

    Бенчмарк-харнес MTA DX GUI. Замеры — единственная база для
    performance-заявок (твёрдое правило промта: никаких чисел без bench).

    Семантика:
      - Каждый сценарий = функция (k, B), где k — готовый Kernel,
        B — этот harness. Сценарий сам строит сцену и сам решает,
        что замерять (frames/ops/создание/уничтожение).
      - Таймер: getRealTime() в MTA, os.clock() в тестах (лупа).
        Ticks — целые миллисекунды; для коротких сценариев harness
        сам повторяет тело N раз, чтобы суммарно было >= 100ms.
      - Результат: { name, msPerUnit, unit, totalMs, repeats, note }.

    Использование (MTA):  addEventHandler("onClientRender", ...) или
    standalone: dofile("bench/bench.lua") и DXUI.Bench.runAll().
    Использование (tests): dofile("../bench/bench.lua"); DXUI.Bench.run("idle_100").
]]

local Bench = {}
DXUI = DXUI or {}
DXUI.Bench = Bench

local function now()
    -- M9/M11: getTickCount() — мс с момента старта (MTA client-side).
    -- getTickCount64 — 64-битная версия (MTA 1.5.5+), фоллбэк для Windows.
    -- os.clock — фоллбэк для lupa/Linux.
    if getTickCount then
        return getTickCount()
    end
    if getTickCount64 then
        return getTickCount64()
    end
    return os.clock() * 1000
end

local function median(t)
    local s = {}
    for i = 1, #t do s[i] = t[i] end
    table.sort(s)
    local n = #s
    if n == 0 then return 0 end
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return (s[n / 2] + s[n / 2 + 1]) / 2
end

-- =======================================================================
-- СЦЕНАРИИ
-- =======================================================================

Bench.scenarios = {}

--- Создание N узлов (холодный путь: proxy-пул, id freelist, SoA init).
local function makeScenario(name, unit, buildFn)
    Bench.scenarios[name] = { name = name, unit = unit, build = buildFn }
end

makeScenario("create_100", "node", function(k)
    return function()
        local n = k:create(1) -- NODE_PANEL
        k:destroy(n)
    end
end)

makeScenario("create_1000", "node", function(k)
    return function()
        local n = k:create(1)
        k:destroy(n)
    end
end)

--- Idle-кадры: N узлов, ничего не меняем, полный renderFrame.
-- Ожидание (§8 ТЗ): zero dirty work; время ≈ только исполнение draw order.
makeScenario("idle_100", "frame", function(k)
    for i = 1, 100 do
        local n = k:create(1)
        n:setPosition(i % 400, (i * 7) % 300)
        n:setSize(50, 50)
    end
    return function()
        k:renderFrame()
    end
end)

makeScenario("idle_500", "frame", function(k)
    for i = 1, 500 do
        local n = k:create(1)
        n:setPosition(i % 800, (i * 13) % 600)
        n:setSize(50, 50)
    end
    return function()
        k:renderFrame()
    end
end)

--- Hot-путь: каждый кадр меняем позицию/цвет M узлов (dirty-каскад,
-- layout, clip, builder, batcher — полный цикл).
makeScenario("move_50", "frame", function(k)
    local nodes = {}
    for i = 1, 50 do
        local n = k:create(1)
        n:setPosition(0, 0):setSize(30, 30)
        nodes[#nodes + 1] = n
    end
    local t = 0
    return function()
        t = t + 1
        for i = 1, 50 do
            nodes[i]:setPosition(t % 800, (t + i * 10) % 600)
        end
        k:renderFrame()
    end
end)

makeScenario("move_200", "frame", function(k)
    local nodes = {}
    for i = 1, 200 do
        local n = k:create(1)
        n:setPosition(0, 0):setSize(30, 30)
        nodes[#nodes + 1] = n
    end
    local t = 0
    return function()
        t = t + 1
        for i = 1, 200 do
            nodes[i]:setPosition(t % 800, (t + i * 3) % 600)
        end
        k:renderFrame()
    end
end)

--- Иерархия: 500 узлов в 50 панелей по 10 детей (layout-каскад по дереву).
makeScenario("hierarchy_500", "frame", function(k)
    local panels = {}
    for p = 1, 50 do
        local panel = k:create(1)
        panel:setPosition((p % 10) * 80, math.floor((p - 1) / 10) * 60)
        panel:setSize(80, 60)
        for i = 1, 10 do
            local c = k:create(1, panel)
            c:setPosition(i * 5, 5):setSize(20, 20)
        end
        panels[#panels + 1] = panel
    end
    local t = 0
    return function()
        t = t + 1
        for p = 1, 50 do
            panels[p]:setPosition((p % 10) * 80 + t % 5, math.floor((p - 1) / 10) * 60)
        end
        k:renderFrame()
    end
end)

--- Clip: 100 узлов в 10 clip-контейнерах (clip-пересчёт + RT push/pop).
makeScenario("clip_100", "frame", function(k)
    local containers = {}
    for p = 1, 10 do
        local c = k:create(1)
        c:setPosition((p % 5) * 160, math.floor((p - 1) / 5) * 120)
        c:setSize(160, 120)
        c:setClip(true)
        for i = 1, 10 do
            local n = k:create(1, c)
            n:setPosition(i * 10, 10):setSize(30, 30)
        end
        containers[#containers + 1] = c
    end
    local t = 0
    return function()
        t = t + 1
        for p = 1, 10 do
            containers[p]:setPosition((p % 5) * 160 + t % 3, math.floor((p - 1) / 5) * 120)
        end
        k:renderFrame()
    end
end)

--- Анимация: 50 узлов анимируются (animPool:update + per-node tick).
makeScenario("anim_50", "frame", function(k)
    local nodes = {}
    for i = 1, 50 do
        local n = k:create(1)
        n:setPosition(0, 0):setSize(40, 40)
        nodes[#nodes + 1] = n
    end
    local started = false
    return function()
        if not started then
            started = true
            for i = 1, 50 do
                nodes[i]:animateTo({ x = 400, y = 200 }, 600)
            end
        end
        k:renderFrame()
    end
end)

--- Hit test: 500 узлов, onCursorMove + onClientClick.
makeScenario("input_500", "op", function(k)
    for i = 1, 500 do
        local n = k:create(1)
        n:setPosition((i % 40) * 20, math.floor((i - 1) / 40) * 20)
        n:setSize(20, 20)
    end
    local t = 0
    return function()
        t = t + 1
        k:onCursorMove(400, 300)
        k:onMouseDown(400, 300, 1)
        k:onMouseUp(400, 300, 1)
    end
end)

-- =======================================================================
-- ЗАПУСК
-- =======================================================================

local MIN_MS = 100 -- суммарно замеряем не меньше 100ms на сценарий

--- Запускает сценарий: build-фаза + тело, повторное выполнение до MIN_MS.
-- M9: MEDIAN из RUNS прогонов (Windows os.clock нестабилен — разброс ×3-5,
-- median снимает выбросы). RUNS=5, MIN_MS=50 на прогон.
-- @return { name, msPerUnit, unit, samples, min, max, median }
local RUNS = 5
local MIN_MS = 50

function Bench.run(name, kernel)
    local sc = Bench.scenarios[name]
    if not sc then
        error("Bench.run: unknown scenario " .. tostring(name))
    end

    -- Warmup: 1 прогон без замера (JIT/пулы прогреваются).
    local body = sc.build(kernel)
    body()

    local samples = {}
    local minReps, maxReps = math.huge, 0
    for r = 1, RUNS do
        -- M9: collectgarbage перед каждым прогоном — убирает GC-шум
        -- (Lua 5.1 incremental GC аллоцирует таблицы в executeOrder и т.п.).
        collectgarbage("collect")
        local t0 = now()
        local repeats = 0
        local last = t0
        while (last - t0) < MIN_MS do
            body()
            repeats = repeats + 1
            last = now()
        end
        local totalMs = last - t0
        if totalMs <= 0 then totalMs = 0.001 end
        samples[#samples + 1] = totalMs / repeats
        if repeats < minReps then minReps = repeats end
        if repeats > maxReps then maxReps = repeats end
    end

    table.sort(samples)
    local min = samples[1]
    local max = samples[#samples]
    return {
        name = name,
        unit = sc.unit,
        msPerUnit = median(samples), -- медиана — устойчивая мера
        min = min,
        max = max,
        samples = #samples,
    }
end

--- Запускает все сценарии на одном Kernel; печатает таблицу.
-- В MTA вызывается из onClientRender один раз после загрузки UI.
function Bench.runAll(kernel)
    local results = {}
    for name in pairs(Bench.scenarios) do
        results[#results + 1] = Bench.run(name, kernel)
    end
    -- сортировка по имени для стабильного вывода
    table.sort(results, function(a, b) return a.name < b.name end)

    print(string.rep("=", 60))
    print("  DXUI M9 BENCHMARK — " .. #results .. " scenarios")
    print(string.rep("=", 60))
    print(string.format("  %-14s %10s %10s %10s %8s", "scenario", "median", "min", "max", "runs"))
    print(string.rep("-", 60))
    for i = 1, #results do
        local r = results[i]
        print(string.format("  %-14s %10.4f %10.4f %10.4f %8d",
            r.name, r.msPerUnit, r.min, r.max, r.samples))
    end
    print(string.rep("=", 60))
    return results
end

return Bench
