--[[
    test_stage7b.lua — DXUI V2 Stage 7b

    Tests: resources (cache), animation (tick/easing/stop), theme (defaults,
    hover, inline), stretch/autosize layout, font pipeline, _set-guard.
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

local mock = { setBlendMode = function() end, drawRect = function() end,
    drawRoundedRect = function() end, drawImage = function() end,
    drawText = function() end, drawLine = function() end,
    beginGroup = function() return false end, endGroup = function() end }

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- fake clock for animation
local now = 0
ui:setClock(function() return now end)

-- ---------------------------------------------------------------------
-- Resources: cache
-- ---------------------------------------------------------------------
local t1 = DXUI.texture("icons/a.png")
local t2 = DXUI.texture("icons/a.png")
eq(t1, t2, "texture cached (same handle)")
local t3 = DXUI.texture("icons/b.png")
ok(t1 ~= t3, "different path - different handle")

local f1 = DXUI.font("Roboto", 12)
local f2 = DXUI.font("Roboto", 12)
eq(f1, f2, "font cached")
local f3 = DXUI.font("Roboto", 14)
ok(f1 == nil or f1 ~= f3, "different size - different font")

DXUI.releaseResources()
local t4 = DXUI.texture("icons/a.png")
ok(t4 ~= nil, "release + re-create works")

-- ---------------------------------------------------------------------
-- Animation: tick, easing, snap, stop
-- ---------------------------------------------------------------------
local n = ui:panel({ x = 0, y = 0, width = 10, height = 10 })
eq(n.x, 0, "anim: start x")

n:animate({ x = 100 }, 100, "linear")
ok(n:isAnimating(), "anim: isAnimating true")
ui:renderFrame() -- t = 0 → x = 0
eq(n.x, 0, "anim: t=0 no move")

now = 50
ui:renderFrame() -- t = 0.5 → x = 50
eq(n.x, 50, "anim: linear midpoint = 50")

now = 100
ui:renderFrame() -- t >= 1 → snap 100, animation cleared
eq(n.x, 100, "anim: snap to target")
eq(n:isAnimating(), false, "anim: finished, not animating")

-- opacity — float via mutation layer
local n2 = ui:panel({ x = 0, y = 0, width = 5, height = 5 })
n2:animate({ opacity = 0 }, 100, "linear")
now = now + 50
ui:renderFrame()
eq(n2.opacity, 0.5, "anim: opacity midpoint 0.5")
now = now + 50
ui:renderFrame()
eq(n2.opacity, 0, "anim: opacity snap 0")

-- interrupt: re-animate from current value
local n3 = ui:panel({ x = 0, y = 0, width = 5, height = 5 })
n3:animate({ x = 100 }, 100, "linear")
now = now + 50
ui:renderFrame()
eq(n3.x, 50, "anim: interrupt at 50")
n3:animate({ x = 200 }, 100, "linear") -- from = 50 (current)
now = now + 100
ui:renderFrame()
eq(n3.x, 200, "anim: re-animate from current")

-- stopAnimations: keeps current value
local n4 = ui:panel({ x = 0, y = 0, width = 5, height = 5 })
n4:animate({ x = 100 }, 100, "linear")
now = now + 25
ui:renderFrame()
n4:stopAnimations()
eq(n4:isAnimating(), false, "anim: stopped")
eq(n4.x, 25, "anim: stopped keeps current value")

-- cancel() is scoped to ITS OWN chain — other handles on the same node
-- keep running and their onDone still fires (regression: was node-wide stop)
local n5 = ui:panel({ x = 0, y = 0, width = 5, height = 5 })
local h1 = n5:animate({ x = 100 }, 100, "linear")
local h2 = n5:animate({ y = 100 }, 100, "linear")
local done1, done2 = false, false
h1:onDone(function() done1 = true end)
h2:onDone(function() done2 = true end)
h1:cancel()
now = now + 100
ui:renderFrame()
eq(n5.y, 100, "anim: cancel doesn't stop the other handle (y completed)")
eq(done2, true, "anim: other handle's onDone fired")
eq(done1, false, "anim: cancelled chain's onDone suppressed")

-- ---------------------------------------------------------------------
-- _set-guard: same value — no invalidation
-- ---------------------------------------------------------------------
local g = ui:panel({ x = 5, y = 0, width = 10, height = 10 })
ui:renderFrame() -- clear dirty
g.x = 5 -- same value
ok(g._dirty[DXUI.DIRTY.LAYOUT] ~= true, "set-guard: same value no invalidate")
g.x = 6
ok(g._dirty[DXUI.DIRTY.LAYOUT] == true, "set-guard: new value invalidates")

-- ---------------------------------------------------------------------
-- Stretch: size follows parent minus margin
-- ---------------------------------------------------------------------
local parentP = ui:panel({ x = 0, y = 0, width = 200, height = 100 })
local stretched = ui:panel({ layoutMode = "stretch", margin = 5 })
stretched:setParent(parentP)
ui:renderFrame()
eq(stretched.width, 190, "stretch: width = 200 - 5*2")
eq(stretched.height, 90, "stretch: height = 100 - 5*2")
eq(stretched.worldX, 5, "stretch: x = margin")
eq(stretched.worldY, 5, "stretch: y = margin")

-- parent grows — child follows (no loops: guard)
parentP.width = 300
ui:renderFrame()
eq(stretched.width, 290, "stretch: follows parent resize")
ui:renderFrame() -- second frame — no invalidations (converged)
eq(stretched.width, 290, "stretch: converged, no loop")

-- ---------------------------------------------------------------------
-- Autosize: size from content
-- ---------------------------------------------------------------------
-- Label from text (monospace estimate outside MTA)
local lbl = ui:label({ text = "Hello", autoSize = true })
ui:renderFrame()
eq(lbl.width, 35, "autosize label: 5 chars * 7")
eq(lbl.height, 15, "autosize label: 1 line * 15")

-- multiline label
local lbl2 = ui:label({ text = "AB\nCD", autoSize = true })
ui:renderFrame()
eq(lbl2.width, 14, "autosize label multiline: 2 chars * 7")
eq(lbl2.height, 30, "autosize label multiline: 2 lines * 15")

-- Panel from children
local autoP = ui:panel({ autoSize = true })
local c1 = ui:panel({ x = 10, y = 10, width = 50, height = 20 })
local c2 = ui:panel({ x = 0, y = 0, width = 5, height = 5 })
c1:setParent(autoP)
c2:setParent(autoP)
ui:renderFrame()
eq(autoP.width, 60, "autosize panel: child extent 10+50")
eq(autoP.height, 30, "autosize panel: child extent 10+20")

-- ---------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------
DXUI.setTheme({
    Button = {
        default = { color = "#111111", textColor = "#EEEEEE" },
        primary = { color = "#3A6EA5", hover = { color = "#5588BB" } },
    },
    Panel = {
        default = { color = "#222222" },
    },
})

local themedBtn = ui:button({ text = "OK" })
eq(themedBtn.color, 0xFF111111, "theme: default color applied")
eq(themedBtn.textColor, 0xFFEEEEEE, "theme: default textColor applied")

local primaryBtn = ui:button({ text = "Save", style = "primary" })
eq(primaryBtn.color, 0xFF3A6EA5, "theme: primary color")

-- explicit props win over theme
local explicitBtn = ui:button({ text = "X", color = "#FF0000" })
eq(explicitBtn.color, 0xFFFF0000, "theme: explicit prop wins")

-- inline style (table)
local inlineBtn = ui:button({ style = { color = "#00FF00" } })
eq(inlineBtn.color, 0xFF00FF00, "theme: inline style table")

-- hover state
local hb = ui:button({ text = "H", style = "primary" })
local hoverCalls = {}
local savedDrawText = mock.drawText
mock.drawText = function(t, x, y, w, h, c, font) hoverCalls[#hoverCalls + 1] = { t, font } end
ui:renderFrame()
ui:onCursorMove(hb.worldX + 2, hb.worldY + 2) -- enter
eq(hb.color, 0xFF5588BB, "theme: hover color on mouseenter")
ui:onCursorMove(700, 700) -- leave
eq(hb.color, 0xFF3A6EA5, "theme: base color on mouseleave")
mock.drawText = savedDrawText

-- Panel theme
local themedPanel = ui:panel({})
eq(themedPanel.color, 0xFF222222, "theme: panel default color")

-- ---------------------------------------------------------------------
-- Font pipeline: renderer:text with font → backend drawText with font
-- ---------------------------------------------------------------------
local fontCalls = {}
local savedDT = mock.drawText
mock.drawText = function(t, x, y, w, h, c, font) fontCalls[#fontCalls + 1] = font end
local fl = ui:label({ text = "F", font = "fake_font_handle" })
ui:renderFrame()
eq(fontCalls[#fontCalls], "fake_font_handle", "font: passed through to backend")
mock.drawText = savedDT

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_stage7b: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end