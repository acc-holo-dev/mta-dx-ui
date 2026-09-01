--[[
    slider.lua — DXUI V3 (composite widget)

    Slider — horizontal value 0..1 with draggable thumb. Drag events from
    the dispatcher; click also sets value. Emits "change" (value) and
    "input" (value) during drag.

        local s = ui:slider({ x=0, y=0, width=200, height=18, value=0.5 })
        s:on("change", function(n, v) volume = v end)
]]

DXUI = DXUI or {}

local Slider = DXUI.Widget:extend("Slider", {
    value = {
        default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return type(v) == "number" and v >= 0 and v <= 1 end,
    },
    thumbSize = { default = 14, invalidates = { DXUI.DIRTY.RENDER } },
    -- theme colors: color (track), bgColor (groove), thumbColor, thumbBorderColor
    bgColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    thumbColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    thumbBorderColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

--- full value from a local x (design units inside the widget).
function Slider:_valueFromX(lx)
    local w = self.width - (self.thumbSize or 14)
    if w <= 0 then return 0 end
    local v = (lx - (self.thumbSize or 14) / 2) / w
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

--- Applies a value, emitting "change" (unless silent) and "input".
function Slider:_applyValue(v, silent)
    if self.value ~= v then
        self.value = v
        if not silent and self.emit then self:emit("change", v) end
    end
    if self.emit then self:emit("input", v) end
end

--- Draws the track, the filled section, and the thumb.
function Slider:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local ts = self.thumbSize or 14
    local trackH = 4
    local ty = wy + (h - trackH) / 2
    renderer:roundedRect(wx, ty, w, trackH, 2, self.bgColor)
    local trackW = w - ts
    local tcx = wx + ts / 2 + trackW * self.value
    -- filled section
    if self.value > 0.02 then
        renderer:roundedRect(wx, ty, tcx - wx, trackH, 2, self.color)
    end
    -- thumb
    renderer:borderedRect(tcx - ts / 2, wy + (h - ts) / 2, ts, ts, ts / 2,
        self.thumbColor, self.thumbBorderColor, self.borderWidth)
end

--- Wires drag and click to update the value.
Slider._build = function(node)
    node:on("drag-start", function(n)
        n._sliderDragging = true
        if n.emit then n:emit("drag-start", n.value) end
    end, "dxui-slider")
    node:on("drag-move", function(n, x, y)
        if n._sliderDragging then
            n:_applyValue(n:_valueFromX(x - n.worldX), false)
        end
    end, "dxui-slider")
    node:on("drag-end", function(n)
        n._sliderDragging = false
        if n.emit then n:emit("drag-end", n.value) end
    end, "dxui-slider")
    node:on("click", function(n, _, x, y)
        n:_applyValue(n:_valueFromX(x - n.worldX), false)
    end, "dxui-slider")
end

DXUI.Builders.register("Slider", Slider)