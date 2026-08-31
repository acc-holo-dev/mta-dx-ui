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
    setBlendMode = function() end,
    drawRect = function(x, y, w, h, c) calls[#calls + 1] = { kind = "rect", x = x, y = y, w = w, h = h, c = c } end,
    drawRoundedRect = function() end,
    drawImage = function() end,
    drawText = function() end,
    drawLine = function(x1, y1, x2, y2, c) calls[#calls + 1] = { kind = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, c = c } end,
    beginGroup = function() return true end,
    endGroup = function() end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- =====================================================================
-- 1. Popup stack cleanup
-- =====================================================================
local p1 = ui:popup({ x = 0, y = 0, width = 50, height = 50 })
p1:show(10, 10)
ui.dispatcher:pushPopup(p1, function() end)
eq(#ui.dispatcher.popupStack, 2, "popup stack has 2 entries")
ui:renderFrame()
ui:onMouseDown(300, 300, "left")
ok(#ui.dispatcher.popupStack <= 2, "popupStack not leaked by broken pop")
p1:destroy()
ui:renderFrame()
ok(#ui.dispatcher.popupStack == 0, "popup stack clean after destroy")

-- =====================================================================
-- 2. Effective layer / modal toggle
-- =====================================================================
local wn = ui:window({ x = 100, y = 100, width = 200, height = 150 })
local ch = ui:panel({ x = 0, y = 0, width = 50, height = 50 })
ch:setParent(wn)
ui:renderFrame()
eq(wn._effLayer, DXUI.LAYER.BASE, "window effLayer BASE before modal")
eq(ch._effLayer, DXUI.LAYER.BASE, "child effLayer BASE before modal")
wn:setModal(true)
ui:renderFrame()
eq(wn.layer, DXUI.LAYER.MODAL, "window.layer = MODAL")
eq(ch._effLayer, DXUI.LAYER.MODAL, "child follows MODAL (effective)")
wn:setModal(false)
ui:renderFrame()
eq(wn.layer, DXUI.LAYER.BASE, "window.layer back to BASE")
eq(ch._effLayer, DXUI.LAYER.BASE, "child NOT stuck in MODAL (effLayer fix)")

-- =====================================================================
-- 3. Modal overlay stretch
-- =====================================================================
local mw = ui:window({ x = 10, y = 10, width = 100, height = 100, modal = true })
ui:renderFrame()
ui:setScreenSize(1024, 768)
ui:renderFrame()
if mw._modal and mw._modal.overlay then
    eq(mw._modal.overlay.width, 1024, "modal overlay width follows screen (stretch)")
    eq(mw._modal.overlay.height, 768, "modal overlay height follows screen (stretch)")
end
mw:destroy()
ui:renderFrame()
ui:setScreenSize(800, 600) -- restore for stable coordinates in later tests
ui:renderFrame()

-- =====================================================================
-- 4. Destroy clears listeners
-- =====================================================================
local btn = ui:button({ x = 0, y = 0, width = 50, height = 20 })
local clicks = 0
btn:on("click", function() clicks = clicks + 1 end)
ui:renderFrame()
ui:onMouseDown(10, 10, "left"); ui:onMouseUp(10, 10, "left")
eq(clicks, 1, "click fires while alive")
btn:destroy()
ui:renderFrame()
ui:onMouseDown(10, 10, "left"); ui:onMouseUp(10, 10, "left")
eq(clicks, 1, "no clicks after destroy (listeners cleared)")
ok(btn._listeners == nil, "destroy clears _listeners")
local ev = btn:emit("click", {})
ok(ev ~= nil, "emit on destroyed node returns event safely")

-- =====================================================================
-- 5. Window double close safe
-- =====================================================================
local wn2 = ui:window({ x = 0, y = 0, width = 50, height = 40 })
wn2:close()
wn2:close()
ok(true, "double close is safe")

-- =====================================================================
-- 6. Style switching
-- =====================================================================
DXUI.setTheme({
    Button = {
        primary = { color = "#3A6EA5", textColor = "#FFFFFF" },
        danger  = { color = "#A53A3A", textColor = "#FFFFFF" },
        default = { color = "#444444", hover = { color = "#888888" } },
    },
})
local st1 = ui:button({ text = "A", style = "primary" })
eq(st1.color, DXUI.resolveColor("#3A6EA5"), "style primary at build")
st1.style = "danger"
eq(st1.color, DXUI.resolveColor("#A53A3A"), "style switched via property")
local st2 = ui:button({ text = "B", style = "primary" })
st2:setStyle("danger")
eq(st2.color, DXUI.resolveColor("#A53A3A"), "setStyle method")
local st3 = ui:button({ text = "C", style = "primary" })
st3.color = 0xFFFF00FF
st3.style = "danger"
eq(st3.color, 0xFFFF00FF, "manual color not overwritten by style switch")
st1.style = "primary"
eq(st1.color, DXUI.resolveColor("#3A6EA5"), "switch back to primary")

-- =====================================================================
-- 7. Edit: drag-select + vertical arrows + escape + clipboard + multi-row selection
-- =====================================================================
local ed = ui:edit({ x = 0, y = 100, width = 200, height = 24 })
ed:setText("Hello World")
ui:renderFrame()
ui:onMouseDown(6, 106, "left")
ui:onCursorMove(6 + 5 * 7, 106)
local sA, sB = ed:getSelection()
eq(sA, 0, "drag-select anchor at mousedown")
eq(sB, 5, "drag-select cursor extended to col5 on move")
ui:onMouseUp(6 + 5 * 7, 106, "left")
local a2, b2 = ed:getSelection()
eq(a2, 0, "selection retained after mouseup")
eq(b2, 5, "selection end preserved")

-- multiline arrows (focus ml first)
local ml = ui:edit({ x = 0, y = 200, width = 150, height = 64, multiline = true })
ml:setText("ab\ncdefg")
ui:renderFrame()
ui:onMouseDown(6, 206, "left")
ui:onMouseUp(6, 206, "left")
ml:setCursor(2) -- row1 col2
ui:onKeyDown("arrow_d", "down", "", nil)
eq(ml:getCursor(), 5, "arrow_d: row2 col2 preserved (goal column)")
ui:onKeyDown("arrow_u", "down", "", nil)
eq(ml:getCursor(), 2, "arrow_u: back to row1 col2")
ml:setCursor(2)
ui:onKeyDown("arrow_d", "down", "shift", nil)
eq(ml:getCursor(), 5, "arrow_d+shift moves cursor")
local xA, xB = ml:getSelection()
ok(xA == 2 and xB == 5, "shift+arrow_d extends selection")

-- escape blurs
ml:setCursor(0)
ui:onMouseDown(6, 206, "left")
ui:onMouseUp(6, 206, "left")
eq(ui:getFocus(), ml, "ml focused before escape")
ui:onKeyDown("escape", "down", "", nil)
eq(ui:getFocus(), nil, "escape blurs edit")

-- clipboard
local ed2 = ui:edit({ x = 200, y = 100, width = 200, height = 24 })
ed2:setText("prefix")
local ed3 = ui:edit({ x = 200, y = 130, width = 200, height = 24 })
ed3:setText("")
ui:renderFrame()
ui:onMouseDown(210, 106, "left"); ui:onMouseUp(210, 106, "left")
ui:onKeyDown("a", "down", "ctrl", nil)
ui:onKeyDown("c", "down", "ctrl", nil)
ui:onMouseDown(210, 136, "left"); ui:onMouseUp(210, 136, "left")
ui:onKeyDown("v", "down", "ctrl", nil)
eq(ed3:getText(), "prefix", "ctrl+c/v within context (internal clipboard)")

-- multi-row selection render
local mr = ui:edit({ x = 0, y = 300, width = 100, height = 64, multiline = true })
mr:setText("ab\ncd\nef")
ui:renderFrame()
ui:onMouseDown(6, 306, "left")
ui:onMouseUp(6, 306, "left")
ui:onKeyDown("a", "down", "ctrl", nil)
calls = {}
ui:renderFrame()
local selCount = 0
for i = 1, #calls do
    if calls[i].kind == "rect" and calls[i].c == 0x663399FF then selCount = selCount + 1 end
end
eq(selCount, 3, "multi-row selection renders 3 per-line rects")

-- =====================================================================
-- 8. Renderer:line clip cull
-- =====================================================================
local pClip = ui:panel({ x = 0, y = 0, width = 100, height = 100, clip = true })
ui:renderFrame()
local listClip = DXUI.RenderList.new()
local rClip = DXUI.Renderer.new(listClip)
rClip.node = pClip
rClip:_loadClip(pClip)
rClip.scaleX, rClip.scaleY, rClip.offsetX, rClip.offsetY = 1, 1, 0, 0
rClip:line(200, 200, 300, 300, 0xFFFFFFFF)
eq(listClip.count, 0, "line fully outside clip is culled")
rClip:line(10, 10, 90, 90, 0xFFFFFFFF)
eq(listClip.count, 1, "line inside clip drawn")

-- =====================================================================
-- 9. resolveColor positional
-- =====================================================================
eq(DXUI.resolveColor({ 255, 0, 0 }), 0xFFFF0000, "positional color table")
eq(DXUI.resolveColor({ r = 0, g = 255, b = 0 }), 0xFF00FF00, "named color table")
eq(DXUI.resolveColor({ 255, 0, 0, 128 }), 0x80FF0000, "positional with alpha")

-- =====================================================================
-- 10. Radio group prune
-- =====================================================================
local ra = ui:radiobutton({ text = "A", group = "pr" })
local rb = ui:radiobutton({ text = "B", group = "pr" })
eq(#ui._radioGroups["pr"], 2, "radio group has 2")
ra:destroy()
ui:renderFrame()
eq(#ui._radioGroups["pr"], 1, "destroyed radio leaves group")

-- =====================================================================
-- 11. EventBus debug pcall
-- =====================================================================
local prevDebug = DXUI.config.debug
DXUI.config.debug = true
local evBtn = ui:button({ x = 500, y = 500, width = 50, height = 20 })
local order = {}
evBtn:on("click", function() table.insert(order, "first"); error("boom") end)
evBtn:on("click", function() table.insert(order, "second") end)
ui:renderFrame()
ui:onMouseDown(510, 510, "left")
ui:onMouseUp(510, 510, "left")
eq(order[1], "first", "first listener ran")
eq(order[2], "second", "second listener ran despite error (debug pcall)")
DXUI.config.debug = prevDebug

-- =====================================================================
-- 12. Button hover survives style switch
-- =====================================================================
local hb = ui:button({ x = 500, y = 400, width = 50, height = 20 })
ui:renderFrame()
ui:onCursorMove(510, 410)
eq(hb.color, DXUI.resolveColor("#888888"), "hover color from current style")
ui:onCursorMove(560, 460)
eq(hb.color, DXUI.resolveColor("#444444"), "leave restores base color")

-- =====================================================================
print(string.format("test_stage12: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
