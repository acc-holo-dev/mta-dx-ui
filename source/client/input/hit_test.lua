---HitTest — hit testing over the LAST render collect's state (_visible,
---_hitClip, world coords — all maintained by RenderPass). The interactive
---list is rebuilt on interactiveDirty (never per mouse move) and mirrors
---the painter's order: the LAST interactive node is the TOPMOST one.
---
---Node "interactive" when it (a) declares itself interactive via the
---`interactive` property, or (b) is explicitly focusable, or (c) has any
---input handler attached (mouse/click/key events). Cheap check, cached.
---
---Coordinates are DESIGN space (the dispatcher/runtime convert screen
---→ design before hit-testing; the mapping is the inverse of render).

DXUI = DXUI or {}

local HitTest = {}

--- Cached predicate: could the node receive input events?
function HitTest.isInteractive(node)
    local cached = rawget(node, "_hitInteractive")
    if cached ~= nil then return cached end
    local interactive = node.interactive or node.focusable
    if not interactive and node._events then
        local names = {
            "click", "press", "release", "mousedown", "mouseup",
            "hover-start", "hover-end", "scroll", "drag-start",
            "drag-move", "drag-end", "key", "focus", "blur",
        }
        for i = 1, #names do
            if DXUI.Events.has(node, names[i]) then
                interactive = true
                break
            end
        end
    end
    local v = interactive == true
    rawset(node, "_hitInteractive", v)
    return v
end

--- Clears the cached predicate on a node (called on _set("interactive")
-- and on event attach/detach).
function HitTest.invalidate(node)
    rawset(node, "_hitInteractive", nil)
end

--- Rebuilds the interactive list (in render order, topmost last).
function HitTest.rebuild(instance)
    local list = instance._interactive
    local count = 0
    -- iterate the PAINTER-ORDERED flat scratch (RenderPass already sorted
    -- it by layer/zIndex/id — the same order as the render list)
    local nodes = instance._renderNodes
    for i = 1, #nodes do
        local nd = nodes[i]
        if nd._visible and HitTest.isInteractive(nd) then
            count = count + 1
            list[count] = nd
        end
    end
    instance._interactiveCount = count
    return count
end

--- Topmost interactive node at design coords (nil when none).
--- The scan is bounded by settings.performance.maxInteractiveScan: at most
--- `cap` nodes are examined, starting from the topmost one (pointer
--- lookups stay O(cap), not O(nodes)).
function HitTest.topAt(instance, x, y)
    local list = instance._interactive
    local n = instance._interactiveCount or 0
    local cap = (DXUI.Settings and DXUI.Settings.performance
        and DXUI.Settings.performance.maxInteractiveScan) or n
    if cap < 1 then cap = 1 end
    local lo = n - cap + 1
    if lo < 1 then lo = 1 end
    for i = n, lo, -1 do
        local node = list[i]
        local inside = node._visible and node.enabled
        if inside then
            local hw, hh = node.width, node.height
            inside = hw > 0 and hh > 0
        end
        if inside then
            local hx, hy = node.worldX, node.worldY
            inside = x >= hx and y >= hy and x < hx + node.width and y < hy + node.height
        end
        if inside then
            local clip = rawget(node, "_hitClip")
            if clip then
                inside = x >= clip[1] and y >= clip[2]
                    and x < clip[1] + clip[3] and y < clip[2] + clip[4]
            end
        end
        if inside then return node end
    end
    return nil
end

DXUI.HitTest = HitTest