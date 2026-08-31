--[[
    layout.lua — DXUI

    LayoutBox: auto-layout container (registered as ui:layout). Positions
    children sequentially:
      mode = "vertical" (default) | "horizontal"
      gap  — spacing between children
      padding — inset from the container edge

    Children are positioned at build; call layout:relayout() after runtime
    add/remove/resize of children.

    Class is LayoutBox (DXUI.Layout is the layout SUBSYSTEM — not clobbered).
]]

DXUI = DXUI or {}

local LayoutBox = DXUI.Widget:extend("LayoutBox", {
    color = { default = 0xFF2A2A2A, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    mode = { default = "vertical", invalidates = { DXUI.DIRTY.LAYOUT, DXUI.DIRTY.RENDER } },
    gap = { default = 8, type = "number", min = 0, invalidates = { DXUI.DIRTY.LAYOUT } },
    padding = { default = 0, type = "number", min = 0, invalidates = { DXUI.DIRTY.LAYOUT } },
})

function LayoutBox:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

--- Repositions children according to mode/gap/padding.
function LayoutBox:relayout()
    local mode = self.mode or "vertical"
    local gap = self.gap or 0
    local pad = self.padding or 0
    local x, y = pad, pad
    local children = self._children
    if mode == "horizontal" then
        for i = 1, #children do
            local c = children[i]
            c.x = x
            c.y = y
            x = x + c.width + gap
        end
    else
        for i = 1, #children do
            local c = children[i]
            c.x = x
            c.y = y
            y = y + c.height + gap
        end
    end
    return self
end

function LayoutBox:setMode(mode)
    self.mode = mode
    return self:relayout()
end

function LayoutBox:setGap(gap)
    self.gap = gap
    return self:relayout()
end

--- Builder: ui:layout({ mode=, gap=, padding=, width=, height=, children= }).
function LayoutBox.build(context, props)
    props = props or {}
    local node = LayoutBox:new(props)
    if props.width == nil then node.width = 300 end
    if props.height == nil then node.height = 200 end
    DXUI.Widget.attachChildren(node, props)
    node:relayout()
    return node
end

DXUI.LayoutBox = LayoutBox
