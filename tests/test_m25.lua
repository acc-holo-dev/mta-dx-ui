--[[
    test_m25.lua — DXUI M25

    Property listeners, translation (setLocale/setTextKey), drag & drop
    (setDraggable / setDropTarget / drop events).
]]

dofile("loader.lua")

local passed, failed = 0, 0

local function ok(cond, name)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name) end
end

local function eq(a, b, name)
    if a == b then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local mock = {
    setBlendMode = function() end,
    drawRect  = function() end,
    drawRoundedRect = function() end,
    drawImage = function() end,
    drawText  = function() end,
    drawLine  = function() end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- Property listeners
-- ---------------------------------------------------------------------
local p = ui:panel({ x = 0, y = 0, width = 100, height = 100 })
local newV, oldV, gotNode = nil, nil, false
local function onW(v, old, node)
    newV, oldV, gotNode = v, old, node == p
end
p:onProperty("width", onW)
p.width = 150
eq(newV, 150, "listener receives new value")
eq(oldV, 100, "listener receives old value")
eq(gotNode, true, "listener receives node")

local fired = 0
local function onOpacity(v) fired = fired + 1 end
p:onProperty("opacity", onOpacity)
p.opacity = 0.5
p.opacity = 0.75
eq(fired, 2, "listener fires on each change")

p:offProperty("opacity", onOpacity)
p.opacity = 0.9
eq(fired, 2, "offProperty removes listener")

-- ---------------------------------------------------------------------
-- Translation
-- ---------------------------------------------------------------------
DXUI.addLocale("en", { hello = "Hello" })
DXUI.addLocale("ru", { hello = "Привет" })
DXUI.setLocale("en")

local lbl = ui:label({ x = 0, y = 0, text = "init" })
lbl:setTextKey("hello")
eq(lbl.text, "Hello", "setTextKey applies current locale")
DXUI.setLocale("ru")
eq(lbl.text, "Привет", "locale switch re-translates bound nodes")
DXUI.setLocale("nope")
eq(lbl.text, "hello", "missing key falls back to the key itself")
DXUI.setLocale("en")

-- Window title binding
local win = ui:window({ x = 0, y = 0, width = 200, height = 150, title = "T" })
win:setTextKey("hello", "title")
eq(win.title, "Hello", "setTextKey targets custom property (title)")

-- ---------------------------------------------------------------------
-- Drag & drop
-- ---------------------------------------------------------------------
local src = ui:panel({ x = 0, y = 0, width = 50, height = 50 })
src:setDraggable(true)
src:setDragData({ item = "X" })
local tgt = ui:panel({ x = 100, y = 100, width = 50, height = 50 })
tgt:setDropTarget(true)

local dropped, ended, entered
tgt:on("drop", function(e) dropped = e end)
src:on("dragend", function(e) ended = e end)
tgt:on("dragenter", function() entered = true end)

ui:renderFrame()                 -- build interactive cache
ui:onMouseDown(10, 10, "left")   -- grab src
ui:onCursorMove(120, 120)        -- move over target
eq(entered, true, "dragenter fires over drop target")
ui:onMouseUp(120, 120)           -- release over target

eq(dropped ~= nil, true, "drop event fired")
eq(dropped.node, src, "drop carries dragged node")
eq(dropped.data.item, "X", "drop carries drag data")
eq(ended ~= nil, true, "dragend fired on dragged node")
eq(ended.dropTarget, tgt, "dragend carries drop target")
eq(src.x, 110, "dragged node moved by delta")
eq(src.y, 110, "dragged node moved by delta y")
eq(tgt._dragOverTarget == nil, true, "drag-over state cleared after drop")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_m25: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
