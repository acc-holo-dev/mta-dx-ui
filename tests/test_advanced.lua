--[[
    test_advanced.lua — DXUI V2 Stage 7

    Tests advanced widgets: checkbox, radiobutton, slider, progressbar,
    scrollpanel (scroll + clip), edit (input/keys), popup (dismiss),
    combobox, tabpanel, gridlist, tooltip, modal.
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

local calls = {}
local mock = {
    setBlendMode = function(m) calls[#calls + 1] = { "blend", m } end,
    drawRect  = function(x, y, w, h, c) calls[#calls + 1] = { "rect", x, y, w, h, c } end,
    drawRoundedRect = function() end,
    drawImage = function(x, y, w, h, t, c) calls[#calls + 1] = { "image", x, y, w, h, t, c } end,
    drawText  = function(t, x, y, w, h, c) calls[#calls + 1] = { "text", t, x, y, w, h, c } end,
    drawLine  = function() end,
    beginGroup = function() return false end,
    endGroup = function() end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- CheckBox
-- ---------------------------------------------------------------------
local changedTo = nil
local cb = ui:checkbox({ text = "Enable", onChange = function(v) changedTo = v end })
eq(cb:isChecked(), false, "checkbox unchecked default")
ui:renderFrame()
ui:onMouseDown(5, 12, "left")  -- inside box
ui:onMouseUp(5, 12, "left")
eq(cb:isChecked(), true, "checkbox toggled on click")
eq(changedTo, true, "checkbox onChange")

-- ---------------------------------------------------------------------
-- RadioButton (group)
-- ---------------------------------------------------------------------
local r1 = ui:radiobutton({ text = "A", group = "g" })
local r2 = ui:radiobutton({ text = "B", group = "g" })
ui:renderFrame()
-- r2 over r1 (higher id) — click selects r2
ui:onMouseDown(5, 12, "left")
ui:onMouseUp(5, 12, "left")
eq(r2:isChecked(), true, "click selects topmost radio (r2)")
eq(r1:isChecked(), false, "r1 unchecked")

-- programmatically: checking r1 unchecks r2 (group)
r1:setChecked(true)
eq(r1:isChecked(), true, "r1 checked")
eq(r2:isChecked(), false, "r2 unchecked by group")

-- props.checked at BUILD must respect group exclusivity too
-- (mutation layer bypasses setChecked — the builder re-applies it)
local ra = ui:radiobutton({ x = 0, y = 100, group = "g2", checked = true })
local rb = ui:radiobutton({ x = 0, y = 100, group = "g2", checked = true })
ok(not (ra:isChecked() and rb:isChecked()), "radio: props.checked group exclusivity at build")

-- ---------------------------------------------------------------------
-- ProgressBar
-- ---------------------------------------------------------------------
local pb = ui:progressbar({ value = 50, min = 0, max = 100 })
eq(pb:_frac(), 0.5, "progressbar frac")

-- ---------------------------------------------------------------------
-- Slider
-- ---------------------------------------------------------------------
local sliderVal = nil
local sl = ui:slider({ x = 100, y = 300, width = 100, height = 16, min = 0, max = 100,
    onChange = function(v) sliderVal = v end })
ui:renderFrame()
-- click-to-jump to middle
ui:onMouseDown(150, 308, "left") -- world 100+50 = middle
ui:onMouseUp(150, 308, "left")
ok(sliderVal ~= nil and sliderVal > 40 and sliderVal < 60, "slider click-to-jump near middle")

-- ---------------------------------------------------------------------
-- ScrollPanel: scroll + clip
-- ---------------------------------------------------------------------
local sp = ui:scrollpanel({ x = 0, y = 0, width = 100, height = 100 })
local child = ui:panel({ x = 0, y = 0, width = 50, height = 50, color = 0xFFFF0000 })
child:setParent(sp:getContent())
sp:refresh()
local m0x, m0y = sp:getScrollMax()
eq(m0y, 0, "no scroll when content fits (maxY=0)")

-- content taller than viewport
local tall = ui:panel({ x = 0, y = 0, width = 50, height = 200, color = 0xFF00FF00 })
tall:setParent(sp:getContent())
sp:refresh()
local m1x, m1y = sp:getScrollMax()
eq(m1y, 100, "scroll maxY = 200-100")

sp:setScroll(0, 50)
local s1x, s1y = sp:getScroll()
eq(s1y, 50, "scrollY set")
eq(sp:getContent().x, 0, "content x unchanged")
eq(sp:getContent().y, -50, "content y = -scrollY")

-- wheel (needs fresh frame: layout + interactive list)
ui:renderFrame()
ui:onMouseWheel(50, 50, -1) -- wheel down
local s2x, s2y = sp:getScroll()
eq(s2y > 50, true, "wheel scrolls down")

-- ---------------------------------------------------------------------
-- Edit: text input + backspace
-- ---------------------------------------------------------------------
local edit = ui:edit({ x = 0, y = 200, width = 160, height = 24 })
ui:renderFrame()
ui:onMouseDown(5, 210, "left") -- focus
eq(ui:getFocus(), edit, "edit focused on mousedown")
ui:onKeyDown("h", "down", "", "h")
eq(edit:getText(), "h", "edit text input")
ui:onKeyDown("i", "down", "", "i")
eq(edit:getText(), "hi", "edit append")
ui:onKeyDown("backspace", "down", "", nil)
eq(edit:getText(), "h", "edit backspace")

-- modifier shortcuts (mods string comes from the init.lua modifier tracker)
ui:onKeyDown("a", "down", "ctrl", nil) -- select all
eq(({ edit:getSelection() })[1], 0, "ctrl+a: selection start 0")
eq(({ edit:getSelection() })[2], 1, "ctrl+a: selection end 1")
ui:onKeyDown("c", "down", "ctrl", nil) -- copy
eq(edit._context.clipboard, "h", "ctrl+c copies selection")
ui:onKeyDown("i", "down", "", "i") -- typing replaces the selection
eq(edit:getText(), "i", "typing replaces the selection")
ui:onKeyDown("v", "down", "ctrl", nil) -- paste
eq(edit:getText(), "ih", "ctrl+v pastes")
ui:onKeyDown("a", "down", "ctrl", nil)
ui:onKeyDown("x", "down", "ctrl", nil) -- cut
eq(edit:getText(), "", "ctrl+x cuts selection")
eq(edit._context.clipboard, "ih", "cut copies to clipboard")

ui:onMouseUp(5, 210, "left") -- finish click gesture (drag-select holds until mouseup)

-- caret movement must repaint — arrows don't change the text but the
-- cursor geometry is part of the render list (regression: no invalidation)
local e2 = ui:edit({ x = 0, y = 240, width = 100, height = 24, text = "ab" })
ui:renderFrame()
ui:onMouseDown(5, 250, "left") -- focus e2
ui:onMouseUp(5, 250, "left")
ui:renderFrame() -- absorb focus dirty
ui:onKeyDown("arrow_r", "down", "", nil)
ok(e2._dirty[DXUI.DIRTY.RENDER] == true, "edit: arrow key invalidates RENDER (caret moved)")

-- ---------------------------------------------------------------------
-- Popup: dismiss on outside click
-- ---------------------------------------------------------------------
local popup = ui:popup({ x = 100, y = 100, width = 100, height = 100 })
eq(popup:isShown(), false, "popup hidden by default")
popup:show(200, 200)
eq(popup:isShown(), true, "popup shown")
ui:renderFrame()
ui:onMouseDown(500, 500, "left") -- click outside popup
eq(popup:isShown(), false, "popup dismissed on outside click")

-- ---------------------------------------------------------------------
-- ComboBox
-- ---------------------------------------------------------------------
local comboVal = nil
local combo = ui:combobox({ items = { "One", "Two", "Three" }, onChange = function(idx, val) comboVal = val end })
combo:setSelected(2)
eq(comboVal, "Two", "combobox onChange value")

-- open() before any frame: must position at the widget, not at stale (0,0)
-- world coords (regression: layout deferred to the next frame)
local cb2 = ui:combobox({ x = 10, y = 20, width = 100, items = { "A", "B" } })
cb2:open()
eq(cb2._dropdown.x, 10, "combobox: open() before layout uses current X")
ok(cb2._dropdown.y > 20, "combobox: open() before layout uses current Y")
cb2:close()

-- ---------------------------------------------------------------------
-- TabPanel
-- ---------------------------------------------------------------------
local tp = ui:tabpanel({ x = 0, y = 400, width = 200, height = 150 })
local page1 = tp:addTab("Tab1", { ui:label({ text = "content1" }) })
local page2 = tp:addTab("Tab2")
eq(tp:getTabCount(), 2, "tabpanel 2 tabs")
eq(tp:getSelectedIndex(), 1, "first tab selected")
tp:selectTab(2)
eq(tp:getSelectedIndex(), 2, "selectTab(2)")

-- barHeight change at runtime must reposition tabs + pages (regression:
-- previously only the header strip redrew, leaving stale geometry)
tp.barHeight = 40
eq(tp._tabs[1].btn.height, 40, "tabpanel: barHeight repositions buttons")
eq(tp._tabs[1].page.y, 40, "tabpanel: barHeight repositions pages")

-- ---------------------------------------------------------------------
-- GridList
-- ---------------------------------------------------------------------
local gl = ui:gridlist({ x = 0, y = 400, width = 200, height = 150, columns = { { text = "Name", width = 100 } } })
gl:addRow({ "Alice" })
gl:addRow({ "Bob" })
eq(gl:getRowCount(), 2, "gridlist 2 rows")

-- ---------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------
local tipNode = ui:button({ x = 300, y = 300, width = 50, height = 20, text = "?" })
tipNode:setTooltip("Help text")
ok(tipNode._tooltip ~= nil, "tooltip created")
ui:renderFrame()
ui:onCursorMove(310, 310) -- enter
eq(tipNode._tooltip.visible, true, "tooltip shown on hover")
ui:onCursorMove(500, 500) -- leave
eq(tipNode._tooltip.visible, false, "tooltip hidden on leave")

-- ---------------------------------------------------------------------
-- Modal: focus lock + input trap
-- ---------------------------------------------------------------------
local modalWin = ui:window({ x = 100, y = 100, width = 200, height = 150, modal = true })
ui:renderFrame()
eq(ui.dispatcher:isModalActive(), true, "modal active")

-- click outside window (on overlay) blocked: focus unchanged
local beforeFocus = ui:getFocus()
ui:onMouseDown(700, 500, "left")
eq(ui:getFocus(), beforeFocus, "modal input trap (focus unchanged)")

-- dismissOnClickOutside
local modal2 = ui:window({ x = 100, y = 100, width = 200, height = 150,
    modal = { dismissOnClickOutside = true } })
ui:renderFrame() -- fresh interactive list (overlay2 in hit-test)
-- top modal is modal2; outside click (on overlay) dismisses it
ui:onMouseDown(700, 500, "left")
ui:onMouseUp(700, 500, "left") -- dismiss fires on click (down+up)
eq(modal2.destroyed, true, "modal dismiss on outside click")

-- a popup/dropdown stays clickable while a modal is open (floats above it;
-- regression: isInsideModal rejected every root-level popup)
local mpop = ui:popup({ x = 0, y = 0, width = 60, height = 60 })
mpop:show(300, 300)
ui:renderFrame()
local popClicks = 0
mpop:on("click", function() popClicks = popClicks + 1 end)
ui:onMouseDown(310, 310, "left")
ui:onMouseUp(310, 310, "left")
eq(popClicks, 1, "popup above modal receives clicks")
mpop:destroy()

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_advanced: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
