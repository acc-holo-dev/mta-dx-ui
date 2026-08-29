dofile("../client/core/constants.lua")
dofile("../client/core/storage.lua")
dofile("../client/core/proxy.lua")
dofile("../client/render/commands.lua")
dofile("../client/render/culling.lua")
dofile("../client/render/layout.lua")
dofile("../client/render/clip.lua")
dofile("../client/render/builder.lua")
dofile("../client/render/batcher.lua")
dofile("../client/render/state_cache.lua")
dofile("../client/anim/animation.lua")
dofile("../client/render/rt_manager.lua")
    dofile("../client/render/profiler.lua")
dofile("../client/input/events.lua")
dofile("../client/input/hittest.lua")
dofile("../client/input/dispatcher.lua")
dofile("../client/core/kernel.lua")

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

local function newKernel()
    return Kernel.new({ -- мок render driver, в input-тестах не задействован по существу
        setBlendMode = function() end,
        drawRect = function() end,
        drawImage = function() end,
        drawText = function() end,
    })
end

-- =======================================================================
-- 1. Базовый hit-test: точка внутри/снаружи прямоугольника
-- =======================================================================
do
    local k = newKernel()
    local btn = k:create(C.NODE_BUTTON)
    btn:setPosition(10, 10):setSize(100, 40)

    -- M4: layout pass вычисляет world-координаты, которые использует HitTest.
    -- Без renderFrame() worldX/worldY не вычислены (остаются 0), и hit-test
    -- будет работать с устаревшими координатами.
    k:renderFrame()

    local hitInside = DXUI.HitTest.pick(k.storage, 50, 20)
    local hitOutside = DXUI.HitTest.pick(k.storage, 5, 5)

    check("hittest: точка внутри AABB находит узел", hitInside == btn.id)
    check("hittest: точка снаружи AABB не находит узел", hitOutside == C.NIL_ID)
end

-- =======================================================================
-- 2. Приоритет верхнего элемента: два перекрывающихся узла, побеждает
--    более высокий layer, при равном layer — больший zIndex
-- =======================================================================
do
    local k = newKernel()
    local back = k:create(C.NODE_PANEL)
    back:setPosition(0, 0):setSize(100, 100):setLayer(C.LAYER_BASE)

    local front = k:create(C.NODE_PANEL)
    front:setPosition(0, 0):setSize(100, 100):setLayer(C.LAYER_MODAL)

    local hit = DXUI.HitTest.pick(k.storage, 50, 50)
    check("hittest: полностью перекрывающиеся узлы -> побеждает более высокий layer",
        hit == front.id)
end

-- =======================================================================
-- 3. Отключённый узел (setEnabled(false)) не участвует в hit-test'е
-- =======================================================================
do
    local k = newKernel()
    local btn = k:create(C.NODE_BUTTON)
    btn:setPosition(0, 0):setSize(50, 50)
    btn:setEnabled(false)

    local hit = DXUI.HitTest.pick(k.storage, 10, 10)
    check("hittest: setEnabled(false) исключает узел из hit-test", hit == C.NIL_ID)

    btn:setEnabled(true)
    local hit2 = DXUI.HitTest.pick(k.storage, 10, 10)
    check("hittest: повторный setEnabled(true) возвращает узел в hit-test", hit2 == btn.id)
end

-- =======================================================================
-- 4. Hover: mouseenter/mouseleave срабатывают ровно по одному разу на смену
-- =======================================================================
do
    local k = newKernel()
    local btn = k:create(C.NODE_BUTTON)
    btn:setPosition(0, 0):setSize(50, 50)

    local enterCount, leaveCount = 0, 0
    btn:on("mouseenter", function() enterCount = enterCount + 1 end)
    btn:on("mouseleave", function() leaveCount = leaveCount + 1 end)

    k:onCursorMove(10, 10) -- вход в btn
    k:onCursorMove(20, 20) -- всё ещё внутри btn -> НЕ должно повторно триггерить enter
    k:onCursorMove(200, 200) -- выход за пределы btn

    check("hover: mouseenter сработал ровно 1 раз (не на каждый onCursorMove)", enterCount == 1)
    check("hover: mouseleave сработал ровно 1 раз при выходе", leaveCount == 1)
end

-- =======================================================================
-- 5. Click: mousedown+mouseup над одним и тем же узлом -> click.
--    Увод курсора с узла перед mouseup -> click НЕ засчитывается.
-- =======================================================================
do
    local k = newKernel()
    local btn = k:create(C.NODE_BUTTON)
    btn:setPosition(0, 0):setSize(50, 50)

    local clicks = 0
    btn:on("click", function() clicks = clicks + 1 end)

    k:onMouseDown(10, 10, "left")
    k:onMouseUp(10, 10, "left")
    check("click: mousedown+mouseup в одной точке над узлом -> 1 click", clicks == 1)

    k:onMouseDown(10, 10, "left")
    k:onMouseUp(500, 500, "left") -- отпустили мимо
    check("click: mouseup вне узла после mousedown на нём -> click НЕ засчитан", clicks == 1)
end

-- =======================================================================
-- 6. Bubble propagation: клик по child должен также сработать на parent,
--    в правильном порядке (target первым, затем предки)
-- =======================================================================
do
    local k = newKernel()
    local window = k:create(C.NODE_WINDOW)
    window:setPosition(0, 0):setSize(200, 200)

    local panel = k:create(C.NODE_PANEL)
    panel:setParent(window)
    panel:setPosition(0, 0):setSize(200, 200)

    local btn = k:create(C.NODE_BUTTON)
    btn:setParent(panel)
    btn:setPosition(0, 0):setSize(50, 50)

    local callOrder = {}
    btn:on("click", function() callOrder[#callOrder+1] = "button" end)
    panel:on("click", function() callOrder[#callOrder+1] = "panel" end)
    window:on("click", function() callOrder[#callOrder+1] = "window" end)

    k:onMouseDown(10, 10, "left")
    k:onMouseUp(10, 10, "left")

    check("bubble: событие дошло до всех 3 уровней", #callOrder == 3)
    check("bubble: порядок target -> parent -> grandparent",
        callOrder[1] == "button" and callOrder[2] == "panel" and callOrder[3] == "window")
end

-- =======================================================================
-- 7. stopPropagation() останавливает всплытие на нужном уровне
-- =======================================================================
do
    local k = newKernel()
    local window = k:create(C.NODE_WINDOW)
    window:setPosition(0, 0):setSize(200, 200)

    local btn = k:create(C.NODE_BUTTON)
    btn:setParent(window)
    btn:setPosition(0, 0):setSize(50, 50)

    local windowClicked = false
    btn:on("click", function(e) e.stopPropagation() end)
    window:on("click", function() windowClicked = true end)

    k:onMouseDown(10, 10, "left")
    k:onMouseUp(10, 10, "left")

    check("stopPropagation: событие не доходит до родителя после остановки",
        windowClicked == false)
end

-- =======================================================================
-- 8. Уничтоженный узел не оставляет мёртвых слушателей (нет утечки/ошибки)
-- =======================================================================
do
    local k = newKernel()
    local btn = k:create(C.NODE_BUTTON)
    btn:setPosition(0, 0):setSize(50, 50)

    local calls = 0
    btn:on("click", function() calls = calls + 1 end)
    k:destroy(btn)

    check("cleanup: слушатели уничтоженного узла не в EventBus",
        k.eventBus.listeners[btn.id] == nil or next(k.eventBus.listeners) == nil)

    -- клик по тому же месту не должен ни на что упасть (узла больше нет в interactiveIds)
    local ok = pcall(function()
        k:onMouseDown(10, 10, "left")
        k:onMouseUp(10, 10, "left")
    end)
    check("cleanup: клик по опустевшей области не падает", ok)
    check("cleanup: обработчик уничтоженного узла не вызывается", calls == 0)
end

-- =======================================================================
-- 9. destroy родителя во время всплытия (обработчик child уничтожает
--    родителя) не должен уронить EventBus:emit
-- =======================================================================
do
    local k = newKernel()
    local window = k:create(C.NODE_WINDOW)
    window:setPosition(0, 0):setSize(200, 200)
    local btn = k:create(C.NODE_BUTTON)
    btn:setParent(window)
    btn:setPosition(0, 0):setSize(50, 50)

    btn:on("click", function() k:destroy(window) end)

    local ok = pcall(function()
        k:onMouseDown(10, 10, "left")
        k:onMouseUp(10, 10, "left")
    end)
    check("robustness: уничтожение родителя обработчиком child не роняет emit", ok)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
