---GridList — a flat, selectable item list with wheel scrolling. Items:
---strings or {text=...}; hover highlight; click selects (single).
---For richer needs wrap in a ScrollPanel (yours: content rows).
---
---    local gl = ui:gridlist({ x=0, y=0, width=200, height=300 })
---    gl:addItem("Player 1"); gl:addItem("Player 2")
---    gl:on("select", function(n, index, item) ... end)


DXUI = DXUI or {}

--- Returns the display text for an item (string or {text=...}).
local function rowText(item)
    return (type(item) == "table") and (item.text or "") or tostring(item)
end

local GridList = DXUI.Widget:extend("GridList", {
    items = { default = {}, invalidates = { DXUI.DIRTY.RENDER } },
    selectedIndex = { default = 0, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, i)
        if node.emit then node:emit("select", i, node.items and node.items[i]) end
    end },
    rowHeight = { default = 22, invalidates = { DXUI.DIRTY.LAYOUT } },
    scrollY = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    hoverColor = { default = 0xFFF3F4F6, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    selectedColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    selectedTextColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

--- Returns the row index at the given design coordinates, or nil.
function GridList:_rowAt(designX, designY)
    local rh = self.rowHeight or 22
    local total = #(self.items or {}) * rh
    local maxScroll = total - self.height
    local off = 0
    if maxScroll > 0 then off = self.scrollY * maxScroll end
    local rel = designY - self.worldY + off
    local idx = math.floor(rel / rh) + 1
    if idx < 1 or idx > #(self.items or {}) then return nil end
    if designX < self.worldX or designX >= self.worldX + self.width then return nil end
    return idx
end

--- Wires click selection, row hover and wheel scrolling.
GridList._build = function(node)
    node.clip = true
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
    node:on("click", function(n, _, x, y)
        local i = n:_rowAt(x, y)
        if i then n.selectedIndex = i end
    end, "dxui-grid")
    node:on("scroll", function(n, wheel)
        local rh = n.rowHeight or 22
        local total = #(n.items or {}) * rh
        -- nothing to scroll when the list fits the viewport: leave
        -- scrollY alone (a 0-1 range clamped by the spec would otherwise
        -- drift with no visible effect)
        if total <= n.height then return true end
        local range = total - n.height
        n.scrollY = n.scrollY - wheel * rh / range
        return true
    end, "dxui-grid")
end

--- Appends an item to the list.
function GridList:addItem(item)
    self.items[#self.items + 1] = item
    return self
end

--- Draws the visible rows and the scrollbar thumb.
function GridList:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local rh = self.rowHeight or 22
    local items = self.items or {}
    local total = #items * rh
    local maxScroll = total - h
    local off = 0
    if maxScroll > 0 then off = self.scrollY * maxScroll end
    local sel = self.selectedIndex or 0
    local hoverIdx = self._hoverRow
    for i = 1, #items do
        local y0 = wy + (i - 1) * rh - off
        if y0 + rh > wy and y0 < wy + h then
            local bg = sel == i and self.selectedColor
                or (hoverIdx == i and self.hoverColor) or nil
            if bg then renderer:rect(wx, y0, w, rh, bg) end
            local tc = sel == i and (self.selectedTextColor or self.textColor) or self.textColor
            renderer:text(rowText(items[i]), wx + 6, y0, w - 12, rh, tc, self.font, "left", "center", 1)
        end
    end
    -- scrollbar thumb
    if maxScroll > 0 then
        local th = h * h / total
        if th < 20 then th = 20 end
        renderer:roundedRect(wx + w - 8, wy + (h - th) * self.scrollY, 6, th, 3, self.borderColor)
    end
end

DXUI.Builders.register("GridList", GridList)