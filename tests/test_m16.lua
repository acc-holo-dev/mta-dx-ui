--[[
    test_m16.lua -- Modal (ADR-020): overlay, focus lock, input trap,
    dismissOnClickOutside, авто-фокус (M20). Паттерн test_m12.
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

-- 1. setModal(true): слой + overlay + стек
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150 })
    win:setModal(true)
    local s = k.storage
    check("modal: слой окна LAYER_MODAL", s.layer[s.idToSlot[win.id]] == C.LAYER_MODAL)
    check("modal: overlay создан и жив", win._win.modal.overlay ~= nil and win._win.modal.overlay:isAlive())
    check("modal: overlay слой LAYER_MODAL",
        s.layer[s.idToSlot[win._win.modal.overlay.id]] == C.LAYER_MODAL)
    check("modal: стек глубиной 1", #k.dispatcher.modalStack == 1)
    check("modal: isModalActive", k.dispatcher:isModalActive())
    check("modal: overlay размер = экран", win._win.modal.overlay:getSize() == 1280)
end

-- 2. Focus lock: фокус вне окна блокируется
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150, modal = true })
    local outside = ui:panel({ x = 500, y = 500, w = 50, h = 50 })
    k:renderFrame()
    -- авто-фокус на окно (нет Edit)
    check("modal: авто-фокус на окно", k.dispatcher:getFocus() == win.id)
    k.dispatcher:setFocus(outside.id)
    check("modal: focus lock — фокус не ушёл на outside", k.dispatcher:getFocus() ~= outside.id)
end

-- 3. Input trap: mousedown вне окна блокируется
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150, modal = true })
    local outside = ui:panel({ x = 500, y = 500, w = 50, h = 50 })
    local downs = 0
    outside:on("mousedown", function() downs = downs + 1 end)
    k:renderFrame()
    k:onMouseDown(520, 520, "left")
    check("modal: input trap — mousedown вне окна не дошёл", downs == 0)
end

-- 4. setModal(false): очистка
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150, modal = true })
    local overlay = win._win.modal.overlay
    win:setModal(false)
    local s = k.storage
    check("modal: setModal(false) -> LAYER_BASE", s.layer[s.idToSlot[win.id]] == C.LAYER_BASE)
    check("modal: стек пуст", #k.dispatcher.modalStack == 0)
    check("modal: overlay уничтожен", not overlay:isAlive())
end

-- 5. Авто-фокус на первый Edit (M20)
do
    local k, ui = newUI()
    local edit = ui:edit({ x = 10, y = 30, w = 100, h = 24 })
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150, children = { edit } })
    win:setModal(true)
    check("modal: авто-фокус на Edit", k.dispatcher:getFocus() == edit.id)
end

-- 6. dismissOnClickOutside: клик по overlay закрывает окно
do
    local k, ui = newUI()
    local win = ui:window({ title = "T", x = 100, y = 100, w = 200, h = 150,
        modal = { dismissOnClickOutside = true } })
    k:renderFrame()
    -- клик по overlay вне окна (600,400 — вне окна 100..300 x 100..250)
    k:onMouseDown(600, 400, "left")
    k:onMouseUp(600, 400, "left")
    check("modal: dismissOnClickOutside закрыл окно", not win:isAlive())
end

print(string.format("test_m16: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
