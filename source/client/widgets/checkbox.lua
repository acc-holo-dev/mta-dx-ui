--[[
    checkbox.lua — DXUI V3 (composite widget)

    Checkbox — box + optional label; toggles on click; emits "change"
    (checked) and keeps `checked` as a real property.

        local cb = ui:checkbox({ text="Enable X", x=0, y=0 })
        cb:on("change", function(n, checked) ... end)
]]

DXUI = DXUI or {}

local Checkbox = DXUI.Widget:extend("Checkbox", {
    checked = {
        default = false, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
            if node.emit then node:emit("change", v) end
        end,
    },
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    boxColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    checkedColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- box size and text offset
    indent = { default = 18, invalidates = { DXUI.DIRTY.RENDER } },
    autoSize = { default = true, invalidates = { DXUI.DIRTY.LAYOUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

--- Measures the box plus label text for autoSize.
function Checkbox:_measureContent()
    local w = (self.indent or 18) + (#self.text * 7) + 4
    return w, self.indent or 18
end

--- Draws the box, the check mark when checked, and the label.
function Checkbox:render(renderer)
    local wx, wy, h = self.worldX, self.worldY, self.height
    local box = self.indent or 18
    -- box: border ring drawn under the inset fill
    local r = self.radius or 4
    renderer:borderedRect(wx, wy, box, box, r, self.boxColor, self.borderColor, self.borderWidth)
    -- check mark (two thick strokes)
    if self.checked then
        local c = self.checkedColor or 0xFFFFFFFF
        renderer:line(wx + box * 0.22, wy + box * 0.52, wx + box * 0.42, wy + box * 0.72, c, 2)
        renderer:line(wx + box * 0.42, wy + box * 0.72, wx + box * 0.78, wy + box * 0.28, c, 2)
    end
    if self.text and self.text ~= "" then
        renderer:text(self.text, wx + box + 6, wy, self.width - box - 6, h,
            self.textColor, self.font, "left", "center", 1)
    end
end

DXUI.Builders.register("Checkbox", Checkbox)

--- Toggles `checked` on click (per-instance handler; users may add their own).
Checkbox._build = function(node, props)
    node:on("click", function(n)
        n.checked = not n.checked
    end, "dxui-toggle")
end