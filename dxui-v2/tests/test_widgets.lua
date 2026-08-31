--[[
    test_widgets.lua — DXUI V2 Stage 6

    Проверяет базовые виджеты: panel, label, button, image, window
    (composite), цвет, declarative children, parent-scoped builders.
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
    drawImage = function(x, y, w, h, t, c) calls[#calls + 1] = { "image", x, y, w, h, t, c } end,
    drawText  = function(t, x, y, w, h, c) calls[#calls + 1] = { "text", t, x, y, w, h, c } end,
    drawLine  = function() end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- Panel + цвет
-- ---------------------------------------------------------------------
local p = ui:panel({ x = 10, y = 20, width = 100, height = 50, color = "#FF0000" })
eq(p.color, 0xFFFF0000, "color string resolved to packed")
eq(p.width, 100, "panel width")
eq(p.parent, ui.root, "builder auto-mounts to root")

-- ---------------------------------------------------------------------
-- Label (не интерактивен)
-- ---------------------------------------------------------------------
local label = ui:label({ text = "Hello", x = 0, y = 0 })
eq(label.text, "Hello", "label text")
eq(label.enabled, false, "label non-interactive by default")

-- ---------------------------------------------------------------------
-- Button + onClick
-- ---------------------------------------------------------------------
local clicked = false
local btn = ui:button({ x = 10, y = 10, width = 100, height = 30, text = "OK",
    onClick = function() clicked = true end })
eq(btn.text, "OK", "button text")
eq(btn.enabled, true, "button interactive")

ui:renderFrame()
ui:onMouseDown(50, 20, "left")
ui:onMouseUp(50, 20, "left")
eq(clicked, true, "button onClick fires on click")

-- ---------------------------------------------------------------------
-- Image
-- ---------------------------------------------------------------------
local img = ui:image({ texture = "fake_tex", width = 32, height = 32 })
eq(img.texture, "fake_tex", "image texture")
eq(img.enabled, false, "image non-interactive by default")

-- ---------------------------------------------------------------------
-- Window (composite): title + close button + close event
-- ---------------------------------------------------------------------
local win = ui:window({ title = "Settings", closable = true, x = 100, y = 100 })
eq(win.title, "Settings", "window title")
ok(win._closeButton ~= nil, "close button created")

-- close button — ребёнок окна, привязан к правому верхнему углу
ui:renderFrame()
local cb = win._closeButton
eq(cb.parent, win, "close button is child of window")
eq(cb.worldX, 100 + 320 - 16, "close button at top-right (relative+anchor TR)")

-- close() уничтожает окно
win:close()
eq(win.destroyed, true, "window close destroys")

-- preventable close
local win2 = ui:window({ title = "Keep" })
win2:on("close", function(e) e:preventDefault() end)
win2:close()
eq(win2.destroyed, false, "preventDefault cancels close")

-- ---------------------------------------------------------------------
-- Declarative children
-- ---------------------------------------------------------------------
local win3 = ui:window({
    children = {
        ui:label({ text = "A" }),
        ui:button({ text = "B" }),
    },
})
eq(#win3.children, 2, "declarative children attached")

-- ---------------------------------------------------------------------
-- Parent-scoped builder: window:label(...)
-- ---------------------------------------------------------------------
local win4 = ui:window({})
local childLabel = win4:label({ text = "Hi" })
eq(childLabel.parent, win4, "parent-scoped builder attaches child")

-- ---------------------------------------------------------------------
-- Итог
-- ---------------------------------------------------------------------
print(string.format("test_widgets: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
