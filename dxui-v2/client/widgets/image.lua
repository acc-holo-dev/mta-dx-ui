--[[
    image.lua — DXUI V2

    Image: текстура (dxImage handle, pass-through). Не интерактивен по умолчанию.

    Stage 9 (§36/§39): mask — текстура-маска (альфа управляет видимостью;
    специальный path через mask-шейдер — обычные узлы идут без шейдеров);
    blur — размытие (прямой шейдер на текстуру, без RT — как legacy M8).
    Маска приоритетнее blur; композиция обоих — RT-проход (future).
]]

DXUI = DXUI or {}

local Image = DXUI.Widget:extend("Image", {
    texture = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    enabled = { default = false, invalidates = { DXUI.DIRTY.INPUT } },
    -- blur/mask наследуются от Widget base (Stage 10); Image использует их
    -- прямым шейдером в собственном render (дешевле RT-группы).
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

--- Билдер: ui:image({ texture=, mask=, blur=, x=, y=, width=, height=,
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