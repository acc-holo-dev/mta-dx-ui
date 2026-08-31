--[[
    test_render.lua вЂ” DXUI V2 Stage 3

    Tests renderer: rect/text, ordering (layer/zIndex), culling
    (visibility), state dedup (blend mode), idle frames.

    Note: the state cache dedups blend mode ACROSS frames
    (dxSetBlendMode is global MTA state), so blend is called
    once for the whole run, not every frame.
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
-- Test widgets
-- ---------------------------------------------------------------------
local Panel = DXUI.Widget:extend("Panel", {})
function Panel:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

local Label = DXUI.Widget:extend("Label", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
})
function Label:render(renderer)
    renderer:text(self.text, self.worldX, self.worldY, self.width, self.height, self.color)
end

-- ---------------------------------------------------------------------
-- Mock backend
-- ---------------------------------------------------------------------
local calls = {}
local mock = {
    setBlendMode = function(mode) calls[#calls + 1] = { "blend", mode } end,
    drawRoundedRect = function() end,
    drawRect  = function(x, y, w, h, c) calls[#calls + 1] = { "rect", x, y, w, h, c } end,
    drawImage = function(x, y, w, h, t, c) calls[#calls + 1] = { "image", x, y, w, h, t, c } end,
    drawText  = function(t, x, y, w, h, c) calls[#calls + 1] = { "text", t, x, y, w, h, c } end,
    drawLine  = function(x1, y1, x2, y2, c) calls[#calls + 1] = { "line", x1, y1, x2, y2, c } end,
}

local function resetCalls()
    for i = 1, #calls do calls[i] = nil end
end

-- Return only draw calls (no blend), in call order.
local function draws()
    local out = {}
    for i = 1, #calls do
        if calls[i][1] ~= "blend" then out[#out + 1] = calls[i] end
    end
    return out
end

-- ---------------------------------------------------------------------
-- Basic render + ordering by id
-- ---------------------------------------------------------------------
local ctx = DXUI.createContext(mock)

local p1 = Panel:new({ x = 10, y = 20, width = 100, height = 50, color = 0xFFFF0000 })
local p2 = Panel:new({ x = 0, y = 0, width = 10, height = 10, color = 0xFF00FF00 })
ctx:mount(p1)
ctx:mount(p2)

ctx:renderFrame()

eq(calls[1][1], "blend", "blend set first")
local d = draws()
eq(#d, 2, "two rects drawn")
eq(d[1][2], 10, "p1 x (id order)")
eq(d[1][6], 0xFFFF0000, "p1 color")
eq(d[2][2], 0, "p2 x (id order)")

-- ---------------------------------------------------------------------
-- Ordering by zIndex
-- ---------------------------------------------------------------------
resetCalls()
p2.zIndex = 10 -- p2 above p1
ctx:renderFrame()
d = draws()
eq(d[1][2], 10, "p1 drawn first (zIndex 0)")
eq(d[2][2], 0, "p2 drawn second (zIndex 10)")

-- ---------------------------------------------------------------------
-- Ordering by layer
-- ---------------------------------------------------------------------
resetCalls()
p1.zIndex = 0
p2.zIndex = 0
p2.layer = DXUI.LAYER.OVERLAY -- p2 in a higher layer
ctx:renderFrame()
d = draws()
eq(d[1][2], 10, "p1 (BASE) drawn first")
eq(d[2][2], 0, "p2 (OVERLAY) drawn second")

-- ---------------------------------------------------------------------
-- Culling: invisible node skipped
-- ---------------------------------------------------------------------
resetCalls()
p2.layer = DXUI.LAYER.BASE
p1.visible = false
ctx:renderFrame()
d = draws()
eq(#d, 1, "only p2 drawn (p1 culled)")
eq(d[1][2], 0, "p2 drawn, p1 skipped")

-- ---------------------------------------------------------------------
-- Text rendering
-- ---------------------------------------------------------------------
resetCalls()
p1.visible = true
local label = Label:new({ x = 5, y = 5, width = 50, height = 20, text = "Hi", color = 0xFFFFFFFF })
ctx:mount(label)
ctx:renderFrame()
local foundText = false
for i = 1, #calls do
    if calls[i][1] == "text" and calls[i][2] == "Hi" then foundText = true end
end
ok(foundText, "text rendered")

-- ---------------------------------------------------------------------
-- Idle frame: unchanged render list not rebuilt (same calls)
-- ---------------------------------------------------------------------
resetCalls()
ctx:renderFrame()
local idleCount = #calls
local listCount = ctx.renderList.count
resetCalls()
ctx:renderFrame()
eq(#calls, idleCount, "idle frame same draw count")
eq(ctx.renderList.count, listCount, "render list not rebuilt on idle")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_render: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
