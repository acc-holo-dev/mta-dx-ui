--[[
    test_m8.lua

    Тесты M8: clip-регионы в cmd-пуле, push/pop-семантика, реальная
    opacity (модуляция альфы в драйвере), blur-state, zero-work idle.
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
dofile("../client/render/rt_manager.lua")
    dofile("../client/render/profiler.lua")
dofile("../client/anim/animation.lua")
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

-- M8: мок-driver применяет opacity к цвету (как реальный backend через
-- bitReplace) — позволяет проверить РЕЗУЛЬТАТ, а не только факт вызова.
local function applyOpacity(color, opacity)
    if opacity >= 255 then return color end
    if opacity <= 0 then return color % 0x1000000 end
    local a = math.floor(color / 0x1000000)
    local newA = math.floor(a * opacity / 255 + 0.5)
    return newA * 0x1000000 + (color % 0x1000000)
end

local function newMockDriver()
    local log = {}
    local driver = { log = log, curOpacity = 255, curBlur = 0 }
    driver.setBlendMode = function(mode) log[#log+1] = {"blend", mode} end
    driver.pushClip = function(x, y, w, h) log[#log+1] = {"pushClip", x, y, w, h} end
    driver.popClip = function() log[#log+1] = {"popClip"} end
    driver.setOpacity = function(opacity) driver.curOpacity = opacity; log[#log+1] = {"opacity", opacity} end
    driver.setBlur = function(blur) driver.curBlur = blur; log[#log+1] = {"blur", blur} end
    driver.drawRect = function(x, y, w, h, color) log[#log+1] = {"rect", x, y, w, h, applyOpacity(color, driver.curOpacity)} end
    driver.drawImage = function(x, y, w, h, tex, color) log[#log+1] = {"image", x, y, w, h, tex, applyOpacity(color, driver.curOpacity)} end
    driver.drawText = function(text, x, y, w, h, color) log[#log+1] = {"text", text, x, y, w, h, applyOpacity(color, driver.curOpacity)} end
    return driver
end

local function newKernel()
    return Kernel.new(newMockDriver())
end

local function lastOfType(log, t)
    local last = nil
    for i = 1, #log do
        if log[i][1] == t then last = log[i] end
    end
    return last
end

-- =======================================================================
-- 1. Clip-регион в cmd-пуле: child получает world-границы родителя
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)
    parent:setClip(true)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 20):setSize(50, 40)

    k:renderFrame()

    local pCmd = k.storage.cmdSlot[k.storage.idToSlot[parent.id]]
    local cCmd = k.storage.cmdSlot[k.storage.idToSlot[child.id]]

    check("clip rect: parent cmd has no region",
        k.cmdPool.clipX[pCmd] == 0 and k.cmdPool.clipW[pCmd] == 0)
    check("clip rect: child cmd = parent world bounds",
        k.cmdPool.clipX[cCmd] == 100 and k.cmdPool.clipY[cCmd] == 200
        and k.cmdPool.clipW[cCmd] == 300 and k.cmdPool.clipH[cCmd] == 200)

    local push = lastOfType(k.driver.log, "pushClip")
    check("clip rect: pushClip got parent world bounds",
        push and push[2] == 100 and push[3] == 200 and push[4] == 300 and push[5] == 200)
    check("clip rect: popClip balanced at frame end",
        lastOfType(k.driver.log, "popClip") ~= nil)
end

-- =======================================================================
-- 2. Nested clips: depth-2 child получает INNERMOST регион (M8: single-level)
-- =======================================================================
do
    local k = newKernel()
    local p1 = k:create(C.NODE_PANEL)
    p1:setPosition(0, 0):setSize(400, 400)
    p1:setClip(true)
    local p2 = k:create(C.NODE_PANEL)
    p2:setParent(p1)
    p2:setPosition(50, 50):setSize(200, 200)
    p2:setClip(true)
    local child = k:create(C.NODE_PANEL)
    child:setParent(p2)
    child:setPosition(10, 10):setSize(20, 20)

    k:renderFrame()

    local cCmd = k.storage.cmdSlot[k.storage.idToSlot[child.id]]
    check("nested: child clipDepth=2", k.cmdPool.clipDepth[cCmd] == 2)
    -- M8 single-level: pushClip получает innermost регион (p2: 50,50,200,200)
    local push = lastOfType(k.driver.log, "pushClip")
    check("nested: pushClip got innermost region",
        push and push[2] == 50 and push[3] == 50 and push[4] == 200 and push[5] == 200)

    -- M10: ПОЛНЫЙ вложенный стек — clipX1 (outermost) и clipX2 (innermost).
    check("nested: clipX1 = p1 bounds (outermost)",
        k.cmdPool.clipX1[cCmd] == 0 and k.cmdPool.clipY1[cCmd] == 0
        and k.cmdPool.clipW1[cCmd] == 400 and k.cmdPool.clipH1[cCmd] == 400)
    check("nested: clipX2 = p2 bounds (innermost)",
        k.cmdPool.clipX2[cCmd] == 50 and k.cmdPool.clipY2[cCmd] == 50
        and k.cmdPool.clipW2[cCmd] == 200 and k.cmdPool.clipH2[cCmd] == 200)

    -- M10: два pushClip в правильном порядке (outer → inner).
    local pushes = {}
    for i = 1, #k.driver.log do
        if k.driver.log[i][1] == "pushClip" then pushes[#pushes + 1] = k.driver.log[i] end
    end
    check("nested: two pushClip (outer then inner)",
        #pushes == 2
        and pushes[1][2] == 0 and pushes[1][3] == 0 and pushes[1][4] == 400 and pushes[1][5] == 400
        and pushes[2][2] == 50 and pushes[2][3] == 50 and pushes[2][4] == 200 and pushes[2][5] == 200)
end

-- =======================================================================
-- 2b. Deep move: ДВИЖЕНИЕ ГЛУБОКОГО узла (клип-контейнер НЕ dirty)
--     -> регион контейнера НЕ теряется (баг M8: region 0/0/0/0)
-- =======================================================================
do
    local k = newKernel()
    local container = k:create(C.NODE_PANEL)
    container:setPosition(100, 200):setSize(300, 200)
    container:setClip(true)
    local mid = k:create(C.NODE_PANEL)
    mid:setParent(container)
    mid:setPosition(0, 0):setSize(100, 100)
    local leaf = k:create(C.NODE_PANEL)
    leaf:setParent(mid)
    leaf:setPosition(10, 10):setSize(20, 20)

    k:renderFrame()
    local lCmd = k.storage.cmdSlot[k.storage.idToSlot[leaf.id]]
    check("deep move: initial region = container bounds",
        k.cmdPool.clipX[lCmd] == 100 and k.cmdPool.clipY[lCmd] == 200
        and k.cmdPool.clipW[lCmd] == 300 and k.cmdPool.clipH[lCmd] == 200)

    leaf:setPosition(30, 40) -- dirty только leaf; контейнер не тронут
    k:renderFrame()
    check("deep move: region survives child-only move",
        k.cmdPool.clipX[lCmd] == 100 and k.cmdPool.clipY[lCmd] == 200
        and k.cmdPool.clipW[lCmd] == 300 and k.cmdPool.clipH[lCmd] == 200)
end

-- =======================================================================
-- 3. Cascade: parent move -> clip-регион в cmd-пуле обновляется
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(0, 0):setSize(300, 200)
    parent:setClip(true)
    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 10):setSize(20, 20)

    k:renderFrame()
    local cCmd = k.storage.cmdSlot[k.storage.idToSlot[child.id]]
    check("cascade: initial region x=0", k.cmdPool.clipX[cCmd] == 0)

    parent:setPosition(150, 250)
    k:renderFrame()
    check("cascade: region follows parent",
        k.cmdPool.clipX[cCmd] == 150 and k.cmdPool.clipY[cCmd] == 250)
end

-- =======================================================================
-- 4. Opacity: РЕАЛЬНАЯ модуляция альфы в driver (0xFFFF0000 -> ~0x80FF0000)
-- =======================================================================
do
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(50, 50)
    n:setColor(0xFFFF0000)
    n:setOpacity(128)

    k:renderFrame()

    local rect = lastOfType(k.driver.log, "rect")
    check("opacity: driver received modulated alpha",
        rect and rect[6] == 0x80FF0000)
end

-- =======================================================================
-- 5. Opacity=0: полностью прозрачный
-- =======================================================================
do
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(50, 50)
    n:setColor(0xFFFF0000)
    n:setOpacity(0)

    k:renderFrame()

    local rect = lastOfType(k.driver.log, "rect")
    check("opacity: 0 -> alpha 0", rect and rect[6] == 0x00FF0000)
end

-- =======================================================================
-- 6. Blur: state доходит до драйвера, default 0 — без вызовов
-- =======================================================================
do
    local k = newKernel()
    local n = k:create(C.NODE_PANEL)
    n:setPosition(0, 0):setSize(50, 50)
    n:setBlur(3)
    k:renderFrame()
    local b = lastOfType(k.driver.log, "blur")
    check("blur: setBlur(3) reached driver", b and b[2] == 3)

    local k2 = newKernel()
    k2:create(C.NODE_PANEL):setSize(50, 50)
    k2:renderFrame()
    check("blur: default 0 not sent", lastOfType(k2.driver.log, "blur") == nil)
end

-- =======================================================================
-- 7. Zero-work idle: второй кадр без изменений.
--    RT-клип — per-frame state: пара push/pop невозвратима (RT должен
--    пересоздаваться/очищаться каждый кадр). Дедуп-гарантия M8:
--    нет НОВЫХ setOpacity/setBlur, и push/pop остаётся одной парой.
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(0, 0):setSize(100, 100)
    parent:setClip(true)
    parent:setOpacity(128)
    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 10):setSize(20, 20)

    local res1 = k:renderFrame()
    local lenAfter = #k.driver.log
    local res2 = k:renderFrame()

    -- Zero-work: на idle-кадре нет НИКАКОЙ dirty-пересборки (согласно §49/
    -- ADR-002: "zero-work idle frame"). Дро-вызовы (rect + per-frame RT-пара)
    -- — это ИСПОЛНЕНИЕ draw order, не работа dirty-pipeline.
    check("idle: 2nd frame zero-work (no order rebuild)", res2.rebuiltOrder == false)
    check("idle: command count stable", res2.commandCount == res1.commandCount)

    local newPush, newPop = 0, 0
    for i = lenAfter + 1, #k.driver.log do
        local t = k.driver.log[i][1]
        if t == "pushClip" then newPush = newPush + 1
        elseif t == "popClip" then newPop = newPop + 1
        end
    end
    check("idle: 2nd frame clip = one balanced push/pop pair (per-frame RT)", newPush == 1 and newPop == 1)
end

-- =======================================================================
-- 8. RT Manager (юнит, вне кадра): acquire/release пул + offset
-- =======================================================================
do
    -- RT Manager использует dx* нативы: эмулируем их минимально.
    local created, destroyed = 0, 0
    local rtCounter = 0
    _G.dxCreateRenderTarget = function(w, h)
        created = created + 1
        rtCounter = rtCounter + 1
        return { fake = rtCounter, w = w, h = h }
    end
    _G.dxSetRenderTarget = function(rt) end
    _G.dxDrawImage = function() end
    _G.dxGetMaterialSize = function(rt) return rt.w, rt.h end
    _G.isElement = function(rt) return type(rt) == "table" end
    _G.destroyElement = function(rt) destroyed = destroyed + 1 end

    local rm = DXUI.RTManager.new()
    local rt1 = rm:acquire(64, 32)
    check("rt pool: first acquire creates", created == 1)
    rm:release(rt1)
    local rt2 = rm:acquire(64, 32)
    check("rt pool: second acquire reuses (no new)", created == 1 and rt1 == rt2)

    local other = rm:acquire(100, 50)
    check("rt pool: different size creates new", created == 2 and other ~= rt1)
    rm:release(other)
    -- rt2 == rt1 (reused) ещё не возвращён в пул — возвращаем, чтобы в пуле было 2 RT
    rm:release(rt2)

    rm:resize()
    check("rt pool: resize destroys all pooled (2 RTs)", destroyed == 2)

    _G.dxCreateRenderTarget = nil
    _G.dxSetRenderTarget = nil
    _G.dxDrawImage = nil
    _G.dxGetMaterialSize = nil
    _G.isElement = nil
    _G.destroyElement = nil
end

print(string.format("test_m8: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
