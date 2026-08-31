--[[
    switchbutton.lua — DXUI

    SwitchButton: toggle switch (track + knob). Extends Toggle; click toggles
    checked. Colors via inline properties (theme-friendly: color = track color).
]]

DXUI = DXUI or {}

local SwitchButton = DXUI.Toggle:extend("SwitchButton", {
    trackOnColor = { default = 0xFF3A6EA5, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    trackOffColor = { default = 0xFF555555, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    knobColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

local TRACK_W = 36
local TRACK_H = 18
local KNOB = 14

function SwitchButton:render(renderer)
    local x = self.worldX
    local y = self.worldY + (self.height - TRACK_H) / 2
    local knobX = self.checked and (x + TRACK_W - KNOB - 2) or (x + 2)
    local knobY = y + (TRACK_H - KNOB) / 2
    local radius = TRACK_H / 2
    renderer:roundedRect(x, y, TRACK_W, TRACK_H, radius,
        self.checked and self.trackOnColor or self.trackOffColor)
    renderer:roundedRect(knobX, knobY, KNOB, KNOB, KNOB / 2, self.knobColor)
    if self.text ~= "" then
        renderer:text(self.text, x + TRACK_W + 6, self.worldY,
            self.width - TRACK_W - 6, self.height, self.labelColor)
    end
end

--- Builder: ui:switchbutton({ text=, checked=, onChange=, ... }).
function SwitchButton.build(context, props)
    props = props or {}
    local node = SwitchButton:new(props)
    if props.width == nil then node.width = 60 end
    if props.height == nil then node.height = 20 end
    if props.onChange then node._onChange = props.onChange end
    node:on("click", function()
        if node:isAlive() then node:toggle() end
    end)
    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.SwitchButton = SwitchButton
