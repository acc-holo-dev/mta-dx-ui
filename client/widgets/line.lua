--[[
    line.lua — DXUI

    Line: straight line from (x, y) to (x + x2, y + y2). x2/y2 are offsets
    from the node's position. Thin visual leaf (no hit-test surface).
]]

DXUI = DXUI or {}

local Line = DXUI.Widget:extend("Line", {
    x2 = { default = 100, type = "number", invalidates = { DXUI.DIRTY.RENDER } },
    y2 = { default = 0, type = "number", invalidates = { DXUI.DIRTY.RENDER } },
    thickness = { default = 1, type = "number", min = 1, invalidates = { DXUI.DIRTY.RENDER } },
})

function Line:render(renderer)
    renderer:line(self.worldX, self.worldY,
        self.worldX + self.x2, self.worldY + self.y2, self.color, self.thickness)
end

--- Builder: ui:line({ x2=, y2=, color=, ... }).
function Line.build(context, props)
    props = props or {}
    local node = Line:new(props)
    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Line = Line
