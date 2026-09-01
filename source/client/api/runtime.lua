--[[
    runtime.lua — DXUI V3

    UI Runtime: owns one instance's frame loop, derived caches and
    lifecycle. THE zero-work idle guarantee lives here:

        tick(dtMs):
            anim:update()                        -- runs only with active
            if layoutDirty then Layout.update    -- animations (early out)
            if renderDirty/orderDirty then RenderPass.build
            if interactiveDirty then HitTest.rebuild
            draw the CACHED render list          -- ~zero work idle

    Invalidation: Node mutations set per-node category flags and call
    instance:_queueNode(node) which ORs them into four instance-level flags
    (layoutDirty/renderDirty/orderDirty/interactiveDirty). Consequent
    mutations in the same frame coalesce; the flags are drained once.

    Purposely no per-node dirty drilling in v1: collect() walks the tree
    anyway (it must, for opacity/clip), so flag granularity is a
    diagnostics/roadmap concern (orderDirty is reserved for incremental
    work — v1 always re-sorts).

    Pure Lua: rendering delegates to an injected backend (DXUI.BackendMTA
    in MTA; mock in tests); the clock is injectable too.
]]

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

    self.backend = opts.backend or Runtime.backend
    self.clock = opts.clock or Runtime.clockDefault

    -- design resolution (else screen space behaior: design == screen)
    local design = opts.design or {}
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
    self.perf = nil -- { zeroWork = true } asserts the idle-frame contract

    -- subsystems
    self.anim = DXUI.Anim and DXUI.Anim.new(self) or nil
    self.dispatcher = DXUI.Dispatcher and DXUI.Dispatcher.new(self) or nil

    -- dirty model
    self.layoutDirty = true
    self.renderDirty = true
    self.orderDirty = false
    self.interactiveDirty = true
    self.dirty = false

    -- design resolution mode: stretch | fit | none (letterbox reserved)
    self.designMode = (design.width and design.height) and "stretch" or "none"

    -- settings snapshot (engine behavior lives in DXUI.config.dev)
    if opts.settings then
        if DXUI.applySettings then DXUI.applySettings(opts.settings) end
    end
    self.settings = (DXUI.config and DXUI.config.dev) or DXUI.Settings or {}
    return self
end

-- ---------------------------------------------------------------------
-- Dirty model integration (Node mutations call these)
-- ---------------------------------------------------------------------

function Runtime:_queueNode(node)
    if node._layoutDirty then self.layoutDirty = true end
    if node._renderDirty then self.renderDirty = true end
    if node._orderDirty then self.orderDirty = true end
    if node._interactiveDirty then self.interactiveDirty = true end
end

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
    else -- stretch
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
        self._prevLayoutRuns = stats.layoutRuns
        self._prevRebuilds = stats.rebuilds
    end

    -- 2. layout
    if self.layoutDirty then
        DXUI.Layout.update(self)
        stats.layoutRuns = stats.layoutRuns + 1
        self.layoutDirty = false
        self.renderDirty = true -- positions changed
        self.interactiveDirty = true
    end

    -- 3. render list rebuild + interactive list
    if self.renderDirty or self.orderDirty then
        if self.backend ~= nil or not DXUI.Renderer then
            stats.rebuilds = stats.rebuilds + 1
            stats.items = DXUI.RenderPass.build(self)
        end
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
end

--- Draws the cached render list via the injected backend (state-deduped).
function Runtime:draw()
    local backend = self.backend
    if not backend then return end
    if self.renderList.count == 0 then return end
    -- lazy state cache per backend instance
    if not self._state then
        self._state = DXUI.RenderState.new(backend)
    end
    local list = self.renderList
    self.stats.draws = self.stats.draws + list.count
    for i = 1, list.count do
        self._state:draw(list.items[i])
    end
end

-- ---------------------------------------------------------------------
-- Input bridge (screen coords in, design routing; MTA wiring in init.lua)
-- ---------------------------------------------------------------------

function Runtime:mouseMove(sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    self.dispatcher:mouseMove(dx, dy)
end

function Runtime:mouseDown(button, sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    self.dispatcher:mouseDown(button, dx, dy)
end

function Runtime:mouseUp(button, sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    self.dispatcher:mouseUp(button, dx, dy)
end

function Runtime:scroll(wheel, sx, sy)
    if not self.dispatcher then return end
    local dx, dy = self:designPoint(sx, sy)
    return self.dispatcher:scroll(wheel, dx, dy)
end

function Runtime:key(keyName, pressed2, ...)
    if not self.dispatcher then return false end
    return self.dispatcher:key(keyName, pressed2, ...)
end

-- ---------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------

--- Fully destroys the instance (tree, caches, animations, resources).
function Runtime:destroy()
    if self._destroyed then return end
    self._destroyed = true
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