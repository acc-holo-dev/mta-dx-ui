---Memo — multi-line text input (DXUI Widget) built on the Edit
---mechanics: byte caret into the whole `text` ("\n" is a normal byte),
---selection anchors (shift+arrows), undo/redo (ctrl+z/ctrl+y, see
---widgets/edit.lua for the semantics), readOnly/maxLength.
---
---    local m = ui:memo({ x=0, y=0, width=260, height=120,
---                         placeholder="Notes...", wrap=true })
---    m:on("submit", function(n, text) save(text) end)  -- ctrl+enter
---
---Lines: `wrap=true` folds long logical lines to the client width (the
---fold cut is byte-based — never inside a UTF-8 sequence — and estimated
---from the average char width, so it approximates, not pixel-perfect);
---`wrap=false` keeps logical lines intact and scrolls horizontally with
---the caret. Enter inserts "\n", ctrl+enter emits "submit". Vertical
---scroll: mouse wheel (3 lines per notch); the focused caret always
---stays visible. Key names follow the MTA wiki: arrow_u/d/l/r, home,
---end, pgup, pgdn.
---
---No masking (that is a single-line Edit feature). Byte-level UTF-8 —
---documented limitation, same as Edit.

DXUI = DXUI or {}

local Memo = DXUI.Widget:extend("Memo", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node)
        -- clamp caret/selection into the new text
        if node.caret > #node.text then node.caret = #node.text end
        if node.selectionFrom and node.selectionFrom > #node.text then
            node.selectionFrom = nil
        end
    end },
    placeholder = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    -- caret position (byte index into the whole text)
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
    placeholderVisibleWhenFocused = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    bgColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    focusBorderColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    padding = { default = { left = 8, right = 8, top = 4, bottom = 4 }, invalidates = { DXUI.DIRTY.LAYOUT } },
    maxLength = { default = 0, type = "number", min = 0, invalidates = { DXUI.DIRTY.RENDER } },
    readOnly = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    -- fold long lines to the client width (false = h-scroll instead)
    wrap = { default = true, invalidates = { DXUI.DIRTY.RENDER } },
    -- explicit visual line height (px); nil = measured text height + 2
    lineHeight = { default = nil, invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v) return v == nil or (type(v) == "number" and v >= 8) end },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

local EMPTY = ""

--- Returns the effective visual line height from explicit prop or theme metric.
function Memo:_lineHeight()
    return self.lineHeight or self:_metric("lineHeight", nil)
end

--- Returns the effective caret width from explicit prop or theme metric.
function Memo:_caretWidth()
    return self.caretWidth or self:_metric("caretWidth", 1)
end

--- Returns the effective caret blink interval from explicit prop, theme metric, or engine default.
function Memo:_caretBlinkInterval()
    return self.caretBlinkInterval
        or self:_metric("caretBlinkInterval", nil)
        or (DXUI.Settings and DXUI.Settings.defaults and DXUI.Settings.defaults.caretBlinkInterval)
        or 500
end

--- Returns the scroll step in lines from theme metrics.
function Memo:_scrollStepLines()
    return self:_metric("scrollStepLines", 3)
end

--- Returns the undo coalesce window from theme metrics.
function Memo:_undoCoalesceMs()
    return self:_metric("undoCoalesceMs", 300)
end

--- History limit (defaults.editHistoryLimit, 64; 0 = history off).
local function historyLimit()
    local d = DXUI.Settings and DXUI.Settings.defaults
    local v = d and d.editHistoryLimit
    if v == nil then v = 64 end
    return v
end

--- Selection range as (lo, hi) byte indexes, or nil without a selection.
function Memo:_selectionRange()
    local from = self.selectionFrom
    if from == nil then return nil end
    local a, b = from, self.caret or 0
    if a > b then a, b = b, a end
    if a == b then return nil end
    return a, b
end

--- Deletes [lo, hi) from the text and places the caret at lo.
--- Internal helper — the PUBLIC entry points wrap history around it.
function Memo:_deleteRange(lo, hi)
    self.text = self.text:sub(1, lo) .. self.text:sub(hi + 1)
    self.caret = lo
    self.selectionFrom = nil
    if self.emit then self:emit("change", self.text) end
end

-- ---------------------------------------------------------------------
-- Undo/redo (user edits only; the semantics mirror widgets/edit.lua)
-- ---------------------------------------------------------------------

--- Captures the pre-edit state (call BEFORE a user mutation). Returns
--- the pre-state table, or nil when history is off. Re-baselines the
--- chain when the text changed outside user edits since the last
--- snapshot (the old chain is stale then).
function Memo:_histPre()
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
--- keystroke burst (< HIST_COALESCE_MS) collapses into ONE undo step.
function Memo:_histPost(pre)
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
        h[pos] = post
    else
        for i = #h, pos + 1, -1 do h[i] = nil end
        h[#h + 1] = post
        if #h > historyLimit() then
            table.remove(h, 1)
        end
        self._editHistPos = #h
    end
    self._editLastT = now
end

--- Applies a snapshot WITHOUT recording (undo/redo path).
function Memo:_histApply(snap)
    if not snap then return end
    self.text = snap.text or ""
    self.caret = snap.caret or 0
    self.selectionFrom = snap.sel
    if self.emit then self:emit("change", self.text) end
end

--- Steps back one user edit (ctrl+z). No-op at the chain start.
function Memo:_undo()
    local h = self._editHistory
    local pos = self._editHistPos
    if not h or pos <= 1 then return end
    self._editHistPos = pos - 1
    self:_histApply(h[pos - 1])
    self._editLastT = nil
end

--- Steps forward one undone edit (ctrl+y). No-op without a redo tail.
function Memo:_redo()
    local h = self._editHistory
    local pos = self._editHistPos
    if not h or pos >= #h then return end
    self._editHistPos = pos + 1
    self:_histApply(h[pos + 1])
    self._editLastT = nil
end

-- ---------------------------------------------------------------------
-- Mutations (byte-string generic, same contract as Edit)
-- ---------------------------------------------------------------------

--- Inserts a string (character or "\n") at the caret.
function Memo:_insert(ch)
    if self.readOnly or not ch or ch == EMPTY then return end
    local pre = self:_histPre()
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) end
    local maxLen = self.maxLength or 0
    if maxLen > 0 and #self.text >= maxLen then return end
    local pos = self.caret or 0
    self.text = self.text:sub(1, pos) .. ch .. self.text:sub(pos + 1)
    self.caret = pos + #ch
    if self.emit then self:emit("change", self.text) end
    self:_histPost(pre)
end

--- Deletes the character before the caret (or the selection).
function Memo:_backspace()
    if self.readOnly then return end
    local pre = self:_histPre()
    local lo, hi = self:_selectionRange()
    if lo then self:_deleteRange(lo, hi) return end
    local pos = self.caret or 0
    if pos <= 0 then return end
    -- deleting a "\n" merges two visual lines
    self.text = self.text:sub(1, pos - 1) .. self.text:sub(pos + 1)
    self.caret = pos - 1
    if self.emit then self:emit("change", self.text) end
    self:_histPost(pre)
end

--- Deletes forward: the selection, or the character after the caret.
function Memo:_deleteForward()
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
end

--- Moves the caret; `extend` (shift) anchors/extends the selection.
function Memo:_moveCaret(pos, extend)
    local cur = self.caret or 0
    if extend then
        if self.selectionFrom == nil then self.selectionFrom = cur end
    else
        self.selectionFrom = nil
    end
    self.caret = pos
end

-- ---------------------------------------------------------------------
-- Visual lines
-- ---------------------------------------------------------------------

--- Visual line table { {s = text, o = caret offset of the start}, ... }:
--- logical lines split on "\n"; wrap=true folds long lines by an
--- estimated per-byte width, never splitting INSIDE a UTF-8 sequence.
function Memo:_buildLines(cw)
    local text = self.text or ""
    if text == EMPTY then
        return { { s = EMPTY, o = 0 } }
    end
    local font = self.font
    local wrap = self.wrap ~= false
    local out = {}
    local pos = 1
    while true do
        local nl = text:find("\n", pos, true)
        local seg = nl and text:sub(pos, nl - 1) or text:sub(pos)
        local o = pos - 1
        local fullW = DXUI.Text and select(1, DXUI.Text.measure(seg, font, 1)) or (#seg * 7)
        if not wrap or seg == EMPTY or cw <= 0 or fullW <= cw then
            out[#out + 1] = { s = seg, o = o }
        else
            -- fold: max bytes per visual line from the average byte width
            local avg = fullW / #seg
            local maxBytes = math.max(4, math.floor(cw / math.max(avg, 1)))
            local i = 1
            local nseg = #seg
            while i <= nseg do
                local j = i + maxBytes - 1
                if j >= nseg then
                    j = nseg
                else
                    -- back up onto the UTF-8 sequence head (>= 0xC0);
                    -- continuation bytes are 0x80..0xBF
                    local b = seg:byte(j)
                    while j > i and b and b >= 0x80 and b < 0xC0 do
                        j = j - 1
                        b = seg:byte(j)
                    end
                end
                out[#out + 1] = { s = seg:sub(i, j), o = o + i - 1 }
                i = j + 1
            end
        end
        if not nl then break end
        pos = nl + 1
    end
    return out
end

--- Visual line index holding the caret (0-based offsets; a caret exactly
--- before a "\n" belongs to that line's END, a fold boundary belongs to
--- the NEXT visual line).
function Memo:_caretLineIdx(lines, caret)
    local text = self.text or EMPTY
    local n = #lines
    for i = 1, n do
        local ln = lines[i]
        local endC = ln.o + #ln.s
        if caret < endC then return i end
        if caret == endC then
            if i == n then return i end
            if text:byte(caret + 1) == 10 then return i end
        end
    end
    return n
end

--- Maps a design-space click to a caret position (visual line + column).
function Memo:_caretAt(x, y)
    local lines = self._lastLines
    if not lines or #lines == 0 then return 0 end
    local pad = self.padding or {}
    local padL = pad.left or 8
    local padT = pad.top or 4
    local lh = self._lineH or 18
    local rel = y - self.worldY - padT + (self._scrollY or 0)
    local idx = math.floor(rel / lh) + 1
    if idx < 1 then idx = 1 elseif idx > #lines then idx = #lines end
    local ln = lines[idx]
    local s = ln.s
    local cx = x - self.worldX - padL + (self._scrollX or 0)
    if cx <= 0 then return ln.o end
    local col = #s
    local prev = 0
    for i = 1, #s do
        local wd = DXUI.Text and DXUI.Text.charX(s, self.font, 1, i) or i * 7
        if wd >= cx then
            if cx - prev > (wd - prev) / 2 then col = i else col = i - 1 end
            break
        end
        prev = wd
    end
    return ln.o + col
end

--- Whether the caret is drawn this frame (blink phase from the clock).
function Memo:_caretOn()
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

-- ---------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------

--- Draws the box, the visible lines, the selection and the placeholder.
--- The caret itself is an overlay (see Memo:overlay) — blinking never
--- invalidates the cached render list.
function Memo:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local r = self.radius or 4
    local fmt = self:getState()
    local border = (fmt == "focused") and (self.focusBorderColor or self.borderColor)
        or self.borderColor
    renderer:borderedRect(wx, wy, w, h, r, self.bgColor, border, self.borderWidth)

    local pad = self.padding or {}
    local padL = pad.left or 8
    local padR = pad.right or 8
    local padT = pad.top or 4
    local padB = pad.bottom or 4
    local cw = w - padL - padR
    local viewH = h - padT - padB
    if cw <= 0 or viewH <= 0 then return end

    local font = self.font
    local lines = self:_buildLines(cw)
    self._lastLines = lines
    local lh = self.lineHeight
    if not lh then
        lh = (DXUI.Text and select(2, DXUI.Text.measure("Ag", font, 1))) or 14
        lh = lh + 2
    end
    self._lineH = lh
    local n = #lines

    -- caret line + x (computed BEFORE scroll clamping: it drives them)
    local caret = self.caret or 0
    local li = self:_caretLineIdx(lines, caret)
    local line = lines[li]
    local caretCol = math.min(caret - line.o, #line.s) + 1
    local caretX = DXUI.Text and DXUI.Text.charX(line.s, font, 1, caretCol)
        or (caretCol - 1) * 7

    -- vertical scroll (internal px): the focused caret stays visible
    local contentH = n * lh
    local maxScroll = contentH - viewH
    if maxScroll < 0 then maxScroll = 0 end
    self._maxScrollY = maxScroll
    local scroll = self._scrollY or 0
    if fmt == "focused" then
        local caretTop = (li - 1) * lh
        local caretBottom = caretTop + lh
        if caretTop < scroll then scroll = caretTop
        elseif caretBottom > scroll + viewH then scroll = caretBottom - viewH end
    end
    if scroll < 0 then scroll = 0 elseif scroll > maxScroll then scroll = maxScroll end
    self._scrollY = scroll

    -- horizontal scroll (wrap off): Edit-style caret-following
    local hScroll = 0
    if self.wrap == false then
        local lineW = DXUI.Text and select(1, DXUI.Text.measure(line.s, font, 1)) or 0
        if lineW > cw then
            local cur = self._scrollX or 0
            if caretX < cur then hScroll = caretX
            elseif caretX > cur + cw - (self.caretWidth or 1) then
                hScroll = caretX - cw + (self.caretWidth or 1)
            else hScroll = cur end
            if hScroll < 0 then hScroll = 0
            elseif hScroll > lineW - cw then hScroll = lineW - cw end
        end
    end
    self._scrollX = hScroll

    -- cached for the overlay (caret) and click mapping
    self._caretScrX = wx + padL - hScroll + caretX
    self._caretScrY = wy + padT + (li - 1) * lh - scroll

    -- visible line range (culling)
    local first = math.floor(scroll / lh) + 1
    local last = math.ceil((scroll + viewH) / lh)
    if first < 1 then first = 1 end
    if last > n then last = n end

    local selLo, selHi = self:_selectionRange()
    for i = first, last do
        local ln = lines[i]
        local y0 = wy + padT + (i - 1) * lh - scroll
        if selLo then
            -- selection ∩ this visual line
            local cA = math.max(selLo, ln.o) - ln.o + 1
            local cB = math.min(selHi, ln.o + #ln.s) - ln.o
            if cA <= cB then
                local x0 = DXUI.Text and DXUI.Text.charX(ln.s, font, 1, cA - 1) or (cA - 1) * 7
                local x1 = DXUI.Text and DXUI.Text.charX(ln.s, font, 1, cB) or cB * 7
                renderer:rect(wx + padL - hScroll + x0, y0, x1 - x0, lh, self.selectionColor)
            end
        end
        if ln.s ~= EMPTY then
            renderer:text(ln.s, wx + padL - hScroll, y0, cw, lh,
                self.textColor, font, "left", "top", 1)
        end
    end

    -- placeholder (only while empty; logical lines, no folding)
    local showPlaceholder = self.text == EMPTY
        and (fmt ~= "focused" or self.placeholderVisibleWhenFocused)
        and self.placeholder ~= EMPTY
    if showPlaceholder then
        local ph = self.placeholder
        local idx = 0
        local pos = 1
        repeat
            local nl = ph:find("\n", pos, true)
            idx = idx + 1
            local seg = nl and ph:sub(pos, nl - 1) or ph:sub(pos)
            local y0 = wy + padT + (idx - 1) * lh - scroll
            if idx >= first and idx <= last and idx <= viewH / lh + 1 then
                renderer:text(seg, wx + padL - hScroll, y0, cw, lh,
                    self.placeholderColor or self.textColor, font, "left", "top", 1)
            end
            pos = nl and (nl + 1) or #ph + 1
        until not nl
    end

    -- v-scrollbar thumb
    if maxScroll > 0 then
        local th = viewH * viewH / contentH
        if th < 20 then th = 20 end
        renderer:roundedRect(wx + w - 8, wy + (h - th) * (scroll / maxScroll),
            6, th, 3, self.borderColor)
    end
end

--- Overlay pass (Runtime:draw): caret drawn every frame from the clock
--- without touching the cached render list.
function Memo:overlay(renderer)
    if self._destroyed or not self._visible then return end
    if self.enabled == false then return end
    if self:getState() ~= "focused" then return end
    if not self:_caretOn() then return end
    local cx = self._caretScrX
    local cy = self._caretScrY
    if cx == nil or cy == nil then return end
    renderer:_loadClip(self)
    renderer:rect(cx, cy, self.caretWidth or 1, self._lineH or 14, self.caretColor)
end

--- Registers the overlay when mounted (frame-clock caret repaint).
function Memo:_onMount(ctx)
    local list = ctx and ctx._overlays
    if not list then return end
    for i = 1, #list do
        if list[i] == self then return end
    end
    list[#list + 1] = self
    self._overlayCtx = ctx
end

--- Unregisters the overlay when detached.
function Memo:_onDetached()
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

--- Wires focus/blur/key/character/click/scroll behavior.
Memo._build = function(node)
    node.clip = true
    node:on("focus", function(n)
        n.caret = #n.text
        n.selectionFrom = nil
        n._caretPhaseStart = n._context and n._context.clock() or 0
        n:setState("focused")
    end, "dxui-memo")
    node:on("blur", function(n)
        n.selectionFrom = nil
        n:setState("normal")
    end, "dxui-memo")
    node:on("key", function(n, keyName, pressed, shift)
        if not pressed then return true end
        local ctrl = getKeyState and (getKeyState("lctrl") or getKeyState("rctrl"))
        -- undo/redo first (mirror the Edit handler)
        if ctrl and (keyName == "z" or keyName == "y") then
            if keyName == "z" then n:_undo() else n:_redo() end
            return true
        end
        local caret = n.caret or 0
        if keyName == "backspace" then n:_backspace()
        elseif keyName == "delete" then n:_deleteForward()
        elseif keyName == "enter" then
            if ctrl then
                if n.emit then n:emit("submit", n.text) end
            else
                n:_insert("\n")
            end
        elseif keyName == "escape" then
            if n._context and n._context.dispatcher then
                n._context.dispatcher:setFocus(nil)
            end
        elseif keyName == "arrow_l" then
            n._memoCol = nil
            n:_moveCaret(math.max(0, caret - 1), shift)
        elseif keyName == "arrow_r" then
            n._memoCol = nil
            n:_moveCaret(math.min(#n.text, caret + 1), shift)
        elseif keyName == "arrow_u" or keyName == "arrow_d" then
            local lines = n._lastLines
            if lines and #lines > 0 then
                local li = n:_caretLineIdx(lines, caret)
                local target = n._memoCol
                if target == nil then target = caret - lines[li].o end
                local other = (keyName == "arrow_u") and lines[li - 1] or lines[li + 1]
                if other then
                    local col = math.min(target, #other.s)
                    n._memoCol = target
                    n:_moveCaret(other.o + col, shift)
                end
            end
        elseif keyName == "home" then
            n._memoCol = nil
            local lines = n._lastLines
            if lines and #lines > 0 then
                local ln = lines[n:_caretLineIdx(lines, caret)]
                n:_moveCaret(ln.o, shift)
            else
                n:_moveCaret(0, shift)
            end
        elseif keyName == "end" then
            n._memoCol = nil
            local lines = n._lastLines
            if lines and #lines > 0 then
                local ln = lines[n:_caretLineIdx(lines, caret)]
                n:_moveCaret(ln.o + #ln.s, shift)
            else
                n:_moveCaret(#n.text, shift)
            end
        elseif ctrl and keyName == "a" then
            -- select all: anchor at 0, caret at the end
            n.caret = #n.text
            n.selectionFrom = 0
        else
            return false
        end
        return true
    end, "dxui-memo")
    node:on("character", function(n, ch)
        n:_insert(ch)
    end, "dxui-memo")
    node:on("click", function(n, _, x, y)
        -- click positions the caret (x/y are design coordinates)
        n.caret = n:_caretAt(x, y)
        n.selectionFrom = nil
    end, "dxui-memo")
    node:on("scroll", function(n, wheel)
        local lh = n._lineH or 18
        local max = n._maxScrollY or 0
        if max <= 0 then return true end
        local s = (n._scrollY or 0) - wheel * lh * 3
        if s < 0 then s = 0 elseif s > max then s = max end
        n._scrollY = s
        n:_invalidate({ DXUI.DIRTY.RENDER })
        return true
    end, "dxui-memo")
end

DXUI.Builders.register("Memo", Memo)