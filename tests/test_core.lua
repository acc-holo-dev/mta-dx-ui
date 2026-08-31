--[[
    test_core.lua — DXUI V2 Stage 2

    Tests core: Node (property-style + method-style), invalidation,
    parent/child, lifecycle, inheritance, color.
]]

-- Load modules in meta.xml order
dofile("loader.lua")

local passed, failed = 0, 0

local function ok(cond, name)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name)
    end
end

local function eq(a, b, name)
    if a == b then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
    end
end

-- ---------------------------------------------------------------------
-- Property-style + method-style converge on one mutation layer
-- ---------------------------------------------------------------------
local ctx = DXUI.createContext()
local node = ctx:createNode()

node.x = 100
eq(node.x, 100, "property-style x")
eq(node._dirty[DXUI.DIRTY.LAYOUT], true, "x invalidates layout")

node:setPosition(200, 50)
eq(node.x, 200, "method-style setPosition x")
eq(node.y, 50, "method-style setPosition y")

node.width = 300
node.height = 40
eq(node:getSize(), 300, "getSize w")
eq(node.height, 40, "property height")

-- opacity float 0..1
node.opacity = 0.5
eq(node.opacity, 0.5, "opacity float")
eq(node._dirty[DXUI.DIRTY.RENDER], true, "opacity invalidates render")

-- visible
node.visible = false
eq(node.visible, false, "visible false")
eq(node._dirty[DXUI.DIRTY.VISIBILITY], true, "visible invalidates visibility")
node:show()
eq(node.visible, true, "show()")

-- userData — arbitrary data, no invalidation
node.userData = { itemId = 125, slot = 7 }
eq(node.userData.itemId, 125, "userData arbitrary")

-- arbitrary custom field (not in spec) — rawset
node.customField = "hello"
eq(node.customField, "hello", "custom field rawset")

-- ---------------------------------------------------------------------
-- Parent / child
-- ---------------------------------------------------------------------
local parent = ctx:createNode()
ctx:mount(parent) -- parent._context = ctx
local child = ctx:createNode()
parent:addChild(child)
eq(child.parent, parent, "child.parent")
eq(parent.children[1], child, "parent.children[1]")
eq(child.context, ctx, "child inherits context")

-- reparent
local other = ctx:createNode()
child:setParent(other)
eq(child.parent, other, "reparent")
eq(#parent.children, 0, "old parent children empty")
eq(other.children[1], child, "new parent children")

-- cycle protection
local c1 = ctx:createNode()
local c2 = ctx:createNode()
c1:addChild(c2)
local cycleOk = pcall(function() c1:setParent(c2) end)
eq(cycleOk, false, "cycle rejected")

-- destroyed parent rejected
local dead = ctx:createNode()
dead:destroy()
local deadOk = pcall(function() ctx:createNode():setParent(dead) end)
eq(deadOk, false, "destroyed parent rejected")

-- ---------------------------------------------------------------------
-- Lifecycle / destroy
-- ---------------------------------------------------------------------
local a = ctx:createNode()
local b = ctx:createNode()
a:addChild(b)
a:destroy()
eq(a.destroyed, true, "a destroyed")
eq(b.destroyed, true, "b destroyed (cascade)")

-- destroyed node: write is a no-op (does not crash)
local d = ctx:createNode()
d:destroy()
d.x = 999
eq(d.x, nil, "destroyed node property read is nil")

-- ---------------------------------------------------------------------
-- Inheritance (extend)
-- ---------------------------------------------------------------------
local Widget = DXUI.Widget
local Button = Widget:extend("Button", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
})

local btn = Button:new({ text = "Hello", x = 10, y = 20 })
eq(btn.text, "Hello", "Button.text")
eq(btn.x, 10, "Button inherits x")
eq(btn.color, 0xFFFFFFFF, "Button inherits color default")
btn.text = "World"
eq(btn._dirty[DXUI.DIRTY.RENDER], true, "text invalidates render")

-- base-class method reachable through chain
btn:setPosition(1, 2)
eq(btn.x, 1, "Button inherits setPosition")

-- ---------------------------------------------------------------------
-- Color
-- ---------------------------------------------------------------------
eq(DXUI.resolveColor("#FFFFFF"), 0xFFFFFFFF, "resolveColor #FFFFFF")
eq(DXUI.resolveColor("#FF0000"), 0xFFFF0000, "resolveColor #FF0000")
eq(DXUI.resolveColor({ r = 255, g = 0, b = 0, a = 128 }), 0x80FF0000, "resolveColor table")
eq(DXUI.color(255, 0, 0), 0xFFFF0000, "color()")

-- extended string forms (regression: Lua-style 0xRRGGBB and #RGB shorthand
-- produced garbage; unknown strings silently resolved to transparent black)
eq(DXUI.resolveColor("#ABC"), 0xFFAABBCC, "resolveColor #RGB shorthand")
eq(DXUI.resolveColor("#FF000080"), 0x80FF0000, "resolveColor #RRGGBBAA")
eq(DXUI.resolveColor("0xFF0000"), 0xFFFF0000, "resolveColor 0xRRGGBB string")
eq(DXUI.resolveColor("0x80FF0000"), 0x80FF0000, "resolveColor 0xAARRGGBB string")
local colorErr = pcall(DXUI.resolveColor, "white")
eq(colorErr, false, "resolveColor: unknown string raises instead of silent black")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_core: %d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
