--[[
    progressbar.lua — DXUI V2

    ProgressBar: progress indicator. track (background) + fill.
    All drawn in render; no interactive parts (enabled=false).
]]

DXUI = DXUI or {}

local ProgressBar = DXUI.Widget:extend("ProgressBar", {
    value = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    min   = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    max   = { default = 100, invalidates = { DXUI.DIRTY.RENDER } },
    trackColor = { default = 0xFF333333, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    fillColor  = { default = 0xFF00CC00, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    enabled = { default = false, invalidates = { DXUI.DIRTY.INPUT } },
})

function ProgressBar:_frac()
    local span = self.max - self.min
    if span <= 0 then return 0 end
    local f = (self.value - self.min) / span
    if f < 0 then return 0 elseif f > 1 then return 1 end
    return f
end

function ProgressBar:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.trackColor)
    renderer:rect(self.worldX, self.worldY, self.width * self:_frac(), self.height, self.fillColor)
end

function ProgressBar:setValue(v)
    self.value = v
    return self
end

function ProgressBar:getValue()
    return self.value
end

function ProgressBar:setRange(min, max)
    if min >= max then min, max = 0, 1 end
    self.min = min
    self.max = max
    return self
end

--- Builder: ui:progressbar({ value=, min=, max=, ... }).
function ProgressBar.build(context, props)
    props = props or {}
    local node = ProgressBar:new(props)
    if props.width == nil then node.width = 200 end
    if props.height == nil then node.height = 16 end
    return node
end

DXUI.ProgressBar = ProgressBar
