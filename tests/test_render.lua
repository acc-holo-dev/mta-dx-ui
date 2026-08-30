dofile("loader.lua")

local Kernel = DXUI.Kernel
local C = DXUI.Constants

local passed, failed = 0, 0
local function check(name, cond)
    if cond then
        passed = passed + 1
        print("[OK]   " .. name)
    else
        failed = failed + 1
        print("[FAIL] " .. name)
    end
end

-- Мок-driver: вместо реальных dx*-вызовов пишет в лог. Позволяет проверять
-- и факт вызова, и (что важнее) факт ЕГО ОТСУТСТВИЯ там, где ожидается
-- дедупликация (§62/§63 ТЗ).
local function newMockDriver()
    local log = {}
    local driver = { log = log }
    driver.setBlendMode = function(mode) log[#log+1] = {"blend", mode} end
    driver.drawRect = function(x, y, w, h, color) log[#log+1] = {"rect", x, y, w, h, color} end
    driver.drawImage = function(x, y, w, h, tex, color) log[#log+1] = {"image", x, y, w, h, tex, color} end
    driver.drawText = function(text, x, y, w, h, color) log[#log+1] = {"text", text, x, y, w, h, color} end
    return driver
end

local function countByType(log, t)
    local n = 0
    for i = 1, #log do if log[i][1] == t then n = n + 1 end end
    return n
end

-- =======================================================================
-- 1. Базовая эмиссия команды: rect по умолчанию, image при наличии texture,
--    text при наличии text (приоритет text > image > rect, см. builder.lua)
-- =======================================================================
do
    local driver = newMockDriver()
    local k = Kernel.new(driver)

    local a = k:create(C.NODE_PANEL)
    a:setPosition(10, 20):setSize(100, 50)

    local b = k:create(C.NODE_IMAGE)
    b:setPosition(0, 0):setSize(32, 32):setTexture("tex_handle_1")

    local c = k:create(C.NODE_TEXT)
    c:setPosition(5, 5):setSize(80, 16):setText("hello")

    k:renderFrame()

    check("builder: panel без texture/text -> CMD_RECT", countByType(driver.log, "rect") == 1)
    check("builder: image с texture -> CMD_IMAGE", countByType(driver.log, "image") == 1)
    check("builder: text с содержимым -> CMD_TEXT", countByType(driver.log, "text") == 1)
end

-- =======================================================================
-- 2. Zero-work idle: если ничего не dirty, повторный renderFrame не должен
--    порождать новые blend-переключения сверх одного (переиспользуем
--    закэшированный draw order и state cache)
-- =======================================================================
do
    local driver = newMockDriver()
    local k = Kernel.new(driver)
    local a = k:create(C.NODE_PANEL)
    a:setPosition(0, 0):setSize(10, 10)

    k:renderFrame()
    local blendCallsAfterFirst = countByType(driver.log, "blend")

    -- второй кадр без изменений: контент дерева не менялся
    local result2 = k:renderFrame()
    check("idle: второй кадр без изменений не пересобирает draw order",
        result2.rebuiltOrder == false)

    local blendCallsAfterSecond = countByType(driver.log, "blend")
    check("idle: blend mode не переключается повторно между кадрами (StateCache переживает кадр, §62)",
        blendCallsAfterSecond == blendCallsAfterFirst)
end

-- =======================================================================
-- 2b. StateCache dedup изолированно: два прямоугольника подряд не должны
--     дать два вызова setBlendMode, только один
-- =======================================================================
do
    local driver = newMockDriver()
    local sc = DXUI.StateCache.new(driver)
    local pool = DXUI.RenderCmdPool.new()

    local s1 = pool:alloc(1)
    pool.type[s1] = C.CMD_RECT
    pool.x[s1], pool.y[s1], pool.w[s1], pool.h[s1], pool.color[s1] = 0, 0, 10, 10, 0xFFFFFFFF

    local s2 = pool:alloc(2)
    pool.type[s2] = C.CMD_RECT
    pool.x[s2], pool.y[s2], pool.w[s2], pool.h[s2], pool.color[s2] = 10, 10, 10, 10, 0xFFFFFFFF

    sc:executeOrder(pool, {s1, s2})

    check("state_cache: 2 rect подряд -> ровно 1 setBlendMode (не 2)",
        countByType(driver.log, "blend") == 1)
    check("state_cache: оба прямоугольника всё же отрисованы", countByType(driver.log, "rect") == 2)
end

-- =======================================================================
-- 3. Culling: невидимый родитель -> невидимые дети, команда родителя
--    освобождается, у детей команда не создаётся вовсе
-- =======================================================================
do
    local driver = newMockDriver()
    local k = Kernel.new(driver)

    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(0,0):setSize(100,100)
    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(0,0):setSize(10,10)

    k:renderFrame()
    check("culling: изначально видимый родитель+ребёнок дают 2 rect-команды",
        countByType(driver.log, "rect") == 2)

    driver.log = {} -- сбрасываем лог, смотрим только следующий кадр
    parent:setVisible(false)
    k:renderFrame()

    check("culling: скрытие родителя убирает команды обоих узлов из кадра",
        countByType(driver.log, "rect") == 0)

    -- узел жив, просто невидим — cmdSlot должен быть освобождён (NO_CMD_SLOT)
    local storage = k.storage
    local pslot = storage.idToSlot[parent.id]
    local cslot = storage.idToSlot[child.id]
    check("culling: у скрытого родителя cmdSlot освобождён",
        storage.cmdSlot[pslot] == C.NO_CMD_SLOT)
    check("culling: у скрытого (через родителя) ребёнка cmdSlot тоже освобождён",
        storage.cmdSlot[cslot] == C.NO_CMD_SLOT)
end

-- =======================================================================
-- 4. Порядок отрисовки: сортировка по layer, затем по типу команды;
--    и orderDirty не взводится там, где порядок реально не менялся
-- =======================================================================
do
    local driver = newMockDriver()
    local k = Kernel.new(driver)

    local base = k:create(C.NODE_PANEL)
    base:setPosition(0,0):setSize(5,5):setLayer(C.LAYER_BASE)

    local tooltip = k:create(C.NODE_PANEL)
    tooltip:setPosition(0,0):setSize(5,5):setLayer(C.LAYER_TOOLTIP)

    local r1 = k:renderFrame()
    check("batcher: первый кадр всегда пересобирает порядок", r1.rebuiltOrder == true)

    local order = k.drawOrder
    local pool = k.cmdPool
    check("batcher: LAYER_BASE идёт раньше LAYER_TOOLTIP в draw order",
        pool.layer[order[1]] == C.LAYER_BASE and pool.layer[order[2]] == C.LAYER_TOOLTIP)

    -- меняем только цвет (не влияет на порядок) -> orderDirty НЕ должен взводиться
    base:setColor(0x00FF00FF)
    local r2 = k:renderFrame()
    check("batcher: смена цвета не триггерит пересборку порядка (§60, дёшево)",
        r2.rebuiltOrder == false)

    -- а смена layer — должна
    base:setLayer(C.LAYER_MODAL)
    local r3 = k:renderFrame()
    check("batcher: смена layer триггерит пересборку порядка", r3.rebuiltOrder == true)
end

-- =======================================================================
-- 5. Destroy во время наличия активной команды освобождает cmdPool-слот
--    (проверка сквозного пути Storage listener -> Builder.onNodeDestroyed)
-- =======================================================================
do
    local driver = newMockDriver()
    local k = Kernel.new(driver)
    local a = k:create(C.NODE_PANEL)
    a:setPosition(0,0):setSize(10,10)
    k:renderFrame()

    check("destroy: узел получил активную команду до уничтожения",
        k.cmdPool.activeCount == 1)

    k:destroy(a)

    check("destroy: после уничтожения узла активных команд 0 (слот освобождён)",
        k.cmdPool.activeCount == 0)
end

-- =======================================================================
-- 6. Стресс: 500 узлов, половина невидима — количество исполненных
--    rect-команд равно числу ВИДИМЫХ, не общему числу узлов
-- =======================================================================
do
    local driver = newMockDriver()
    local k = Kernel.new(driver)
    local visibleCount = 0

    for i = 1, 500 do
        local n = k:create(C.NODE_PANEL)
        n:setPosition(i, i):setSize(5, 5)
        if i % 2 == 0 then
            n:setVisible(false)
        else
            visibleCount = visibleCount + 1
        end
    end

    k:renderFrame()
    check("stress: число нарисованных rect == числу видимых узлов (culling реально работает)",
        countByType(driver.log, "rect") == visibleCount)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
