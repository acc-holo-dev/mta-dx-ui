---HitTest — hit testing over the LAST render collect's state (_visible,
---_hitClip, world coords — all maintained by RenderPass). The interactive
---list is rebuilt on interactiveDirty (never per mouse move) and mirrors
---the painter's order: the LAST interactive node is the TOPMOST one.
---
---Node "interactive" when it (a) declares itself interactive via the
---`interactive` property, or (b) is explicitly focusable, or (c) has any
---input handler attached (mouse/click/key events). Cheap check, cached.
---
---Pixel-perfect hits: a node with `pixelHit = true` and a `texture` is
---alpha-tested after the rect check (bit-packed mask from the resource
---manager, ≤256 per side; `rotation` is NOT supported — a rotating quad
---falls back to the rect; a section crop maps through correctly).
---
---Coordinates are DESIGN space (the dispatcher/runtime convert screen
---→ design before hit-testing; the mapping is the inverse of render).

DXUI = DXUI or {}

local HitTest = {}

--- Cached predicate: could the node receive input events?
function HitTest.isInteractive(node)
    local cached = rawget(node, "_hitInteractive")
    if cached ~= nil then return cached end
    local interactive = node.interactive or node.focusable or node.dragData ~= nil
    if not interactive and node._events then
        local names = {
            "click", "press", "release", "mousedown", "mouseup",
            "hover-start", "hover-end", "pointer-move", "scroll",
            "drag-start", "drag-move", "drag-end", "drop", "drag-over",
            "drag-out", "key", "focus", "blur",
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

--- Cached predicate: does the node accept drops (a drag-over or drop
--- handler)? Mirrors isInteractive; the list lives in _dropTargets.
function HitTest.isDropTarget(node)
    local cached = rawget(node, "_hitDropTarget")
    if cached ~= nil then return cached end
    local v = false
    if node._events then
        v = DXUI.Events.has(node, "drop") or DXUI.Events.has(node, "drag-over")
    end
    rawset(node, "_hitDropTarget", v)
    return v
end

--- Clears the cached predicate on a node (called on _set("interactive")
-- and on event attach/detach).
function HitTest.invalidate(node)
    rawset(node, "_hitInteractive", nil)
    rawset(node, "_hitDropTarget", nil)
end

--- Rebuilds the interactive list (in render order, topmost last) and the
--- drop-target list (drag & drop; separate because pure drop zones do
--- not have to be interactive widgets).
function HitTest.rebuild(instance)
    local list = instance._interactive
    local count = 0
    -- iterate the PAINTER-ORDERED flat scratch (RenderPass already sorted
    -- it by layer/zIndex/id — the same order as the render list)
    local nodes = instance._renderNodes
    local targets = instance._dropTargets
    local tcount = 0
    for i = 1, #nodes do
        local nd = nodes[i]
        if nd._visible then
            if HitTest.isInteractive(nd) then
                count = count + 1
                list[count] = nd
            end
            if HitTest.isDropTarget(nd) then
                tcount = tcount + 1
                targets[tcount] = nd
            end
        end
    end
    instance._interactiveCount = count
    instance._dropTargetCount = tcount
    return count
end

--- Alpha test for pixelHit nodes: maps the design point into the
--- material's texel space (section-aware), then into the bit-packed
--- alpha mask. Returns true (hit) when anything is missing — the rect
--- check has already passed, so `true` IS the rect fallback.
local function alphaInside(node, x, y)
    if (node.rotation or 0) ~= 0 then return true end
    local mat = node.texture
    local m = mat and DXUI.alphaMask and DXUI.alphaMask(mat)
    if not m or m == false then return true end
    local lx, ly = x - node.worldX, y - node.worldY
    local tw, th = m.tw, m.th
    local tx, ty
    local sec = node.section
    if sec then
        tx = sec[1] + lx / node.width * sec[3]
        ty = sec[2] + ly / node.height * sec[4]
    else
        tx = lx / node.width * tw
        ty = ly / node.height * th
    end
    if tx < 0 or ty < 0 or tx >= tw or ty >= th then return false end
    local mx = math.floor(tx / tw * m.mw)
    local my = math.floor(ty / th * m.mh)
    if mx < 0 then mx = 0 elseif mx >= m.mw then mx = m.mw - 1 end
    if my < 0 then my = 0 elseif my >= m.mh then my = m.mh - 1 end
    local byte = string.byte(m.data, my * m.stride + math.floor(mx / 8) + 1)
    local b = mx % 8
    -- Lua 5.1 without a bit library: exact power-of-two float math
    return (byte % (2 ^ (b + 1))) >= (2 ^ b)
end

--- Whether the point is inside the node's hit rect (visible, enabled,
--- sized, clipped; pixelHit alpha-tested when enabled).
function HitTest.pointIn(node, x, y)
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
    if inside and node.pixelHit then
        inside = alphaInside(node, x, y)
    end
    return inside
end

--- Topmost interactive node at design coords (nil when none).
--- The scan is bounded by settings.performance.maxInteractiveScan: at most
--- `cap` nodes are examined first, starting from the topmost one (pointer
--- lookups stay O(cap) in the common case). If the capped scan misses, a
--- full scan of the remaining nodes runs so a click on a node below the
--- top `cap` still lands (correctness over the perf guardrail).
function HitTest.topAt(instance, x, y)
    local list = instance._interactive
    local n = instance._interactiveCount or 0
    local cap = (DXUI.Settings and DXUI.Settings.performance
        and DXUI.Settings.performance.maxInteractiveScan) or n
    if cap < 1 then cap = 1 end
    local lo = n - cap + 1
    if lo < 1 then lo = 1 end
    -- fast path: scan the top `cap` nodes (topmost first)
    for i = n, lo, -1 do
        if HitTest.pointIn(list[i], x, y) then return list[i] end
    end
    -- correctness fallback: the target sits below the top `cap`
    for i = lo - 1, 1, -1 do
        if HitTest.pointIn(list[i], x, y) then return list[i] end
    end
    return nil
end

--- Topmost DROP TARGET at design coords (nil when none). Painter order
--- like topAt; the caller applies modal reachability.
function HitTest.topDropAt(instance, x, y)
    local list = instance._dropTargets
    local n = instance._dropTargetCount or 0
    for i = n, 1, -1 do
        local nd = list[i]
        if not nd._destroyed and HitTest.pointIn(nd, x, y) then return nd end
    end
    return nil
end

DXUI.HitTest = HitTest