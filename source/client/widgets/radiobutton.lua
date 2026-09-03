---RadioButton — circle + dot; independent by default; group radios by
---giving them the same `group` name and manage exclusivity yourself, or
---use a RadioGroup container (below).
---
---    local r1 = ui:radiobutton({ text="A", x=0, y=0 })
---    r1:on("change", function(n, checked) ... end)


DXUI = DXUI or {}

local RadioButton = DXUI.Widget:extend("RadioButton", {
    checked = {
        default = false, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
            if node.emit then node:emit("change", v) end
        end,
    },
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    color = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    dotColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    indent = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    autoSize = { default = true, invalidates = { DXUI.DIRTY.LAYOUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

--- Returns the effective dot/indent size from explicit prop or theme metric.
function RadioButton:_dotSize()
    return self.indent or self:_metric("dotSize", 18)
end

--- Returns the text-to-dot gap from theme metrics.
function RadioButton:_textOffset()
    return self:_metric("textOffset", 6)
end

--- Measures the circle plus label text for autoSize.
function RadioButton:_measureContent()
    -- measure with the REAL font (the #text*7 estimate is wrong for every
    -- non-monospace font); the circle side stays the height floor
    local tw, th
    if DXUI.Text then
        tw, th = DXUI.Text.measure(self.text, self.font, 1)
    else
        tw, th = #self.text * 7, 15
    end
    local d = self:_dotSize()
    local offset = self:_textOffset()
    return d + tw + offset, (th > d) and th or d
end

--- Draws the circle, the dot when checked, and the label.
function RadioButton:render(renderer)
    local wx, wy = self.worldX, self.worldY
    local d = self:_dotSize()
    local offset = self:_textOffset()
    local r = d / 2
    -- ring: border color under the inset fill (ring stays visible)
    renderer:borderedRect(wx, wy, d, d, r, self.color, self.borderColor, self.borderWidth)
    if self.checked then
        local ratio = self:_metric("dotFillRatio", 0.42)
        local dot = d * ratio
        renderer:roundedRect(wx + (d - dot) / 2, wy + (d - dot) / 2, dot, dot, dot / 2, self.dotColor)
    end
    if self.text and self.text ~= "" then
        renderer:text(self.text, wx + d + offset, wy, self.width - d - offset, self.height,
            self.textColor, self.font, "left", "center", 1)
    end
end

--- Selects the radio on click.
RadioButton._build = function(node)
    node:on("click", function(n)
        n.checked = true
    end, "dxui-select")
end

--- RadioGroup: manages mutual exclusivity of radios sharing the group.
local RadioGroup = DXUI.Widget:extend("RadioGroup", {
    gap = { default = 6, invalidates = { DXUI.DIRTY.LAYOUT } },
    direction = { default = "column", invalidates = { DXUI.DIRTY.LAYOUT } },
})
--- Adds a radio to the group and enforces mutual exclusivity on change.
function RadioGroup:addRadio(radio)
    radio:setParent(self)
    radio:on("change", function(n, checked)
        if not checked then return end
        for _, other in ipairs(self._children) do
            if other ~= n and other.checked then
                other.checked = false
            end
        end
    end, "dxui-group")
    return radio
end
DXUI.Builders.register("RadioGroup", RadioGroup)

DXUI.Builders.register("RadioButton", RadioButton)