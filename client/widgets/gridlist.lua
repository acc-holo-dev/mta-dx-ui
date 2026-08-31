--[[
    gridlist.lua — DXUI V2

    GridList: a table widget. columns = { {text=, width=}, ... }. addColumn/addRow/
    selectRow/getSelected/getRowCount/clearRows. Scroll is a built-in ScrollPanel.
]]

DXUI = DXUI or {}

local HEADER_H = 20
local ROW_H = 22
local ROW_COLOR = 0xFF222222
local ROW_HOVER = 0xFF2E4A6B
local ROW_SELECTED = 0xFF3A6EA5

local GridList = DXUI.Widget:extend("GridList", {
    headerColor = { default = 0xFF181818, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function GridList:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    renderer:rect(self.worldX, self.worldY, self.width, self.headerHeight, self.headerColor)
end

function GridList:_totalWidth()
    local w = 0
    for i = 1, #self.columns do w = w + self.columns[i].width end
    return w
end

function GridList:addColumn(text, width)
    self.columns[#self.columns + 1] = { text = text or "", width = width or 100 }
    self:_rebuildHeader()
    return self
end

function GridList:_rebuildHeader()
    -- headers are label children of the header node
    local header = self._header
    if not header then return end
    -- destroy old labels
    local children = header._children
    for i = #children, 1, -1 do children[i]:destroy() end
    local x = 0
    for i = 1, #self.columns do
        local col = self.columns[i]
        local label = self._context:label({ x = x + 4, y = (self.headerHeight - 14) / 2, width = col.width - 8, height = 14, text = col.text })
        label:setParent(header)
        x = x + col.width
    end
end

function GridList:addRow(cells)
    local content = self._scroll:getContent()
    local totalW = self:_totalWidth()
    local y = #self.rows * self.rowHeight

    local row = self._context:panel({ x = 0, y = y, width = totalW, height = self.rowHeight, color = ROW_COLOR })
    row:setParent(content)

    local x = 0
    for i = 1, #self.columns do
        local label = self._context:label({ x = x + 4, y = (self.rowHeight - 14) / 2, width = self.columns[i].width - 8, height = 14, text = tostring(cells[i] or "") })
        label:setParent(row)
        x = x + self.columns[i].width
    end

    local idx = #self.rows + 1
    self.rows[idx] = { row = row, cells = cells }
    row:on("mouseenter", function() if self.selected ~= idx and row:isAlive() then row.color = ROW_HOVER end end)
    row:on("mouseleave", function() if self.selected ~= idx and row:isAlive() then row.color = ROW_COLOR end end)
    row:on("click", function() self:selectRow(idx) end)

    self._scroll:refresh()
    return idx
end

function GridList:selectRow(idx)
    if idx < 1 or idx > #self.rows then return self end
    if self.selected > 0 and self.rows[self.selected] then
        self.rows[self.selected].row.color = ROW_COLOR
    end
    self.selected = idx
    self.rows[idx].row.color = ROW_SELECTED
    if self._onSelect then self._onSelect(idx, self.rows[idx].cells) end
    return self
end

function GridList:getSelected()
    return self.selected
end

function GridList:getSelectedCells()
    if self.selected > 0 and self.rows[self.selected] then
        return self.rows[self.selected].cells
    end
    return nil
end

function GridList:getRowCount()
    return #self.rows
end

function GridList:clearRows()
    for i = 1, #self.rows do
        self.rows[i].row:destroy()
    end
    self.rows = {}
    self.selected = 0
    self._scroll:refresh()
    return self
end

function GridList:setSize(w, h)
    DXUI.Node.setSize(self, w, h)
    self._scroll:setPosition(0, self.headerHeight)
    self._scroll:setSize(w, h - self.headerHeight)
    return self
end

--- Builder: ui:gridlist({ columns=, rowHeight=, headerHeight=, onSelect=, ... }).
function GridList.build(context, props)
    props = props or {}
    local node = GridList:new(props)
    -- addColumn/_rebuildHeader create labels via context before mounting
    rawset(node, "_context", context)
    if props.width == nil then node.width = 300 end
    if props.height == nil then node.height = 200 end
    node.columns = {}
    node.rows = {}
    node.selected = 0
    node.rowHeight = props.rowHeight or ROW_H
    node.headerHeight = props.headerHeight or HEADER_H
    if props.onSelect then node._onSelect = props.onSelect end

    -- header node (invisible background, a container for headers only)
    local header = context:panel({ x = 0, y = 0, width = node.width, height = node.headerHeight, color = node.headerColor })
    header:setParent(node)
    node._header = header

    -- built-in scrollpanel
    local scroll = context:scrollpanel({ x = 0, y = node.headerHeight, width = node.width, height = node.height - node.headerHeight })
    scroll:setParent(node)
    node._scroll = scroll

    if props.columns then
        for i = 1, #props.columns do
            node:addColumn(props.columns[i].text, props.columns[i].width)
        end
    end

    return node
end

DXUI.GridList = GridList
