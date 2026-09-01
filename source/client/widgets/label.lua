--[[
    label.lua — DXUI V3 (basic widget)

    Label — single/multi-line text with wrap/ellipsis flags, alignment and
    valignment. autoSize measures via the text engine (design units).

        local t = ui:label({ text="Hello", x=10, y=10, color="#FFFFFF" })
]]

DXUI = DXUI or {}

local Text = DXUI.Text
local DIRTY = DXUI.DIRTY

local Label = DXUI.Widget:extend("Label", {
    -- content-sized by nature: no explicit size -> measured text
    autoSize = { default = true, invalidates = { DIRTY.LAYOUT } },
    text = { default = "", invalidates = { DIRTY.RENDER, DIRTY.LAYOUT } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER }, transform = DXUI.resolveColor },
    align = { default = "left", invalidates = { DIRTY.RENDER } },   -- left|center|right
    valign = { default = "top", invalidates = { DIRTY.RENDER } },   -- top|middle|bottom
    wrap = { default = false, invalidates = { DIRTY.RENDER, DIRTY.LAYOUT } },
    ellipsis = { default = false, invalidates = { DIRTY.RENDER } },
    shadow = { default = nil, invalidates = { DIRTY.RENDER }, transform = DXUI.resolveColor },
})

--- Content measurement for autoSize / percent sizing.
-- Padding is part of the box (like CSS content-box vs border-box):
-- measured text + padding.
function Label:_measureContent()
    if not Text then return 0, 0 end
    local w, h = Text.measure(self.text, self.font, 1)
    local pL, pT, pR, pB = DXUI.Dimension.box(self.padding)
    return w + pL + pR, h + pT + pB
end

function Label:render(renderer)
    if self.text == nil or self.text == "" then return end
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    if w <= 0 or h <= 0 then return end
    if not Text then return end

    local pL, pT, pR, pB = DXUI.Dimension.box(self.padding)
    local availW = w - pL - pR
    local availH = h - pT - pB
    if availW < 1 then availW = 1 end
    if availH < 1 then availH = 1 end

    local laid
    if self.wrap then
        laid = Text.layout(self.text, self.font, 1, { wrap = true, width = availW })
    elseif self.ellipsis then
        laid = Text.layout(self.text, self.font, 1, { ellipsis = true, width = availW })
    else
        laid = Text.layout(self.text, self.font, 1, {})
    end
    local lines = laid.lines
    local lh = laid.lineHeight

    -- vertical offset for valign (within the padded box)
    local w9, h9 = laid.width, laid.height
    local x0 = wx + pL
    local yTop = wy + pT
    if self.valign == "middle" then yTop = wy + pT + (availH - h9) / 2
    elseif self.valign == "bottom" then yTop = wy + pT + availH - h9 end

    local font = self.font
    -- shadow pass first (under the text)
    local sh = self.shadow
    if sh then
        for i = 1, #lines do
            renderer:text(lines[i], x0 + 1, yTop + (i - 1) * lh + 1, availW, lh,
                sh, font, self.align, "top", 1)
        end
    end
    for i = 1, #lines do
        local line = lines[i]
        renderer:text(line, x0, yTop + (i - 1) * lh, availW, lh,
            self.textColor, font, self.align, "top", 1)
    end
end

DXUI.Builders.register("Label", Label)