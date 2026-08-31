--[[
    render_list.lua — DXUI V2

    Flat list of render items — a derived cache of the tree.

    Rendering does not walk the tree every frame. The runtime keeps a flat
    list of items rebuilt only on invalidation (orderDirty); an idle frame
    just draws it with zero rebuild work.

    Each item is a plain table:
        { kind = "rect"|"image"|"text"|"line", x, y, w, h, color, ... }
]]

DXUI = DXUI or {}

local RenderList = {}
RenderList.__index = RenderList

function RenderList.new()
    local self = setmetatable({}, RenderList)
    self.items = {}   -- flat array of items
    self.count = 0
    return self
end

--- Clears the list (reuses the array, no allocations).
function RenderList:clear()
    for i = 1, self.count do
        self.items[i] = nil
    end
    self.count = 0
end

--- Adds an item to the end of the list.
function RenderList:add(item)
    self.count = self.count + 1
    self.items[self.count] = item
end

DXUI.RenderList = RenderList
