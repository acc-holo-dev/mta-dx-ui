--[[
    pass.lua — DXUI V3

    RenderPass: builds the persistent render list from the tree.

      collect:   visibility + opacity + layer + clip accumulate + screen
                 culling; pushes every VISIBLE NON-GROUP-MEMBER node into
                 the flat scratch array (children emit as their own flat
                 entries — the sorted array IS the global painter's order).
      sort:      (effLayer, zIndex, insertion id) across the whole tree;
                 the same order later feeds the hit-test list.
      emit:      each flat node renders its own primitives ONCE (no child
                 recursion inside emitSingle — children are siblings in the
                 flat list); nodes needing an RT group (clipMode="rt" or
                 container blur/mask) emit an rtgroup item whose contents
                 are a TREE WALK of the group's own subtree (layer/zIndex
                 inside an RT composite is local tree order — documented:
                 an RT is a single quad, so nothing can interleave anyway).

    Arrays: group contents live in per-group arrays from a small module
    pool; they are recycled by the state cache AFTER the group is drawn
    (not at build time) — the rtgroup item references them.
]]

DXUI = DXUI or {}

local RenderPass = {}

local nodeLess
nodeLess = function(a, b)
    if a._effLayer ~= b._effLayer then return a._effLayer < b._effLayer end
    if a.zIndex ~= b.zIndex then return a.zIndex < b.zIndex end
    return a._id < b._id
end

local function intersectClip(rect, x, y, w, h)
    local x2, y2 = x + w, y + h
    if rect then
        local rx2, ry2 = rect[1] + rect[3], rect[2] + rect[4]
        local nx = (x > rect[1]) and x or rect[1]
        local ny = (y > rect[2]) and y or rect[2]
        local nx2 = (x2 < rx2) and x2 or rx2
        local ny2 = (y2 < ry2) and y2 or ry2
        if nx2 <= nx or ny2 <= ny then return false end
        return { nx, ny, nx2 - nx, ny2 - ny }
    end
    return { x, y, w, h }
end

local function screenCullingEnabled(instance)
    local perf = DXUI.Settings and DXUI.Settings.performance
    return not perf or perf.screenCulling ~= false
end

local function hasGroup(node)
    return DXUI.Effects ~= nil and DXUI.Effects.canGroup() and DXUI.Effects.needsGroup(node)
end

--- Collect phase. Returns the number of pushed nodes.
-- `insideGroup`: true while under an RT-group ancestor — those nodes get
-- full state (opacity/clip/visibility) but are NOT pushed (the group walk
-- emits them into the group array).
local function collect(instance, node, nodes, count, parentVisible, parentOpacity, parentLayer, parentClip, insideGroup)
    local visible = parentVisible and node.visible
    if not visible then
        rawset(node, "_visible", false) -- explicit (stale-proof for group walks)
        rawset(node, "_hitClip", nil)
        return count
    end
    -- accumulate draw state
    local opacity = parentOpacity * (node.opacity or 1)
    local layer = node.layer
    if layer == DXUI.LAYER.BASE then layer = parentLayer end
    local myGroup = hasGroup(node)
    local clip = parentClip
    if node.clip or myGroup then
        local rect = intersectClip(parentClip, node.worldX, node.worldY, node.width, node.height)
        if rect == false then
            rawset(node, "_visible", false)
            rawset(node, "_hitClip", parentClip)
            return count
        end
        clip = rect
    end
    rawset(node, "_visible", true)
    rawset(node, "_effOpacity", opacity)
    rawset(node, "_effLayer", layer)
    rawset(node, "_hitClip", clip)
    if clip then
        rawset(node, "_clipX", clip[1]); rawset(node, "_clipY", clip[2])
        rawset(node, "_clipW", clip[3]); rawset(node, "_clipH", clip[4])
    else
        rawset(node, "_clipX", nil); rawset(node, "_clipY", nil)
        rawset(node, "_clipW", nil); rawset(node, "_clipH", nil)
    end

    -- screen-space culling (layout space); culled nodes are never emitted.
    if screenCullingEnabled(instance) then
        local lw = instance.layoutW or instance.screenW or 0
        local lh = instance.layoutH or instance.screenH or 0
        local x2 = node.worldX + node.width
        local y2 = node.worldY + node.height
        if x2 <= 0 or y2 <= 0 or node.worldX >= lw or node.worldY >= lh then
            rawset(node, "_visible", false)
            return count
        end
    end

    local inGroup = insideGroup or myGroup
    -- group roots ARE flat entries (their rtgroup item belongs to the
    -- global painter's order); everything under a group emits via the
    -- group's own tree walk instead.
    if not insideGroup then
        count = count + 1
        nodes[count] = node
    end

    local children = node._children
    for i = 1, #children do
        count = collect(instance, children[i], nodes, count, true, opacity, layer, clip, inGroup)
    end
    return count
end

-- ---------------------------------------------------------------------
-- Emit
-- ---------------------------------------------------------------------

--- Single node: its own primitives only (children are flat siblings).
local function emitSingle(node, renderer, list)
    renderer:_loadClip(node)
    renderer.fx = nil
    if node._class ~= DXUI.Node and node.render then
        if node._class._name == "Image" and DXUI.Effects then
            renderer.fx = DXUI.Effects.effectForImage(node)
        end
        node:render(renderer)
    end
end

-- Group content arrays: pooled, recycled after draw (state cache).
local arrPool = {}
local ARR_POOL_CAP = 16

local function acquireArr()
    return table.remove(arrPool) or {}
end

function RenderPass.releaseArr(arr)
    if #arrPool < ARR_POOL_CAP then
        arrPool[#arrPool + 1] = arr
    end
    for i = 1, #arr do arr[i] = nil end
end

--- Tree walk INSIDE an RT group: the group node + its visible subtree,
-- local tree order (documented: RT = one composite quad).
local function emitTree(node, renderer, list, baseOpacity, sx, sy, ox, oy)
    if hasGroup(node) then
        -- nested group
        local effOp = node._effOpacity or 1
        if effOp <= 0 then return end
        local it = DXUI.RenderList.obtain()
        it.kind = "rtgroup"
        it.x = node.worldX * sx + ox
        it.y = node.worldY * sy + oy
        it.w = node.width * sx
        it.h = node.height * sy
        it.scaleX, it.scaleY = sx, sy
        it.effect = (node.blur and node.blur > 0 and DXUI.Effects.blur(node.width, node.height, node.blur))
            or (node.mask and DXUI.Effects.mask(node.mask))
        it.alpha = effOp * baseOpacity
        local arr = acquireArr()
        local sub = { items = arr, count = 0 }
        emitTree(node, renderer, sub, (1 / effOp) * baseOpacity, sx, sy, ox, oy)
        it.items = arr
        it.count = sub.count
        it.fromPool = true
        it.releaseArr = true
        list:add(it)
        return
    end
    renderer:_loadClip(node)
    renderer.fx = nil
    if node._class ~= DXUI.Node and node.render then
        if node._class._name == "Image" and DXUI.Effects then
            renderer.fx = DXUI.Effects.effectForImage(node)
        end
        renderer.effOpacity = (node._effOpacity or 1) * baseOpacity
        node:render(renderer)
    end
    local children = node._children
    for i = 1, #children do
        local c = children[i]
        if c._visible then
            emitTree(c, renderer, list, baseOpacity, sx, sy, ox, oy)
        end
    end
end

local function emitGroup(node, renderer, list)
    local effOp = node._effOpacity or 1
    if effOp <= 0 then return end
    local sx, sy = renderer.scaleX, renderer.scaleY
    local ox, oy = renderer.offsetX, renderer.offsetY
    local it = DXUI.RenderList.obtain()
    it.kind = "rtgroup"
    it.x = node.worldX * sx + ox
    it.y = node.worldY * sy + oy
    it.w = node.width * sx
    it.h = node.height * sy
    it.scaleX, it.scaleY = sx, sy
    it.effect = (node.blur and node.blur > 0 and DXUI.Effects.blur(node.width, node.height, node.blur))
        or (node.mask and DXUI.Effects.mask(node.mask))
    it.alpha = effOp
    local arr = acquireArr()
    local sub = { items = arr, count = 0 }
    emitTree(node, renderer, sub, 1 / effOp, sx, sy, ox, oy)
    it.items = arr
    it.count = sub.count
    it.fromPool = true
    it.releaseArr = true
    list:add(it)
end

--- Rebuilds instance.renderList. Returns the item count.
function RenderPass.build(instance)
    local list = instance.renderList
    list:release() -- recycle the previous frame's item tables

    local renderer = instance.renderer
    renderer:reset(list)
    renderer.scaleX = instance._mapScaleX or 1
    renderer.scaleY = instance._mapScaleY or 1
    renderer.offsetX = instance._mapOffX or 0
    renderer.offsetY = instance._mapOffY or 0

    local nodes = instance._renderNodes
    -- root is never rendered/culled itself — collect starts at its children
    local count = 0
    local root = instance.root
    for i = 1, #root._children do
        count = collect(instance, root._children[i], nodes, count, true, 1, DXUI.LAYER.BASE, nil, false)
    end

    table.sort(nodes, nodeLess, 1, count)

    for i = 1, count do
        local node = nodes[i]
        if hasGroup(node) then
            emitGroup(node, renderer, list)
        else
            emitSingle(node, renderer, list)
        end
    end
    return list.count
end

DXUI.RenderPass = RenderPass