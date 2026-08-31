--[[
    test_input.lua — DXUI V2 Stage 4

    Tests input: hit-test (topmost node), click, bubble, stopPropagation,
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
-- Test widget (interactive panel)
-- ---------------------------------------------------------------------
local Panel = DXUI.Widget:extend("Panel", {})
function Panel:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

local ctx = DXUI.createContext({
    setBlendMode = function() end,
    drawRect = function() end,
    drawRoundedRect = function() end,
    drawImage = function() end,
    drawText = function() end,
    drawLine = function() end,
    beginGroup = function() return false end,
    endGroup = function() end,
})

-- ---------------------------------------------------------------------
-- Hit-test: topmost node under point
-- ---------------------------------------------------------------------
local a = Panel:new({ x = 0, y = 0, width = 100, height = 100 })
local b = Panel:new({ x = 50, y = 50, width = 100, height = 100 })
ctx:mount(a)
ctx:mount(b)
ctx:renderFrame() -- rebuild interactive list

eq(DXUI.HitTest.pick(ctx, 10, 10), a, "hit a (only a covers 10,10)")
eq(DXUI.HitTest.pick(ctx, 60, 60), b, "hit b (b on top at 60,60)")
eq(DXUI.HitTest.pick(ctx, 200, 200), nil, "no hit outside")

-- zIndex: b above a
b.zIndex = 10
ctx:renderFrame()
eq(DXUI.HitTest.pick(ctx, 60, 60), b, "b on top (zIndex)")

-- ---------------------------------------------------------------------
-- Clip-aware hit-test: ancestors with clip=true bound their children's
-- interactive region (a scrolled-out child must not eat clicks)
-- ---------------------------------------------------------------------
local vp = Panel:new({ x = 0, y = 200, width = 100, height = 100, clip = true })
local inner = Panel:new({ x = 0, y = 150, width = 50, height = 50 })
vp:addChild(inner)
ctx:mount(vp)
ctx:renderFrame()
local innerClicks = 0
inner:on("click", function() innerClicks = innerClicks + 1 end)
-- inside inner's AABB (0..50 × 350..400) but BELOW the clip region (0..100) —
-- visually clipped out: the click must NOT reach it
ctx:onMouseDown(25, 375, "left"); ctx:onMouseUp(25, 375, "left")
eq(innerClicks, 0, "clip: clipped-out child receives no click")
-- move the child back inside the clip region → clickable again
inner:setPosition(0, 50)
ctx:renderFrame()
ctx:onMouseDown(25, 275, "left"); ctx:onMouseUp(25, 275, "left")
eq(innerClicks, 1, "clip: visible child receives click")

-- ---------------------------------------------------------------------
-- Click + bubble
-- ---------------------------------------------------------------------
local clickLog = {}
local child = Panel:new({ x = 0, y = 0, width = 10, height = 10 })
a:addChild(child)
ctx:renderFrame()

a:on("click", function(e) clickLog[#clickLog + 1] = "a" end)
child:on("click", function(e) clickLog[#clickLog + 1] = "child" end)

-- click on child (inside a): child first, then bubble to a
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
-- Disable child and b so hover/focus tests are clean on a.
child.enabled = false
b.enabled = false
ctx:renderFrame()

local hoverLog = {}
a:on("mouseenter", function() hoverLog[#hoverLog + 1] = "enter" end)
a:on("mouseleave", function() hoverLog[#hoverLog + 1] = "leave" end)

ctx:onCursorMove(10, 10) -- into a
ctx:onCursorMove(20, 20) -- still in a (no change)
ctx:onCursorMove(300, 300) -- outside a
eq(hoverLog[1], "enter", "mouseenter")
eq(hoverLog[2], "leave", "mouseleave")
eq(#hoverLog, 2, "no redundant enter/leave")

-- ---------------------------------------------------------------------
-- Focus: mousedown focuses, blur/focus events
-- ---------------------------------------------------------------------
local focusLog = {}
a:on("focus", function() focusLog[#focusLog + 1] = "focus" end)
a:on("blur", function() focusLog[#focusLog + 1] = "blur" end)

ctx:onMouseDown(10, 10, "left")
eq(ctx:getFocus(), a, "mousedown focuses node")
eq(focusLog[1], "focus", "focus event")

ctx:onMouseDown(300, 300, "left") -- click elsewhere
eq(ctx:getFocus(), nil, "click outside clears focus")
eq(focusLog[2], "blur", "blur event")

-- ---------------------------------------------------------------------
-- Keyboard: key/text to focused node
-- ---------------------------------------------------------------------
local keyLog = {}
a:on("key", function(e) keyLog[#keyLog + 1] = e.key end)
a:on("text", function(e) keyLog[#keyLog + 1] = "text:" .. e.text end)

ctx:onMouseDown(10, 10, "left") -- focus on a
ctx:onKeyDown("a", "down", "", "a")
eq(keyLog[1], "text:a", "text event")
eq(keyLog[2], "a", "key event")

-- ---------------------------------------------------------------------
-- Character input (MTA onClientCharacter bridge → Context:onCharacter)
-- ---------------------------------------------------------------------
keyLog = {}
ctx:onCharacter("x")
eq(keyLog[1], "text:x", "onCharacter emits text event on focused node")
eq(keyLog[2], nil, "onCharacter does not emit a key event")

ctx:onCharacter("") -- empty char: no event
eq(#keyLog, 1, "empty character is ignored")

-- no focus: no event
ctx:setFocus(nil)
ctx:onCharacter("y")
eq(#keyLog, 1, "no focus → onCharacter ignored")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_input: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
