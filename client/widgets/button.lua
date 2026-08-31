--[[
    button.lua — DXUI V2

    Button: background (rect) + caption (text). Interactive. "click" event
    emitted by the dispatcher; onClick in props is a convenience shortcut.

    M22: hover/pressed/disabled states come from the theme state matrix
    (theme.lua), applied centrally by the dispatcher.
]]

DXUI = DXUI or {}

local Button = DXUI.Widget:extend("Button", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- Stage 8: button text centered by default (native dxDrawText align)
    align = { default = "center", invalidates = { DXUI.DIRTY.RENDER } },
    valign = { default = "middle", invalidates = { DXUI.DIRTY.RENDER } },
    scale = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- Stage 9: rounded corners and border
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    outlineWidth = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    outlineColor = { default = 0xFF000000, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function Button:render(renderer)
    if self.radius > 0 then
        renderer:roundedRect(self.worldX, self.worldY, self.width, self.height, self.radius, self.color)
    else
        renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    end
    if self.outlineWidth > 0 then
        renderer:outline(self.worldX, self.worldY, self.width, self.height, self.outlineWidth, self.outlineColor)
    end
    if self.text ~= "" then
        renderer:text(self.text, self.worldX, self.worldY, self.width, self.height,
            self.textColor, self.font, self.align, self.valign, self.scale)
    end
end

--- Builder: ui:button({ text=, onClick=, style=, x=, y=, width=, height=,
-- color=, ... }).
function Button.build(context, props)
    props = props or {}
    local node = Button:new(props)
    if props.width == nil then node.width = 100 end
    if props.height == nil then node.height = 30 end
    if props.onClick then node:on("click", props.onClick) end

    -- M22: hover/pressed/disabled states are handled centrally by the
    -- dispatcher + state matrix (theme.lua), not per-widget handlers.

    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Button = Button