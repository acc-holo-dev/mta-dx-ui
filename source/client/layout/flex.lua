---Flex container layout: row | column, gap, align (cross axis:
---start|center|end|stretch), justify (main axis: start|center|end|
---spaceBetween|spaceAround|spaceEvenly), grow/shrink (weights), wrap.
---
---Run INSIDE the layout walk: the container's size is resolved first
---(Layout), then Flex.flex(container, children, contentW, contentH)
---computes child sizes (auto/fill/pct with parent size) and places
---children in flow order. Child x/y are ignored inside a flex flow
---(margins are added to the gap). Positions are written to children
---via _set(..., "system") so worldX/worldY follow on the same pass.

DXUI = DXUI or {}

local Flex = {}
local Dimension = DXUI.Dimension

--- Resolves a child's main-axis size (px/pct/fill/auto) against the line.
local function childMainSize(child, mainSize, axis)
    local key = (axis == "row") and "layoutWidth" or "layoutHeight"
    local compiled = child[key]
    if compiled == nil then
        -- plain px numbers on width/height are fixed sizes
        local k2 = (axis == "row") and "width" or "height"
        return child[k2]
    end
    -- fill: distributed among growers
    if compiled.k == "fill" then return nil end
    if compiled.k == "pct" then return mainSize * compiled.v / 100 end
    if compiled.k == "px" then return compiled.v end
    -- auto: measure
    return nil
end

--- Measures a child's main-axis content size (0 when not auto-sized).
local function measureMain(child, axis)
    if child.autoSize then
        local mw, mh = child:_measureContent()
        return (axis == "row") and mw or mh
    end
    return 0
end

--- Resolves a child's cross-axis size (px/pct/fill/auto) against the line.
local function crossSize(child, crossSize, axis, align)
    local key = (axis == "row") and "layoutHeight" or "layoutWidth"
    local compiled = child[key]
    if compiled then
        if compiled.k == "fill" or compiled.k == "auto" then return nil end
        if compiled.k == "pct" then return crossSize * compiled.v / 100 end
        return compiled.v
    end
    -- plain numbers on the cross axis are fixed
    local k2 = (axis == "row") and "height" or "width"
    local v = child[k2]
    if v and v > 0 then return v end
    if child.autoSize then
        local mw, mh = child:_measureContent()
        return (axis == "row") and mh or mw
    end
    return nil
end

--- Flex layout of container's children inside the content box.
function Flex.flex(container, children, contentW, contentH)
    local axis = container.flexDirection or "row"
    local gap = container.gap or 0
    local mainSize = (axis == "row") and contentW or contentH
    local crossSize_ = (axis == "row") and contentH or contentW

    -- 1. measure pass: fixed/percent/auto sizes, grow weights
    -- { node, main, grow, shrink, cross }
    local items = {}
    for i = 1, #children do
        local c = children[i]
        local main = childMainSize(c, mainSize, axis)
        local grow = c.grow or 0
        if main == nil then
            local lwC = (axis == "row") and c.layoutWidth or c.layoutHeight
            if lwC and lwC.k == "fill" then
                -- fill items act as growers
                grow = grow + 1
                main = 0
            else
                -- auto size (or 0)
                main = measureMain(c, axis)
            end
        end
        items[i] = { node = c, main = main, grow = grow, cross = nil }
    end

    -- 2. wrap into lines
    local lines = {}
    local line, lineMain = {}, 0
    for i = 1, #items do
        local it = items[i]
        local need = it.main or 0
        local sep = (#line > 0) and gap or 0
        if container.wrap and lineMain + sep + need > mainSize and #line > 0 then
            lines[#lines + 1] = line
            line, lineMain = {}, 0
        end
        if it.main == nil then
            -- fill/grow inside a wrapped line: give a sensible default
            -- (line share) — resolved again in placement
            it.main = 0
        end
        line[#line + 1] = it
        lineMain = lineMain + (#line > 1 and gap or 0) + (it.main or 0)
    end
    if #line > 0 then lines[#lines + 1] = line end

    -- 3. place lines
    local cursor = 0
    for li = 1, #lines do
        local l = lines[li]
        -- distribute leftover among growers in this line
        local used = 0
        local growers = {}
        for i = 1, #l do
            used = used + l[i].main
            if l[i].grow > 0 then growers[#growers + 1] = l[i] end
        end
        local leftover = mainSize - used - (#l - 1) * gap
        if leftover > 0 and #growers > 0 then
            local gTotal = 0
            for i = 1, #growers do gTotal = gTotal + growers[i].grow end
            for i = 1, #growers do
                growers[i].main = growers[i].main + math.floor(leftover * growers[i].grow / gTotal)
            end
        end

        -- line cross size
        local lineCross = 0
        for i = 1, #l do
            local cs = crossSize(l[i].node, crossSize_, axis, container.align)
            l[i].cross = cs or 0
            if cs and cs > lineCross then lineCross = cs end
        end
        -- stretch: items fill the line's cross. A single (unwrapped) line
        -- fills the container; wrapped lines keep their natural cross so
        -- they don't balloon to the full container height.
        if container.align == "stretch" and #lines == 1 then lineCross = crossSize_ end

        -- justify
        local contentMain = 0
        for i = 1, #l do contentMain = contentMain + l[i].main end
        local space = mainSize - contentMain - (#l - 1) * gap
        local startX = 0
        if container.justify == "center" then startX = space / 2
        elseif container.justify == "end" then startX = space
        elseif container.justify == "spaceBetween" then
            -- gap grows to fill space
        elseif container.justify == "spaceAround" then
            startX = (#l > 0) and (space / #l / 2) or 0
        elseif container.justify == "spaceEvenly" then
            startX = (#l > 0) and (space / (#l + 1)) or 0
        end

        -- place children
        local mainPos = startX
        for i = 1, #l do
            local it = l[i]
            local sepGap = 0
            if container.justify == "spaceBetween" and #l > 1 then
                sepGap = space / (#l - 1)
            elseif container.justify == "spaceAround" and #l > 1 then
                sepGap = space / #l
            elseif container.justify == "spaceEvenly" then
                sepGap = space / (#l + 1)
            end
            if i > 1 then mainPos = mainPos + sepGap end
            -- cross-axis placement
            local crossPos = 0
            local align_ = container.align or "start"
            if align_ == "center" then crossPos = (crossSize_ - it.cross) / 2
            elseif align_ == "end" then crossPos = crossSize_ - it.cross
            elseif align_ == "stretch" then
                it.cross = lineCross
            end
            if axis == "row" then
                it.node:_set("x", math.floor(mainPos), "system")
                it.node:_set("y", cursor + math.floor(crossPos), "system")
                if it.main ~= nil then it.node:_set("width", it.main, "system") end
                if it.cross ~= nil then it.node:_set("height", it.cross, "system") end
            else
                it.node:_set("y", math.floor(mainPos), "system")
                it.node:_set("x", cursor + math.floor(crossPos), "system")
                if it.main ~= nil then it.node:_set("height", it.main, "system") end
                if it.cross ~= nil then it.node:_set("width", it.cross, "system") end
            end
            mainPos = mainPos + it.main + (gap or 0)
        end
        cursor = cursor + lineCross + (gap or 0)
    end
end

DXUI.Flex = Flex