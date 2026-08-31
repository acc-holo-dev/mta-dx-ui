--[[
    scalepane.lua — DXUI

    ScalePane: container that scales its whole subtree. Children are rendered
    to an offscreen RT at 1x (clipMode="rt"), then the RT quad is drawn
    stretched by scaleX/scaleY (DX9 stretch — no per-child work).

    width/height are the NATIVE (1x) size; the displayed size is
    width*scaleX x height*scaleY. Hit-test uses native coords — clicks are
    only accurate at scale == 1 (visual container).
]]

DXUI = DXUI or {}

local ScalePane = DXUI.Widget:extend("ScalePane", {
    color = { default = 0xFF2A2A2A, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    scaleX = { default = 1, type = "number", min = 0.01, invalidates = { DXUI.DIRTY.RENDER } },
    scaleY = { default = 1, type = "number", min = 0.01, invalidates = { DXUI.DIRTY.RENDER } },
    -- whole subtree → offscreen RT → stretched quad
    clipMode = { default = "rt", invalidates = { DXUI.DIRTY.RENDER } },
})

function ScalePane:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

--- Sets uniform (sx only) or per-axis scale.
function ScalePane:setScale(sx, sy)
    sx = sx or 1
    self.scaleX = sx
    self.scaleY = sy or sx
    return self
end

--- Builder: ui:scalepane({ width=, height=, scale=, scaleX=, scaleY=, children= }).
function ScalePane.build(context, props)
    props = props or {}
    local node = ScalePane:new(props)
    if props.width == nil then node.width = 100 end
    if props.height == nil then node.height = 100 end
    DXUI.Widget.attachChildren(node, props)
    if props.scale then
        node:setScale(props.scale)
    elseif props.scaleX or props.scaleY then
        node:setScale(props.scaleX or 1, props.scaleY or 1)
    end
    return node
end

DXUI.ScalePane = ScalePane
