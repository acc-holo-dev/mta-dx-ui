---Runtime: owns one instance's frame loop, derived caches and lifecycle.
---THE zero-work idle guarantee lives here:
---
---    tick(dtMs):
---        anim:update()                        -- runs only with active
---        if layoutDirty then Layout.update    -- animations (early out)
---        if renderDirty/orderDirty then RenderPass.build
---        if interactiveDirty then HitTest.rebuild
---        draw the CACHED render list          -- ~zero work idle
---
---Invalidation: Node mutations OR their category into four instance-level
---flags (layoutDirty/renderDirty/orderDirty/interactiveDirty) directly.
---Consequent mutations in the same frame coalesce; the flags are drained
---once per frame.
---
---Purposely no per-node dirty drilling: collect() walks the tree anyway
---(it must, for opacity/clip), so flag granularity is a diagnostics/
---roadmap concern (orderDirty is reserved for incremental work).
---
---Pure Lua: rendering delegates to an injected backend (DXUI.BackendMTA
---in MTA; mock in tests); the clock is injectable too.

DXUI = DXUI or {}

local Runtime = {}

--- Backend provider, injected by init.lua (DXUI.BackendMTA) or tests.
Runtime.backend = nil

--- Clock source (ms). Injectable: init.lua wires getTickCount.
function Runtime.clockDefault()
    if getTickCount then return getTickCount() end
    return 0
end

--- Creates a UI instance.
-- opts:  name (string), design = {width,height}, settings overrides,
--        backend (default DXUI.BackendMTA), clock = fn()
function Runtime.create(opts)
    opts = opts or {}
    local self = setmetatable({}, Runtime)

    self.name = opts.name or string.format("ui%d", DXUI.Runtime._counter)
    DXUI.Runtime._counter = (DXUI.Runtime._counter or 0) + 1

    self._destroyed = false
    self.backend = opts.backend or Runtime.backend
    self.clock = opts.clock or Runtime.clockDefault

    -- design resolution: explicit opts win, else the engine-wide default
    -- from DXUI.Settings.designResolution, else screen space (design == screen)
    local design = opts.design
    if not design and DXUI.Settings then
        local dr = DXUI.Settings.designResolution
        if dr and dr.width and dr.height and dr.width > 0 and dr.height > 0 then
            design = dr
        end
    end
    design = design or {}
    self.layoutW = design.width or 0
    self.layoutH = design.height or 0
    self.screenW = 0
    self.screenH = 0

    -- root + derived caches
    local Node = DXUI.Node
    self.root = Node:new()
    rawset(self.root, "_context", self)
    self.renderList = DXUI.RenderList.new()
    self.renderer = DXUI.Renderer.new(self.renderList)
    self._renderNodes = {}
    self._groupScratchList = DXUI.RenderList.new()
    self._interactive = {}
    self._interactiveCount = 0

    -- frame diagnostics (always on: a few integer increments per frame)
    self.stats = {
        frames = 0, layoutRuns = 0, rebuilds = 0, hitRebuilds = 0,
        items = 0, draws = 0,
    }
    self._prevLayoutRuns = 0
    self._prevRebuilds = 0
    -- { zeroWork = true } asserts the idle-frame contract
    self.perf = nil

    -- subsystems
    self.anim = DXUI.Anim and DXUI.Anim.new(self) or nil
    self.dispatcher = DXUI.Dispatcher and DXUI.Dispatcher.new(self) or nil
    -- overlay nodes (frame-clock repaints: the Edit caret blink); drawn
    -- every frame after the cached list, never invalidating it
    self._overlays = {}

    -- dirty model
    self.layoutDirty = true
    self.renderDirty = true
    self.orderDirty = false
    self.interactiveDirty = true
    self.dirty = false

    -- design resolution mode: stretch | fit | none (letterbox reserved)
    self.designMode = (design.width and design.height)
        and (design.mode or "stretch") or "none"

    -- settings snapshot (engine behavior lives in DXUI.config.dev)
    if opts.settings then
        if DXUI.applySettings then DXUI.applySettings(opts.settings) end
    end
    return self
end

-- ---------------------------------------------------------------------
-- Dirty model integration (Node mutations call these)
-- ---------------------------------------------------------------------

--- Handles a node's destruction: notifies subsystems and marks dirty.
function Runtime:_onNodeDestroyed(node)
    if self.dispatcher then self.dispatcher:nodeDestroyed(node) end
    if self.anim then self.anim:stop(node) end
    -- a destroy always changes the draw set
    self.renderDirty = true
    self.interactiveDirty = true
end

-- ---------------------------------------------------------------------
-- Viewport + design mapping
-- ---------------------------------------------------------------------

--- Updates the screen viewport; recomputes the design->screen mapping.
-- Mode "stretch": design coords fill the screen exactly (scaleX=sw/lw).
-- Mode "fit": letterboxed to the largest contained rect (offsets set).
function Runtime:setViewport(w, h)
    self.screenW = w
    self.screenH = h
    if self.designMode == "none" or self.layoutW <= 0 or self.layoutH <= 0 then
        self.layoutW = w
        self.layoutH = h
    end
    if self.designMode == "fit" then
        local sx = w / self.layoutW
        local sy = h / self.layoutH
        local s = (sx < sy) and sx or sy
        self._mapScaleX = s
        self._mapScaleY = s
        self._mapOffX = (w - self.layoutW * s) / 2
        self._mapOffY = (h - self.layoutH * s) / 2
    -- stretch
    else
        self._mapScaleX = w / self.layoutW
        self._mapScaleY = h / self.layoutH
        self._mapOffX = 0
        self._mapOffY = 0
    end
    self.layoutDirty = true
    self.renderDirty = true
end

--- Screen -> design coords (inverse mapping).
function Runtime:designPoint(sx, sy)
    local s = self._mapScaleX or 1
    local sy2 = self._mapScaleY or 1
    return (sx - (self._mapOffX or 0)) / s, (sy - (self._mapOffY or 0)) / sy2
end

-- ---------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------

--- One frame. Never blocks; early-outs when nothing to do.
-- Diagnostics: `self.stats` accumulates cheap frame counters ALWAYS;
-- `self.perf.zeroWork = true` additionally asserts that no pass runs
-- without its dirty flag (measures the "idle frame = zero work" contract).
function Runtime:tick()
    if self._destroyed then return end
    local stats = self.stats
    stats.frames = stats.frames + 1

    -- 1. animations (writes properties through the mutation layer — the
    --    dirty flags they set are consumed by the same frame's passes)
    if self.anim then self.anim:update() end

    if self.perf and self.perf.zeroWork then
        if not self.layoutDirty then
            assert(stats.layoutRuns == self._prevLayoutRuns,
                "zero-work violated: layout ran without layoutDirty")
        end
        if not (self.renderDirty or self.orderDirty) then
            assert(stats.rebuilds == self._prevRebuilds,
                "zero-work violated: render list rebuilt without dirty")
        end
    end

    -- 2. layout
    if self.layoutDirty then
        DXUI.Layout.update(self)
        stats.layoutRuns = stats.layoutRuns + 1
        self.layoutDirty = false
        -- positions changed
        self.renderDirty = true
        self.interactiveDirty = true
    end

    -- 3. render list rebuild + interactive list
    if self.renderDirty or self.orderDirty then
        stats.rebuilds = stats.rebuilds + 1
        stats.items = DXUI.RenderPass.build(self)
        self.renderDirty = false
        self.orderDirty = false
    end
    if self.interactiveDirty then
        if DXUI.HitTest then
            DXUI.HitTest.rebuild(self)
            stats.hitRebuilds = stats.hitRebuilds + 1
        end
        self.interactiveDirty = false
    end

    -- 4. draw the cached list (zero work when the list is empty)
    self:draw()

    -- baseline for the NEXT frame's zero-work check — must be taken AFTER
    -- the passes (same tick may legitimately consume dirty flags)
    if self.perf and self.perf.zeroWork then
        self._prevLayoutRuns = stats.layoutRuns
        self._prevRebuilds = stats.rebuilds
    end
end

--- Draws the cached render list via the injected backend (state-deduped),
--- then the overlay pass: live per-frame repaints (caret blink) drawn
--- directly through the backend WITHOUT invalidating the cached list —
--- the zero-work idle contract holds.
function Runtime:draw()
    local backend = self.backend
    if not backend then return end
    -- lazy state cache per backend instance
    if not self._state then
        self._state = DXUI.RenderState.new(backend)
    end
    local list = self.renderList
    self.stats.draws = self.stats.draws + list.count
    for i = 1, list.count do
        self._state:draw(list.items[i])
    end
    local overlays = self._overlays
    if overlays and #overlays > 0 then
        local r = self.renderer
        r.direct = self._state
        for i = 1, #overlays do
            local n = overlays[i]
            if n and not n._destroyed and n._visible and n.overlay then
                n:overlay(r)
            end
        end
        r.direct = nil
    end
end

-- ---------------------------------------------------------------------
-- Input bridge (screen coords in, design routing; MTA wiring in init.lua)
-- ---------------------------------------------------------------------

--- Routes a mouse-move to the dispatcher in design coordinates.
function Runtime:mouseMove(sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    self.dispatcher:mouseMove(dx, dy)
end

--- Routes a mouse-down to the dispatcher in design coordinates.
function Runtime:mouseDown(button, sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    self.dispatcher:mouseDown(button, dx, dy)
end

--- Routes a mouse-up to the dispatcher in design coordinates.
function Runtime:mouseUp(button, sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    self.dispatcher:mouseUp(button, dx, dy)
end

--- Routes a scroll event to the dispatcher in design coordinates.
function Runtime:scroll(wheel, sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    return self.dispatcher:scroll(wheel, dx, dy)
end

--- Routes a key event to the dispatcher (isDown = down/up edge; extra
--- args ride along — e.g. the shift modifier from init.lua).
function Runtime:key(keyName, isDown, ...)
    if not self.dispatcher then return false end
    return self.dispatcher:key(keyName, isDown, ...)
end

--- Routes a character input to the dispatcher.
function Runtime:character(ch)
    if not self.dispatcher then return false end
    return self.dispatcher:character(ch)
end

-- ---------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------

--- Fully destroys the instance (tree, caches, animations, resources) and
-- drops it from the global tick list so the frame loop stops visiting it.
function Runtime:destroy()
    if self._destroyed then return end
    self._destroyed = true
    -- leave the tick list (a direct ui:destroy() must not keep the
    -- instance being ticked every frame; releaseResource removes it too,
    -- which is harmless here)
    local uis = DXUI._uis
    if uis then
        for i = #uis, 1, -1 do
            if uis[i] == self then table.remove(uis, i) end
        end
    end
    self.root:destroy()
    if self.anim then
        self.anim.active = nil
        self.anim.activeCount = 0
    end
    DXUI.RenderList.recycle(self.renderList.items, self.renderList.count)
    self.renderList.count = 0
    self._renderNodes = nil
    self._interactive = nil
end

Runtime.__index = Runtime

DXUI.Runtime = Runtime