---Edit — single-line text input (DXUI Widget).
---
---    local e = ui:edit({ x=0, y=0, width=200, height=24, placeholder="Name" })
---    e:on("submit", function(n, text) ... end)
---    e:on("change", function(n, text) ... end)
---
---Caret (`caret`, a byte index into `text`) supports three modes:
---"blink" (default, interval via `caretBlinkInterval` or
---Settings.defaults.caretBlinkInterval), "solid", "off". The caret is an
---OVERLAY: it repaints every frame from the instance clock and never
--- invalidates the cached render list (the zero-work idle contract holds).
---Selection: `selectionFrom` anchors a range (shift+arrows/home/end);
---typing/backspace/delete replace the selection. maxLength/readOnly/masked
---(`maskChar` display) and alignment ("left"|"center"|"right") are real
---properties. Overflow keeps the caret visible via an internal scroll.
---Byte-level UTF-8 (Lua 5.1 has no native UTF-8) — documented limitation.
---
---Keys: printable characters, backspace, delete, left/right (shift
---extends selection), home/end (shift too), enter (submit, keeps focus),
---escape (blur). Click positions the caret.

DXUI = DXUI or {}

local Edit = DXUI.Widget:extend("Edit", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node)
        -- clamp caret/selection into the new text
        if node.caret > #node.text then node.caret = #node.text end
        if node.selectionFrom and node.selectionFrom > #node.text then
            node.selectionFrom = nil
        end
    end },
    placeholder = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    -- caret position (byte index); BREAKING: was `cursor` in V3
    caret = { default = 0, type = "number", invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
        local len = #node.text
        if v < 0 then v = 0 end
        if v > len then v = len end
        if node.caret ~= v then node.caret = v end
        -- a plain caret move collapses the selection
        if node.selectionFrom and node.selectionFrom == v then
            node.selectionFrom = nil
        end
    end },
    caretColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    caretWidth = { default = 1, type = "number", min = 1, invalidates = { DXUI.DIRTY.RENDER } },
    caretMode = { default = "blink", invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return v == "blink" or v == "solid" or v == "off" end },
    caretBlinkInterval = { default = nil, invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return v == nil or (type(v) == "number" and v >= 0) end },
    -- selection anchor (byte index); nil = no selection
    selectionFrom = { default = nil, invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return v == nil or type(v) == "number" end,
        onSet = function(node, v)
            if v ~= nil then
                if v < 0 then v = 0 end
                if v > #node.text then v = #node.text end
                if node.selectionFrom ~= v then node.selectionFrom = v end
            end
        end },
    selectionColor = { default = 0x332563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    placeholderColor = { default = 0xFF6B7280, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- placeholder stays visible while focused (default: hidden)
    placeholderVisibleWhenFocused = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    bgColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    focusBorderColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    padding = { default = { left = 8, right = 8, top = 0, bottom = 0 }, invalidates = { DXUI.DIRTY.LAYOUT } },
    alignment = { default = "left", invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return v == "left" or v == "center" or v == "right" end },
    maxLength = { default = 0, type = "number", min = 0, invalidates = { DXUI.DIRTY.RENDER } },
    readOnly = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    masked = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    maskChar = { default = "*", invalidates = { DXUI.DIRTY.RENDER } },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

local EMPTY = ""

--- The string drawn for the current text (masked display).
function Edit:_displayText()
    if self.masked then
        return string.rep(self.maskChar or "*", #self.text)
    end
    return self.text
end

--- Selection range as (lo, hi) byte indexes, or nil without a selection.
function Edit:_selectionRange()
    local from = self.selectionFrom
    if from == nil then return nil end
    local a, b = from, self.caret or 0
    if a > b then a, b = b, a end
    if a == b then return nil end
    return a, b
end

--- Deletes [lo, hi) from the text and places the caret at lo.
function Edit:_deleteRange(lo, hi)
    self.text = self.text:sub(1, lo) .. self.text:sub(hi + 1)
    self.caret = lo
    self.selectionFrom = nil
    if self.emit then self:emit("change", self.text) end
end

--- Inserts a character at the caret (replacing a selection, honoring
--- maxLength/readOnly).
function Edit:_insert(ch)
    if self.readOnly then return end
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) end
    local maxLen = self.maxLength or 0
    if maxLen > 0 and #self.text >= maxLen then return end
    local pos = self.caret or 0
    self.text = self.text:sub(1, pos) .. ch .. self.text:sub(pos + 1)
    self.caret = pos + 1
    if self.emit then self:emit("change", self.text) end
end

--- Deletes the character before the caret (or the selection).
function Edit:_backspace()
    if self.readOnly then return end
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) return end
    local pos = self.caret or 0
    if pos <= 0 then return end
    self.text = self.text:sub(1, pos - 1) .. self.text:sub(pos + 1)
    self.caret = pos - 1
    if self.emit then self:emit("change", self.text) end
end

--- Deletes forward: the selection, or the character after the caret.
function Edit:_deleteForward()
    if self.readOnly then return end
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) return end
    local pos = self.caret or 0
    if pos >= #self.text then return end
    self.text = self.text:sub(1, pos) .. self.text:sub(pos + 2)
    self.caret = pos
    if self.emit then self:emit("change", self.text) end
end

--- Moves the caret; `extend` (shift) anchors/extends the selection.
function Edit:_moveCaret(pos, extend)
    local cur = self.caret or 0
    if extend then
        if self.selectionFrom == nil then self.selectionFrom = cur end
    else
        self.selectionFrom = nil
    end
    self.caret = pos
end

--- Byte index of the caret for a click at design-space x.
function Edit:_caretAtX(lx)
    local display = self:_displayText()
    local padL = (self.padding and self.padding.left) or 8
    local scroll = self._scrollX or 0
    local cx = lx - self.worldX - padL + scroll - (self._alignOff or 0)
    if cx <= 0 then return 0 end
    local len = #display
    local prev = 0
    for i = 1, len do
        local w = DXUI.Text and DXUI.Text.charX(display, self.font, 1, i) or i * 7
        if w >= cx then
            -- snap to the nearer half of the character cell
            if cx - prev > (w - prev) / 2 then return i end
            return i - 1
        end
        prev = w
    end
    return len
end

--- Whether the caret is drawn this frame (blink phase from the clock).
function Edit:_caretOn()
    local mode = self.caretMode
    if mode == "off" then return false end
    if mode == "solid" then return true end
    local iv = self.caretBlinkInterval
        or (DXUI.Settings and DXUI.Settings.defaults and DXUI.Settings.defaults.caretBlinkInterval)
        or 500
    if iv <= 0 then return true end
    local clock = self._context and self._context.clock
    local t = clock and clock() or 0
    t = t - (self._caretPhaseStart or 0)
    return math.floor(t / iv) % 2 == 0
end

--- Align offset (0 when overflowing — overflow scrolls from the left).
function Edit:_alignOffset(textW, contentW)
    if (self._scrollX or 0) > 0 then return 0 end
    local a = self.alignment
    if a == "center" then return (contentW - textW) / 2 end
    if a == "right" then return contentW - textW end
    return 0
end

--- Draws the input box, selection highlight, text/placeholder.
--- The caret itself is an overlay (see Edit:overlay) — blinking never
--- invalidates the cached render list.
function Edit:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local r = self.radius or 4
    local fmt = self:getState()
    local border = (fmt == "focused") and (self.focusBorderColor or self.borderColor)
        or self.borderColor
    renderer:borderedRect(wx, wy, w, h, r, self.bgColor, border, self.borderWidth)

    local padL = (self.padding and self.padding.left) or 8
    local padR = (self.padding and self.padding.right) or 8
    local cw = w - padL - padR
    if cw <= 0 then return end

    local display = self:_displayText()
    -- keep the caret inside the visible area (overflow scroll)
    local textW = DXUI.Text and select(1, DXUI.Text.measure(display, self.font, 1)) or 0
    local scroll = self._scrollX or 0
    if textW <= cw then
        scroll = 0
    else
        local caretX = DXUI.Text and DXUI.Text.charX(display, self.font, 1, self.caret or 0) or 0
        if caretX < scroll then scroll = caretX end
        if caretX > scroll + cw - (self.caretWidth or 1) then
            scroll = caretX - cw + (self.caretWidth or 1)
        end
        if scroll < 0 then scroll = 0 end
        local maxScroll = textW - cw
        if scroll > maxScroll then scroll = maxScroll end
    end
    self._scrollX = scroll
    self._alignOff = self:_alignOffset(textW, cw)

    -- selection highlight (under the text)
    local lo, hi = self:_selectionRange()
    if lo then
        local selX = DXUI.Text and DXUI.Text.charX(display, self.font, 1, lo) or lo * 7
        local selEnd = DXUI.Text and DXUI.Text.charX(display, self.font, 1, hi) or hi * 7
        renderer:rect(wx + padL + self._alignOff - scroll + selX, wy + 2,
            selEnd - selX, h - 4, self.selectionColor)
    end

    local showPlaceholder = display == EMPTY
        and (fmt ~= "focused" or self.placeholderVisibleWhenFocused)
    local shown = showPlaceholder and self.placeholder or display
    if shown ~= EMPTY then
        local color = showPlaceholder and (self.placeholderColor or self.textColor) or self.textColor
        renderer:text(shown, wx + padL + self._alignOff - scroll, wy, cw, h,
            color, self.font, "left", "center", 1)
    end
end

--- Overlay pass (Runtime:draw): caret drawn every frame from the clock
--- without touching the cached render list.
function Edit:overlay(renderer)
    if self._destroyed or not self._visible then return end
    if self.enabled == false then return end
    if self:getState() ~= "focused" then return end
    if not self:_caretOn() then return end
    renderer:_loadClip(self)
    local display = self:_displayText()
    local padL = (self.padding and self.padding.left) or 8
    local cx = DXUI.Text and DXUI.Text.charX(display, self.font, 1, self.caret or 0) or 0
    renderer:rect(self.worldX + padL + (self._alignOff or 0) - (self._scrollX or 0) + cx,
        self.worldY + 2, self.caretWidth or 1, self.height - 4, self.caretColor)
end

--- Registers the overlay when mounted (frame-clock caret repaint).
function Edit:_onMount(ctx)
    local list = ctx and ctx._overlays
    if not list then return end
    for i = 1, #list do
        if list[i] == self then return end
    end
    list[#list + 1] = self
    self._overlayCtx = ctx
end

--- Unregisters the overlay when detached.
function Edit:_onDetached()
    local ctx = self._overlayCtx
    if not ctx then return end
    self._overlayCtx = nil
    local list = ctx._overlays
    if not list then return end
    for i = 1, #list do
        if list[i] == self then
            table.remove(list, i)
            return
        end
    end
end

--- Wires focus/blur/key/character/click behavior for text editing.
Edit._build = function(node)
    node.clip = true
    node:on("focus", function(n)
        n.caret = #n.text
        n.selectionFrom = nil
        n._caretPhaseStart = n._context and n._context.clock() or 0
        n:setState("focused")
    end, "dxui-edit")
    node:on("blur", function(n)
        n.selectionFrom = nil
        n:setState("normal")
    end, "dxui-edit")
    node:on("key", function(n, keyName, pressed, shift)
        if not pressed then return true end
        local caret = n.caret or 0
        if keyName == "backspace" then n:_backspace()
        elseif keyName == "delete" then n:_deleteForward()
        elseif keyName == "enter" then
            if n.emit then n:emit("submit", n.text) end
        elseif keyName == "escape" then
            if n._context and n._context.dispatcher then
                n._context.dispatcher:setFocus(nil)
            end
        elseif keyName == "left" then
            n:_moveCaret(math.max(0, caret - 1), shift)
        elseif keyName == "right" then
            n:_moveCaret(math.min(#n.text, caret + 1), shift)
        elseif keyName == "home" then
            n:_moveCaret(0, shift)
        elseif keyName == "end" then
            n:_moveCaret(#n.text, shift)
        end
        return true
    end, "dxui-edit")
    node:on("character", function(n, ch)
        n:_insert(ch)
    end, "dxui-edit")
    node:on("click", function(n, _, x, y)
        -- click positions the caret (x/y are design coordinates)
        n.caret = n:_caretAtX(x)
        n.selectionFrom = nil
    end, "dxui-edit")
end

DXUI.Builders.register("Edit", Edit)