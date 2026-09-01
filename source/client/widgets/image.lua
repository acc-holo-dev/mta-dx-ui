--[[
    image.lua — DXUI V3 (basic widget)

    Image — texture quad with tint (color), section cropping and optional
    blur/mask effect (via node.fx properties, rendered with the direct
    shader path — the cheap one).

        local img = ui:image({ texture = "assets/logo.png",
                               x=0, y=0, width=64, height=64 })
]]

DXUI = DXUI or {}

local Image = DXUI.Widget:extend("Image", {
    texture = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    section = { default = nil, invalidates = { DXUI.DIRTY.RENDER } }, -- {x,y,w,h} px
})

function Image:render(renderer)
    if not self.texture then return end
    renderer:image(self.texture, self.worldX, self.worldY, self.width, self.height,
        self.color, self.section)
end

DXUI.Builders.register("Image", Image)