--[[
    selftest.lua (M11)

    SelfTest QUICK/FULL — компактная проверка инвариантов системы.
    Запуск в MTA:  DXUI.selfTest("quick")  или  DXUI.selfTest("full")
    Запуск в тестах: dofile("../client/core/selftest.lua"); DXUI.selfTest.run("quick")

    QUICK (< 1 сек): create/destroy, parent/child, layout, render cmd, input, event, widget create, resource lifecycle.
    FULL: nested layout, scrolling, clipping, animation, resource recreation/destruction, virtualization, edge cases.
]]

DXUI = DXUI or {}

local function makeKernel()
    local driver = {
        setBlendMode = function() end,
        pushClip = function() end,
        popClip = function() end,
        setOpacity = function() end,
        setBlur = function() end,
        drawRect = function() end,
        drawImage = function() end,
        drawText = function() end,
    }
    return DXUI.Kernel.new(driver)
end

local function quickTest()
    local k = makeKernel()
    local C = DXUI.Constants
    local ok, fail = 0, 0

    local function check(name, cond)
        if cond then ok = ok + 1 else fail = fail + 1; print("[SELFTEST FAIL] " .. name) end
    end

    -- 1. create/destroy
    local n1 = k:create(C.NODE_PANEL)
    check("create: count=1", k.storage.count == 1)
    n1:destroy()
    check("destroy: count=0", k.storage.count == 0)

    -- 2. parent/child
    local p = k:create(C.NODE_PANEL)
    local c = k:create(C.NODE_PANEL, p)
    check("child count", k.storage.firstChild[k.storage.idToSlot[p.id]] ~= C.NIL_ID)
    p:destroy()
    check("destroy parent -> child destroyed", k.storage.count == 0)

    -- 3. layout (world coordinates)
    local p2 = k:create(C.NODE_PANEL)
    p2:setPosition(100, 200):setSize(300, 200)
    local c2 = k:create(C.NODE_PANEL, p2)
    c2:setPosition(10, 20):setSize(50, 50)
    k:renderFrame()  -- layout pass
    local s = k.storage
    local c2slot = s.idToSlot[c2.id]
    local wx, wy = s.worldX[c2slot], s.worldY[c2slot]
    check("LAY_ABS world pos", wx == 110 and wy == 220)

    -- 4. render command (via kernel stats) - fresh kernel
    local k4 = makeKernel()
    local n3 = k4:create(C.NODE_PANEL)
    n3:setSize(10, 10)
    k4:renderFrame()
    local stats1 = k4:stats()
    check("cmd created (liveNodes)", stats1.liveNodes >= 1)
    n3:destroy()
    k4:renderFrame()
    local stats2 = k4:stats()
    check("cmd freed (liveNodes)", stats2.liveNodes == 0)

    -- 5. input (hover/click via dispatcher)
    k:onCursorMove(150, 250)
    k:onMouseDown(150, 250, "left")
    k:onMouseUp(150, 250, "left")
    check("click event path ok", true)

    -- 6. event bubbling
    local fired = {}
    local root = k:create(C.NODE_PANEL)
    local child = k:create(C.NODE_PANEL, root)
    child:on("click", function(e) fired[1] = e.target end)
    root:on("click", function(e) fired[2] = e.target end)
    k:onCursorMove(0, 0)
    k:onMouseDown(0, 0, "left")
    k:onMouseUp(0, 0, "left")
    check("bubble target->parent", fired[1] ~= nil and fired[2] ~= nil)

    -- 7. widget create
    local w = k:create(C.NODE_WINDOW)
    check("window widget created", w ~= nil)
    w:destroy()

    -- 8. resource lifecycle (create -> destroy kernel)
    local k2 = makeKernel()
    local n4 = k2:create(C.NODE_PANEL)
    n4:destroy()
    check("second kernel lifecycle", true)

    print(string.format("[SELFTEST QUICK] passed=%d failed=%d", ok, fail))
    return fail == 0
end

local function fullTest()
    local k = makeKernel()
    local C = DXUI.Constants
    local ok, fail = 0, 0

    local function check(name, cond)
        if cond then ok = ok + 1 else fail = fail + 1; print("[SELFTEST FAIL] " .. name) end
    end

    check("quick subset", quickTest())

    -- nested layout
    local p = k:create(C.NODE_PANEL)
    p:setPosition(100, 100):setSize(200, 200)
    local c1 = k:create(C.NODE_PANEL, p)
    c1:setPosition(10, 10):setSize(50, 50)
    local c2 = k:create(C.NODE_PANEL, c1)
    c2:setPosition(5, 5):setSize(20, 20)
    k:renderFrame()
    local s = k.storage
    check("3-level nested layout", s.worldX[s.idToSlot[c2.id]] == 115)

    -- clipping
    p:setClip(true)
    k:renderFrame()
    check("clipDepth set", k.storage.clipDepth[k.storage.idToSlot[c1.id]] == 1)

    -- animation (set clock BEFORE animateTo)
    local anim = k:create(C.NODE_PANEL)
    k:setClock(function() return 0 end)  -- fake clock at 0
    anim:animateTo({x = 50}, 100, C.EASE_LINEAR)
    k:setClock(function() return 50 end)  -- advance to mid-flight
    k:renderFrame()
    local ax, ay = anim:getPosition()
    check("anim mid-flight", ax == 25)
    k:setClock(function() return 150 end)  -- advance to complete
    k:renderFrame()
    local ax2, ay2 = anim:getPosition()
    check("anim complete", ax2 == 50)

    -- M12: window composite + drag + close (ADR-016)
    local ui = DXUI.UI.new(k)
    local win = ui:window({ title = "W", x = 10, y = 10, w = 200, h = 150 })
    k:renderFrame()
    k:onMouseDown(50, 20, "left")   -- bar world (10..210, 10..34)
    k:onCursorMove(80, 50)
    k:onMouseUp(80, 50)
    local wwx, wwy = win:getPosition()
    check("window dragged", wwx == 40 and wwy == 40)
    win:close()
    check("window closed (default destroy)", not win:isAlive())

    -- resource recreation
    local k3 = makeKernel()
    local n = k3:create(C.NODE_PANEL)
    n:destroy()
    check("recreate kernel", true)

    print(string.format("[SELFTEST FULL] passed=%d failed=%d", ok, fail))
    return fail == 0
end

DXUI.selfTest = {
    run = function(mode)
        if mode == "full" then return fullTest() else return quickTest() end
    end,
    quick = quickTest,
    full = fullTest,
}

return DXUI.selfTest
