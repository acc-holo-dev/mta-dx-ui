---Panel — a plain styled surface. Default visual surface; theme props:
---color (surface), radius, borderColor.
---
---    local p = ui:panel({ x=0, y=0, width=200, height=50, style="card" })


DXUI = DXUI or {}

local Panel = DXUI.Widget:extend("Panel", {
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    borderColor = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
})

--- Draws the panel as a bordered rounded rectangle.
function Panel:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    if w <= 0 or h <= 0 then return end
    renderer:borderedRect(wx, wy, w, h, self.radius or 0, self.color, self.borderColor, self.borderWidth)
end

DXUI.Builders.register("Panel", Panel)