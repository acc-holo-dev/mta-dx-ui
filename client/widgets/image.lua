--[[
    image.lua — DXUI V2

    Image: texture (dxImage handle, pass-through). Not interactive by default.

    Stage 9: mask — mask texture (alpha controls visibility; special
    path through the mask shader — plain nodes render without shaders);
    blur — blur (direct shader on the texture, no RT — like legacy M8).
    Mask takes priority over blur; combining both is an RT pass (future).
]]

DXUI = DXUI or {}

local Image = DXUI.Widget:extend("Image", {
    texture = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    enabled = { default = false, invalidates = { DXUI.DIRTY.INPUT } },
    -- blur/mask inherited from Widget base (Stage 10); Image applies them
    -- with a direct shader in its own render (cheaper than an RT group).
})

function Image:render(renderer)
    if not self.texture then return end
    local effect
    if self.mask then
        effect = DXUI.Effects and DXUI.Effects.mask(self.mask) or nil
    elseif self.blur and self.blur > 0 then
        effect = DXUI.Effects and DXUI.Effects.blur(self.width, self.height, self.blur) or nil
    end
    renderer:image(self.texture, self.worldX, self.worldY, self.width, self.height, self.color, effect)
end

--- Builder: ui:image({ texture=, mask=, blur=, x=, y=, width=, height=,
-- color=, ... }).
function Image.build(context, props)
    props = props or {}
    local node = Image:new(props)
    if props.width == nil then node.width = 64 end
    if props.height == nil then node.height = 64 end
    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Image = Image