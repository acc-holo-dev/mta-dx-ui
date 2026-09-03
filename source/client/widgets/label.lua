---Label — single/multi-line text with wrap/ellipsis flags, alignment and
---valignment. autoSize measures via the text engine (design units).
---
---    local t = ui:label({ text="Hello", x=10, y=10, color="#FFFFFF" })


DXUI = DXUI or {}

local Text = DXUI.Text
local DIRTY = DXUI.DIRTY

local Label = DXUI.Widget:extend("Label", {
    -- content-sized by nature: no explicit size -> measured text
    autoSize = { default = true, invalidates = { DIRTY.LAYOUT } },
    text = { default = "", invalidates = { DIRTY.RENDER, DIRTY.LAYOUT } },
    -- rich text: #RRGGBB codes render (colorCoded draw); codes measure
    -- zero-width (layout/autoSize see the code-stripped widths)
    rich = { default = false, invalidates = { DIRTY.RENDER, DIRTY.LAYOUT } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- horizontal alignment: left|center|right
    align = { default = "left", invalidates = { DIRTY.RENDER } },
    -- vertical alignment: top|center|bottom
    valign = { default = "top", invalidates = { DIRTY.RENDER } },
    wrap = { default = false, invalidates = { DIRTY.RENDER, DIRTY.LAYOUT } },
    ellipsis = { default = false, invalidates = { DIRTY.RENDER } },
    shadow = { default = nil, invalidates = { DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- shadow offset (px; the pre-opts hardcode was +1/+1)
    shadowOffsetX = { default = 1, invalidates = { DIRTY.RENDER } },
    shadowOffsetY = { default = 1, invalidates = { DIRTY.RENDER } },
})

--- Content measurement for autoSize / percent sizing.
-- Padding is part of the box (like CSS content-box vs border-box):
-- measured text + padding.
function Label:_measureContent()
    if not Text then return 0, 0 end
    local w, h = Text.measure(self.text, self.font, 1, self.rich)
    local pL, pT, pR, pB = DXUI.Dimension.box(self.padding)
    return w + pL + pR, h + pT + pB
end

--- Draws the text (with optional shadow) honoring wrap/ellipsis/alignment.
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

    local rich = self.rich
    local laid
    if self.wrap then
        laid = Text.layout(self.text, self.font, 1, { wrap = true, width = availW, rich = rich })
    elseif self.ellipsis then
        laid = Text.layout(self.text, self.font, 1, { ellipsis = true, width = availW, rich = rich })
    else
        laid = Text.layout(self.text, self.font, 1, { rich = rich })
    end
    local lines = laid.lines
    local lh = laid.lineHeight

    -- vertical offset for valign (within the padded box)
    local w9, h9 = laid.width, laid.height
    local x0 = wx + pL
    local yTop = wy + pT
    if self.valign == "center" then yTop = wy + pT + (availH - h9) / 2
    elseif self.valign == "bottom" then yTop = wy + pT + availH - h9 end

    local font = self.font
    -- shadow pass first (under the text); rich codes stay active in the
    -- shadow too (a color-offset copy of the visible text)
    local sh = self.shadow
    if sh then
        local sox = self.shadowOffsetX or 0
        local soy = self.shadowOffsetY or 0
        for i = 1, #lines do
            renderer:text(lines[i], x0 + sox, yTop + (i - 1) * lh + soy, availW, lh,
                sh, font, self.align, "top", 1, rich)
        end
    end
    for i = 1, #lines do
        local line = lines[i]
        renderer:text(line, x0, yTop + (i - 1) * lh, availW, lh,
            self.textColor, font, self.align, "top", 1, rich)
    end
end

DXUI.Builders.register("Label", Label)