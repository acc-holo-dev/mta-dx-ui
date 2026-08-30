--[[
    test_m17.lua -- Tooltip + Popup + ContextMenu (ADR-021): tooltip delay
    (M20), popup show/hide/dismiss, contextmenu rows. Паттерн test_m12.
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

-- 1. Tooltip: создание panel+label, скрыт по умолчанию
do
    local k, ui = newUI()
    local before = k.storage.count
    local p = ui:panel({ x = 0, y = 0, w = 100, h = 30 })
    p:setTooltip("Help text")
    check("tooltip: panel+label созданы (2 узла)", k.storage.count - before == 3)
    check("tooltip: panel скрыт по умолчанию", not p._tooltip.panel:isVisible())
    local lslot = k.storage.idToSlot[p._tooltip.label.id]
    check("tooltip: label текст", k.storage.text[lslot] == "Help text")
    check("tooltip: panel слой LAYER_TOOLTIP",
        k.storage.layer[k.storage.idToSlot[p._tooltip.panel.id]] == C.LAYER_TOOLTIP)
end

-- 2. Tooltip: показ с задержкой (M20) + скрытие на leave
do
    local k, ui = newUI()
    local tick = 0
    k:setClock(function() return tick end)
    local p = ui:panel({ x = 0, y = 0, w = 100, h = 30 })
    p:setTooltip("Help")
    k:renderFrame()
    k:onCursorMove(50, 15) -- hover на панель
    check("tooltip: не виден сразу (задержка)", not p._tooltip.panel:isVisible())
    tick = tick + 500 -- > TOOLTIP_DELAY_MS(400)
    k:renderFrame()   -- _runTimers выполнит schedule
    check("tooltip: виден после задержки", p._tooltip.panel:isVisible())
    k:onCursorMove(500, 500) -- leave
    check("tooltip: скрыт после leave", not p._tooltip.panel:isVisible())
end

-- 3. Popup: show/hide/isShown/toggle + стек
do
    local k, ui = newUI()
    local popup = ui:popup({ x = 100, y = 100, w = 160, h = 40 })
    check("popup: скрыт по умолчанию", not popup:isShown())
    popup:show()
    check("popup: показан", popup:isShown())
    check("popup: в стеке (1)", #k.dispatcher.popupStack == 1)
    popup:hide()
    check("popup: скрыт", not popup:isShown())
    check("popup: стек пуст", #k.dispatcher.popupStack == 0)
    popup:toggle()
    check("popup: toggle -> показан", popup:isShown())
    popup:toggle()
    check("popup: toggle -> скрыт", not popup:isShown())
end

-- 4. Popup: dismiss по клику вне
do
    local k, ui = newUI()
    local popup = ui:popup({ x = 100, y = 100, w = 160, h = 40 })
    popup:show()
    k:renderFrame()
    k:onMouseDown(500, 500, "left") -- вне popup
    check("popup: dismiss по клику вне", not popup:isShown())
    check("popup: стек пуст после dismiss", #k.dispatcher.popupStack == 0)
end

-- 5. ContextMenu: строки + клик -> onClick + hide
do
    local k, ui = newUI()
    local clicked = 0
    local menu = ui:contextmenu({ items = {
        { text = "Item 1", onClick = function() clicked = clicked + 1 end },
        { text = "Item 2", onClick = function() clicked = clicked + 1 end },
    } })
    check("contextmenu: скрыт по умолчанию", not menu:isShown())
    menu:show(100, 100)
    k:renderFrame()
    check("contextmenu: показан", menu:isShown())
    -- клик по первой строке (100..260, 100..124)
    k:onMouseDown(110, 110, "left")
    k:onMouseUp(110, 110, "left")
    check("contextmenu: onClick вызван", clicked == 1)
    check("contextmenu: скрыт после клика", not menu:isShown())
end

print(string.format("test_m17: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
