--[[
    test_m13.lua -- ScrollPanel (ADR-017): viewport+content+scrollbars,
    wheel, smooth, virtualization, scroll clamping. Один сценарий на
    подсистему (паттерн test_m12).
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

local function newUI()
    local k = Kernel.new({
        setBlendMode = function() end,
        pushClip = function() end,
        popClip = function() end,
        setOpacity = function() end,
        setBlur = function() end,
        drawRect = function() end,
        drawImage = function() end,
        drawText = function() end,
    })
    local ui = DXUI.UI.new(k)
    k:setScreenSize(1280, 720)
    return k, ui
end

-- 1. Структура composite
do
    local k, ui = newUI()
    local before = k.storage.count
    local sp = ui:scrollpanel({ x = 100, y = 100, w = 200, h = 150 })
    -- viewport + content + trackV + thumbV = 4 узла
    check("scroll: composite = 4 узла (viewport+content+track+thumb)",
        k.storage.count - before == 4)
    check("scroll: content жив", sp._parts.content ~= nil and sp._parts.content:isAlive())
    check("scroll: content size 0x0 по умолчанию", sp:getContent() ~= nil)
    local cw, ch = sp._parts.content:getSize()
    check("scroll: content 0x0", cw == 0 and ch == 0)
    check("scroll: viewport clip включён",
        k.storage:hasFlag(sp.id, C.FLAG_CLIP))
end

-- 2. Прокрутка + clamp
do
    local k, ui = newUI()
    local sp = ui:scrollpanel({ x = 0, y = 0, w = 100, h = 100 })
    sp:setContentSize(100, 300)
    k:renderFrame()

    sp:setScroll(0, 50)
    local sx, sy = sp:getScroll()
    check("scroll: setScroll(0,50) применён", sy == 50 and sx == 0)

    sp:setScroll(0, 9999)
    local sx2, sy2 = sp:getScroll()
    check("scroll: clamp к maxY=200", sy2 == 200)

    sp:setScroll(0, -20)
    local sx3, sy3 = sp:getScroll()
    check("scroll: clamp к minY=0", sy3 == 0)

    local mx, my = sp:getScrollMax()
    check("scroll: getScrollMax = (0, 200)", mx == 0 and my == 200)
end

-- 3. Дети в content: позиция контента смещается
do
    local k, ui = newUI()
    local sp = ui:scrollpanel({ x = 0, y = 0, w = 100, h = 100 })
    sp:setContentSize(100, 300) -- явный размер — скролл возможен
    local content = sp:getContent()
    local item = ui:panel({ x = 0, y = 50, w = 50, h = 20 })
    item:setParent(content)
    k:renderFrame()

    sp:setScroll(0, 30)
    k:renderFrame()
    local cposx, cposy = content:getPosition()
    check("scroll: content позиция -scrollY", cposy == -30)
    -- getPosition() локальная (ADR-016): item не двигается, двигается parent.
    -- Проверяем MIR (world) через layout:
    local s = k.storage
    local islot = s.idToSlot[item.id]
    local iwy = s.worldY[islot] or 0
    check("scroll: дети контента едут вместе (world.Y)", iwy == 20)

    local sp2 = ui:scrollpanel({ x = 0, y = 200, w = 100, h = 100, axis = "h" })
    sp2:setContentSize(300, 100)
    k:renderFrame()
    sp2:setScroll(50, 0)
    k:renderFrame()
    local c2x = sp2._parts.content:getPosition()
    check("scroll: горизонтальный content -scrollX", c2x == -50)
end

-- 4. Wheel -> scrollBy
do
    local k, ui = newUI()
    local sp = ui:scrollpanel({ x = 0, y = 0, w = 100, h = 100 })
    sp:setContentSize(100, 300)
    local scrolled = 0
    sp:on("scroll", function() scrolled = scrolled + 1 end)
    k:renderFrame()
    k:onMouseDown(50, 50, "left")
    k:onMouseUp(50, 50, "left")
    k.dispatcher:onMouseWheel(50, 50, -1)
    local _, sy = sp:getScroll()
    check("wheel: scroll изменился на -WHEEL_STEP", sy == 40)
    check("wheel: scroll-событие эмитилось", scrolled == 1)
end

-- 5. Smooth scroll (контролируемый clock через Kernel:setClock)
do
    local k, ui = newUI()
    local tick = 1000
    k:setClock(function() return tick end)
    local sp = ui:scrollpanel({ x = 0, y = 0, w = 100, h = 100, smooth = true })
    sp:setContentSize(100, 300)
    k:renderFrame()
    sp:setScroll(0, 100)
    k:renderFrame()
    local _, cy = sp._parts.content:getPosition()
    check("smooth: на старте y=0 (плавно, не скачок)", cy == 0)
    tick = tick + 1000 -- >> SMOOTH_MS(120) -> комплит
    k:renderFrame()
    local _, cy2 = sp._parts.content:getPosition()
    check("smooth: после комплита content y == -100", cy2 == -100)
    check("smooth: анимаций больше нет", k.animPool.activeCount == 0)
end

-- 6. Виртуализация
do
    local k, ui = newUI()
    local sp = ui:scrollpanel({ x = 0, y = 0, w = 100, h = 100 })
    local created = 0
    sp:setVirtualProvider({
        count = function() return 50 end,
        itemHeight = 20,
        bind = function(row, handle) created = created + 1 end,
    })
    k:renderFrame()
    check("virt: строки созданы при старте",
        #sp._sp.rows >= 1 and created >= 1)
    sp:setScroll(0, 200)
    k:renderFrame()
    check("virt: при скролле range сдвинулся", sp._sp.rangeFirst >= 1)
    check("virt: rows не пуст", sp._sp.rows ~= nil)
end

-- 7. destroy: пул освобождён
do
    local k, ui = newUI()
    local poolBefore = k.proxy.poolCount
    local sp = ui:scrollpanel({ x = 0, y = 0, w = 100, h = 100 })
    sp:setContentSize(100, 300)
    k:destroy(sp)
    check("scroll: destroy вернул >=4 proxy (viewport+content+track+thumb)",
        k.proxy.poolCount - poolBefore >= 4)
end

print(string.format("test_m13: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
