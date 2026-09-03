---GridList — a flat, selectable item list with wheel scrolling.
---
---Single-column mode (columns = nil — the classic): items are strings or
---{text=...}; hover highlight; click selects (single).
---
---Columns mode: columns = { {key, title, width[, align, sortable]}, ... }.
---Rows are {cells = {[key]=string|number|{text=...}}, ...} (a flat row
---{[key]=value} also works). Sum of widths > client width → horizontal
---scroll (wheel or shift+wheel). Clicking a sortable header sorts
---asc/desc — items rearrange IN PLACE; selection survives by row
---identity. Multi-select (multiSelect=true): plain click re-selects,
---ctrl+click toggles, shift+click selects the range from the anchor;
---keyboard arrow_u/arrow_d/home/end/pgup/pgdn (+shift extend, +ctrl moves
---the anchor only), ctrl+A selects all (MTA key names). Emits "select" (single),
---"select-multi" (index array) and "sort" (colIndex, direction).
---
---    local gl = ui:gridlist({ x=0, y=0, width=200, height=300 })
---    gl:addItem("Player 1"); gl:addItem("Player 2")
---    gl:on("select", function(n, index, item) ... end)
---
---    local gl = ui:gridlist({
---        columns = {
---            { key = "name",  title = "Name",  width = 120, sortable = true },
---            { key = "score", title = "Score", width = 80, align = "right", sortable = true },
---        },
---        rowHeight = 22, multiSelect = true,
---    })
---    gl.items = { { cells = { name = "Ann", score = 5 } } }
---    gl:sort(1, "asc")


DXUI = DXUI or {}

--- Display text of one cell (columns mode): {cells={[key]=v}} rows, flat
--- {[key]=v} rows, numbers and {text=...} all coerce to strings.
local function cellDisplay(row, col)
    if type(row) ~= "table" then return tostring(row) end
    local v = (row.cells and row.cells[col.key]) or row[col.key]
    if type(v) == "table" then v = v.text end
    if v == nil then return "" end
    return tostring(v)
end

--- Raw cell value for sorting (numbers stay numbers; strings compare
--- byte-wise — Cyrillic order is codepage-stable, not dictionary-wise).
local function cellSortKey(row, key)
    local v
    if type(row) == "table" then
        v = (row.cells and row.cells[key]) or row[key]
        if type(v) == "table" then v = v.text end
    end
    if v == nil then return "" end
    return v
end

local GridList = DXUI.Widget:extend("GridList", {
    items = { default = {}, invalidates = { DXUI.DIRTY.RENDER } },
    selectedIndex = { default = 0, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, i)
        if node.emit then node:emit("select", i, node.items and node.items[i]) end
    end },
    -- columns mode: { {key, title, width[, align, sortable]}, ... };
    -- nil = classic single-column list (strings / {text=...} rows)
    columns = { default = nil, invalidates = { DXUI.DIRTY.RENDER },
        validate = function(v)
            if v == nil then return true end
            if type(v) ~= "table" then return false end
            for i = 1, #v do
                local c = v[i]
                if type(c) ~= "table" or type(c.width) ~= "number" or c.width <= 0 then
                    return false
                end
            end
            return true
        end },
    -- horizontal scroll fraction (columns overflow the client width)
    scrollX = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- multi-selection enable (ctrl/shift/keyboard range selection)
    multiSelect = { default = false, invalidates = { DXUI.DIRTY.INPUT } },
    -- selected row indexes (display order); setSelectedIndices normalizes
    selectedIndices = { default = {}, invalidates = { DXUI.DIRTY.RENDER } },
    rowHeight = { default = 22, invalidates = { DXUI.DIRTY.LAYOUT } },
    scrollY = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    hoverColor = { default = 0xFFF3F4F6, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    selectedColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    selectedTextColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    headerColor = { default = 0xFFE5E7EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    headerTextColor = { default = 0xFF374151, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- opt-in persistent RT content cache: idle frames draw ONE composite
    -- image instead of the rows; scrolling inside a half-height margin
    -- window is a pure section shift (rebake on leaving it). RT size =
    -- width × height × 2 (keep the node ≤ ~1000 px tall). Ignored when
    -- the node has blur/mask. In-place row text edits are NOT detected —
    -- re-assign `items` to force a rebake. See render/state.lua.
    cacheContent = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    -- keyboard navigation needs focus (arrows/home/end/pageup/pagedown,
    -- ctrl+A)
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

-- ---------------------------------------------------------------------
-- Component metrics (theme-driven geometry; see style/defaults.lua)
-- ---------------------------------------------------------------------

--- Row text left padding (single-column mode).
function GridList:_rowTextPadX() return self:_metric("rowTextPadX", 6) end
--- Header text left padding (columns mode).
function GridList:_headerTextPadX() return self:_metric("headerTextPadX", 4) end
--- Header text right padding (columns mode).
function GridList:_headerTextPadRight() return self:_metric("headerTextPadRight", 8) end
--- Cell text left/right padding (columns mode).
function GridList:_cellPadX() return self:_metric("cellPadX", 4) end
--- Scrollbar thumb minimum length.
function GridList:_minThumbSize() return self:_metric("minThumbSize", 20) end
--- Scrollbar thumb thickness.
function GridList:_thumbWidth() return self:_metric("thumbWidth", 6) end
--- Scrollbar thumb corner radius.
function GridList:_thumbRadius() return self:_metric("thumbRadius", 3) end
--- Scrollbar thumb inset from the list edge.
function GridList:_thumbInset() return self:_metric("thumbInset", 8) end
--- Sort-direction icon reserved width in the header.
function GridList:_sortIconSize() return self:_metric("sortIconSize", 8) end
--- Persistent-RT bake margin as a fraction of the node height.
function GridList:_rtMarginFactor() return self:_metric("rtMarginFactor", 0.5) end

--- Columns-mode content width (sum of the column widths).
function GridList:_contentWidth()
    local cols = self.columns
    if not cols then return 0 end
    local tw = 0
    for i = 1, #cols do tw = tw + cols[i].width end
    return tw
end

--- Horizontal pixel offset (0 without overflow).
function GridList:_hOffsetPx()
    local cw = self:_contentWidth()
    if cw <= self.width then return 0 end
    return self.scrollX * (cw - self.width)
end

--- Vertical scroll offset, header height and the v-scroll range (px).
function GridList:_vOffset()
    local rh = self.rowHeight or 22
    local headerH = self.columns and rh or 0
    local total = #(self.items or {}) * rh
    local visible = self.height - headerH
    local maxScroll = total - visible
    local off = 0
    if maxScroll > 0 then off = self.scrollY * maxScroll end
    return off, headerH, maxScroll
end

--- Returns the row index at the given design coordinates, or nil.
function GridList:_rowAt(designX, designY)
    local rh = self.rowHeight or 22
    local off, headerH = self:_vOffset()
    local rel = designY - self.worldY - headerH + off
    local idx = math.floor(rel / rh) + 1
    if idx < 1 or idx > #(self.items or {}) then return nil end
    if designX < self.worldX or designX >= self.worldX + self.width then return nil end
    return idx
end

--- Column index at design X (header clicks), honoring the horizontal scroll.
function GridList:_colAt(designX)
    local cols = self.columns
    if not cols then return nil end
    local x = designX - self.worldX + self:_hOffsetPx()
    local cx = 0
    for i = 1, #cols do
        cx = cx + cols[i].width
        if x < cx then return i end
    end
    return nil
end

--- Small sort-direction triangle in the header (px rects — no font glyph
--- needed; MTA default fonts lack the Unicode arrows).
function GridList:_drawSortMark(renderer, cx, cy, dir)
    local c = self.headerTextColor or self.textColor
    if dir == "asc" then
        renderer:rect(cx - 3, cy + 1, 7, 1, c)
        renderer:rect(cx - 2, cy, 5, 1, c)
        renderer:rect(cx - 1, cy - 1, 3, 1, c)
    else
        renderer:rect(cx - 3, cy - 1, 7, 1, c)
        renderer:rect(cx - 2, cy, 5, 1, c)
        renderer:rect(cx - 1, cy + 1, 3, 1, c)
    end
end

--- Wires click selection (multi/ctrl/shift), header-click sorting, row
--- hover, wheel scrolling (incl. horizontal) and keyboard navigation.
GridList._build = function(node)
    node.clip = true
    -- rows with textKey re-translate on locale switches (a Translate
    -- binding whose applyTranslation only invalidates the render)
    if DXUI._textBindings then
        DXUI._textBindings[node] = true
    end
    -- rows are NOT child widgets, so the list opts into continuous pointer
    -- position (the dispatcher emits pointer-move to hovered opt-ins only)
    node._hasPointerMove = true
    node:on("pointer-move", function(n, x, y)
        local i = n:_rowAt(x, y)
        if i ~= n._hoverRow then
            n._hoverRow = i
            n:_invalidate({ DXUI.DIRTY.RENDER })
        end
    end, "dxui-grid")
    node:on("hover-end", function(n)
        if n._hoverRow ~= nil then
            n._hoverRow = nil
            n:_invalidate({ DXUI.DIRTY.RENDER })
        end
    end, "dxui-grid")
    node:on("click", function(n, button, x, y)
        local rh = n.rowHeight or 22
        -- columns mode: a click inside the header row sorts that column
        if n.columns and y - n.worldY < rh then
            local c = n:_colAt(x)
            if c then
                if n._sortCol == c then
                    n:sort(c, n._sortDir == "asc" and "desc" or "asc")
                else
                    n:sort(c, "asc")
                end
            end
            return
        end
        local i = n:_rowAt(x, y)
        if not i then return end
        local ctrl = getKeyState and (getKeyState("lctrl") or getKeyState("rctrl"))
        local shift = getKeyState and (getKeyState("lshift") or getKeyState("rshift"))
        if n.multiSelect then
            if ctrl then
                n:_toggleSelect(i)
            elseif shift then
                n:_rangeSelect(n._selAnchor or i, i)
            else
                n:_singleSelect(i)
            end
        else
            n:_singleSelect(i)
        end
    end, "dxui-grid")
    node:on("scroll", function(n, wheel)
        local rh = n.rowHeight or 22
        local headerH = n.columns and rh or 0
        local total = #(n.items or {}) * rh
        local visible = n.height - headerH
        local shift = getKeyState and (getKeyState("lshift") or getKeyState("rshift"))
        -- horizontal scroll: shift+wheel, or plain wheel when there is
        -- nothing to scroll vertically (columns overflow)
        local cw = n:_contentWidth()
        local hRange = (cw > n.width) and (cw - n.width) or 0
        if hRange > 0 and (shift or visible >= total) then
            local nx = n.scrollX + wheel * rh / hRange
            if nx < 0 then nx = 0 elseif nx > 1 then nx = 1 end
            n.scrollX = nx
            return true
        end
        -- nothing to scroll when the list fits the viewport: leave
        -- scrollY alone (no visible effect; avoids drift)
        if visible >= total then return true end
        local range = total - visible
        -- spec min/max VALIDATE (they error, they do not clamp): clamp
        -- here, or the last wheel notch overshoots [0,1] and throws
        local nextY = n.scrollY - wheel * rh / range
        if nextY < 0 then nextY = 0 elseif nextY > 1 then nextY = 1 end
        n.scrollY = nextY
        return true
    end, "dxui-grid")
    node:on("key", function(n, keyName, pressed, shift)
        if not pressed then return true end
        local ctrl = getKeyState and (getKeyState("lctrl") or getKeyState("rctrl"))
        local items = n.items or {}
        local count = #items
        if count == 0 then return false end
        if ctrl and keyName == "a" then
            if n.multiSelect then
                local all = {}
                for i = 1, count do all[i] = i end
                n.selectedIndices = all
                if n.emit then n:emit("select-multi", n:getSelectedIndices()) end
            end
            return true
        end
        local rh = n.rowHeight or 22
        local visible = math.max(1, math.floor((n.height - (n.columns and rh or 0)) / rh))
        local cur = n._selAnchor or n.selectedIndex or 1
        local target = nil
        if keyName == "arrow_u" then target = math.max(1, cur - 1)
        elseif keyName == "arrow_d" then target = math.min(count, cur + 1)
        elseif keyName == "home" then target = 1
        elseif keyName == "end" then target = count
        elseif keyName == "pgup" then target = math.max(1, cur - visible)
        elseif keyName == "pgdn" then target = math.min(count, cur + visible)
        else return false end
        n:_moveSel(target, shift, ctrl)
        -- scroll follows the anchor
        n:_ensureVisible(n._selAnchor or n.selectedIndex)
        return true
    end, "dxui-grid")
end

--- Appends an item to the list.
function GridList:addItem(item)
    self.items[#self.items + 1] = item
    return self
end

-- ---------------------------------------------------------------------
-- Selection API (multi)
-- ---------------------------------------------------------------------

--- Plain click: single selection; indices stay consistent in both modes.
function GridList:_singleSelect(i)
    self._selAnchor = i
    self.selectedIndices = { i }
    self.selectedIndex = i
end

--- ctrl+click: toggle one row in the selection set.
function GridList:_toggleSelect(i)
    local sel = self:getSelectedIndices()
    local found = false
    for k = 1, #sel do
        if sel[k] == i then table.remove(sel, k) found = true break end
    end
    if not found then
        sel[#sel + 1] = i
        table.sort(sel)
    end
    self._selAnchor = i
    self.selectedIndices = sel
    if self.emit then self:emit("select-multi", self:getSelectedIndices()) end
end

--- shift+click: fill the range from the anchor (inclusive both ends).
function GridList:_rangeSelect(a, b)
    if a > b then a, b = b, a end
    local sel = {}
    for i = a, b do sel[#sel + 1] = i end
    self.selectedIndices = sel
    if self.emit then self:emit("select-multi", self:getSelectedIndices()) end
end

--- Keyboard move: plain = single select, shift = extend from the anchor,
--- ctrl = move the anchor only (selection untouched, desktop-list style).
function GridList:_moveSel(target, extend, anchorOnly)
    if self.multiSelect then
        if anchorOnly then
            self._selAnchor = target
        elseif extend then
            self:_rangeSelect(self._selAnchor or target, target)
        else
            self:_singleSelect(target)
        end
    else
        self._selAnchor = target
        self.selectedIndices = { target }
        self.selectedIndex = target
    end
end

--- Ordered copy of the selected row indexes.
function GridList:getSelectedIndices()
    local out = {}
    local sel = self.selectedIndices or {}
    for i = 1, #sel do out[i] = sel[i] end
    return out
end

--- Replaces the whole selection: clamped to existing rows, deduped,
--- ascending. The last index becomes the shift anchor.
function GridList:setSelectedIndices(indices)
    if type(indices) ~= "table" then return self end
    local seen = {}
    local out = {}
    local n = #(self.items or {})
    for i = 1, #indices do
        local idx = indices[i]
        if type(idx) == "number" and idx >= 1 and idx <= n and not seen[idx] then
            seen[idx] = true
            out[#out + 1] = idx
        end
    end
    table.sort(out)
    self._selAnchor = out[#out]
    self.selectedIndices = out
    if self.emit then self:emit("select-multi", self:getSelectedIndices()) end
    return self
end

--- Scrolls so the row index is inside the viewport (keyboard navigation).
function GridList:_ensureVisible(idx)
    if not idx or idx < 1 then return end
    local rh = self.rowHeight or 22
    local off, headerH, maxScroll = self:_vOffset()
    if maxScroll <= 0 then return end
    local top = (idx - 1) * rh
    local bottom = top + rh
    local visBottom = off + self.height - headerH
    local newOff = off
    if top < off then newOff = top
    elseif bottom > visBottom then newOff = bottom - (self.height - headerH) end
    if newOff ~= off then
        local ny = newOff / maxScroll
        if ny < 0 then ny = 0 elseif ny > 1 then ny = 1 end
        self.scrollY = ny
    end
end

-- ---------------------------------------------------------------------
-- Sorting (columns mode)
-- ---------------------------------------------------------------------

--- Sorts the items by a column, direction "asc"|"desc" (default asc).
--- Items rearrange IN PLACE; the selection is preserved by row identity
--- and re-mapped to the new order. Non-sortable columns are ignored.
function GridList:sort(colIndex, direction)
    local cols = self.columns
    local col = cols and cols[colIndex]
    if not col or col.sortable == false then return self end
    direction = (direction == "desc") and "desc" or "asc"
    local items = self.items or {}
    -- extract keys once per row (O(n)); numbers sort numerically
    local keyed = {}
    for i = 1, #items do
        local raw = cellSortKey(items[i], col.key)
        keyed[i] = {
            row = items[i],
            num = (type(raw) == "number") and raw or nil,
            str = (type(raw) ~= "number") and tostring(raw) or nil,
        }
    end
    local function less(a, b)
        if a.num and b.num then
            return (direction == "asc") and a.num < b.num or a.num > b.num
        end
        local as, bs = a.str or "", b.str or ""
        return (direction == "asc") and as < bs or as > bs
    end
    table.sort(keyed, less)
    -- remember selection/anchors by ITEM IDENTITY before moving rows
    local selected = {}
    local sel = self.selectedIndices or {}
    for k = 1, #sel do
        local it = items[sel[k]]
        if it ~= nil then selected[it] = true end
    end
    local anchorItem = items[self._selAnchor or 0]
    local selIdxItem = items[self.selectedIndex or 0]
    for i = 1, #keyed do items[i] = keyed[i].row end
    -- re-map selection to the new order
    local newSel = {}
    for i = 1, #items do
        if selected[items[i]] then newSel[#newSel + 1] = i end
    end
    self.selectedIndices = newSel
    if anchorItem ~= nil then
        for i = 1, #items do
            if items[i] == anchorItem then self._selAnchor = i break end
        end
    end
    if selIdxItem ~= nil then
        -- property write: re-emits "select" with the NEW index (the row
        -- moved — consumers deserve to know)
        for i = 1, #items do
            if items[i] == selIdxItem then self.selectedIndex = i break end
        end
    end
    self._sortCol = colIndex
    self._sortDir = direction
    self:_invalidate({ DXUI.DIRTY.RENDER })
    if self.emit then self:emit("sort", colIndex, direction) end
    return self
end

--- Display text of a row (single-column mode): string | {text=…} |
--- {textKey=…} — textKey rows translate in the INSTANCE locale (falling
--- back to the engine locale), so they switch live on locale changes.
function GridList:_rowText(item)
    if type(item) ~= "table" then return tostring(item) end
    local k = item.textKey
    if k ~= nil then
        local T = DXUI.Translate
        if T then
            local ctx = self._context
            local loc = (ctx and ctx.getLocale and ctx:getLocale()) or T.locale
            return T.trFor(loc, k)
        end
        return k
    end
    return item.text or ""
end

--- Translate binding: rows with textKey re-render on locale switches.
function GridList:applyTranslation()
    self:_invalidate({ DXUI.DIRTY.RENDER })
    return self
end

--- Draws the visible rows and the scrollbar thumb (in cacheContent mode
--- the row window extends ± half the node height — the margin that makes
--- scrolling a pure composite-section shift).
function GridList:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local rh = self.rowHeight or 22
    local items = self.items or {}
    local rowPadX = self:_rowTextPadX()
    local minThumb = self:_minThumbSize()
    local thumbW = self:_thumbWidth()
    local thumbR = self:_thumbRadius()
    local thumbInset = self:_thumbInset()
    local first, last
    if self.cacheContent then
        self:_rtUpdateScrollState()
        first, last = self:_rtRowWindow()
    end
    if self.columns then
        self:_renderColumns(renderer, wx, wy, w, h, rh, items, self.columns, first, last)
        return
    end
    -- single-column mode: the classic path (window = visible, or the
    -- wider bake window in cacheContent mode)
    local total = #items * rh
    local maxScroll = total - h
    local off = 0
    if maxScroll > 0 then off = self.scrollY * maxScroll end
    local sel = self.selectedIndex or 0
    local hoverIdx = self._hoverRow
    if not first then
        -- only iterate the visible row range (off = scroll offset in px)
        first = math.floor(off / rh) + 1
        last = math.ceil((h + off) / rh)
        if first < 1 then first = 1 end
        if last > #items then last = #items end
    end
    for i = first, last do
        local y0 = wy + (i - 1) * rh - off
        local bg = sel == i and self.selectedColor
            or (hoverIdx == i and self.hoverColor) or nil
        if bg then renderer:rect(wx, y0, w, rh, bg) end
        local tc = sel == i and (self.selectedTextColor or self.textColor) or self.textColor
        renderer:text(self:_rowText(items[i]), wx + rowPadX, y0, w - rowPadX * 2, rh, tc, self.font, "left", "center", 1)
    end
    -- scrollbar thumb
    if maxScroll > 0 then
        local th = h * h / total
        if th < minThumb then th = minThumb end
        renderer:roundedRect(wx + w - thumbInset, wy + (h - th) * self.scrollY, thumbW, th, thumbR, self.borderColor)
    end
end

--- Columns-mode renderer: fixed header (h-scrolls with the rows), row
--- strip, column separators, v/h scroll thumbs. `first`/`last` override
--- the visible row window (the cacheContent bake margin).
function GridList:_renderColumns(renderer, wx, wy, w, h, rh, items, cols, first, last)
    local headerPadX = self:_headerTextPadX()
    local headerPadRight = self:_headerTextPadRight()
    local cellPadX = self:_cellPadX()
    local sortIcon = self:_sortIconSize()
    local minThumb = self:_minThumbSize()
    local thumbW = self:_thumbWidth()
    local thumbR = self:_thumbRadius()
    local thumbInset = self:_thumbInset()
    local cw = 0
    for i = 1, #cols do cw = cw + cols[i].width end
    local hOff = (cw > w) and self.scrollX * (cw - w) or 0
    local total = #items * rh
    local visible = h - rh
    local maxScroll = total - visible
    local off = 0
    if maxScroll > 0 then off = self.scrollY * maxScroll end
    local sel = self.selectedIndex or 0
    -- O(1) selected lookup for this frame
    local selMap = nil
    local selArr = self.selectedIndices or {}
    if #selArr > 0 then
        selMap = {}
        for i = 1, #selArr do selMap[selArr[i]] = true end
    end
    local hoverIdx = self._hoverRow
    -- header (never scrolls vertically; scrolls horizontally with rows)
    renderer:rect(wx, wy, w, rh, self.headerColor or self.hoverColor)
    local hx = wx - hOff
    for i = 1, #cols do
        local col = cols[i]
        renderer:text(col.title or "", hx + headerPadX, wy, col.width - headerPadX - headerPadRight, rh,
            self.headerTextColor or self.textColor, self.font,
            col.align or "left", "center", 1)
        if self._sortCol == i then
            self:_drawSortMark(renderer, hx + col.width - sortIcon, wy + rh / 2, self._sortDir)
        end
        hx = hx + col.width
    end
    -- column separators
    local sx = wx - hOff
    for i = 1, #cols - 1 do
        sx = sx + cols[i].width
        renderer:rect(sx, wy, 1, h, self.borderColor)
    end
    -- rows (culling: visible window, or the caller's bake window)
    if not first then
        first = math.floor(off / rh) + 1
        last = math.ceil((visible + off) / rh)
        if first < 1 then first = 1 end
        if last > #items then last = #items end
    end
    for i = first, last do
        local y0 = wy + rh + (i - 1) * rh - off
        local isSel = (sel == i) or (selMap and selMap[i])
        local bg = isSel and self.selectedColor
            or (hoverIdx == i and self.hoverColor) or nil
        if bg then renderer:rect(wx, y0, w, rh, bg) end
        local tc = isSel and (self.selectedTextColor or self.textColor) or self.textColor
        local cx = wx - hOff
        local row = items[i]
        for c = 1, #cols do
            local col = cols[c]
            renderer:text(cellDisplay(row, col), cx + cellPadX, y0, col.width - cellPadX * 2, rh,
                tc, self.font, col.align or "left", "center", 1)
            cx = cx + col.width
        end
    end
    -- vertical thumb (track starts below the header)
    if maxScroll > 0 then
        local th = visible * visible / total
        if th < minThumb then th = minThumb end
        renderer:roundedRect(wx + w - thumbInset, wy + rh + (visible - th) * self.scrollY,
            thumbW, th, thumbR, self.borderColor)
    end
    -- horizontal thumb
    if cw > w then
        local tw = w * w / cw
        if tw < minThumb then tw = minThumb end
        renderer:roundedRect(wx + (w - tw) * self.scrollX, wy + h - thumbInset, tw, thumbW, thumbR,
            self.borderColor)
    end
end

DXUI.Builders.register("GridList", GridList)

-- ---------------------------------------------------------------------
-- Persistent RT cache lifecycle (cacheContent)
-- ---------------------------------------------------------------------

--- Releases the keyed RT and the cache state. Called on detach (the node
--- left the tree) and on destroy; a hidden-but-attached node keeps its
--- RT (same VRAM cost as one texture — usually fine).
function GridList:_rtRelease()
    if self._rtKey and DXUI.BackendMTA and DXUI.BackendMTA.destroyPersistentRT then
        DXUI.BackendMTA.destroyPersistentRT(self._rtKey)
    end
    self._rtBaseOff = nil
    self._rtShift = nil
    self._rtSig = nil
    self._rtSigDirty = nil
end

--- Detached: free the persistent RT (a re-attach rebakes from scratch).
function GridList:_onDetached()
    self:_rtRelease()
end

--- Destroyed: the keyed RT must not outlive the node.
function GridList:_onDestroy()
    self:_rtRelease()
end

--- cacheContent bookkeeping (called from render): decides whether the
--- draw phase REBAKES the persistent RT (content changed / scrolled out
--- of the margin window) or only shifts the composite section.
function GridList:_rtUpdateScrollState()
    local sy = (self._context and self._context._mapScaleY) or 1
    -- content signature: identity-compared tables (items/columns) +
    -- scalars. scrollY is NOT here — it goes through the shift math.
    local cur = {
        self.items, #self.items, self.selectedIndex, self.selectedIndices,
        self._hoverRow, self._sortCol, self._sortDir,
        self.width, self.height, self.columns, self.scrollX,
        self.color, self.textColor, self.selectedColor, self.hoverColor,
    }
    local s = self._rtSig
    local changed = not s or self._rtSigDirty == nil
    if s and not changed then
        for i = 1, #cur do
            if cur[i] ~= s[i] then changed = true break end
        end
    end
    if changed then
        self._rtSig = cur
    end
    local off = self:_vOffset()
    local base = self._rtBaseOff
    local d = off - (base or off)
    -- margin: a fraction of the node height (design px); the RT holds the
    -- client window plus this margin above and below
    local m = (self.height or 0) * self:_rtMarginFactor()
    if changed or not base or d < -m * 0.9 or d > m * 0.9 then
        -- rebake: re-anchor the RT at the current scroll
        self._rtBaseOff = off
        self._rtShift = 0
        self._rtSigDirty = true
    else
        self._rtShift = d * sy
        self._rtSigDirty = false
    end
end

--- Row window for the RT bake: the visible client ± half the node height
--- of margin rows (scroll inside the margin = a section shift only).
function GridList:_rtRowWindow()
    local rh = self.rowHeight or 22
    local off = self:_vOffset()
    local items = self.items or {}
    local m = (self.height or 0) * self:_rtMarginFactor()
    local first = math.floor(math.max(0, off - m) / rh) + 1
    local last = math.ceil(math.min(#items * rh, off + self.height + m) / rh)
    if first < 1 then first = 1 end
    if last > #items then last = #items end
    if last < first then last = first end
    return first, last
end