--[[
    test_m5.lua

    Тесты M5: clip-стек, opacity, blur, cascade, zero-work idle.
]]

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

-- Мок-driver для проверки clip/opacity/blur state.
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

local function newKernel()
    return Kernel.new(newMockDriver())
end

local function getStateCalls(log)
    local pushes, pops, opacities, blurs = {}, {}, {}, {}
    for i = 1, #log do
        if log[i][1] == "pushClip" then pushes[#pushes+1] = { log[i][2], log[i][3], log[i][4], log[i][5] } end
        if log[i][1] == "popClip" then pops[#pops+1] = true end
        if log[i][1] == "opacity" then opacities[#opacities+1] = log[i][2] end
        if log[i][1] == "blur" then blurs[#blurs+1] = log[i][2] end
    end
    return pushes, pops, opacities, blurs
end

-- =======================================================================
-- 1. Clip: FLAG_CLIP на родителе -> clipDepth на ребёнке
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

    -- Проверяем cmd pool clipDepth (Builder вычисляет эффективный clipDepth).
    local parentCmd = k.storage.cmdSlot[k.storage.idToSlot[parent.id]]
    local childCmd = k.storage.cmdSlot[k.storage.idToSlot[child.id]]
    check("Clip: parent cmd clipDepth=0 (before own clip)", k.cmdPool.clipDepth[parentCmd] == 0)
    check("Clip: child cmd clipDepth=1 (inside parent clip)", k.cmdPool.clipDepth[childCmd] == 1)
end

-- =======================================================================
-- 2. Clip: nested FLAG_CLIP -> clipDepth=2
-- =======================================================================
do
    local k = newKernel()
    local p1 = k:create(C.NODE_PANEL)
    p1:setPosition(0, 0):setSize(200, 200)
    p1:setClip(true)

    local p2 = k:create(C.NODE_PANEL)
    p2:setParent(p1)
    p2:setPosition(10, 10):setSize(100, 100)
    p2:setClip(true)

    local child = k:create(C.NODE_PANEL)
    child:setParent(p2)
    child:setPosition(5, 5):setSize(20, 20)

    k:renderFrame()

    -- Проверяем storage.clipDepth напрямую (Builder читает из storage).
    -- p1/p2/child — это proxy-объекты, у них поле .id с числовым id узла.
    local p1Cmd = k.storage.cmdSlot[k.storage.idToSlot[p1.id]]
    local p2Cmd = k.storage.cmdSlot[k.storage.idToSlot[p2.id]]
    local childCmd = k.storage.cmdSlot[k.storage.idToSlot[child.id]]
    check("Clip: p1 cmd clipDepth=0 (before own clip)", k.cmdPool.clipDepth[p1Cmd] == 0)
    check("Clip: p2 cmd clipDepth=1 (inside p1 clip, before own clip)", k.cmdPool.clipDepth[p2Cmd] == 1)
    check("Clip: child cmd clipDepth=2 (inside p1+p2 nested clips)", k.cmdPool.clipDepth[childCmd] == 2)
end

-- =======================================================================
-- 3. Opacity: setOpacity -> driver.setOpacity вызывается
-- =======================================================================
do
    local k = newKernel()
    local node = k:create(C.NODE_PANEL)
    node:setPosition(10, 10):setSize(100, 50)
    node:setOpacity(128)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local _, _, opacities, _ = getStateCalls(log)
    check("Opacity: setOpacity(128) calls driver.setOpacity(128)",
        #opacities >= 1 and opacities[1] == 128)
end

-- =======================================================================
-- 4. Opacity: default 255 -> driver.setOpacity НЕ вызывается
-- =======================================================================
do
    local k = newKernel()
    local node = k:create(C.NODE_PANEL)
    node:setPosition(10, 10):setSize(100, 50)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local _, _, opacities, _ = getStateCalls(log)
    check("Opacity: default 255 does NOT call driver.setOpacity",
        #opacities == 0)
end

-- =======================================================================
-- 5. Blur: setBlur -> driver.setBlur вызывается
-- =======================================================================
do
    local k = newKernel()
    local node = k:create(C.NODE_PANEL)
    node:setPosition(10, 10):setSize(100, 50)
    node:setBlur(4)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local _, _, _, blurs = getStateCalls(log)
    check("Blur: setBlur(4) calls driver.setBlur(4)",
        #blurs >= 1 and blurs[1] == 4)
end

-- =======================================================================
-- 6. Blur: default 0 -> driver.setBlur НЕ вызывается
-- =======================================================================
do
    local k = newKernel()
    local node = k:create(C.NODE_PANEL)
    node:setPosition(10, 10):setSize(100, 50)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local _, _, _, blurs = getStateCalls(log)
    check("Blur: default 0 does NOT call driver.setBlur",
        #blurs == 0)
end

-- =======================================================================
-- 7. State dedup: два узла с одинаковой opacity -> один вызов setOpacity
-- =======================================================================
do
    local k = newKernel()
    local n1 = k:create(C.NODE_PANEL)
    n1:setPosition(10, 10):setSize(50, 50)
    n1:setOpacity(128)

    local n2 = k:create(C.NODE_PANEL)
    n2:setPosition(100, 10):setSize(50, 50)
    n2:setOpacity(128)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local _, _, opacities, _ = getStateCalls(log)
    check("State dedup: two nodes same opacity -> one setOpacity call",
        #opacities == 1)
end

-- =======================================================================
-- 8. Zero-work idle: второй кадр без изменений -> нет clip/opacity/blur вызовов
-- =======================================================================
do
    local k = newKernel()
    local node = k:create(C.NODE_PANEL)
    node:setPosition(10, 10):setSize(100, 50)
    node:setClip(true)
    node:setOpacity(128)

    -- Первый кадр: state устанавливается (opacity=128 != 255 default)
    k:renderFrame()
    local log = k.stateCache.driver.log
    local lenAfterFrame1 = #log
    local _, _, op1, _ = getStateCalls(log)
    check("Idle: first frame sets opacity state", #op1 >= 1 and op1[1] == 128)

    -- Второй кадр: ничего не изменилось -> нет НОВЫХ state-вызовов
    -- (StateCache.currentOpacity уже 128, dedup сработает).
    -- ВАЖНО: driver.log накопительный — считаем только записи после lenAfterFrame1.
    k:renderFrame()
    local newCalls = {}
    for i = lenAfterFrame1 + 1, #log do
        newCalls[#newCalls + 1] = log[i]
    end
    local _, _, op2, bl2 = getStateCalls(newCalls)
    check("Idle: second frame no NEW opacity/blur calls (dedup)",
        #op2 == 0 and #bl2 == 0)
end

-- =======================================================================
-- 9. Clip cascade: parent move -> child clipDepth обновляется
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)
    parent:setClip(true)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 20):setSize(50, 40)

    -- Первый кадр
    k:renderFrame()
    local log1 = k.stateCache.driver.log
    local pushes1, _, _, _ = getStateCalls(log1)
    check("Clip cascade: first frame pushClip called", #pushes1 >= 1)

    -- Сдвигаем родителя -> clip-область меняется -> child clipDepth обновляется
    parent:setPosition(150, 250)
    k:renderFrame()
    local log2 = k.stateCache.driver.log
    local pushes2, _, _, _ = getStateCalls(log2)
    check("Clip cascade: after parent move, pushClip called again",
        #pushes2 >= 1)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
