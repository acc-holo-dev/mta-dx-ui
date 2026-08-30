--[[
    test_m7.lua

    Тесты M7: декларативный widget API (ui.window/panel/button/label/image),
    цвета, иерархия, клики, каскад destroy, интеграция с M5/M6.
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

local now = 0
local function newKernelWithUI()
    local k = Kernel.new(newMockDriver())
    k:setClock(function() return now end)
    return k, DXUI.UI.new(k)
end

local function childCount(k, proxy)
    local slot = k.storage.idToSlot[proxy.id]
    if not slot then return 0 end
    local n, c = 0, k.storage.firstChild[slot]
    while c ~= C.NIL_ID do
        n = n + 1
        c = k.storage.nextSibling[k.storage.idToSlot[c]]
    end
    return n
end

local function nodeType(k, id)
    local slot = k.storage.idToSlot[id]
    return slot and k.storage.nodeType[slot] or nil
end

-- =======================================================================
-- 1. ui.window: тип узла, дефолтные размеры
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local w = ui:window()
    local slot = k.storage.idToSlot[w.id]
    check("window: NODE_WINDOW", k.storage.nodeType[slot] == C.NODE_WINDOW)
    check("window: default 320x240", k.storage.w[slot] == 320 and k.storage.h[slot] == 240)
end

-- =======================================================================
-- 2. ui.window: title -> title bar + label (2 auto-узла)
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local w = ui:window({ title = "Hello", x = 10, y = 20, w = 200, h = 150 })
    check("window title: 1 auto child (bar)", childCount(k, w) == 1)
    local bar = k.storage.firstChild[k.storage.idToSlot[w.id]]
    check("window title: bar has 1 child (text)", childCount(k, { id = bar }) == 1)
    local slot = k.storage.idToSlot[w.id]
    check("window title: props x/y/w/h applied", k.storage.x[slot] == 10 and k.storage.y[slot] == 20 and k.storage.w[slot] == 200 and k.storage.h[slot] == 150)
end

-- =======================================================================
-- 3. Общие свойства: color/clip/opacity/layer/visible
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local p = ui:panel({ x = 5, y = 6, w = 33, h = 44, color = ui:color(10, 20, 30, 255),
                         clip = true, opacity = 128, layer = C.LAYER_MODAL, visible = false })
    local slot = k.storage.idToSlot[p.id]
    check("panel: color packed 0xFF0A141E", k.storage.color[slot] == 0xFF0A141E)
    check("panel: clip flag", k.storage:hasFlag(p.id, C.FLAG_CLIP))
    check("panel: opacity 128", k.storage.opacity[slot] == 128)
    check("panel: layer MODAL", k.storage.layer[slot] == C.LAYER_MODAL)
    check("panel: hidden", k.storage:hasFlag(p.id, C.FLAG_VISIBLE) == false)
end

-- =======================================================================
-- 4. Вложенная декларация: window > panel > button
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local win = ui:window({
        w = 300, h = 200,
        children = {
            ui:panel({
                x = 10, y = 10, w = 100, h = 100,
                children = {
                    ui:button({ text = "OK", x = 10, y = 10, w = 50, h = 20 }),
                },
            }),
        },
    })
    local panel = k.storage.firstChild[k.storage.idToSlot[win.id]]
    local btn = k.storage.firstChild[k.storage.idToSlot[panel]]
    check("nest: win -> panel", panel ~= C.NIL_ID and k.storage.nodeType[k.storage.idToSlot[panel]] == C.NODE_PANEL)
    check("nest: panel -> button", btn ~= C.NIL_ID and k.storage.nodeType[k.storage.idToSlot[btn]] == C.NODE_BUTTON)
    -- world-каскад после layout
    k:renderFrame()
    local btnSlot = k.storage.idToSlot[btn]
    check("nest: world cascade (10+10, 10+10)", k.storage.worldX[btnSlot] == 20 and k.storage.worldY[btnSlot] == 20)
end

-- =======================================================================
-- 5. ui.button: auto-child NODE_TEXT при text
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local b = ui:button({ text = "Press", x = 0, y = 0, w = 80, h = 30 })
    check("button: 1 auto child (text)", childCount(k, b) == 1)
    local t = k.storage.firstChild[k.storage.idToSlot[b.id]]
    check("button: child is NODE_TEXT", k.storage.nodeType[k.storage.idToSlot[t]] == C.NODE_TEXT)
    check("button: text stored", k.storage.text[k.storage.idToSlot[t]] == "Press")

    -- Рендер: CMD_TEXT на весь размер кнопки
    k:renderFrame()
    local found = false
    for i = 1, #k.driver.log do
        local e = k.driver.log[i]
        if e[1] == "text" and e[2] == "Press" and e[3] == 0 and e[4] == 0 and e[5] == 80 and e[6] == 30 then
            found = true
        end
    end
    check("button: renders text over full size", found)
end

-- =======================================================================
-- 6. Цвета: number / hex string / table
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    check("color: ui.color packed", ui:color(255, 0, 0, 255) == 0xFFFF0000)
    check("color: ui.color alpha default", ui:color(0, 255, 0) == 0xFF00FF00)
    local a = ui:panel({ color = "#ff0000" })
    local b = ui:panel({ color = "#ff0000ff" })
    local c = ui:panel({ color = { r = 0, g = 0, b = 255, a = 128 } })
    check("color: hex #rrggbb", k.storage.color[k.storage.idToSlot[a.id]] == 0xFFFF0000)
    check("color: hex #rrggbbaa", k.storage.color[k.storage.idToSlot[b.id]] == 0xFFFF0000)
    check("color: table rgba", k.storage.color[k.storage.idToSlot[c.id]] == 0x800000FF)
end

-- =======================================================================
-- 7. Клик по кнопке: onClick fires
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local clicked = 0
    local b = ui:button({ text = "Go", x = 10, y = 10, w = 100, h = 40, onClick = function() clicked = clicked + 1 end })
    k:renderFrame() -- layout: world-координаты

    k:onMouseDown(50, 30, 1)
    k:onMouseUp(50, 30, 1)
    check("click: onClick fired once", clicked == 1)

    k:onMouseDown(5, 5, 1)
    k:onMouseUp(5, 5, 1)
    check("click: outside does not fire", clicked == 1)
end

-- =======================================================================
-- 8. Disabled: enabled=false — клики игнорируются
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local clicked = 0
    ui:button({ x = 10, y = 10, w = 100, h = 40, enabled = false, onClick = function() clicked = clicked + 1 end })
    k:renderFrame()
    k:onMouseDown(50, 30, 1)
    k:onMouseUp(50, 30, 1)
    check("disabled: click ignored", clicked == 0)
end

-- =======================================================================
-- 9. Destroy каскадно (виджеты = узлы, M1-механика)
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local before = k.storage.count
    local w = ui:window({ title = "T", children = { ui:button({ text = "B" }) } })
    local afterCreate = k.storage.count
    -- window + bar + title-text + button + button-text = 5
    check("cascade: window+title+button+text = +5 nodes", afterCreate - before == 5)

    k:destroy(w)
    check("cascade: all destroyed", k.storage.count == before)
    check("cascade: window proxy dead", w:isAlive() == false)
end

-- =======================================================================
-- 10. Hidden: visible=false не отрисовывается
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local vis = ui:panel({ x = 0, y = 0, w = 10, h = 10 })
    local hid = ui:panel({ x = 20, y = 20, w = 10, h = 10, visible = false })
    k:renderFrame()
    local rects = 0
    for i = 1, #k.driver.log do
        if k.driver.log[i][1] == "rect" then rects = rects + 1 end
    end
    check("hidden: only visible panel drawn (1 rect)", rects == 1)
end

-- =======================================================================
-- 11. ui.image: texture -> CMD_IMAGE
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    local img = 42 -- мок dxImage handle
    ui:image({ x = 0, y = 0, w = 32, h = 32, texture = img })
    k:renderFrame()
    local found = false
    for i = 1, #k.driver.log do
        local e = k.driver.log[i]
        if e[1] == "image" and e[6] == img then found = true end
    end
    check("image: CMD_IMAGE with texture", found)
end

-- =======================================================================
-- 12. Интеграция M6: виджет анимируется
-- =======================================================================
do
    now = 0
    local k, ui = newKernelWithUI()
    local p = ui:panel({ x = 0, y = 0, w = 50, h = 50 })
    p:animateTo({ x = 100 }, 100, C.EASE_LINEAR)
    now = 50
    k:renderFrame()
    local slot = k.storage.idToSlot[p.id]
    check("m6 integration: panel animated to x=50", k.storage.x[slot] == 50)
end

-- =======================================================================
-- 13. Интеграция M5: clip на виджете + opacity в driver
-- =======================================================================
do
    local k, ui = newKernelWithUI()
    ui:panel({ x = 0, y = 0, w = 100, h = 100, clip = true, opacity = 100,
               children = { ui:panel({ x = 50, y = 50, w = 50, h = 50 }) } })
    k:renderFrame()
    local found = false
    for i = 1, k.storage.count do
        if k.storage.slotToId[i] and k.storage.clipDepth[i] == 1 then
            found = true
        end
    end
    check("m5 integration: child clipDepth=1 under clip widget", found)
    local hasOpacityCall = false
    for i = 1, #k.driver.log do
        if k.driver.log[i][1] == "opacity" and k.driver.log[i][2] == 100 then hasOpacityCall = true end
    end
    check("m5 integration: opacity=100 reached driver", hasOpacityCall)
end

print(string.format("test_m7: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
