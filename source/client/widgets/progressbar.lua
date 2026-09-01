--[[
    progressbar.lua — DXUI V3 (composite widget)

    ProgressBar — value 0..1 rendered as a filled bar (bg + fill).

        local pb = ui:progressbar({ x=0, y=0, width=200, height=14, value=0.4 })
]]

DXUI = DXUI or {}

local ProgressBar = DXUI.Widget:extend("ProgressBar", {
    value = {
        default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return type(v) == "number" and v >= 0 and v <= 1 end,
    },
    -- theme colors: color (fill), bgColor, radius
    bgColor = { default = 0xFFF3F4F6, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
})

function ProgressBar:setProgress(v)
    local cl = v
    if cl < 0 then cl = 0 elseif cl > 1 then cl = 1 end
    self.value = cl
    return self
end

function ProgressBar:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    if w <= 0 or h <= 0 then return end
    local r = self.radius or 4
    renderer:roundedRect(wx, wy, w, h, r, self.bgColor or self.color)
    local filled = w * self.value
    if filled > 0.5 then
        renderer:roundedRect(wx, wy, filled, h, r, self.color)
    end
end

DXUI.Builders.register("ProgressBar", ProgressBar)