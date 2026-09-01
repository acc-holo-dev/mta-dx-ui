--[[
    render_list.lua — DXUI V3

    Persistent flat list of render items — a derived cache of the tree.
    Rendering never walks the tree per frame: the pass rebuilds the list
    only on invalidation; an idle frame just draws it (zero rebuild).

    Items are pooled tables (RenderList.obtain/recycle) so rebuilds do not
    churn allocations.

    Item kinds: rect | rrect | image | text | line | rtgroup
        { kind="rect", x,y,w,h,color }
        { kind="rrect", x,y,w,h,radius,color,effect }
        { kind="image", x,y,w,h,texture,color,effect,section }
        { kind="text", text,x,y,w,h,color,font,align,valign,scaleX,scaleY }
        { kind="line", x1,y1,x2,y2,color,width }
        { kind="rtgroup", x,y,w,h,scaleX,scaleY,effect,alpha,items,count,pool }
]]

DXUI = DXUI or {}

local RenderList = {}
RenderList.__index = RenderList

local POOL_CAP = 4096
-- recycled item tables
local pool = {}

--- Obtains an item table (reused or fresh).
function RenderList.obtain()
    local it = table.remove(pool)
    if it then return it end
    return {}
end

--- Recycles the items of a list (returns them to the pool, bounded).
function RenderList.recycle(items, count)
    for i = 1, count do
        local it = items[i]
        items[i] = nil
        if #pool < POOL_CAP then
            pool[#pool + 1] = it
        end
    end
end

--- Creates a new empty render list.
function RenderList.new()
    local self = setmetatable({}, RenderList)
    self.items = {}
    self.count = 0
    return self
end

--- Clears the list WITHOUT recycling (draw-many-times lists keep items).
function RenderList:clear()
    for i = 1, self.count do
        self.items[i] = nil
    end
    self.count = 0
end

--- Clears AND recycles the item tables (end of a rebuild frame).
function RenderList:release()
    RenderList.recycle(self.items, self.count)
    self.count = 0
end

--- Appends an item to the list.
function RenderList:add(item)
    self.count = self.count + 1
    self.items[self.count] = item
end

DXUI.RenderList = RenderList