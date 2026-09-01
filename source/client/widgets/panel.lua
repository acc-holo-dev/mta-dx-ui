--[[
    panel.lua — DXUI V3 (basic widget)

    Panel — a plain styled surface. Default visual surface; theme props:
    color (surface), radius, borderColor.

        local p = ui:panel({ x=0, y=0, width=200, height=50, style="card" })
]]

DXUI = DXUI or {}

local Panel = DXUI.Widget:extend("Panel", {
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    borderColor = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
})

function Panel:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    if w <= 0 or h <= 0 then return end
    local r = self.radius or 0
    if r > 0 then
        renderer:roundedRect(wx, wy, w, h, r, self.color)
    else
        renderer:rect(wx, wy, w, h, self.color)
    end
    local bc = self.borderColor
    if bc then
        if r > 0 then
            renderer:roundedRect(wx, wy, w, h, r, bc) -- approximates a border
        else
            renderer:outline(wx, wy, w, h, 1, bc)
        end
    end
end

DXUI.Builders.register("Panel", Panel)