--[[
    hit_test.lua — DXUI V2

    Hit-test: a plain rectangular node needs only a cheap AABB test
    (x >= left, x <= right, y >= top, y <= bottom). No complex geometry.

    Iterates the flat list of interactive nodes (context.interactiveList,
    a derived cache rebuilt on DIRTY_INPUT), not the whole tree.
    The list is sorted by (layer, zIndex, id) — the same order as render,
    so "visually on top" = "gets the click". Reverse iteration returns
    the topmost node first.
]]

DXUI = DXUI or {}

local HitTest = {}

--- Return the topmost interactive node under (x, y), or nil.
-- Uses world coords (Stage 5 layout), not local x/y.
function HitTest.pick(context, x, y)
    local list = context.interactiveList
    for i = context.interactiveCount, 1, -1 do
        local node = list[i]
        if x >= node.worldX and x <= node.worldX + node.width
           and y >= node.worldY and y <= node.worldY + node.height then
            return node
        end
    end
    return nil
end

DXUI.HitTest = HitTest
