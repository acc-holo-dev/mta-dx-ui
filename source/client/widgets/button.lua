--[[
    button.lua — DXUI V3 (basic widget)

    Button — themed surface + centered text; interaction states wired to
    the style system (hover/pressed/disabled). Variants via node.style:

        local b = ui:button({ text="Save", x=10, y=100, style="secondary" })
        b:on("click", function(n) save() end)

    Theme props: color, textColor, radius, borderColor.
]]

DXUI = DXUI or {}

local Button = DXUI.Widget:extend("Button", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    borderColor = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- buttons are interactive + focusable by default
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

--- Draws the button surface and its centered text.
function Button:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    if w <= 0 or h <= 0 then return end
    local r = self.radius or 0
    local bc = self.borderColor
    renderer:borderedRect(wx, wy, w, h, r, self.color, bc, 1)
    if self.text and self.text ~= "" then
        renderer:text(self.text, wx, wy, w, h, self.textColor, self.font, "center", "center", 1)
    end
end

DXUI.Builders.register("Button", Button)