--[[
    test_m6.lua

    Тесты M6 (ADR-010): анимация = данные + единый тик, без per-node таймеров.
    Фейковый clock с ручным advance: k:setClock(function() return now end).
]]

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

local function newMockDriver()
    local log = {}
    local driver = { log = log }
    driver.setBlendMode = function(mode) log[#log+1] = {"blend", mode} end
    driver.drawRect = function(x, y, w, h, color) log[#log+1] = {"rect", x, y, w, h, color} end
    driver.drawImage = function(x, y, w, h, tex, color) log[#log+1] = {"image", x, y, w, h, tex, color} end
    driver.drawText = function(text, x, y, w, h, color) log[#log+1] = {"text", text, x, y, w, h, color} end
    driver.pushClip = function(x, y, w, h) log[#log+1] = {"pushClip", x, y, w, h} end
    driver.popClip = function() log[#log+1] = {"popClip"} end
    driver.setOpacity = function(opacity) log[#log+1] = {"opacity", opacity} end
    driver.setBlur = function(blur) log[#log+1] = {"blur", blur} end
    return driver
end

-- Общий фейковый clock: now — время в мс, advance() двигает вперёд.
local now = 0
local function newKernel()
    local k = Kernel.new(newMockDriver())
    k:setClock(function() return now end)
    return k
end
local function resetClock() now = 0 end
local function advance(ms) now = now + ms end

-- =======================================================================
-- 1. Linear: середина интервала
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_LINEAR)

    advance(50)
    k:renderFrame()
    local slot = k.storage.idToSlot[n.id]
    check("Anim linear: x=50 at t=50ms/100ms", k.storage.x[slot] == 50)
    check("Anim linear: isAnimating=true mid-flight", n:isAnimating() == true)
end

-- =======================================================================
-- 2. Комплит: точный snap на to, слот освобождён
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_LINEAR)

    advance(100)
    k:renderFrame()
    local slot = k.storage.idToSlot[n.id]
    check("Anim complete: x==to exactly", k.storage.x[slot] == 100)
    check("Anim complete: isAnimating=false", n:isAnimating() == false)
    check("Anim complete: pool empty", k.animPool.activeCount == 0)

    -- Дальнейшие кадры не двигают узел.
    advance(500)
    k:renderFrame()
    check("Anim complete: no drift on later frames", k.storage.x[slot] == 100)
end

-- =======================================================================
-- 3. Easing: IN_OUT (smoothstep) на t=0.25 -> 0.15625
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_IN_OUT)

    advance(25)
    k:renderFrame()
    local slot = k.storage.idToSlot[n.id]
    check("Easing IN_OUT: x=15.625 at t=0.25", math.abs(k.storage.x[slot] - 15.625) < 1e-9)
end

-- =======================================================================
-- 4. Easing: OUT (cubic out) на t=0.5 -> 0.875
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_OUT)

    advance(50)
    k:renderFrame()
    local slot = k.storage.idToSlot[n.id]
    check("Easing OUT: x=87.5 at t=0.5", math.abs(k.storage.x[slot] - 87.5) < 1e-9)
end

-- =======================================================================
-- 5. Easing: IN (cubic in) на t=0.5 -> 0.125
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_IN)

    advance(50)
    k:renderFrame()
    local slot = k.storage.idToSlot[n.id]
    check("Easing IN: x=12.5 at t=0.5", math.abs(k.storage.x[slot] - 12.5) < 1e-9)
end

-- =======================================================================
-- 6. Несколько свойств одновременно (x, y, w, h)
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100, y = 100, w = 200, h = 200 }, 100, C.EASE_LINEAR)

    advance(50)
    k:renderFrame()
    local s = k.storage
    local slot = s.idToSlot[n.id]
    check("Multi-prop: x=50", s.x[slot] == 50)
    check("Multi-prop: y=50", s.y[slot] == 50)
    check("Multi-prop: w=150", s.w[slot] == 150)
    check("Multi-prop: h=150", s.h[slot] == 150)
    check("Multi-prop: 4 pool slots active", k.animPool.activeCount == 4)
end

-- =======================================================================
-- 7. Прерывание: новая анимация стартует от ТЕКУЩЕГО значения
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_LINEAR)

    advance(50)
    k:renderFrame() -- x = 50
    n:animateTo({ x = 200 }, 100, C.EASE_LINEAR) -- from=50, to=200

    advance(50)
    k:renderFrame()
    local slot = k.storage.idToSlot[n.id]
    check("Interrupt: starts from current (50 + 0.5*150 = 125)", math.abs(k.storage.x[slot] - 125) < 1e-9)
    check("Interrupt: single slot for property", k.animPool.activeCount == 1)
end

-- =======================================================================
-- 8. stopAnimations: фиксация на текущем значении
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_LINEAR)

    advance(50)
    k:renderFrame() -- x = 50
    n:stopAnimations()
    local slot = k.storage.idToSlot[n.id]
    check("Stop: value frozen at 50", k.storage.x[slot] == 50)
    check("Stop: isAnimating=false", n:isAnimating() == false)
    check("Stop: pool empty", k.animPool.activeCount == 0)

    advance(500)
    k:renderFrame()
    check("Stop: no movement after stop", k.storage.x[slot] == 50)
end

-- =======================================================================
-- 9. duration=0 — мгновенный snap
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 77 }, 0)
    local slot = k.storage.idToSlot[n.id]
    check("Snap: x=77 immediately", k.storage.x[slot] == 77)
    check("Snap: no active pool slot", k.animPool.activeCount == 0)
end

-- =======================================================================
-- 10. Destroy узла в полёте: слоты анимаций чистятся, без краша
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(0, 0):setSize(50, 50)
    child:animateTo({ x = 100 }, 100, C.EASE_LINEAR)

    advance(25)
    k:renderFrame()
    check("Destroy: animation active before destroy", k.animPool.activeCount == 1)

    k:destroy(child)
    check("Destroy: pool empty after destroy", k.animPool.activeCount == 0)

    advance(100)
    k:renderFrame() -- не должно упасть и не должно двигать ничего
    check("Destroy: later frame safe", k.animPool.activeCount == 0)
end

-- =======================================================================
-- 11. Zero-work idle: без активных анимаций тик не помечает dirty
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    k:renderFrame() -- кадр "встаёт": все dirty очищены endFrame'ом

    k.animPool:update() -- прямой вызов: activeCount=0 -> немедленный return
    check("Idle: update() no-op, no dirty", k.storage.dirtyCount == 0)
    check("Idle: zero active", k.animPool.activeCount == 0)
end

-- =======================================================================
-- 12. Реиспользование pool-слотов (freelist)
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_LINEAR)
    advance(100)
    k:renderFrame() -- комплит, слот в freelist
    check("Reuse: one fresh slot allocated so far", k.animPool.nextFreshSlot == 2)

    n:animateTo({ y = 100 }, 100, C.EASE_LINEAR)
    check("Reuse: freelist slot reused (no new fresh)", k.animPool.nextFreshSlot == 2)
    check("Reuse: active again", k.animPool.activeCount == 1)
end

-- =======================================================================
-- 13. Финальный кадр: рендер на конечной позиции (world)
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(100, 100)
    n:animateTo({ x = 100 }, 100, C.EASE_LINEAR)
    advance(100)
    local res = k:renderFrame()

    -- LAY_ABS (default) => worldX = x; ищем rect на x=100 в логe драйвера.
    local found = false
    for i = 1, #k.driver.log do
        local e = k.driver.log[i]
        if e[1] == "rect" and e[2] == 100 and e[3] == 0 and e[4] == 100 and e[5] == 100 then
            found = true
        end
    end
    check("Render: final frame draws at animated world pos", found)
end

-- =======================================================================
-- 14. Независимость узлов: два узла анимируются параллельно
-- =======================================================================
do
    resetClock()
    local k = newKernel()
    local a = k:create(C.NODE_PANEL)
    a:setPosition(0, 0):setSize(10, 10)
    local b = k:create(C.NODE_PANEL)
    b:setPosition(0, 0):setSize(10, 10)
    a:animateTo({ x = 100 }, 100, C.EASE_LINEAR)
    b:animateTo({ x = 400 }, 100, C.EASE_LINEAR)

    advance(50)
    k:renderFrame()
    local sa = k.storage.idToSlot[a.id]
    local sb = k.storage.idToSlot[b.id]
    check("Parallel: a x=50", k.storage.x[sa] == 50)
    check("Parallel: b x=200", k.storage.x[sb] == 200)
end

print(string.format("test_m6: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
