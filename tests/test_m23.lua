--[[
    test_m23.lua — DXUI M23

    Property validation (type/min/max) and the plugin API
    (registerWidget / registerEffect).
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

local mock = {
    setBlendMode = function() end,
    drawRect  = function() end,
    drawImage = function() end,
    drawText  = function() end,
    drawLine  = function() end,
}

local ui = DXUI.createContext(mock)
ui:setScreenSize(800, 600)

-- ---------------------------------------------------------------------
-- Validation: type + min on core properties
-- ---------------------------------------------------------------------
local ok1 = pcall(function() ui:panel({ width = 120, height = 80 }) end)
eq(ok1, true, "valid width/height accepted")

local ok2 = pcall(function() ui:panel({ width = -5 }) end)
eq(ok2, false, "width < 0 rejected (min=0)")

local ok3 = pcall(function() ui:panel({ x = "abc" }) end)
eq(ok3, false, "x string rejected (type=number)")

local ok4 = pcall(function() ui:panel({ opacity = "high" }) end)
eq(ok4, false, "opacity string rejected (type=number)")

-- ---------------------------------------------------------------------
-- registerWidget: custom widget, both builders
-- ---------------------------------------------------------------------
local MyWidget = DXUI.Widget:extend("MyWidget", {})
function MyWidget:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end
function MyWidget.build(context, props)
    props = props or {}
    local node = MyWidget:new(props)
    if props.width == nil then node.width = 50 end
    if props.height == nil then node.height = 30 end
    DXUI.Widget.attachChildren(node, props)
    return node
end
DXUI.registerWidget("mywidget", MyWidget)

eq(DXUI._widgets.mywidget, MyWidget, "registry holds class")

local w = ui:mywidget({ x = 0, y = 0 })
eq(w._class._name, "MyWidget", "context builder builds registered class")
eq(w.parent, ui.root, "context builder auto-mounts")

local host = ui:panel({ x = 0, y = 0, width = 200, height = 200 })
local child = host:mywidget({})
eq(child.parent, host, "parent-scoped builder attaches child")

-- ---------------------------------------------------------------------
-- registerEffect / getEffect
-- ---------------------------------------------------------------------
local called = false
DXUI.registerEffect("customFx", function(node)
    called = true
    return { shader = "S", params = { radius = 1 } }
end)
local fx = DXUI.getEffect("customFx", {})
eq(called, true, "effect fn invoked")
eq(fx ~= nil and fx.shader, "S", "effect returns shader/params")
eq(DXUI.getEffect("noSuchEffect", {}), nil, "unknown effect -> nil")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------
print(string.format("test_m23: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
