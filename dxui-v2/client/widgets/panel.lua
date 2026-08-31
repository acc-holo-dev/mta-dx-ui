--[[
    panel.lua — DXUI V2

    Panel: прямоугольная панель (фон). Базовый контейнер.

    Stage 9 (§37/§38): radius — скруглённые углы (SDF-шейдер, кэш —
    один на процесс, не resource per node); outlineWidth/outlineColor —
    рамка из 4 рёбер (T-раскладка, композируется из rect).
]]

DXUI = DXUI or {}

local Panel = DXUI.Widget:extend("Panel", {
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    outlineWidth = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    outlineColor = { default = 0xFF000000, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function Panel:render(renderer)
    if self.radius > 0 then
        renderer:roundedRect(self.worldX, self.worldY, self.width, self.height, self.radius, self.color)
    else
        renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    end
    if self.outlineWidth > 0 then
        renderer:outline(self.worldX, self.worldY, self.width, self.height, self.outlineWidth, self.outlineColor)
    end
end

--- Билдер: ui:panel({ x=, y=, width=, height=, color=, radius=,
-- outlineWidth=, outlineColor=, children=, ... }).
function Panel.build(context, props)
    props = props or {}
    local node = Panel:new(props)
    if props.width == nil then node.width = 100 end
    if props.height == nil then node.height = 100 end
    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Panel = Panel