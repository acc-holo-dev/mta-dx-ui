--[[
    test_m24.lua — DXUI M24

    New widgets: memo, menu, selector, switchbutton, line, layout, scalepane.
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

local lines = {}
local mock = {
    setBlendMode = function() end,
    drawRect  = function() end,
    drawRoundedRect = function() end,
    drawImage = function() end,
    drawText  = function() end,
    drawLine  = function(x1, y1, x2, y2, c, w) lines[#lines + 1] = { x1, y1, x2, y2, c, w } end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- Memo
-- ---------------------------------------------------------------------
local memo = ui:memo({ x = 0, y = 0, width = 100, height = 60, text = "line1\nline2\nline3" })
eq(memo.text, "line1\nline2\nline3", "memo stores text")
eq(memo.wrap, true, "memo wraps by default")
eq(memo.enabled, true, "memo interactive (wheel)")
memo:scrollBy(20)
eq(memo.scrollY, 20, "scrollBy moves scrollY")
eq(select("#", memo:getScroll()), 2, "getScroll returns offset + max")
ui:renderFrame() -- must not crash

-- scrollBy clamps at 0 (regression: repeated wheel-up at the top raised a
-- validator error on negative write)
memo:scrollBy(-100)
eq(memo.scrollY, 0, "scrollBy clamps at 0")
memo:scrollBy(-50)
eq(memo.scrollY, 0, "scrollBy stays clamped at 0")

-- textColor is a real property (regression: rendered with nil color)
memo.textColor = "#FF0000"
eq(memo.textColor, 0xFFFF0000, "memo textColor property resolves")

-- ---------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------
local menuClicked
local ev = {}
local menu = ui:menu({
    x = 0, y = 0, width = 120,
    items = {
        { text = "Open", onClick = function() menuClicked = true end },
        { text = "Close" },
    },
})
eq(#menu.children, 2, "menu builds item rows")
menu:on("select", function(e) ev = e end)
ui:renderFrame()
ui:onMouseDown(10, 10, "left")
ui:onMouseUp(10, 10, "left")
eq(menu.selected, 1, "click selects item 1")
eq(menuClicked, true, "item onClick fires")
eq(ev.index, 1, "menu select event index")
eq(ev.text, "Open", "menu select event text")

-- ---------------------------------------------------------------------
-- Selector
-- ---------------------------------------------------------------------
local selEv
local sel = ui:selector({ x = 0, y = 0, width = 100, items = { "A", "B", "C" } })
sel:on("select", function(e) selEv = e end)
eq(sel.selected, 0, "selector starts unselected")
ui:renderFrame()
ui:onMouseDown(10, 30, "left") -- row 2 (24..48)
ui:onMouseUp(10, 30, "left")
eq(sel.selected, 2, "selector click selects row 2")
eq(sel:getSelectedItem(), "B", "getSelectedItem")
eq(selEv.index, 2, "selector select event index")
sel:selectItem("C")
eq(sel.selected, 3, "selectItem by value")
sel:setSelected(1)
eq(sel.selected, 1, "setSelected clamps")

-- repeated setSelected with the same value emits "select" only ONCE
-- (regression: emitted on every call; also emitted at build for index 0)
local selN = 0
sel:on("select", function() selN = selN + 1 end)
sel:setSelected(2) -- change: one emission
sel:setSelected(2) -- same value: no re-emission
sel:setSelected(2) -- same value: no re-emission
eq(selN, 1, "selector: repeated setSelected emits once")

-- ---------------------------------------------------------------------
-- SwitchButton
-- ---------------------------------------------------------------------
local sw = ui:switchbutton({ x = 0, y = 0, text = "WiFi" })
eq(sw.checked, false, "switch off by default")
eq(sw._class._name, "SwitchButton", "switch class registered")
ui:renderFrame()
ui:onMouseDown(10, 10, "left")
ui:onMouseUp(10, 10, "left")
eq(sw.checked, true, "click toggles switch on")

-- ---------------------------------------------------------------------
-- Line (thickness param)
-- ---------------------------------------------------------------------
local ln = ui:line({ x = 5, y = 10, x2 = 40, y2 = 20, color = 0xFFFF0000, thickness = 3 })
ui:renderFrame()
local drew = false
for i = 1, #lines do
    if lines[i][5] == 0xFFFF0000 and lines[i][6] == 3 then drew = true end
end
eq(drew, true, "line drawn with color and thickness")

-- ---------------------------------------------------------------------
-- Layout (auto-positioning)
-- ---------------------------------------------------------------------
local c1 = ui:panel({ width = 40, height = 20 })
local c2 = ui:panel({ width = 40, height = 30 })
local lyt = ui:layout({ x = 0, y = 0, mode = "vertical", gap = 4, padding = 2, children = { c1, c2 } })
eq(lyt._class._name, "LayoutBox", "layout widget class is LayoutBox")
eq(c1.x, 2, "layout vertical: first child at padding")
eq(c2.y, 2 + 20 + 4, "layout vertical: second child after first + gap")
lyt:setMode("horizontal")
eq(c1.y, 2, "layout horizontal: y fixed at padding")
eq(c2.x, 2 + 40 + 4, "layout horizontal: x advances")

-- ---------------------------------------------------------------------
-- ScalePane (RT-based scale)
-- ---------------------------------------------------------------------
local sp = ui:scalepane({ x = 0, y = 0, width = 50, height = 50, scale = 2 })
eq(sp.scaleX, 2, "scalepane uniform scale")
eq(sp.scaleY, 2, "scalepane uniform scale y")
eq(sp.clipMode, "rt", "scalepane renders subtree via RT group")
ui:renderFrame() -- must not crash (degrades without RT)

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_m24: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
