--[[
    selector.lua — DXUI

    Selector: selection list. items = { "A", "B", ... } or
    { {text=...}, ... }. Click selects (selector.selected = index);
    the selected row is highlighted. Emits "select".
]]

DXUI = DXUI or {}

local Selector = DXUI.Widget:extend("Selector", {
    color = { default = 0xFF2A2A2A, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    selected = { default = 0, type = "number", min = 0, invalidates = { DXUI.DIRTY.RENDER } },
    itemHeight = { default = 24, type = "number", min = 1, invalidates = { DXUI.DIRTY.RENDER } },
    itemColor = { default = 0xFF2A2A2A, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    selectedColor = { default = 0xFF3A6EA5, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    hoverColor = { default = 0xFF3A5A80, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function Selector:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

local function rowColor(sel, idx, isHover)
    if idx == sel.selected then return sel.selectedColor end
    if isHover then return sel.hoverColor end
    return sel.itemColor
end

--- Builder: ui:selector({ items=, width=, itemHeight=, selected=, ... }).
function Selector.build(context, props)
    props = props or {}
    local items = props.items or {}
    local node = Selector:new(props)
    node._items = items
    local ITEM_H = node.itemHeight or 24
    if props.width == nil then node.width = 180 end
    node.height = #items * ITEM_H

    local rows = {}
    for i = 1, #items do
        local it = items[i]
        local text = type(it) == "table" and (it.text or "") or tostring(it)
        local row = context:panel({ x = 0, y = (i - 1) * ITEM_H, width = node.width, height = ITEM_H, color = rowColor(node, i, false) })
        row:setParent(node)
        local label = context:label({ x = 8, y = (ITEM_H - 14) / 2, width = node.width - 16, height = 14, text = text, color = node.textColor })
        label:setParent(row)
        row:on("mouseenter", function()
            if row:isAlive() and i ~= node.selected then row.color = rowColor(node, i, true) end
        end)
        row:on("mouseleave", function()
            if row:isAlive() and i ~= node.selected then row.color = rowColor(node, i, false) end
        end)
        row:on("click", function()
            if node:isAlive() then node:setSelected(i) end
        end)
        rows[i] = row
    end
    node._rows = rows

    -- apply initial selected index (from props)
    node:setSelected(props.selected or 0)

    DXUI.Widget.attachChildren(node, props)
    return node
end

--- Selects index (highlights rows, emits "select").
function Selector:setSelected(index)
    index = index or 0
    if index < 0 or index > #(self._rows or {}) then index = 0 end
    self.selected = index
    local rows = self._rows
    if rows then
        for i = 1, #rows do
            if rows[i]:isAlive() then
                rows[i].color = rowColor(self, i, false)
            end
        end
    end
    self:emit("select", { index = index })
    return self
end

--- Returns the selected item (original items[index]) or nil.
function Selector:getSelectedItem()
    return self._items and self._items[self.selected]
end

--- Selects by item (index of first match), or 0.
function Selector:selectItem(item)
    if self._items then
        for i = 1, #self._items do
            if self._items[i] == item then return self:setSelected(i) end
        end
    end
    return self:setSelected(0)
end

DXUI.Selector = Selector
