--[[
    test_stage8.lua — DXUI V2 Stage 8

    Проверяет text engine (§41): measure, wrap (+color-carry, word-break),
    ellipsis, align/valign, shadow; Label/Button integration; design
    resolution scaling (§31–§33): stretch/fit mapping, hit-test, события.
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
-- Text engine: measure (monospace вне MTA)
-- ---------------------------------------------------------------------
local w, h = DXUI.Text.measure("Hello")
eq(w, 35, "measure: 5 chars * 7")
eq(h, 15, "measure: 1 line")

local w2, h2 = DXUI.Text.measure("AB\nCD")
eq(w2, 14, "measure multiline: max 2 chars")
eq(h2, 30, "measure multiline: 2 lines")

-- кэш: повторное измерение — те же значения (без stale)
local w3 = DXUI.Text.measure("Hello")
eq(w3, 35, "measure: cached same value")

-- ---------------------------------------------------------------------
-- Text engine: wrap (word wrap + color-code carry + word break)
-- ---------------------------------------------------------------------
local laid = DXUI.Text.wrap("Hello World", nil, 1, 35)
eq(#laid.lines, 2, "wrap: 2 lines")
eq(laid.lines[1], "Hello", "wrap: line 1")
eq(laid.lines[2], "World", "wrap: line 2")
eq(laid.height, 30, "wrap: height 2*15")

-- перенос активного #RRGGBB-кода на следующую строку
-- "#FF0000Red" = 70px; wrap 70: слово влезает, "text" — нет. Перенесённый
-- код увеличивает monospace-ширину строк → "text"/"here" на отдельных строках.
local laid2 = DXUI.Text.wrap("#FF0000Red text here", nil, 1, 70)
eq(#laid2.lines, 3, "wrap color: 3 lines (code inflates width)")
eq(laid2.lines[1], "#FF0000Red", "wrap color: line 1 keeps coded word")
ok(laid2.lines[2]:match("^#FF0000"), "wrap color: code carried to line 2")
ok(laid2.lines[3]:match("^#FF0000"), "wrap color: code carried to line 3")

-- жёсткий word-break: одно слово шире wrapWidth
local laid3 = DXUI.Text.wrap("AAAAAAAA", nil, 1, 35) -- 8*7=56 > 35
ok(#laid3.lines >= 2, "word-break: long word split")
ok(#laid3.lines[1] <= 5, "word-break: pieces fit width")

-- без wrap — разбивка по \n
local laid4 = DXUI.Text.wrap("AB\nCD", nil, 1, nil)
eq(#laid4.lines, 2, "no-wrap: split by newline")

-- ---------------------------------------------------------------------
-- Text engine: ellipsis
-- ---------------------------------------------------------------------
eq(DXUI.Text.ellipsis("Hello", nil, 1, 35), "Hello", "ellipsis: fits — unchanged")
eq(DXUI.Text.ellipsis("Hello", nil, 1, 28), "H...", "ellipsis: keep 1 char + '...' (28px)")
eq(DXUI.Text.ellipsis("Hello", nil, 1, 21), "...", "ellipsis: nothing fits, only '...' (21px)")

-- ---------------------------------------------------------------------
-- Label: wrap / align / valign / shadow через render items
-- ---------------------------------------------------------------------
local items = {}
local mock = {
    setBlendMode = function() end,
    drawRect = function(x, y, w, h, c) items[#items + 1] = { kind = "rect", x = x, y = y, w = w, h = h, c = c } end,
    drawImage = function() end,
    drawText = function(t, x, y, w, h, c, font, align, valign, sx, sy)
        items[#items + 1] = { kind = "text", text = t, x = x, y = y, w = w, h = h,
            c = c, font = font, align = align, valign = valign, sx = sx, sy = sy }
    end,
    drawLine = function() end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

local lbl = ui:label({ x = 0, y = 0, width = 35, height = 40, text = "Hello World", wrap = true, align = "center" })
ui:renderFrame()
local textItems = {}
for i = 1, #items do
    if items[i].kind == "text" then textItems[#textItems + 1] = items[i] end
end
eq(#textItems, 2, "label wrap: 2 text items")
eq(textItems[1].text, "Hello", "label wrap: item 1")
eq(textItems[2].text, "World", "label wrap: item 2")
eq(textItems[1].align, "center", "label wrap: align passed")
eq(textItems[2].y - textItems[1].y, 15, "label wrap: line step = lineHeight")

-- valign middle: контент 30 в box 40 → offset 5 (ищем item именно этого label)
items = {}
local lblV = ui:label({ x = 0, y = 0, width = 100, height = 40, text = "AB\nCD", valign = "middle" })
ui:renderFrame()
local first = nil
for i = 1, #items do
    if items[i].kind == "text" and items[i].text == "AB" then first = items[i] end
end
eq(first.y, 5, "label valign middle: offset (40-30)/2")

-- shadow: два item на строку (тень + основной), тень смещена
items = {}
local lblS = ui:label({ x = 0, y = 0, width = 100, height = 20, text = "S", shadow = true, shadowColor = "#000000" })
ui:renderFrame()
local shadowItem, mainItem = nil, nil
for i = 1, #items do
    if items[i].kind == "text" then
        if items[i].c == 0xFF000000 then shadowItem = items[i] else mainItem = items[i] end
    end
end
ok(shadowItem ~= nil, "label shadow: shadow item emitted")
eq(shadowItem.x - mainItem.x, 1, "label shadow: offset x")
eq(shadowItem.y - mainItem.y, 1, "label shadow: offset y")

-- ellipsis в label
items = {}
local lblE = ui:label({ x = 0, y = 0, width = 21, height = 15, text = "Hello", ellipsis = true })
ui:renderFrame()
local eItem = nil
for i = 1, #items do if items[i].kind == "text" then eItem = items[i] end end
ok(eItem and eItem.text:match("%.%.%.$"), "label ellipsis: truncated with ...")

-- Button: центрированный текст по умолчанию
items = {}
local b = ui:button({ x = 0, y = 0, width = 100, height = 30, text = "OK" })
ui:renderFrame()
local btnText = nil
for i = 1, #items do
    if items[i].kind == "text" then btnText = items[i] end
end
eq(btnText.align, "center", "button: text centered by default")
eq(btnText.valign, "middle", "button: text middle by default")

-- ---------------------------------------------------------------------
-- Design resolution: stretch (§31–§33)
-- ---------------------------------------------------------------------
DXUI.setDesignResolution(400, 300) -- экран 800x600 → scale 2
ui:setScreenSize(800, 600)

local node = ui:panel({ x = 10, y = 20, width = 50, height = 25, color = 0xFFFF0000 })
items = {}
ui:renderFrame()
local rectItem = nil
for i = 1, #items do
    if items[i].kind == "rect" and items[i].c == 0xFFFF0000 then rectItem = items[i] end
end
eq(rectItem.x, 20, "design stretch: x scaled 10*2")
eq(rectItem.y, 40, "design stretch: y scaled 20*2")
eq(rectItem.w, 100, "design stretch: w scaled 50*2")
eq(rectItem.h, 50, "design stretch: h scaled 25*2")

-- hit-test: клик по экрану → design-координаты → узел найден
-- узел (10..60, 20..45); screen (30,60) → design (15,30) — внутри
local clicked = false
node:on("click", function(e) clicked = true end)
ui:onMouseDown(30, 60, "left")
ui:onMouseUp(30, 60, "left")
eq(clicked, true, "design: click hits scaled node")

-- события несут design-координаты (согласованы с worldX)
local evX = nil
node:on("mousedown", function(e) evX = e.x end)
ui:onMouseDown(30, 60, "left")
eq(evX, 15, "design: event x in design space (30/2)")

-- layout в design-пространстве: root-children получают design size
local relNode = ui:panel({ layoutMode = "relative", x = 0.5, y = 0.5, width = 10, height = 10 })
ui:renderFrame()
eq(relNode.worldX, 200, "design: relative 0.5 of 400")

-- ---------------------------------------------------------------------
-- Design resolution: fit (letterbox)
-- ---------------------------------------------------------------------
DXUI.setDesignResolution(300, 300, "fit") -- экран 800x600: s=2, offX=(800-600)/2=100
ui:setScreenSize(800, 600)
items = {}
local fitNode = ui:panel({ x = 10, y = 10, width = 20, height = 20, color = 0xFF00FF00 })
ui:renderFrame()
local fitRect = nil
for i = 1, #items do
    if items[i].kind == "rect" and items[i].c == 0xFF00FF00 then fitRect = items[i] end
end
eq(fitRect.x, 120, "design fit: x = 10*2 + offset 100")
eq(fitRect.w, 40, "design fit: w = 20*2")

-- hit-test через letterbox-offset
local fitClicked = false
fitNode:on("click", function() fitClicked = true end)
ui:onMouseDown(130, 30, "left") -- design ((130-100)/2, (30-0)/2) = (15,15) внутри
ui:onMouseUp(130, 30, "left")
eq(fitClicked, true, "design fit: click through letterbox offset")

-- ---------------------------------------------------------------------
-- Итог
-- ---------------------------------------------------------------------
print(string.format("test_stage8: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end