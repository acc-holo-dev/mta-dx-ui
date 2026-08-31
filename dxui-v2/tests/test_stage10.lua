--[[
    test_stage10.lua — DXUI V2 Stage 10

    Проверяет: opacity (§34 — inherited alpha-модуляция: значения, наследование,
    нулевой early-out, анимация), RT effect layer (§35/§39 — node-level
    blur/mask через rtgroup: эмиссия, offset-композитинг, fallback без RT).
]]

dofile("loader.lua")

-- Фейковые dx-функции (effects lazy — inject до первого использования)
dxCreateShader = function(code) return { code = code } end
dxSetShaderValue = function(sh, k, v) sh[k] = v end
dxCreateRenderTarget = function(w, h) return { rt = true, w = w, h = h } end
dxGetRenderTarget = function() return nil end
dxSetRenderTarget = function(rt) end
dxDrawRectangle = function() end

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
-- Mock backend с RT-group-семантикой (зеркалит backend_mta: offset-стек)
-- ---------------------------------------------------------------------
local calls = {}
local groupStack = {}
local function adjust(x, y)
    local n = #groupStack
    if n > 0 then
        local g = groupStack[n]
        return x - g.x, y - g.y
    end
    return x, y
end
local mock = {
    setBlendMode = function() end,
    drawRect = function(x, y, w, h, c)
        x, y = adjust(x, y)
        calls[#calls + 1] = { kind = "rect", x = x, y = y, w = w, h = h, c = c } end,
    drawRoundedRect = function(x, y, w, h, r, c, eff)
        x, y = adjust(x, y)
        calls[#calls + 1] = { kind = "rrect", x = x, y = y, w = w, h = h, r = r, c = c } end,
    drawImage = function(x, y, w, h, t, c, eff, sec)
        x, y = adjust(x, y)
        calls[#calls + 1] = { kind = "image", x = x, y = y, w = w, h = h } end,
    drawText = function(t, x, y, w, h, c)
        x, y = adjust(x, y)
        calls[#calls + 1] = { kind = "text", x = x, y = y } end,
    drawLine = function() end,
    beginGroup = function(x, y, w, h)
        groupStack[#groupStack + 1] = { x = x, y = y, w = w, h = h }
        calls[#calls + 1] = { kind = "beginGroup", x = x, y = y, w = w, h = h }
        return true
    end,
    endGroup = function(x, y, w, h, eff)
        table.remove(groupStack)
        calls[#calls + 1] = { kind = "endGroup", x = x, y = y, eff = eff }
    end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- Opacity (§34): alpha-модуляция
-- ---------------------------------------------------------------------
local p = ui:panel({ x = 0, y = 0, width = 50, height = 20, color = 0xFFFF0000 })
p.opacity = 0.5
calls = {}
ui:renderFrame()
local op = nil
for i = 1, #calls do if calls[i].kind == "rect" and calls[i].w == 50 then op = calls[i] end end
eq(op.c, 0x7FFF0000, "opacity 0.5: alpha 255 -> 127")

-- наследование: parent 0.5 × child 0.5 = 0.25
local child = ui:panel({ x = 0, y = 0, width = 10, height = 5, color = 0xFF00FF00 })
child:setParent(p)
child.opacity = 0.5
calls = {}
ui:renderFrame()
local opCh = nil
for i = 1, #calls do if calls[i].kind == "rect" and calls[i].w == 10 then opCh = calls[i] end end
eq(opCh.c, 0x3F00FF00, "opacity inheritance: 0.5*0.5 -> alpha 63")

-- opacity 0: узел полностью прозрачен — items не эмитятся (early-out)
child.opacity = 0
calls = {}
ui:renderFrame()
local sawChild = false
for i = 1, #calls do if calls[i].kind == "rect" and calls[i].w == 10 then sawChild = true end end
eq(sawChild, false, "opacity 0: no items emitted (zero draw)")

-- анимация opacity: середина пути модулирует цвет
local now = 0
ui:setClock(function() return now end)
child.opacity = 1
calls = {}
ui:renderFrame() -- очистим
local animP = ui:panel({ x = 0, y = 0, width = 8, height = 8, color = 0xFF0000FF })
calls = {}
animP:animate({ opacity = 0 }, 100, "linear")
now = 50
ui:renderFrame()
local animItem = nil
for i = 1, #calls do if calls[i].kind == "rect" and calls[i].w == 8 then animItem = calls[i] end end
eq(animItem.c, 0x7F0000FF, "animate opacity: mid 0.5 modulates alpha")

-- ---------------------------------------------------------------------
-- RT effect layer (§35/§39): node-level blur на Panel
-- ---------------------------------------------------------------------
local bp = ui:panel({ x = 100, y = 100, width = 80, height = 40, color = 0xFF204060, blur = 2 })
calls = {}
ui:renderFrame()

-- эмиссия: rtgroup c blur-эффектом, внутри — rect панели
local group = nil
for i = 1, #calls do if calls[i].kind == "beginGroup" then group = calls[i] end end
ok(group ~= nil, "rtgroup: beginGroup called")
eq(group.x, 100, "rtgroup: bounds x")
eq(group.w, 80, "rtgroup: bounds w")

-- содержимое рисуется в ЛОКАЛЬНЫХ координатах (offset вычтен)
local inner = nil
for i = 1, #calls do
    if calls[i].kind == "rect" and calls[i].w == 80 then inner = calls[i] end
end
ok(inner ~= nil, "rtgroup: panel rect drawn inside group")
eq(inner.x, 0, "rtgroup: content offset to local (x=0)")
eq(inner.y, 0, "rtgroup: content offset to local (y=0)")

-- endGroup с blur-эффектом
local eg = nil
for i = 1, #calls do if calls[i].kind == "endGroup" then eg = calls[i] end end
ok(eg ~= nil and eg.eff ~= nil, "rtgroup: endGroup with effect")
eq(eg.eff.params.gBlur, 2, "rtgroup: blur strength param")
eq(eg.eff.params.gTexelSize[1], 1 / 80, "rtgroup: gTexelSize from bounds")

-- порядок: begin → содержимое → end
local order = {}
for i = 1, #calls do order[#order + 1] = calls[i].kind end
ok(order[1] == "beginGroup" or (order[1] == "blend" and order[2] == "beginGroup")
    or order[#order] == "endGroup", "rtgroup: begin..end sequence present")

-- ---------------------------------------------------------------------
-- RT mask на Panel (§36 для rect-виджетов)
-- ---------------------------------------------------------------------
local mp = ui:panel({ x = 0, y = 200, width = 60, height = 30, color = 0xFF888888, mask = "softMask" })
calls = {}
ui:renderFrame()
local meg = nil
for i = 1, #calls do if calls[i].kind == "endGroup" then meg = calls[i] end end
ok(meg ~= nil and meg.eff ~= nil, "rtgroup mask: emitted")
eq(meg.eff.params.gMask, "softMask", "rtgroup mask: gMask param")

-- mask приоритетнее blur
local both = ui:panel({ x = 0, y = 300, width = 40, height = 20, blur = 5, mask = "m2" })
calls = {}
ui:renderFrame()
local beg = nil
for i = 1, #calls do if calls[i].kind == "endGroup" then beg = calls[i] end end
eq(beg.eff.params.gMask, "m2", "rtgroup: mask wins over blur")

-- ---------------------------------------------------------------------
-- Fallback: RT недоступен → обычный рендер без группы
-- ---------------------------------------------------------------------
dxCreateRenderTarget = nil -- «забираем» RT (canGroup → false)
local fb = ui:panel({ x = 0, y = 400, width = 30, height = 10, color = 0xFF123456, blur = 3 })
calls = {}
ui:renderFrame()
local sawGroup = false
local sawPlain = false
for i = 1, #calls do
    if calls[i].kind == "beginGroup" then sawGroup = true end
    if calls[i].kind == "rect" and calls[i].w == 30 then sawPlain = true end
end
eq(sawGroup, false, "fallback: no rtgroup without RT")
eq(sawPlain, true, "fallback: plain rect rendered (graceful)")

-- ---------------------------------------------------------------------
-- Итог
-- ---------------------------------------------------------------------
print(string.format("test_stage10: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end