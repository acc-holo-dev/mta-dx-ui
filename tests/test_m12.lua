--[[
    test_m12.lua -- Window 2.0 (ADR-016): composite-proxy, drag, resize,
    close (preventable), z-order, pool hygiene. Инварианты, не пересказ
    реализации. Один сценарий на подсистему.
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

local function childCount(k, proxy)
    local s = k.storage
    local slot = s.idToSlot[proxy.id]
    local n = 0
    local child = s.firstChild[slot]
    while child ~= C.NIL_ID do
        n = n + 1
        child = s.nextSibling[s.idToSlot[child]]
    end
    return n
end

-- =======================================================================
-- 1. Composite-структура (ADR-016 §1)
-- =======================================================================
do
    local k, ui = newUI()
    local before = k.storage.count
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150 })
    check("composite: win+bar+text = 3 nodes", k.storage.count - before == 3)
    check("composite: bar -- единственный ребёнок win", childCount(k, win) == 1)
    check("composite: text -- единственный ребёнок bar", childCount(k, win._parts.bar) == 1)
    check("composite: _parts.bar alive", win._parts.bar:isAlive())
    check("composite: _parts.title alive", win._parts.title:isAlive())

    local win2 = ui:window({ title = "T2", closable = true, resizable = true })
    check("composite: closable+resizable добавляют close и grip",
        childCount(k, win2) == 2 and childCount(k, win2._parts.bar) == 2)

    -- bare window (M7-совместимость): 1 узел, без bar
    local b = k.storage.count
    local bare = ui:window()
    check("bare: 1 узел без bar", k.storage.count - b == 1 and bare._parts.bar == nil)
end

-- =======================================================================
-- 2. setTitle / getTitle
-- =======================================================================
do
    local k, ui = newUI()
    local win = ui:window({ title = "A" })
    win:setTitle("B")
    check("setTitle: storage text обновлён", win:getTitle() == "B")
end

-- =======================================================================
-- 3. Drag через dispatcher capture (ADR-016 §2)
-- =======================================================================
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150 })
    k:renderFrame() -- world-координаты для hit-test

    -- hover на bar ДО drag (чтобы потом проверить заморозку hover)
    local leaves = 0
    win._parts.bar:on("mouseleave", function() leaves = leaves + 1 end)
    k:onCursorMove(150, 110) -- bar world (100..300, 100..124)
    check("drag: hover установился на bar", k.dispatcher.hoveredId == win._parts.bar.id)

    k:onMouseDown(150, 110, "left") -- grab = (50, 10)
    check("drag: dispatcher захватил курсор", k.dispatcher.dragMove ~= nil)

    k:onCursorMove(200, 160) -- (200-50, 160-10) = (150, 150)
    local wx, wy = win:getPosition()
    check("drag: окно переехало в (150,150)", wx == 150 and wy == 150)

    check("drag: hover заморожен на bar (без leave)", leaves == 0)

    k:onMouseUp(200, 160)
    check("drag: capture снят на mouseup", k.dispatcher.dragMove == nil)

    k:onCursorMove(600, 600) -- уводим курсор -- теперь leave должен сработать
    check("drag: после mouseup hover отвис", leaves == 1 and k.dispatcher.hoveredId == C.NIL_ID)

    -- setDraggable(false) отключает drag
    local win2 = ui:window({ title = "D", x = 100, y = 100, w = 200, h = 150 })
    k:renderFrame()
    win2:setDraggable(false)
    k:onMouseDown(150, 110, "left")
    check("drag: отключён -> нет захвата", k.dispatcher.dragMove == nil)
    k:onMouseUp(150, 110, "left")
end

-- =======================================================================
-- 4. Resize grip + клэмп до minW/minH
-- =======================================================================
do
    local k, ui = newUI()
    local win = ui:window({
        title = "T", x = 10, y = 10, w = 200, h = 150,
        resizable = true, minW = 100, minH = 90,
    })
    k:renderFrame()

    -- grip world = (10+200-14, 10+150-14) = (196..210, 146..160)
    k:onMouseDown(200, 150, "left")
    check("resize: захват на grip", k.dispatcher.dragMove ~= nil)

    k:onCursorMove(310, 260) -- (200+110, 150+110) = (310, 260)
    local ww, wh = win:getSize()
    check("resize: вырос до 310x260", ww == 310 and wh == 260)
    local bw, bh = win._parts.bar:getSize()
    check("resize: bar следует шириной окна", bw == 310 and bh == 24)

    k:onCursorMove(0, 0) -- сжатие: клэмп до minW=100, minH=90
    local ww2, wh2 = win:getSize()
    check("resize: клэмп до (100,90)", ww2 == 100 and wh2 == 90)

    k:onMouseUp(0, 0)
    check("resize: capture снят", k.dispatcher.dragMove == nil)
end

-- =======================================================================
-- 5. Close: кнопка, событие, destroy по умолчанию
-- =======================================================================
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", closable = true }) -- (0,0,320,240)
    k:renderFrame()
    -- close world = (320-16..320, 4..20)
    k:onMouseDown(312, 12, "left")
    check("close: клик по close НЕ начинает drag", k.dispatcher.dragMove == nil)
    k:onMouseUp(312, 12, "left")
    check("close: окно уничтожено", not win:isAlive())
    check("close: proxy-пулы чисты (storage пуст)", k.storage.count == 0)
end

-- =======================================================================
-- 6. Close preventDefault (ADR-016 §4)
-- =======================================================================
do
    local k, ui = newUI()
    local closedEvents = 0
    local win = ui:window({
        title = "T", closable = true,
        onClose = function(e)
            closedEvents = closedEvents + 1
            e.preventDefault()
        end,
    })
    k:renderFrame()
    k:onMouseDown(312, 12, "left")
    k:onMouseUp(312, 12, "left")
    check("preventDefault: close-событие пришло", closedEvents == 1)
    check("preventDefault: окно живо после кнопки", win:isAlive())

    win:close() -- программное закрытие тоже отменяется
    check("preventDefault: программный close тоже отменён",
        closedEvents == 2 and win:isAlive())

    -- снятие preventDefault недоступно снаружи -- окно закрывается через
    -- повторный subscribe-паттерн; здесь достаточно инварианта отмены.
    win:setClosable(false)
    check("setClosable: кнопка скрыта", win._parts.close:isVisible() == false)
end

-- =======================================================================
-- 7. Z-order: bringToFront (ADR-016 §3)
-- =======================================================================
do
    local k, ui = newUI()
    local a = ui:window({ title = "A", x = 0, y = 0, w = 100, h = 100 })
    local b = ui:window({ title = "B", x = 50, y = 0, w = 100, h = 100 }) -- частичное перекрытие
    local s = k.storage
    check("z: начальные zIndex равны",
        s.zIndex[s.idToSlot[a.id]] == s.zIndex[s.idToSlot[b.id]])
    a:bringToFront()
    local za1 = s.zIndex[s.idToSlot[a.id]]
    check("z: a поднялся", za1 > s.zIndex[s.idToSlot[b.id]])
    a:bringToFront()
    check("z: повторный bringToFront не растит z", s.zIndex[s.idToSlot[a.id]] == za1)
    b:bringToFront()
    check("z: b теперь выше a", s.zIndex[s.idToSlot[b.id]] > za1)
    -- клик по ЭКСКЛЮЗИВНОЙ зоне a (x=10 < 50, вне b): mousedown бабблится
    -- до узла a -> bringToFront
    k:renderFrame()
    k:onMouseDown(10, 60, "left")
    k:onMouseUp(10, 60, "left")
    check("z: mousedown по окну поднимает его",
        s.zIndex[s.idToSlot[a.id]] > s.zIndex[s.idToSlot[b.id]])
end

-- =======================================================================
-- 8. Pool hygiene: composite handle не "грязнит" пул (ADR-016 §1)
-- =======================================================================
do
    local k, ui = newUI()
    local poolBefore = k.proxy.poolCount
    local win = ui:window({ title = "T" }) -- держит 3 proxy: win+bar+text
    k:destroy(win)
    check("pool: 3 handle вернулись (win+bar+text)", k.proxy.poolCount - poolBefore == 3)
    local n = k:create(C.NODE_PANEL) -- acquire из пула
    check("pool: переиспользованный handle чист",
        n._parts == nil and n._win == nil and n._kernel == nil)
    check("pool: у переиспользованного handle нет window-методов", n.setTitle == nil)
end

-- =======================================================================
-- 9. Modal-флаг (базовый -- слой; полный trap в M18)
-- =======================================================================
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", modal = true })
    local s = k.storage
    check("modal: слой LAYER_MODAL", s.layer[s.idToSlot[win.id]] == C.LAYER_MODAL)
    win:setModal(false)
    check("modal: setModal(false) -> LAYER_BASE", s.layer[s.idToSlot[win.id]] == C.LAYER_BASE)
end

print(string.format("test_m12: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
