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
---Keys: printable characters, backspace, delete, arrow_l/arrow_r (shift
---extends selection), home/end (shift too), enter (submit, keeps focus),
---escape (blur). Key names follow the MTA wiki (Key_names). Click
---positions the caret.
---
---Undo/redo: ctrl+z / ctrl+y step through USER edits only (typing,
---backspace/delete, selection replace); programmatic `text` writes do
---not record — the next user edit re-baselines the chain. Keystrokes
---within 300 ms coalesce into one undo step. History depth:
---Settings.defaults.editHistoryLimit (0 = history off).
---
---AutoComplete: `autoComplete = {"alpha","algol"}` (built-in prefix filter)
---or `autoComplete = function(prefix) return candidates end`. The
---dropdown lists up to `autoCompleteMax` (8) entries; arrow_u/arrow_d
---move, enter/tab insert (replacing the typed prefix), escape closes.

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
    -- autoComplete: an ARRAY of candidate strings (built-in case-
    -- insensitive prefix filter) or a function(prefix, node) returning an
    -- array | nil. The dropdown opens under the Edit on USER edits only
    -- (Popup sibling — outside-click closes it, LAYER.POPUP)
    autoComplete = { default = nil, invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return v == nil or type(v) == "table" or type(v) == "function" end },
    autoCompleteMax = { default = 8, type = "number", min = 1, invalidates = { DXUI.DIRTY.RENDER } },
    masked = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    maskChar = { default = "*", invalidates = { DXUI.DIRTY.RENDER } },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

local EMPTY = ""
-- keystrokes closer than this coalesce into one undo step
local HIST_COALESCE_MS = 300

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
--- Internal helper — the PUBLIC entry points wrap history around it.
function Edit:_deleteRange(lo, hi)
    self.text = self.text:sub(1, lo) .. self.text:sub(hi + 1)
    self.caret = lo
    self.selectionFrom = nil
    if self.emit then self:emit("change", self.text) end
end

-- ---------------------------------------------------------------------
-- Undo/redo (user edits only; see the file header)
-- ---------------------------------------------------------------------

--- History limit (defaults.editHistoryLimit, 64; 0 = history off).
local function historyLimit()
    local d = DXUI.Settings and DXUI.Settings.defaults
    local v = d and d.editHistoryLimit
    if v == nil then v = 64 end
    return v
end

--- Captures the pre-edit state (call BEFORE a user mutation). Returns the
--- pre-state table, or nil when history is off. Re-baselines the chain
--- when the text changed outside user edits since the last snapshot (the
--- old chain is stale then).
function Edit:_histPre()
    local limit = historyLimit()
    if limit <= 0 then self._editHistory = nil return nil end
    local h = self._editHistory
    local pre = { text = self.text, caret = self.caret or 0, sel = self.selectionFrom }
    if not h or #h == 0 then
        self._editHistory = { pre }
        self._editHistPos = 1
        return pre
    end
    local cur = h[self._editHistPos]
    if not cur or cur.text ~= pre.text then
        self._editHistory = { pre }
        self._editHistPos = 1
        return pre
    end
    return pre
end

--- Commits the post-edit state (call AFTER a user mutation). A rapid
--- keystroke burst (< HIST_COALESCE_MS) collapses into ONE undo step;
--- after an undo the next edit starts a fresh branch (redo tail drops).
function Edit:_histPost(pre)
    if pre == nil then return end
    if pre.text == self.text and pre.caret == (self.caret or 0)
        and pre.sel == self.selectionFrom then
        return -- nothing changed (maxLength clamp, empty insert, ...)
    end
    local h = self._editHistory
    local pos = self._editHistPos
    local post = { text = self.text, caret = self.caret or 0, sel = self.selectionFrom }
    local clock = self._context and self._context.clock
    local now = clock and clock() or 0
    if pos == #h and now - (self._editLastT or 0) < HIST_COALESCE_MS then
        -- coalesce into the current step
        h[pos] = post
    else
        -- drop the redo tail, push the new branch state
        for i = #h, pos + 1, -1 do h[i] = nil end
        h[#h + 1] = post
        if #h > historyLimit() then
            -- oldest drops out; pos == #h keeps the pointer consistent
            table.remove(h, 1)
        end
        self._editHistPos = #h
    end
    self._editLastT = now
end

--- Applies a snapshot WITHOUT recording (undo/redo path).
function Edit:_histApply(snap)
    if not snap then return end
    self.text = snap.text or ""
    self.caret = snap.caret or 0
    self.selectionFrom = snap.sel
    if self.emit then self:emit("change", self.text) end
end

--- Steps back one user edit (ctrl+z). No-op at the chain start.
function Edit:_undo()
    local h = self._editHistory
    local pos = self._editHistPos
    if not h or pos <= 1 then return end
    self._editHistPos = pos - 1
    self:_histApply(h[pos - 1])
    -- next user edit starts a fresh burst (no coalescing across undo)
    self._editLastT = nil
end

--- Steps forward one undone edit (ctrl+y). No-op without a redo tail.
function Edit:_redo()
    local h = self._editHistory
    local pos = self._editHistPos
    if not h or pos >= #h then return end
    self._editHistPos = pos + 1
    self:_histApply(h[pos + 1])
    self._editLastT = nil
end

-- ---------------------------------------------------------------------
-- AutoComplete (dropdown under the Edit; see the file header)
-- ---------------------------------------------------------------------

--- The word prefix at the caret: (prefix string, 1-based start byte).
function Edit:_acPrefix()
    local caret = self.caret or 0
    local text = self.text
    local s = 1
    for i = caret, 1, -1 do
        local b = text:byte(i)
        if b == 32 or b == 10 or b == 9 then s = i + 1 break end
    end
    return text:sub(s, caret), s
end

--- Refreshes the dropdown after a USER edit (programmatic writes never
--- trigger it — the same rule as undo history). Opens when the resolved
--- candidate list is non-empty, closes otherwise.
function Edit:_updateAutoComplete()
    local src = self.autoComplete
    if src == nil then self:_acClose() return end
    local prefix, s = self:_acPrefix()
    if prefix == "" then self:_acClose() return end
    local cands = nil
    if type(src) == "function" then
        -- user callbacks run guarded: a throw must not break typing
        local ok, res = pcall(src, prefix, self)
        if ok then cands = res end
    else
        -- built-in filter: case-insensitive prefix match
        local lower = prefix:lower()
        cands = {}
        for i = 1, #src do
            local it = src[i]
            if type(it) == "string" and it:lower():sub(1, #prefix) == lower then
                cands[#cands + 1] = it
            end
        end
    end
    if type(cands) ~= "table" or #cands == 0 then self:_acClose() return end
    local maxItems = self.autoCompleteMax or 8
    for i = #cands, maxItems + 1, -1 do cands[i] = nil end
    self._acList = cands
    self._acActive = 1
    self._acPrefixStart = s
    self:_acShow()
end

--- Creates (once) and shows the dropdown: a Popup SIBLING of the Edit —
--- children would be clipped by the Edit's own clip; the sibling floats
--- beside it in the same coordinate space.
function Edit:_acShow()
    local Popup = DXUI.Widgets and DXUI.Widgets.Popup
    if not Popup then return end
    local p = self._acPopup
    if not p or p._destroyed then
        p = Popup:new({ x = self.x, y = self.y, width = self.width, height = 10 })
        -- parent to the Edit's PARENT (sibling): escapes the clip; the
        -- dispatcher popup manager closes it on outside clicks
        p:setParent(self._parent or self)
        if DXUI.LAYER then p.layer = DXUI.LAYER.POPUP end
        p.zIndex = 900
        p._acEdit = self
        local ITEM_H = 18
        p.render = function(ps, renderer)
            local e = ps._acEdit
            local cands = e and e._acList
            if not cands then return end
            local wx, wy, w, h = ps.worldX, ps.worldY, ps.width, ps.height
            renderer:borderedRect(wx, wy, w, h, 6, 0xFFFFFFFF, 0xFFD1D5DB, 1)
            local active = e._acActive or 1
            for i = 1, #cands do
                local y0 = wy + 4 + (i - 1) * ITEM_H
                if i == active then
                    renderer:rect(wx + 2, y0, w - 4, ITEM_H, 0xFF2563EB)
                end
                local tc = (i == active) and 0xFFFFFFFF or 0xFF111827
                renderer:text(cands[i], wx + 8, y0, w - 16, ITEM_H,
                    tc, e.font, "left", "center", 1)
            end
        end
        p:on("click", function(ps, _, px, py)
            local e = ps._acEdit
            if not e or not e._acList then return end
            local rel = py - ps.worldY - 4
            local idx = math.floor(rel / ITEM_H) + 1
            if idx >= 1 and idx <= #e._acList then
                e._acActive = idx
                e:_acApply()
            end
        end, "dxui-edit-ac")
        self._acPopup = p
    end
    -- size to the candidates (never narrower than the Edit)
    local cands = self._acList
    local maxW = self.width
    for i = 1, #cands do
        local tw = DXUI.Text and select(1, DXUI.Text.measure(cands[i], self.font, 1)) or 0
        if tw + 16 > maxW then maxW = tw + 16 end
    end
    p.width = maxW
    p.height = #cands * 18 + 8
    p.x = self.x
    p.y = self.y + self.height
    self._acOpen = true
    p:open(p.x, p.y)
end

--- Closes the dropdown (keeps the popup node for reuse).
function Edit:_acClose()
    self._acOpen = false
    self._acList = nil
    self._acActive = nil
    local p = self._acPopup
    if p and not p._destroyed and p.close then
        p:close()
    end
end

--- Moves the active suggestion (keyboard).
function Edit:_acMove(d)
    local list = self._acList
    if not list or #list == 0 then return end
    local a = (self._acActive or 1) + d
    if a < 1 then a = 1 elseif a > #list then a = #list end
    if a ~= self._acActive then
        self._acActive = a
        local p = self._acPopup
        if p and p._invalidate then p:_invalidate({ DXUI.DIRTY.RENDER }) end
    end
end

--- Inserts the active candidate in place of the typed prefix (a USER
--- edit: recorded in undo history like typing).
function Edit:_acApply()
    local cand = self._acList and self._acList[self._acActive or 1]
    self:_acClose()
    if not cand then return end
    local s = self._acPrefixStart or 1
    local caret = self.caret or 0
    local pre = self:_histPre()
    self.text = self.text:sub(1, s - 1) .. cand .. self.text:sub(caret + 1)
    self.caret = s - 1 + #cand
    self.selectionFrom = nil
    if self.emit then self:emit("change", self.text) end
    self:_histPost(pre)
    self._editLastT = nil
end

--- Inserts a character at the caret (replacing a selection, honoring
--- maxLength/readOnly).
function Edit:_insert(ch)
    if self.readOnly then return end
    local pre = self:_histPre()
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) end
    local maxLen = self.maxLength or 0
    if maxLen > 0 and #self.text >= maxLen then return end
    local pos = self.caret or 0
    self.text = self.text:sub(1, pos) .. ch .. self.text:sub(pos + 1)
    self.caret = pos + 1
    if self.emit then self:emit("change", self.text) end
    self:_histPost(pre)
    self:_updateAutoComplete()
end

--- Deletes the character before the caret (or the selection).
function Edit:_backspace()
    if self.readOnly then return end
    local pre = self:_histPre()
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) return end
    local pos = self.caret or 0
    if pos <= 0 then return end
    self.text = self.text:sub(1, pos - 1) .. self.text:sub(pos + 1)
    self.caret = pos - 1
    if self.emit then self:emit("change", self.text) end
    self:_histPost(pre)
    self:_updateAutoComplete()
end

--- Deletes forward: the selection, or the character after the caret.
function Edit:_deleteForward()
    if self.readOnly then return end
    local pre = self:_histPre()
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) return end
    local pos = self.caret or 0
    if pos >= #self.text then return end
    self.text = self.text:sub(1, pos) .. self.text:sub(pos + 2)
    self.caret = pos
    if self.emit then self:emit("change", self.text) end
    self:_histPost(pre)
    self:_updateAutoComplete()
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
    self:_acClose()
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
        n:_acClose()
        n:setState("normal")
    end, "dxui-edit")
    node:on("key", function(n, keyName, pressed, shift)
        if not pressed then return true end
        -- undo/redo first: ctrl+z / ctrl+y (poll the modifier — the
        -- dispatcher routes only shift)
        local ctrl = getKeyState and (getKeyState("lctrl") or getKeyState("rctrl"))
        if ctrl then
            if keyName == "z" then
                n:_undo()
                return true
            elseif keyName == "y" then
                n:_redo()
                return true
            end
        end
        -- open dropdown first: arrows/enter/tab/escape belong to it
        if n._acOpen and n._acList then
            if keyName == "arrow_u" then
                n:_acMove(-1)
                return true
            elseif keyName == "arrow_d" then
                n:_acMove(1)
                return true
            elseif keyName == "enter" or keyName == "tab" then
                n:_acApply()
                return true
            elseif keyName == "escape" then
                n:_acClose()
                return true
            end
        end
        local caret = n.caret or 0
        if keyName == "backspace" then n:_backspace()
        elseif keyName == "delete" then n:_deleteForward()
        elseif keyName == "enter" then
            if n.emit then n:emit("submit", n.text) end
        elseif keyName == "escape" then
            if n._context and n._context.dispatcher then
                n._context.dispatcher:setFocus(nil)
            end
        elseif keyName == "arrow_l" then
            n:_moveCaret(math.max(0, caret - 1), shift)
        elseif keyName == "arrow_r" then
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