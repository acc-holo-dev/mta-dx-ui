--[[
    test_input.lua — DXUI V2 Stage 4

    Проверяет input: hit-test (верхний узел), click, bubble, stopPropagation,
    hover (mouseenter/mouseleave), focus (blur/focus), keyboard (key/text).
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

-- ---------------------------------------------------------------------
-- Тестовый виджет (интерактивная панель)
-- ---------------------------------------------------------------------
local Panel = DXUI.Widget:extend("Panel", {})
function Panel:render(renderer)
    renderer:rect(self.x, self.y, self.width, self.height, self.color)
end

local ctx = DXUI.createContext({}) -- пустой backend (render не важен)

-- ---------------------------------------------------------------------
-- Hit-test: верхний узел под точкой
-- ---------------------------------------------------------------------
local a = Panel:new({ x = 0, y = 0, width = 100, height = 100 })
local b = Panel:new({ x = 50, y = 50, width = 100, height = 100 })
ctx:mount(a)
ctx:mount(b)
ctx:renderFrame() -- пересобрать interactive list

eq(DXUI.HitTest.pick(ctx, 10, 10), a, "hit a (only a covers 10,10)")
eq(DXUI.HitTest.pick(ctx, 60, 60), b, "hit b (b on top at 60,60)")
eq(DXUI.HitTest.pick(ctx, 200, 200), nil, "no hit outside")

-- zIndex: b поверх a
b.zIndex = 10
ctx:renderFrame()
eq(DXUI.HitTest.pick(ctx, 60, 60), b, "b on top (zIndex)")

-- ---------------------------------------------------------------------
-- Click + bubble
-- ---------------------------------------------------------------------
local clickLog = {}
local child = Panel:new({ x = 0, y = 0, width = 10, height = 10 })
a:addChild(child)
ctx:renderFrame()

a:on("click", function(e) clickLog[#clickLog + 1] = "a" end)
child:on("click", function(e) clickLog[#clickLog + 1] = "child" end)

-- клик по child (внутри a): child первым, потом bubble к a
ctx:onMouseDown(5, 5, "left")
ctx:onMouseUp(5, 5, "left")
eq(clickLog[1], "child", "click target first")
eq(clickLog[2], "a", "click bubbles to parent")

-- ---------------------------------------------------------------------
-- stopPropagation
-- ---------------------------------------------------------------------
clickLog = {}
child:on("click", function(e) e:stopPropagation() end)
ctx:onMouseDown(5, 5, "left")
ctx:onMouseUp(5, 5, "left")
eq(#clickLog, 1, "stopPropagation stops bubble (only child)")

-- ---------------------------------------------------------------------
-- Hover: mouseenter / mouseleave
-- ---------------------------------------------------------------------
local hoverLog = {}
a:on("mouseenter", function() hoverLog[#hoverLog + 1] = "enter" end)
a:on("mouseleave", function() hoverLog[#hoverLog + 1] = "leave" end)

ctx:onCursorMove(10, 10) -- в a
ctx:onCursorMove(20, 20) -- всё ещё в a (no change)
ctx:onCursorMove(300, 300) -- вне a
eq(hoverLog[1], "enter", "mouseenter")
eq(hoverLog[2], "leave", "mouseleave")
eq(#hoverLog, 2, "no redundant enter/leave")

-- ---------------------------------------------------------------------
-- Focus: mousedown фокусирует, blur/focus события
-- ---------------------------------------------------------------------
local focusLog = {}
a:on("focus", function() focusLog[#focusLog + 1] = "focus" end)
a:on("blur", function() focusLog[#focusLog + 1] = "blur" end)

ctx:onMouseDown(10, 10, "left")
eq(ctx:getFocus(), a, "mousedown focuses node")
eq(focusLog[1], "focus", "focus event")

ctx:onMouseDown(300, 300, "left") -- клик мимо
eq(ctx:getFocus(), nil, "click outside clears focus")
eq(focusLog[2], "blur", "blur event")

-- ---------------------------------------------------------------------
-- Keyboard: key/text на сфокусированный узел
-- ---------------------------------------------------------------------
local keyLog = {}
a:on("key", function(e) keyLog[#keyLog + 1] = e.key end)
a:on("text", function(e) keyLog[#keyLog + 1] = "text:" .. e.text end)

ctx:onMouseDown(10, 10, "left") -- фокус на a
ctx:onKeyDown("a", "down", "", "a")
eq(keyLog[1], "text:a", "text event")
eq(keyLog[2], "a", "key event")

-- ---------------------------------------------------------------------
-- Итог
-- ---------------------------------------------------------------------
print(string.format("test_input: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
