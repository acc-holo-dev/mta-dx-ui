--[[
    edit.lua — DXUI V2

    Edit: single/multi-line input. Focus via dispatcher (mousedown
    automatic). Input — "text" event; special keys — "key" event (MTA names).

    State (internal, _ prefix): _cursor (0-based), _selAnchor, _goalCol
    (vertical navigation), _hasFocus. The text property is the source
    of truth.

    Cursor/selection geometry via text engine (measure, cached): exact font
    metrics in MTA (dxGetTextSize); line height measured (EDIT_LINE_H
    fallback outside MTA). Selection drawn per-line: first/last line partial
    rects, middle full. Drag-select: motion with the left button held
    extends the selection from the grab point.

    Clipboard: internal context buffer + MTA setClipboard/getClipboard when
    available (outside MTA — internal only, testable).
]]

DXUI = DXUI or {}

local EDIT_PAD_X = 4
local EDIT_PAD_Y = 2
local EDIT_LINE_H = 15

local Edit = DXUI.Widget:extend("Edit", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    placeholder = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    readonly = { default = false, invalidates = {} },
    multiline = { default = false, invalidates = {} },
    maxLength = { default = 0, invalidates = {} },
    placeholderColor = { default = 0xFF888888, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    cursorColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

-- ---------------------------------------------------------------------
-- Internal: lines / cursor
-- ---------------------------------------------------------------------

local function splitLines(s)
    local lines = {}
    local start = 1
    while true do
        local nl = s:find("\n", start, true)
        if not nl then lines[#lines + 1] = s:sub(start); break end
        lines[#lines + 1] = s:sub(start, nl - 1)
        start = nl + 1
    end
    return lines
end

function Edit:_rowCol(cursor)
    local lines = splitLines(self.text)
    local acc = 1
    for i = 1, #lines do
        local len = #lines[i]
        if cursor <= acc - 1 + len then
            return i, cursor - (acc - 1)
        end
        acc = acc + len + 1
    end
    return #lines, #lines[#lines] or 0
end

function Edit:_selRange()
    local a, b = self._selAnchor, self._cursor
    if a > b then a, b = b, a end
    return a, b
end

--- Text of line row (per _rowCol numbering).
function Edit:_rowText(row)
    local lines = splitLines(self.text)
    return lines[row] or ""
end

--- Column pixel via text engine (measure, cached).
-- MTA: dxGetTextSize — exact per the real font; outside MTA — monospace.
function Edit:_colX(row, col)
    local line = self:_rowText(row)
    local w = DXUI.Text.measure(line:sub(1, col), self.font, 1)
    return EDIT_PAD_X + w
end

--- Inverse: local pixel x → column of line row (nearest by width).
function Edit:_colFromX(row, px)
    local line = self:_rowText(row)
    local target = px - EDIT_PAD_X
    local best, bestDist = 0, target -- col 0: dist = |0 - target|
    if bestDist < 0 then bestDist = -bestDist end
    for col = 1, #line do
        local w = DXUI.Text.measure(line:sub(1, col), self.font, 1)
        local dist = w - target
        if dist < 0 then dist = -dist end
        if dist < bestDist then best, bestDist = col, dist end
    end
    local endW = DXUI.Text.measure(line, self.font, 1)
    if target > endW then best = #line end
    return best
end

--- Line height via text engine: exact metrics in MTA;
-- outside MTA — monospace estimate (EDIT_LINE_H fallback).
function Edit:_lineHeight()
    local _, h = DXUI.Text.measure("Ag", self.font, 1)
    if h and h > 0 then return h end
    return EDIT_LINE_H
end

--- Event point (design coords) → (row, col). Shared geometry
--- for field click and drag-select.
function Edit:_posToRowCol(px, py)
    local ly = py - self.worldY - EDIT_PAD_Y
    local row = math.floor(ly / self:_lineHeight()) + 1
    if row < 1 then row = 1 end
    local lines = splitLines(self.text)
    if row > #lines then row = #lines end
    if row < 1 then row = 1 end
    local col = self:_colFromX(row, px - self.worldX)
    return row, col
end

--- (row, col) → 0-based cursor position in the full text.
function Edit:_rowColToCursor(row, col)
    local lines = splitLines(self.text)
    local acc = 1
    for i = 1, row - 1 do acc = acc + #lines[i] + 1 end
    return (acc - 1) + col
end

-- ---------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------

function Edit:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)

    if self.text == "" then
        if not self._hasFocus and self.placeholder ~= "" then
            renderer:text(self.placeholder, self.worldX + EDIT_PAD_X, self.worldY + EDIT_PAD_Y, self.width - EDIT_PAD_X * 2, self.height, self.placeholderColor, self.font)
        end
    else
        renderer:text(self.text, self.worldX + EDIT_PAD_X, self.worldY + EDIT_PAD_Y, self.width - EDIT_PAD_X * 2, self.height, self.textColor, self.font)
    end

    -- selection: per-line rects (first/last line partial,
    -- middle full); widths via text engine measure
    if self._hasFocus then
        local a, b = self:_selRange()
        if b > a then
            local lh = self:_lineHeight()
            local rowA, colA = self:_rowCol(a)
            local rowB, colB = self:_rowCol(b)
            if rowA == rowB then
                local x1 = self:_colX(rowA, colA)
                local x2 = self:_colX(rowB, colB)
                renderer:rect(self.worldX + x1, self.worldY + EDIT_PAD_Y + (rowA - 1) * lh,
                    x2 - x1, lh, 0x663399FF)
            else
                -- first line: from colA to end of line
                local x1 = self:_colX(rowA, colA)
                local endW = DXUI.Text.measure(self:_rowText(rowA), self.font, 1)
                renderer:rect(self.worldX + x1, self.worldY + EDIT_PAD_Y + (rowA - 1) * lh,
                    EDIT_PAD_X + endW - x1, lh, 0x663399FF)
                -- middle lines: full
                for row = rowA + 1, rowB - 1 do
                    local w = DXUI.Text.measure(self:_rowText(row), self.font, 1)
                    renderer:rect(self.worldX + EDIT_PAD_X, self.worldY + EDIT_PAD_Y + (row - 1) * lh,
                        w, lh, 0x663399FF)
                end
                -- last line: from start to colB
                local x2 = self:_colX(rowB, colB)
                renderer:rect(self.worldX + EDIT_PAD_X, self.worldY + EDIT_PAD_Y + (rowB - 1) * lh,
                    x2 - EDIT_PAD_X, lh, 0x663399FF)
            end
        end
    end

    -- cursor
    if self._hasFocus and not self.readonly then
        local lh = self:_lineHeight()
        local row, col = self:_rowCol(self._cursor)
        local cx = self:_colX(row, col)
        renderer:rect(self.worldX + cx, self.worldY + EDIT_PAD_Y + (row - 1) * lh, 2, lh, self.cursorColor)
    end
end

-- ---------------------------------------------------------------------
-- Editing
-- ---------------------------------------------------------------------

function Edit:_insert(text)
    local a, b = self:_selRange()
    self.text = self.text:sub(1, a) .. text .. self.text:sub(b + 1)
    self._cursor = a + #text
    self._selAnchor = self._cursor
    if self.maxLength > 0 and #self.text > self.maxLength then
        self.text = self.text:sub(1, self.maxLength)
        self._cursor = math.min(self._cursor, #self.text)
        self._selAnchor = self._cursor
    end
end

function Edit:_handleKey(key, mods)
    local isCtrl = mods and mods:find("ctrl") ~= nil

    if isCtrl then
        if key == "a" then
            self._selAnchor = 0
            self._cursor = #self.text
            return
        elseif key == "c" then
            local a, b = self:_selRange()
            if b > a then
                local s = self.text:sub(a + 1, b)
                self._context.clipboard = s
                if setClipboard then setClipboard(s) end -- MTA: shared OS clipboard
            end
            return
        elseif key == "v" then
            -- MTA: shared OS clipboard (getClipboard); otherwise internal buffer
            local s = self._context.clipboard
            if getClipboard then
                local ok, v = pcall(getClipboard)
                if ok and type(v) == "string" and v ~= "" then s = v end
            end
            if s ~= nil and s ~= "" then
                if not self.multiline then s = s:gsub("\n", "") end
                self:_insert(s)
                self:_emitChange()
            end
            return
        elseif key == "x" then
            local a, b = self:_selRange()
            if b > a then
                local s = self.text:sub(a + 1, b)
                self._context.clipboard = s
                if setClipboard then setClipboard(s) end
                self:_insert("")
                self:_emitChange()
            end
            return
        end
    end

    -- escape: leave the field — works even in readonly
    if key == "escape" then
        if self._context then self._context:setFocus(nil) end
        return
    end

    if self.readonly then return end

    if key == "backspace" then
        local a, b = self:_selRange()
        if b > a then
            self:_insert("")
        elseif self._cursor > 0 then
            self.text = self.text:sub(1, self._cursor - 1) .. self.text:sub(self._cursor + 1)
            self._cursor = self._cursor - 1
            self._selAnchor = self._cursor
        end
        self:_emitChange()
    elseif key == "delete" then
        local a, b = self:_selRange()
        if b > a then
            self:_insert("")
        elseif self._cursor < #self.text then
            self.text = self.text:sub(1, self._cursor) .. self.text:sub(self._cursor + 2)
        end
        self:_emitChange()
    elseif key == "arrow_l" then
        if self._cursor > 0 then self._cursor = self._cursor - 1 end
        self._goalCol = nil
        if not (mods and mods:find("shift")) then self._selAnchor = self._cursor end
    elseif key == "arrow_r" then
        if self._cursor < #self.text then self._cursor = self._cursor + 1 end
        self._goalCol = nil
        if not (mods and mods:find("shift")) then self._selAnchor = self._cursor end
    elseif key == "arrow_u" or key == "arrow_d" then
        -- vertical navigation (multiline): remember the target column
        -- (_goalCol) so movement works across lines of different lengths
        local row, col = self:_rowCol(self._cursor)
        local lines = splitLines(self.text)
        if self._goalCol == nil then self._goalCol = col end
        if key == "arrow_u" and row > 1 then
            local up = row - 1
            self._cursor = self:_rowColToCursor(up, math.min(self._goalCol, #self:_rowText(up)))
        elseif key == "arrow_d" and row < #lines then
            local dn = row + 1
            self._cursor = self:_rowColToCursor(dn, math.min(self._goalCol, #self:_rowText(dn)))
        end
        if not (mods and mods:find("shift")) then self._selAnchor = self._cursor end
    elseif key == "home" then
        self._cursor = 0
        self._goalCol = nil
        if not (mods and mods:find("shift")) then self._selAnchor = self._cursor end
    elseif key == "end" then
        self._cursor = #self.text
        self._goalCol = nil
        if not (mods and mods:find("shift")) then self._selAnchor = self._cursor end
    elseif key == "enter" then
        if self.multiline then
            self:_insert("\n")
            self:_emitChange()
        else
            for i = 1, #self._enterCbs do self._enterCbs[i]() end
        end
    end
end

function Edit:_emitChange()
    for i = 1, #self._changeCbs do self._changeCbs[i](self.text) end
end

-- ---------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------

function Edit:getText() return self.text end

function Edit:setText(text)
    self.text = tostring(text or "")
    self._cursor = #self.text
    self._selAnchor = self._cursor
    return self
end

function Edit:getCursor() return self._cursor end

function Edit:setCursor(pos)
    self._cursor = pos
    if self._cursor < 0 then self._cursor = 0 end
    if self._cursor > #self.text then self._cursor = #self.text end
    self._selAnchor = self._cursor
    -- cursor position is render state: without invalidation it sticks
    self:_invalidate({ DXUI.DIRTY.RENDER })
    return self
end

function Edit:getSelection()
    local a, b = self:_selRange()
    return a, b
end

function Edit:setSelection(start, finish)
    self._selAnchor = start or 0
    self._cursor = finish or self._selAnchor
    self:_invalidate({ DXUI.DIRTY.RENDER })
    return self
end

function Edit:setPlaceholder(t) self.placeholder = t or ""; return self end
function Edit:setMaxLength(n) self.maxLength = n or 0; return self end
function Edit:setReadonly(v) self.readonly = v == true; return self end
function Edit:onChange(fn) self._changeCbs[#self._changeCbs + 1] = fn; return self end
function Edit:onEnter(fn) self._enterCbs[#self._enterCbs + 1] = fn; return self end

-- ---------------------------------------------------------------------
-- Builder
-- ---------------------------------------------------------------------

--- Builder: ui:edit({ text=, placeholder=, readonly=, multiline=, maxLength=,
-- onChange=, onEnter=, ... }).
function Edit.build(context, props)
    props = props or {}
    local node = Edit:new(props)
    if props.width == nil then node.width = 160 end
    if props.height == nil then node.height = (props.multiline and 64) or 24 end
    node._cursor = #node.text
    node._selAnchor = node._cursor
    node._hasFocus = false
    node._changeCbs = {}
    node._enterCbs = {}
    if props.onChange then node._changeCbs[#node._changeCbs + 1] = props.onChange end
    if props.onEnter then node._enterCbs[#node._enterCbs + 1] = props.onEnter end

    node:on("mousedown", function(e)
        context:setFocus(node)
        if not node:isAlive() then return end
        -- cursor at click position: row by Y, column via text engine
        local row, col = node:_posToRowCol(e.x, e.y)
        node._cursor = node:_rowColToCursor(row, col)
        node._selAnchor = node._cursor
        node:_invalidate({ DXUI.DIRTY.RENDER })
        -- drag-select: motion with the button held extends the selection
        -- (_selAnchor fixed at the grab point, _cursor moves)
        if e.button == "left" then
            context.dispatcher:beginDrag(function(px, py)
                if not node:isAlive() or not node._hasFocus then return end
                local r, c = node:_posToRowCol(px, py)
                node._cursor = node:_rowColToCursor(r, c)
                node:_invalidate({ DXUI.DIRTY.RENDER })
            end)
        end
    end)

    node:on("text", function(e)
        if not node._hasFocus or node.readonly then return end
        if not e.text or e.text == "" then return end
        node:_insert(e.text)
        node:_emitChange()
    end)

    node:on("key", function(e)
        if node._hasFocus and e.state == "down" then
            node:_handleKey(e.key, e.mods)
        end
    end)

    -- focus/blur change cursor visibility — render state
    node:on("focus", function()
        node._hasFocus = true
        node:_invalidate({ DXUI.DIRTY.RENDER })
    end)
    node:on("blur", function()
        node._hasFocus = false
        node:_invalidate({ DXUI.DIRTY.RENDER })
    end)

    return node
end

DXUI.Edit = Edit
