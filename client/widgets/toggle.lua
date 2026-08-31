--[[
    toggle.lua — DXUI V2

    Toggle: common base class for CheckBox and RadioButton.
    box (frame) + mark (check/dot) + label — drawn in render.
    Click toggles checked; onChange(checked) — callback.

    Subclass overrides _drawMark(renderer, bx, by) — the mark shape.
]]

DXUI = DXUI or {}

local Toggle = DXUI.Widget:extend("Toggle", {
    checked = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    boxColor = { default = 0xFF333333, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    markColor = { default = 0xFF00CC00, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    labelColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

local BOX = 16 -- box size

function Toggle:render(renderer)
    local bx = self.worldX
    local by = self.worldY + (self.height - BOX) / 2
    renderer:rect(bx, by, BOX, BOX, self.boxColor)
    if self.checked then
        self:_drawMark(renderer, bx, by)
    end
    if self.text ~= "" then
        renderer:text(self.text, bx + BOX + 6, self.worldY, self.width - BOX - 6, self.height, self.labelColor)
    end
end

-- Default: square check mark (CheckBox).
function Toggle:_drawMark(renderer, bx, by)
    local ms = 10
    renderer:rect(bx + (BOX - ms) / 2, by + (BOX - ms) / 2, ms, ms, self.markColor)
end

function Toggle:setChecked(v)
    v = v == true
    if self.checked == v then return self end
    self.checked = v
    if self._onChange then self._onChange(self.checked) end
    return self
end

function Toggle:isChecked()
    return self.checked
end

function Toggle:toggle()
    return self:setChecked(not self.checked)
end

function Toggle:setLabel(text)
    self.text = text or ""
    return self
end

--- Attach the change callback (or via props.onChange).
function Toggle:onChange(fn)
    self._onChange = fn
    return self
end

DXUI.Toggle = Toggle
