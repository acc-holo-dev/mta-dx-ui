--[[
    slider.lua — DXUI V2

    Slider: track + fill + thumb drawn in render. mousedown sets the value
    by position (click-to-jump) and captures drag; motion keeps changing
    the value. orientation "h" (default) | "v".
]]

DXUI = DXUI or {}

local Slider = DXUI.Widget:extend("Slider", {
    value = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    min   = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    max   = { default = 100, invalidates = { DXUI.DIRTY.RENDER } },
    orientation = { default = "h", invalidates = { DXUI.DIRTY.RENDER } },
    trackColor = { default = 0xFF333333, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    fillColor  = { default = 0xFF00CC00, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    thumbColor = { default = 0xFFDDDDDD, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    thumbSize  = { default = 10, invalidates = { DXUI.DIRTY.RENDER } },
})

function Slider:_frac()
    local span = self.max - self.min
    if span <= 0 then return 0 end
    local f = (self.value - self.min) / span
    if f < 0 then return 0 elseif f > 1 then return 1 end
    return f
end

function Slider:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.trackColor)
    local vertical = self.orientation == "v"
    local trackLen = vertical and self.height or self.width
    local span = trackLen - self.thumbSize
    if span < 0 then span = 0 end
    local pos = self:_frac() * span
    if vertical then
        renderer:rect(self.worldX, self.worldY, self.width, pos, self.fillColor)
        renderer:rect(self.worldX, self.worldY + pos, self.width, self.thumbSize, self.thumbColor)
    else
        renderer:rect(self.worldX, self.worldY, pos, self.height, self.fillColor)
        renderer:rect(self.worldX + pos, self.worldY, self.thumbSize, self.height, self.thumbColor)
    end
end

function Slider:setValue(v)
    if v < self.min then v = self.min elseif v > self.max then v = self.max end
    self.value = v
    if self._onChange then self._onChange(v) end
    return self
end

function Slider:getValue()
    return self.value
end

function Slider:setRange(min, max)
    if min >= max then min, max = 0, 1 end
    self.min = min
    self.max = max
    return self
end

--- Converts screen position (along the track axis) into a value.
function Slider:_valueFromPos(pos)
    local vertical = self.orientation == "v"
    local trackLen = vertical and self.height or self.width
    local span = trackLen - self.thumbSize
    if span <= 0 then return self.min end
    local base = vertical and self.worldY or self.worldX
    local frac = (pos - base) / span
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    return self.min + frac * (self.max - self.min)
end

--- Builder: ui:slider({ value=, min=, max=, orientation=, onChange=, ... }).
function Slider.build(context, props)
    props = props or {}
    local node = Slider:new(props)
    if props.width == nil then node.width = 200 end
    if props.height == nil then node.height = 16 end
    if props.onChange then node._onChange = props.onChange end

    node:on("mousedown", function(e)
        if e.button ~= "left" then return end
        if not node:isAlive() then return end
        local vertical = node.orientation == "v"
        local startPos = vertical and e.y or e.x
        node:setValue(node:_valueFromPos(startPos))
        -- drag keeps changing the value (delta from the grab point)
        context.dispatcher:beginDrag(function(px, py)
            if not node:isAlive() then return end
            node:setValue(node:_valueFromPos(vertical and py or px))
        end)
    end)

    return node
end

DXUI.Slider = Slider
