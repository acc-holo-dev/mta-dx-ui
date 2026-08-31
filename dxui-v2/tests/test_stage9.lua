--[[
    test_stage9.lua — DXUI V2 Stage 9

    Проверяет: rounded rects (§37, SDF-эффект), outline (§38, T-рёбра),
    image blur/mask (§36/§39, шейдер-effect на item), image section (кроп
    без искажения), timeline-анимации (§51/§52: after/onDone/cancel).

    Эффекты тестируются через ФЕЙКОВЫЕ dx-функции (inject до первого
    использования — effects lazy): dxCreateShader → таблица-хендл,
    dxGetMaterialSize → детерминированный размер.
]]

dofile("loader.lua")

-- Фейковые MTA dx-функции (effects/backend проверяют их наличие)
dxCreateShader = function(code) return { code = code } end
dxSetShaderValue = function(sh, k, v) sh[k] = v end
dxCreateRenderTarget = function(w, h) return { rt = true, w = w, h = h } end
dxGetRenderTarget = function() return nil end
dxSetRenderTarget = function(rt) end
dxDrawRectangle = function() end
dxGetMaterialSize = function(tex)
    if type(tex) == "table" and tex.rt then return tex.w, tex.h end
    return 64, 64 -- все строковые placeholder-текстуры — 64×64
end

local passed, failed = 0, 0
local function ok(cond, name)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name) end
end
local function eq(a, b, name)
    if a == b then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local items = {}
local mock = {
    setBlendMode = function() end,
    drawRect = function(x, y, w, h, c) items[#items + 1] = { kind = "rect", x = x, y = y, w = w, h = h, c = c } end,
    drawRoundedRect = function(x, y, w, h, r, c, eff)
        items[#items + 1] = { kind = "rrect", x = x, y = y, w = w, h = h, r = r, c = c, eff = eff } end,
    drawImage = function(x, y, w, h, tex, c, eff, sec)
        items[#items + 1] = { kind = "image", x = x, y = y, w = w, h = h, tex = tex, c = c, eff = eff, sec = sec } end,
    drawText = function() end,
    drawLine = function() end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- Rounded rect (§37): эффект с SDF-параметрами
-- ---------------------------------------------------------------------
local rp = ui:panel({ x = 0, y = 0, width = 100, height = 50, radius = 10, color = "#2255AA" })
ui:renderFrame()
local rr = nil
for i = 1, #items do if items[i].kind == "rrect" then rr = items[i] end end
ok(rr ~= nil, "rrect: item emitted")
eq(rr.r, 10, "rrect: radius passed")
eq(rr.c, 0xFF2255AA, "rrect: color")
ok(rr.eff ~= nil and rr.eff.shader ~= nil, "rrect: effect with shader")
eq(rr.eff.params.gRadius, 10, "rrect: shader gRadius param")
eq(rr.eff.params.gSize[1], 100, "rrect: shader gSize w")
eq(rr.eff.params.gSize[2], 50, "rrect: shader gSize h")

-- radius=0 → обычный rect (fast path, без шейдера)
rp:destroy() -- убираем rounded-панель из дерева (иначе рендерится дальше)
items = {}
local flat = ui:panel({ x = 0, y = 0, width = 10, height = 10 })
ui:renderFrame()
local sawRrect = false
for i = 1, #items do if items[i].kind == "rrect" then sawRrect = true end end
eq(sawRrect, false, "rrect: radius 0 stays on rect fast path")

-- ---------------------------------------------------------------------
-- Outline (§38): T-раскладка — 4 рёбра без двойных углов
-- ---------------------------------------------------------------------
items = {}
local op = ui:panel({ x = 10, y = 10, width = 40, height = 30,
    outlineWidth = 2, outlineColor = "#00FF00" })
ui:renderFrame()
local edges = {}
for i = 1, #items do
    local it = items[i]
    if it.kind == "rect" and it.c == 0xFF00FF00 then edges[#edges + 1] = it end
end
eq(#edges, 4, "outline: 4 edge rects")
-- top: (x+2, y, 36, 2); left: (x, y, 2, 30) — T-junction (углы не дублируются)
local foundTop, foundLeft = false, false
for i = 1, #edges do
    if edges[i].x == 12 and edges[i].y == 10 and edges[i].w == 36 and edges[i].h == 2 then foundTop = true end
    if edges[i].x == 10 and edges[i].y == 10 and edges[i].w == 2 and edges[i].h == 30 then foundLeft = true end
end
ok(foundTop, "outline: top edge (x+t, y, w-2t, t)")
ok(foundLeft, "outline: left edge (x, y, t, h)")

-- ---------------------------------------------------------------------
-- Image effects: blur (§39) и mask (§36)
-- ---------------------------------------------------------------------
items = {}
local bi = ui:image({ texture = "tex1", x = 0, y = 0, width = 64, height = 64, blur = 3 })
ui:renderFrame()
local bItem = nil
for i = 1, #items do if items[i].kind == "image" and items[i].tex == "tex1" then bItem = items[i] end end
ok(bItem ~= nil and bItem.eff ~= nil, "blur: effect on item")
eq(bItem.eff.params.gBlur, 3, "blur: gBlur param")
eq(bItem.eff.params.gTexelSize[1], 1 / 64, "blur: gTexelSize")

items = {}
local mi = ui:image({ texture = "tex2", x = 0, y = 0, width = 50, height = 50, mask = "maskTex" })
ui:renderFrame()
local mItem = nil
for i = 1, #items do if items[i].kind == "image" and items[i].tex == "tex2" then mItem = items[i] end end
ok(mItem ~= nil and mItem.eff ~= nil, "mask: effect on item (special path)")
eq(mItem.eff.params.gMask, "maskTex", "mask: gMask texture param")

-- обычное изображение — без эффекта (fast path)
items = {}
local pi = ui:image({ texture = "tex3", x = 0, y = 0, width = 10, height = 10 })
ui:renderFrame()
local pItem = nil
for i = 1, #items do if items[i].kind == "image" and items[i].tex == "tex3" then pItem = items[i] end end
eq(pItem.eff, nil, "image: no effect on fast path")

-- ---------------------------------------------------------------------
-- Image section (кроп): clip режет текстуру, а не растягивает
-- ---------------------------------------------------------------------
items = {}
local clipper = ui:panel({ x = 0, y = 0, width = 50, height = 50, clip = true, color = 0xFFFFFFFF })
local cropped = ui:image({ texture = "tex4", x = 0, y = 0, width = 100, height = 50 })
cropped:setParent(clipper)
ui:renderFrame()
local cItem = nil
for i = 1, #items do if items[i].kind == "image" and items[i].tex == "tex4" then cItem = items[i] end end
ok(cItem ~= nil, "section: clipped image drawn")
eq(cItem.w, 50, "section: visible quad width = clip")
eq(cItem.sec[1], 0, "section: sx = 0")
eq(cItem.sec[3], 32, "section: sw = 50/100 * 64 (кроп, не растяжение)")

-- ---------------------------------------------------------------------
-- Timeline-анимации (§51/§52): after / onDone / cancel
-- ---------------------------------------------------------------------
local now = 0
ui:setClock(function() return now end)

local n = ui:panel({ x = 0, y = 0, width = 5, height = 5 })
local doneCount = 0
local anim = n:animate({ x = 50 }, 100, "linear")
anim:after({ x = 100 }, 100, "linear")
anim:onDone(function() doneCount = doneCount + 1 end)

now = 50
ui:renderFrame()
eq(n.x, 25, "timeline: step1 midpoint")
now = 100
ui:renderFrame()
eq(n.x, 50, "timeline: step1 done (snap)")
eq(n:isAnimating(), true, "timeline: step2 started automatically")
now = 200
ui:renderFrame()
eq(n.x, 100, "timeline: step2 done")
eq(doneCount, 1, "timeline: onDone fired once")
eq(n:isAnimating(), false, "timeline: finished")

-- cancel: остановить цепочку, onDone не вызывается
local n2 = ui:panel({ x = 0, y = 0, width = 5, height = 5 })
local done2 = 0
local anim2 = n2:animate({ x = 100 }, 100, "linear")
anim2:after({ x = 200 }, 100, "linear")
anim2:onDone(function() done2 = done2 + 1 end)
now = now + 50
ui:renderFrame()
anim2:cancel()
eq(n2:isAnimating(), false, "cancel: stopped")
now = now + 500
ui:renderFrame()
eq(n2.x, 50, "cancel: keeps current value")
eq(done2, 0, "cancel: onDone NOT fired (cancel ≠ complete)")

-- ---------------------------------------------------------------------
-- Итог
-- ---------------------------------------------------------------------
print(string.format("test_stage9: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end