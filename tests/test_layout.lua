--[[
    test_layout.lua (M4)

    Тесты layout-системы: LAY_ABS (backward-compat), LAY_REL, LAY_CENTER,
    anchors, margins, padding, каскадный layout, dirty propagation.
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

-- Мок-driver для проверки координат после layout.
local function newMockDriver()
    local log = {}
    local driver = { log = log }
    driver.setBlendMode = function(mode) log[#log+1] = {"blend", mode} end
    driver.drawRect = function(x, y, w, h, color) log[#log+1] = {"rect", x, y, w, h, color} end
    driver.drawImage = function(x, y, w, h, tex, color) log[#log+1] = {"image", x, y, w, h, tex, color} end
    driver.drawText = function(text, x, y, w, h, color) log[#log+1] = {"text", text, x, y, w, h, color} end
    return driver
end

local function newKernel()
    return Kernel.new(newMockDriver())
end

local function getRect(log)
    -- Возвращает ПОСЛЕДНИЙ rect в log (child рисуется после parent).
    -- Для тестов, где есть только один rect, это тот же rect.
    for i = #log, 1, -1 do
        if log[i][1] == "rect" then
            return log[i][2], log[i][3], log[i][4], log[i][5]
        end
    end
    return nil, nil, nil, nil
end

-- =======================================================================
-- 1. LAY_ABS: backward-compat M1–M3 (world = parentWorld + local)
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 20):setSize(50, 40)
    child:setLayoutMode(C.LAY_ABS)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y, w, h = getRect(log)
    check("LAY_ABS: child world = parent(100,200) + local(10,20) = (110,220)",
        x == 110 and y == 220 and w == 50 and h == 40)
end

-- =======================================================================
-- 2. LAY_REL: relative coordinates (доли 0..1 от родителя)
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(0.5, 0.5):setSize(50, 40)
    child:setLayoutMode(C.LAY_REL)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y, w, h = getRect(log)
    -- world = (100 + 0.5*300, 200 + 0.5*200) = (250, 300)
    check("LAY_REL: child world = parent(100,200) + (0.5*300, 0.5*200) = (250,300)",
        x == 250 and y == 300 and w == 50 and h == 40)
end

-- =======================================================================
-- 3. LAY_CENTER: centered in parent
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(0, 0):setSize(100, 50)
    child:setLayoutMode(C.LAY_CENTER)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y, w, h = getRect(log)
    -- world = (100 + (300-100)/2, 200 + (200-50)/2) = (200, 275)
    check("LAY_CENTER: child centered in parent = (200,275)",
        x == 200 and y == 275 and w == 100 and h == 50)
end

-- =======================================================================
-- 4. ANCHOR_TC: top-center (x - w/2)
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(50, 50):setSize(100, 50)
    child:setLayoutMode(C.LAY_ABS)
    child:setAnchor(C.ANCHOR_TC)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y, w, h = getRect(log)
    -- world = (100 + 50 - 100/2, 200 + 50) = (150, 250)
    -- ANCHOR_TC: top-center — точка привязки (w/2, 0) должна совпасть с (50, 50) локально,
    -- т.е. worldX = parentX + localX - w/2 = 100 + 50 - 50 = 100
    check("ANCHOR_TC: x shifted by -w/2 = (100,250)",
        x == 100 and y == 250 and w == 100 and h == 50)
end

-- =======================================================================
-- 5. ANCHOR_BR: bottom-right (x - w, y - h)
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(50, 50):setSize(100, 50)
    child:setLayoutMode(C.LAY_ABS)
    child:setAnchor(C.ANCHOR_BR)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y, w, h = getRect(log)
    -- world = (100 + 50 - 100, 200 + 50 - 50) = (50, 200)
    check("ANCHOR_BR: x-w, y-h = (50,200)",
        x == 50 and y == 200 and w == 100 and h == 50)
end

-- =======================================================================
-- 6. MARGIN: mL/mT shift position
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 20):setSize(50, 40)
    child:setLayoutMode(C.LAY_ABS)
    child:setMargin(5, 10, 0, 0)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y, w, h = getRect(log)
    -- world = (100 + 10 + 5, 200 + 20 + 10) = (115, 230)
    check("MARGIN: mL/mT shift = (115,230)",
        x == 115 and y == 230 and w == 50 and h == 40)
end

-- =======================================================================
-- 7. PADDING: parent padding shifts children
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)
    parent:setPadding(10, 20, 0, 0)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 20):setSize(50, 40)
    child:setLayoutMode(C.LAY_ABS)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y, w, h = getRect(log)
    -- world = (100 + 10 + 10, 200 + 20 + 20) = (120, 240)
    check("PADDING: parent padding shifts child = (120,240)",
        x == 120 and y == 240 and w == 50 and h == 40)
end

-- =======================================================================
-- 8. Cascade: parent move → children re-layout
-- =======================================================================
do
    local k = newKernel()
    local parent = k:create(C.NODE_PANEL)
    parent:setPosition(100, 200):setSize(300, 200)

    local child = k:create(C.NODE_PANEL)
    child:setParent(parent)
    child:setPosition(10, 20):setSize(50, 40)
    child:setLayoutMode(C.LAY_ABS)

    -- Первый кадр: child в (110, 220)
    k:renderFrame()
    local log1 = k.stateCache.driver.log
    local x1, y1 = getRect(log1)
    check("Cascade: initial child at (110,220)", x1 == 110 and y1 == 220)

    -- Сдвигаем родителя
    parent:setPosition(150, 250)

    k:renderFrame()
    local log2 = k.stateCache.driver.log
    local x2, y2 = getRect(log2)
    check("Cascade: after parent move, child at (160,270)", x2 == 160 and y2 == 270)
end

-- =======================================================================
-- 9. Dirty propagation: only dirty nodes re-layout
-- =======================================================================
do
    local k = newKernel()
    local p1 = k:create(C.NODE_PANEL)
    p1:setPosition(0, 0):setSize(100, 100)
    local c1 = k:create(C.NODE_PANEL)
    c1:setParent(p1):setPosition(10, 10):setSize(20, 20)

    local p2 = k:create(C.NODE_PANEL)
    p2:setPosition(500, 500):setSize(100, 100)
    local c2 = k:create(C.NODE_PANEL)
    c2:setParent(p2):setPosition(10, 10):setSize(20, 20)

    -- Первый кадр: оба subtree layout
    k:renderFrame()

    -- Сдвигаем только p1
    p1:setPosition(10, 10)
    k:renderFrame()

    -- c2 не должен был пересчитываться (его parent p2 не dirty)
    -- Проверка: c2 всё ещё в (510, 510)
    -- Используем getRect, который возвращает ПОСЛЕДНИЙ rect (c2 рисуется последним).
    local log = k.stateCache.driver.log
    local x, y = getRect(log)
    check("Dirty: c2 unchanged at (510,510)", x == 510 and y == 510)
end

-- =======================================================================
-- 10. Screen size: root nodes in LAY_REL use screen as parent
-- =======================================================================
do
    local k = newKernel()
    k:setScreenSize(1920, 1080)

    local root = k:create(C.NODE_PANEL)
    root:setPosition(0.5, 0.5):setSize(200, 100)
    root:setLayoutMode(C.LAY_REL)

    k:renderFrame()

    local log = k.stateCache.driver.log
    local x, y = getRect(log)
    -- world = (0 + 0.5*1920, 0 + 0.5*1080) = (960, 540)
    check("ScreenSize: root LAY_REL centered on screen = (960,540)",
        x == 960 and y == 540)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
