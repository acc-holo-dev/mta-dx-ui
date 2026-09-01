--[[
    edit.lua — DXUI V3 (composite widget)

    Edit — single-line text input. Focusable; receives keys via the
    dispatcher focus chain. Cursor position kept as `cursor`; caret drawn.

        local e = ui:edit({ x=0, y=0, width=200, height=24, placeholder="name" })
        e:on("submit", function(n, text) ... end)
        e:on("change", function(n, text) ... end)

    Keys: printable chars, space, backspace, enter (submit), left/right
    moves cursor, home/end, Escape blurs.
]]

DXUI = DXUI or {}

local Edit = DXUI.Widget:extend("Edit", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    placeholder = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    cursor = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    caretColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    placeholderColor = { default = 0xFF6B7280, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    bgColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    focusBorderColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    padding = { default = { left = 8, right = 8, top = 0, bottom = 0 }, invalidates = { DXUI.DIRTY.LAYOUT } },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

local EMPTY = ""

--- Inserts a character at the cursor.
function Edit:_insert(ch)
    local t = self.text
    local pos = self.cursor or 0
    self.text = t:sub(1, pos) .. ch .. t:sub(pos + 1)
    self.cursor = pos + 1
    if self.emit then self:emit("change", self.text) end
end

--- Deletes the character before the cursor.
function Edit:_backspace()
    local pos = self.cursor or 0
    if pos <= 0 then return end
    local t = self.text
    self.text = t:sub(1, pos - 1) .. t:sub(pos + 1)
    self.cursor = pos - 1
    if self.emit then self:emit("change", self.text) end
end

--- Draws the input box, text/placeholder, and the caret when focused.
function Edit:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local r = self.radius or 4
    local fmt = self:getState()
    local border = (fmt == "focused") and (self.focusBorderColor or self.borderColor) or self.borderColor
    renderer:borderedRect(wx, wy, w, h, r, self.bgColor, border, 1)

    local text = self.text
    local shown = (text == EMPTY or text == nil) and self.placeholder or text
    local color = (text == EMPTY or text == nil) and (self.placeholderColor or self.textColor) or self.textColor
    renderer:text(shown, wx + 8, wy, w - 16, h, color, self.font, "left", "center", 1)

    if fmt == "focused" and text ~= EMPTY then
        local cx = DXUI.Text and DXUI.Text.charX(text, self.font, 1, self.cursor or 0) or 0
        local cy = wy + 3
        renderer:rect(wx + 8 + cx, cy, 1, h - 6, self.caretColor)
    end
end

--- Wires focus/blur/key/character events for text editing.
Edit._build = function(node)
    node:on("focus", function(n)
        n.cursor = #n.text
        n:setState("focused")
    end, "dxui-edit")
    node:on("blur", function(n)
        n:setState("normal")
    end, "dxui-edit")
    node:on("key", function(n, keyName, pressed)
        if not pressed then return true end
        if keyName == "backspace" then n:_backspace()
        elseif keyName == "enter" then
            if n.emit then n:emit("submit", n.text) end
            n:setState("normal")
        elseif keyName == "left" then
            n.cursor = math.max(0, (n.cursor or 0) - 1)
        elseif keyName == "right" then
            n.cursor = math.min(#n.text, (n.cursor or 0) + 1)
        elseif keyName == "home" then n.cursor = 0
        elseif keyName == "end" then n.cursor = #n.text
        end
        return true
    end, "dxui-edit")
    node:on("character", function(n, ch)
        n:_insert(ch)
    end, "dxui-edit")
end

DXUI.Builders.register("Edit", Edit)