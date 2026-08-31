--[[
    test_layout.lua — DXUI V2 Stage 5

    Tests layout: absolute, relative, center, anchor (9 points), margin,
    padding, nesting.
]]

dofile("loader.lua")

local passed, failed = 0, 0

local function eq(a, b, name)
    if a == b then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local function near(a, b, name)
    if math.abs(a - b) < 0.001 then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local Panel = DXUI.Widget:extend("Panel", {})
function Panel:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

local ctx = DXUI.createContext({
    setBlendMode = function() end, drawRect = function() end,
    drawImage = function() end, drawText = function() end, drawLine = function() end,
})
ctx:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- Absolute (default)
-- ---------------------------------------------------------------------
local abs = Panel:new({ x = 10, y = 20, width = 100, height = 50 })
ctx:mount(abs)
ctx:renderFrame()
eq(abs.worldX, 10, "absolute worldX")
eq(abs.worldY, 20, "absolute worldY")

-- ---------------------------------------------------------------------
-- Relative (fraction 0..1 of parent size = screen for root)
-- ---------------------------------------------------------------------
local rel = Panel:new({ x = 0.5, y = 0.5, width = 10, height = 10, layoutMode = "relative" })
ctx:mount(rel)
ctx:renderFrame()
eq(rel.worldX, 400, "relative worldX (0.5 * 800)")
eq(rel.worldY, 300, "relative worldY (0.5 * 600)")

-- ---------------------------------------------------------------------
-- Center
-- ---------------------------------------------------------------------
local centered = Panel:new({ width = 20, height = 10, layoutMode = "center" })
ctx:mount(centered)
ctx:renderFrame()
eq(centered.worldX, 390, "center worldX ((800-20)/2)")
eq(centered.worldY, 295, "center worldY ((600-10)/2)")

-- ---------------------------------------------------------------------
-- Anchor (9 points)
-- ---------------------------------------------------------------------
local tr = Panel:new({ x = 100, y = 0, width = 20, height = 10, anchor = "tr" })
ctx:mount(tr)
ctx:renderFrame()
eq(tr.worldX, 80, "anchor TR worldX (100 - 20)")
eq(tr.worldY, 0, "anchor TR worldY")

local mc = Panel:new({ x = 100, y = 100, width = 20, height = 10, anchor = "mc" })
ctx:mount(mc)
ctx:renderFrame()
eq(mc.worldX, 90, "anchor MC worldX (100 - 10)")
eq(mc.worldY, 95, "anchor MC worldY (100 - 5)")

-- ---------------------------------------------------------------------
-- Margin
-- ---------------------------------------------------------------------
local margined = Panel:new({ x = 0, y = 0, width = 10, height = 10, margin = { left = 5, top = 10 } })
ctx:mount(margined)
ctx:renderFrame()
eq(margined.worldX, 5, "margin left")
eq(margined.worldY, 10, "margin top")

-- ---------------------------------------------------------------------
-- Padding (shifts children)
-- ---------------------------------------------------------------------
local padded = Panel:new({ x = 0, y = 0, width = 100, height = 100, padding = { left = 10, top = 20 } })
ctx:mount(padded)
local padChild = Panel:new({ x = 0, y = 0, width = 5, height = 5 })
padded:addChild(padChild)
ctx:renderFrame()
eq(padChild.worldX, 10, "padding left shifts child")
eq(padChild.worldY, 20, "padding top shifts child")

-- ---------------------------------------------------------------------
-- Nesting (world = sum of locals)
-- ---------------------------------------------------------------------
local gp = Panel:new({ x = 10, y = 10, width = 100, height = 100 })
ctx:mount(gp)
local p = Panel:new({ x = 5, y = 5, width = 50, height = 50 })
gp:addChild(p)
local c = Panel:new({ x = 3, y = 3, width = 10, height = 10 })
p:addChild(c)
ctx:renderFrame()
eq(c.worldX, 18, "nested worldX (10+5+3)")
eq(c.worldY, 18, "nested worldY (10+5+3)")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_layout: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
