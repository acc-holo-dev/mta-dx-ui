--[[
    context.lua — DXUI V2

    Context: an isolated UI context. Owns:
      - its own root node;
      - its own dirty queue (nodes awaiting per-frame processing);
      - its own focus manager (Stage 4);
      - its own layers.

    The global coordinator (screen size, input bridge, frame lifecycle,
    resource manager) lives in api/ui.lua and init.lua — not here.

    Contexts are isolated: one context's tree/focus/layers don't affect another.
]]

DXUI = DXUI or {}

local Context = {}
Context.__index = Context

function Context.new(backend)
    local self = setmetatable({}, Context)

    self._dirtyList = {}   -- flat list of dirty nodes (no duplicates)
    self._dirtyCount = 0
    self.layoutDirty = false -- Stage 5: whether any node has DIRTY_LAYOUT

    self.focusedNode = nil -- Stage 4: focus manager
    self.screenW = 0
    self.screenH = 0

    -- root: top of the tree. Its _context is the context itself.
    self.root = DXUI.Node:new()
    rawset(self.root, "_context", self)

    -- Stage 3: render. backend is the MTA driver or a mock (tests).
    self.backend = backend or DXUI.MtaBackend
    self.renderList = DXUI.RenderList.new()
    self.renderer = DXUI.Renderer.new(self.renderList)
    self.stateCache = DXUI.StateCache.new(self.backend)

    -- Stage 4: input. Flat list of interactive nodes (derived cache).
    self.interactiveList = {}
    self.interactiveCount = 0
    self.dispatcher = DXUI.Dispatcher.new(self)

    -- Stage 7: virtual clipboard (copy/paste between the context's fields).
    self.clipboard = ""

    -- Stage 7b: clock (ms) — single time source for animation/schedule.
    -- MTA: getTickCount(); tests: overridden via setClock.
    if getTickCount then
        self.clock = function() return getTickCount() end
    else
        self.clock = function() return os.clock() * 1000 end
    end

    -- Stage 7b: animation manager (single tick in renderFrame).
    self.animation = DXUI.AnimationManager.new(self)

    return self
end

-- ---------------------------------------------------------------------
-- Creation / mounting
-- ---------------------------------------------------------------------

--- Creates a node (or widget) and optionally mounts it to the root.
-- Stage 6 will add context:panel/button/... on top of this.
function Context:createNode(props)
    return DXUI.Node:new(props)
end

--- Mounts a node to the context root (parent = root).
function Context:mount(node)
    node:setParent(self.root)
    return node
end

--- Destroys a node (and its subtree).
function Context:destroyNode(node)
    if node then node:destroy() end
end

--- Destroys the context: removes it from the global registry and destroys
-- its root node (recursively destroys the whole tree).
function Context:destroy()
    local contexts = DXUI._contexts
    for i = 1, #contexts do
        if contexts[i] == self then
            table.remove(contexts, i)
            break
        end
    end
    if self.root then
        self.root:destroy()
    end
end

-- ---------------------------------------------------------------------
-- Widget builders — registered via DXUI.registerWidget (builders.lua).
-- ui:name(props) and node:name(props) are generated there.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Dirty queue (internal)
-- ---------------------------------------------------------------------

--- Adds a node to the frame queue (dedup via node._queued).
function Context:_queueDirty(node)
    if node._queued then return end
    node._queued = true
    self._dirtyCount = self._dirtyCount + 1
    self._dirtyList[self._dirtyCount] = node
    if node._dirty[DXUI.DIRTY.LAYOUT] then
        self.layoutDirty = true
    end
end

--- Node destroyed: clear the queue flag (the list itself is cleaned in processDirty)
-- and clear input references (hover/pressed/focus) to it.
function Context:_onNodeDestroyed(node)
    node._queued = false
    self.dispatcher:_onNodeDestroyed(node)
    -- Destroying a node changes hit geometry: rebuild interactiveList
    -- immediately, otherwise dead nodes stay stuck in the cache.
    self:_rebuildInteractiveList()
end

-- ---------------------------------------------------------------------
-- Frame processing
-- ---------------------------------------------------------------------

--- Processes dirty nodes per frame. Stages 3/5 hook layout/render/
-- input passes here reading node._dirty. In Stage 2 — queue clearing only.
function Context:processDirty()
    self:_clearDirty()
end

function Context:_clearDirty()
    for i = 1, self._dirtyCount do
        local node = self._dirtyList[i]
        self._dirtyList[i] = nil
        if node and not node._destroyed then
            node._queued = false
            node._dirty = {}
        end
    end
    self._dirtyCount = 0
end

-- ---------------------------------------------------------------------
-- Render (Stage 3)
-- ---------------------------------------------------------------------

--- Full frame: design-mapping → animations → layout (if DIRTY_LAYOUT) →
-- rebuild render list + interactive list (if any dirty) + draw.
-- Idle = draw only.
function Context:renderFrame()
    self:_updateDesignMapping()
    self.animation:update() -- animations first (may add dirty)
    if self._dirtyCount > 0 then
        if self.layoutDirty then
            self:_updateLayout()
            self.layoutDirty = false
        end
        self:_rebuildRenderList()
        self:_rebuildInteractiveList()
        self:_clearDirty()
    end
    self:_draw()
end

--- Stage 8: design → screen mapping. Layout space is the
-- design resolution if set, otherwise the screen. The renderer scales
-- primitives; events are converted back via toLocal.
-- If size is unknown (setScreenSize not called) — identity (scale 1).
function Context:_updateDesignMapping()
    local dw = DXUI.designW or self.screenW
    local dh = DXUI.designH or self.screenH
    local sw, sh = self.screenW or 0, self.screenH or 0
    if not dw or not dh or dw <= 0 or dh <= 0 or sw <= 0 or sh <= 0 then
        -- identity: scale nothing without sizes (not 0/0 = nan!)
        self.layoutW, self.layoutH = sw, sh
        self._mapScaleX, self._mapScaleY = 1, 1
        self._mapOffX, self._mapOffY = 0, 0
        local r = self.renderer
        r.scaleX, r.scaleY, r.offsetX, r.offsetY = 1, 1, 0, 0
        return
    end
    local sx = sw / dw
    local sy = sh / dh
    local offX, offY = 0, 0
    if DXUI.designScaleMode == "fit" then
        local s = math.min(sx, sy)
        offX = (sw - dw * s) / 2
        offY = (sh - dh * s) / 2
        sx, sy = s, s
    end
    self.layoutW, self.layoutH = dw, dh
    self._mapScaleX, self._mapScaleY = sx, sy
    self._mapOffX, self._mapOffY = offX, offY
    local r = self.renderer
    r.scaleX, r.scaleY, r.offsetX, r.offsetY = sx, sy, offX, offY
end

--- Screen coords → design coords (for dispatcher/hit-test).
-- Without design resolution — identity.
function Context:toLocal(x, y)
    if self._mapScaleX and self._mapScaleX ~= 0 then
        return (x - self._mapOffX) / self._mapScaleX,
               (y - self._mapOffY) / self._mapScaleY
    end
    return x, y
end

--- Swaps the time source (ms) — for tests.
function Context:setClock(fn)
    self.clock = fn
end

--- Stage 5: layout pass (computes world coords).
function Context:_updateLayout()
    DXUI.Layout.update(self)
end

--- Node draw order: (layer, zIndex, id) — hit-test uses
--- the same order, so "visually on top" = "receives the click".
local function nodeLess(a, b)
    local la = a._effLayer or a.layer
    local lb = b._effLayer or b.layer
    if la ~= lb then return la < lb end
    if a.zIndex ~= b.zIndex then return a.zIndex < b.zIndex end
    return a.id < b.id
end

--- Rebuilds the render list: collect visible renderable nodes → render.
function Context:_rebuildRenderList()
    self.renderList:clear()

    local nodes = {}
    self:_collectRenderable(self.root, true, nil, 1, DXUI.LAYER.BASE, nodes)

    self:_renderNodes(nodes, self.renderList)
end

--- Sorts nodes and renders them into the list (render preparation).
-- Recursively: nodes with clipMode="rt" render their subtree into an RT-group.
function Context:_renderNodes(nodes, list)
    table.sort(nodes, nodeLess)

    local r = DXUI.Renderer.new(list)
    r.scaleX, r.scaleY = self.renderer.scaleX, self.renderer.scaleY
    r.offsetX, r.offsetY = self.renderer.offsetX, self.renderer.offsetY

    for i = 1, #nodes do
        local node = nodes[i]
        r.node = node
        r:_loadClip(node)

        -- Stage 11 (expensive path): pixel-perfect RT-clip + group-opacity
        if node._rtClip then
            self:_renderRtGroup(node, list, r)

        -- Stage 10: node-level blur/mask on non-Image widgets →
        -- the node's own items via an RT-group (effect layer).
        elseif (node.blur and node.blur > 0 or node.mask ~= nil or node.effect ~= nil)
            and DXUI.Effects and DXUI.Effects.canGroup()
            and node._class._name ~= "Image" then
            local effect
            if node.effect then
                effect = DXUI.getEffect(node.effect, node)
            elseif node.mask then
                effect = DXUI.Effects.mask(node.mask)
            else
                effect = DXUI.Effects.blur(node.width, node.height, node.blur)
            end
            if effect then
                local own = DXUI.RenderList.new()
                local gr = DXUI.Renderer.new(own)
                gr.node = node
                gr:_loadClip(node)
                gr.scaleX, gr.scaleY = r.scaleX, r.scaleY
                gr.offsetX, gr.offsetY = r.offsetX, r.offsetY
                node:render(gr)
                if own.count > 0 then
                    local sx, ox = r.scaleX, r.offsetX
                    local sy, oy = r.scaleY, r.offsetY
                    list:add({
                        kind = "rtgroup",
                        x = node.worldX * sx + ox, y = node.worldY * sy + oy,
                        w = node.width * sx, h = node.height * sy,
                        items = own.items, count = own.count,
                        effect = effect,
                    })
                end
            else
                node:render(r) -- shader unavailable — render without effect
            end
        else
            node:render(r)
        end
    end
end

--- Stage 11 (expensive path): node subtree → offscreen RT → single quad.
-- Pixel-perfect clip (RT bounds clip in hardware) + TRUE group-opacity
-- (alpha on the quad — internal overlaps aren't blended twice) + blur/mask
-- on the WHOLE subtree (container semantics — unlike Stage 10, where
-- blur applies only to the node's own items).
function Context:_renderRtGroup(node, list, r)
    local sx, ox = r.scaleX, r.offsetX
    local sy, oy = r.scaleY, r.offsetY

    -- node's clip region (parent geometric chain) — for children INSIDE the RT
    local parentClip
    if node._clipX ~= nil then
        parentClip = { node._clipX, node._clipY, node._clipW, node._clipH }
    end

    -- node's own items as background (node opacity on the quad, not in items)
    local subList = DXUI.RenderList.new()
    if node.render then
        local orr = DXUI.Renderer.new(subList)
        orr.node = node
        orr:_loadClip(node)
        orr.effOpacity = 1
        orr.scaleX, orr.scaleY = r.scaleX, r.scaleY
        orr.offsetX, orr.offsetY = r.offsetX, r.offsetY
        node:render(orr)
    end

    -- subtree: collect with opacity RELATIVE to the group (node opacity on quad)
    local sub = {}
    local children = node._children
    for i = 1, #children do
        self:_collectRenderable(children[i], true, parentClip, 1,
            node._effLayer or node.layer, sub)
    end
    self:_renderNodes(sub, subList) -- recursion (nested RT-groups)

    if subList.count == 0 then return end

    -- effect on the whole composite (container): named effect > mask > blur
    local effect
    if node.effect then
        effect = DXUI.getEffect(node.effect, node)
    elseif node.mask then
        effect = DXUI.Effects.mask(node.mask)
    elseif node.blur and node.blur > 0 then
        effect = DXUI.Effects.blur(node.width, node.height, node.blur)
    end

    list:add({
        kind = "rtgroup",
        x = node.worldX * sx + ox, y = node.worldY * sy + oy,
        w = node.width * sx, h = node.height * sy,
        items = subList.items, count = subList.count,
        effect = effect,
        alpha = node._effOpacity or 1, -- true group-opacity
        scaleX = node.scaleX or 1, scaleY = node.scaleY or 1, -- ScalePane
    })
end

--- Intersects a clip region (table {x,y,w,h} or nil) with a rectangle.
-- Returns {nx,ny,nw,nh} or nil (fully outside).
local function intersectClip(clip, x, y, w, h)
    local cx, cy, cw, ch
    if clip then
        cx, cy, cw, ch = clip[1], clip[2], clip[3], clip[4]
    else
        cx, cy, cw, ch = x, y, w, h
    end
    local x2, y2 = x + w, y + h
    local cx2, cy2 = cx + cw, cy + ch
    local nx = (x > cx) and x or cx
    local ny = (y > cy) and y or cy
    local nx2 = (x2 < cx2) and x2 or cx2
    local ny2 = (y2 < cy2) and y2 or cy2
    if nx2 <= nx or ny2 <= ny then return nil end
    return { nx, ny, nx2 - nx, ny2 - ny }
end

--- Recursively collects visible renderable nodes (basic culling: visible AND
-- all ancestors visible). parentVisible — parent's effective visibility;
-- clip — accumulated clip region (nil if none); parentOpacity —
-- inherited opacity (effective = node.opacity × parent's).
-- A node with clip=true creates its own region (intersected with parent's);
-- fully outside — the subtree is dropped.
function Context:_collectRenderable(node, parentVisible, parentClip, parentOpacity, parentLayer, out)
    local visible = parentVisible and node.visible

    -- effective layer: the node's own non-BASE layer, otherwise the
    -- nearest ancestor with a non-BASE layer (modal subtree above overlay)
    local effLayer = node.layer
    if effLayer == DXUI.LAYER.BASE then
        effLayer = parentLayer or DXUI.LAYER.BASE
    end
    rawset(node, "_effLayer", effLayer)

    local clip = parentClip
    if node.clip then
        clip = intersectClip(parentClip, node.worldX, node.worldY, node.width, node.height)
        if not clip then return end -- fully outside clip — drop the subtree
    end

    -- effective opacity: inherited downward multiplicatively.
    -- Cheap path — alpha modulation in the renderer; true group-opacity — RT.
    local op = node.opacity
    if op == nil or op > 1 then op = 1 elseif op < 0 then op = 0 end
    local effOpacity = parentOpacity * op
    rawset(node, "_effOpacity", effOpacity)

    -- store the clip region on the node (renderer reads it in _loadClip)
    if clip then
        rawset(node, "_clipX", clip[1]); rawset(node, "_clipY", clip[2])
        rawset(node, "_clipW", clip[3]); rawset(node, "_clipH", clip[4])
    else
        rawset(node, "_clipX", nil); rawset(node, "_clipY", nil)
        rawset(node, "_clipW", nil); rawset(node, "_clipH", nil)
    end

    -- Stage 11: clipMode="rt" — the subtree renders into an RT-group
    -- (pixel-perfect clip + group-opacity). Children don't join the main list.
    local rtClip = visible and node.clipMode == "rt"
        and DXUI.Effects and DXUI.Effects.canGroup()
    rawset(node, "_rtClip", rtClip or nil)

    if visible and (node.render or rtClip) then
        out[#out + 1] = node
    end
    if rtClip then return end -- subtree via _renderRtGroup

    local children = node._children
    for i = 1, #children do
        self:_collectRenderable(children[i], visible, clip, effOpacity, effLayer, out)
    end
end

--- Rebuilds the flat list of interactive nodes (derived cache).
-- Interactive = enabled AND visible (and all ancestors visible). Sorted in
-- the same order (layer, zIndex, id) as render, so "visually on top"
-- = "receives the click".
function Context:_rebuildInteractiveList()
    local nodes = {}
    self:_collectInteractive(self.root, true, DXUI.LAYER.BASE, nodes)

    table.sort(nodes, function(a, b)
        local la = a._effLayer or a.layer
        local lb = b._effLayer or b.layer
        if la ~= lb then return la < lb end
        if a.zIndex ~= b.zIndex then return a.zIndex < b.zIndex end
        return a.id < b.id
    end)

    self.interactiveList = {}
    self.interactiveCount = 0
    for i = 1, #nodes do
        self.interactiveCount = self.interactiveCount + 1
        self.interactiveList[self.interactiveCount] = nodes[i]
    end
end

function Context:_collectInteractive(node, parentVisible, parentLayer, out)
    local visible = parentVisible and node.visible
    local effLayer = node.layer
    if effLayer == DXUI.LAYER.BASE then
        effLayer = parentLayer or DXUI.LAYER.BASE
    end
    rawset(node, "_effLayer", effLayer)
    if visible and node.enabled then
        out[#out + 1] = node
    end
    local children = node._children
    for i = 1, #children do
        self:_collectInteractive(children[i], visible, effLayer, out)
    end
end

--- Draws the cached render list through the state cache.
function Context:_draw()
    local items = self.renderList.items
    for i = 1, self.renderList.count do
        self.stateCache:draw(items[i])
    end
end

-- ---------------------------------------------------------------------
-- Input (Stage 4) — thin passthroughs to the Dispatcher
-- ---------------------------------------------------------------------

function Context:onCursorMove(x, y)
    self.dispatcher:onCursorMove(x, y)
end

function Context:onMouseDown(x, y, button)
    self.dispatcher:onMouseDown(x, y, button)
end

function Context:onMouseUp(x, y, button)
    self.dispatcher:onMouseUp(x, y, button)
end

function Context:onMouseWheel(x, y, dz)
    self.dispatcher:onMouseWheel(x, y, dz)
end

function Context:onKeyDown(key, state, mods, text)
    self.dispatcher:onKeyDown(key, state, mods, text)
end

function Context:setFocus(node)
    self.dispatcher:setFocus(node)
end

function Context:getFocus()
    return self.dispatcher:getFocus()
end

-- ---------------------------------------------------------------------
-- Screen size (for layout, Stage 5)
-- ---------------------------------------------------------------------

function Context:setScreenSize(w, h)
    self.screenW = w
    self.screenH = h
    -- Stage 5: screen size change → recompute layout (root dirty cascades).
    self.root:_invalidate({ DXUI.DIRTY.LAYOUT })
end

-- ---------------------------------------------------------------------
-- Publication
-- ---------------------------------------------------------------------
DXUI.Context = Context
