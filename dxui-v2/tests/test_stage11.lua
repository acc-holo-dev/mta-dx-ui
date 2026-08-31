--[[
    test_stage11.lua — DXUI V2 Stage 11

    Проверяет: clipMode="rt" (§35 expensive path — поддерево в RT: pixel-
    perfect clip + true group-opacity §34 + blur на контейнер), вложенные
    RT-группы, fallback без RT; Edit↔text-engine (§41): курсор/клик через
    measure (фейковый dxGetTextSize — 9px/символ, отличается от monospace 7).
]]

dofile("loader.lua")

-- Фейковые dx-функции
dxCreateShader = function(code) return { code = code } end
dxSetShaderValue = function(sh, k, v) sh[k] = v end
dxCreateRenderTarget = function(w, h) return { rt = true, w = w, h = h } end
dxGetRenderTarget = function() return nil end
dxSetRenderTarget = function(rt) end
dxDrawRectangle = function() end
-- ФЕЙКОВЫЙ measurement: 9px/символ, 18px/строка (≠ monospace 7/15 —
-- доказывает, что Edit использует text engine, а не константу)
dxGetTextSize = function(s, scale, font) return #s * 9, 18 end

local passed, failed = 0, 0
local function ok(cond, name)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name) end
end
local function eq(a, b, name)
    if a == b then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

-- Mock backend с RT-group-семантикой (offset-стек, как backend_mta)
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
    drawRoundedRect = function() end,
    drawImage = function() end,
    drawText = function(t, x, y, w, h, c)
        x, y = adjust(x, y)
        calls[#calls + 1] = { kind = "text", t = t, x = x, y = y } end,
    drawLine = function() end,
    beginGroup = function(x, y, w, h)
        groupStack[#groupStack + 1] = { x = x, y = y, w = w, h = h }
        calls[#calls + 1] = { kind = "beginGroup", x = x, y = y, w = w, h = h }
        return true
    end,
    endGroup = function(x, y, w, h, eff, alpha)
        table.remove(groupStack)
        calls[#calls + 1] = { kind = "endGroup", x = x, y = y, eff = eff, alpha = alpha } end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- clipMode="rt": поддерево композитится (дети ВНУТРИ группы)
-- ---------------------------------------------------------------------
local rtPanel = ui:panel({ x = 100, y = 100, width = 200, height = 150,
    color = 0xFF203040, clipMode = "rt" })
local inner1 = ui:panel({ x = 0, y = 0, width = 50, height = 20, color = 0xFFFF0000 })
local inner2 = ui:panel({ x = 60, y = 0, width = 30, height = 20, color = 0xFF00FF00 })
inner1:setParent(rtPanel)
inner2:setParent(rtPanel)

calls = {}
ui:renderFrame()

-- группа создана; дети НЕ в основном списке — они ВНУТРИ группы (локальные)
local bg, begins = 0, 0
local innerRed, innerGreen = nil, nil
for i = 1, #calls do
    local c = calls[i]
    if c.kind == "beginGroup" then begins = begins + 1 end
    if c.kind == "rect" and c.w == 200 then bg = bg + 1 end
    if c.kind == "rect" and c.w == 50 and c.c == 0xFFFF0000 then innerRed = c end
    if c.kind == "rect" and c.w == 30 and c.c == 0xFF00FF00 then innerGreen = c end
end
eq(begins, 1, "rtclip: one group emitted")
ok(bg >= 1, "rtclip: own rect inside group")

-- группа с alpha=1 (без opacity) и БЕЗ эффекта (просто pixel-perfect clip)
local eg = nil
for i = 1, #calls do if calls[i].kind == "endGroup" then eg = calls[i] end end
ok(eg ~= nil, "rtclip: endGroup called")
eq(eg.eff, nil, "rtclip: no effect (pure clip mode)")
eq(eg.alpha, 1, "rtclip: alpha 1 (no group opacity set)")

-- children внутри группы: локальные координаты относительно группы.
-- inner1: local x=0 → world 100; group origin 100 → adjusted 0 (offset работает)
ok(innerRed ~= nil, "rtclip: inner child rendered inside group")
if innerRed then
    eq(innerRed.x, 0, "rtclip: child local x (world 100 - origin 100 = 0)")
end
-- inner2: local x=60 → world 160 - 100 = 60
if innerGreen then
    eq(innerGreen.x, 60, "rtclip: second child local x = 60")
end

-- порядок: фон группы ПЕРЕД детьми
local bgIdx, redIdx = 0, 0
for i = 1, #calls do
    if calls[i].kind == "rect" and calls[i].w == 200 then bgIdx = i end
    if calls[i].kind == "rect" and calls[i].w == 50 and calls[i].c == 0xFFFF0000 then redIdx = i end
end
ok(bgIdx > 0 and redIdx > bgIdx, "rtclip: own body under children")

-- ---------------------------------------------------------------------
-- TRUE group-opacity (§34): opacity на квад, дети не пере-модулируются
-- ---------------------------------------------------------------------
rtPanel.opacity = 0.5
calls = {}
ui:renderFrame()
local eg2 = nil
local redItem = nil
for i = 1, #calls do
    if calls[i].kind == "endGroup" then eg2 = calls[i] end
    if calls[i].kind == "rect" and calls[i].c == 0xFFFF0000 then redItem = calls[i] end
end
eq(eg2.alpha, 0.5, "group-opacity: alpha on quad (0.5)")
eq(redItem.c, 0xFFFF0000, "group-opacity: children NOT re-modulated (full color inside)")

-- ---------------------------------------------------------------------
-- clipMode="rt" + blur: эффект на ВЕСЬ композит (контейнер)
-- ---------------------------------------------------------------------
rtPanel.opacity = 1
rtPanel.blur = 3
calls = {}
ui:renderFrame()
local eg3 = nil
for i = 1, #calls do if calls[i].kind == "endGroup" then eg3 = calls[i] end end
ok(eg3.eff ~= nil, "rtclip+blur: effect on whole composite")
eq(eg3.eff.params.gBlur, 3, "rtclip+blur: strength param")

-- ---------------------------------------------------------------------
-- Вложенные RT-группы (rt-узел внутри rt-поддерева)
-- ---------------------------------------------------------------------
rtPanel.blur = 0
local nested = ui:panel({ x = 10, y = 10, width = 60, height = 60, color = 0xFF111111, clipMode = "rt" })
nested:setParent(rtPanel)
local deepChild = ui:panel({ x = 0, y = 0, width = 10, height = 10, color = 0xFF0000FF })
deepChild:setParent(nested)

calls = {}
ui:renderFrame()
local beginCount, endCount = 0, 0
local deep = nil
for i = 1, #calls do
    if calls[i].kind == "beginGroup" then beginCount = beginCount + 1 end
    if calls[i].kind == "endGroup" then endCount = endCount + 1 end
    if calls[i].kind == "rect" and calls[i].c == 0xFF0000FF then deep = calls[i] end
end
eq(beginCount, 2, "nested rtclip: two groups (outer + inner)")
eq(endCount, 2, "nested rtclip: both groups closed")
ok(deep ~= nil, "nested rtclip: deepest child rendered")

-- ---------------------------------------------------------------------
-- Fallback: без RT → обычный рендер поддерева (geometric clip).
-- NB: _set-guard — нужно РЕАЛЬНОЕ изменение, чтобы был rebuild.
-- ---------------------------------------------------------------------
dxCreateRenderTarget = nil
rtPanel.visible = false -- инвалидация → rebuild (уже без RT)
rtPanel.visible = true  -- и обратно
calls = {}
ui:renderFrame()
local sawGroup = false
local sawDeep = false
for i = 1, #calls do
    if calls[i].kind == "beginGroup" then sawGroup = true end
    if calls[i].kind == "rect" and calls[i].c == 0xFF0000FF then sawDeep = true end
end
eq(sawGroup, false, "rtclip fallback: no group without RT")
eq(sawDeep, true, "rtclip fallback: subtree rendered flat (graceful)")
dxCreateRenderTarget = function(w, h) return { rt = true, w = w, h = h } end

-- ---------------------------------------------------------------------
-- Edit↔text-engine (§41): курсор через measure (9px/символ фейка)
-- ---------------------------------------------------------------------
local edit = ui:edit({ x = 0, y = 400, width = 200, height = 24 })
edit:setText("Hello")
ui:renderFrame()
ui:onMouseDown(0 + 4 + 18, 400 + 6, "left") -- x = pad + 2*9 → колонка 2
eq(edit:getCursor(), 2, "edit: click maps col via text engine (9px/char)")

-- курсор-рект на позиции measure: col 2 → x = 4 + 18 = 22
edit:setCursor(3)
calls = {}
ui:renderFrame()
local cur = nil
for i = 1, #calls do
    if calls[i].kind == "rect" and calls[i].w == 2 then cur = calls[i] end
end
ok(cur ~= nil, "edit: cursor rect rendered")
eq(cur.x, 0 + 4 + 3 * 9, "edit: cursor x = pad + measure(prefix) (4+27)")

-- ---------------------------------------------------------------------
-- Итог
-- ---------------------------------------------------------------------
print(string.format("test_stage11: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end