--[[
    node.lua — DXUI V2

    Node: the public UI object. A plain Lua table with a metatable that
    intercepts property reads/writes to funnel everything through a single
    mutation layer (validation + invalidation).

    Key decisions (see ARCHITECTURE.md):
      - AoS: node state is the object itself (not SoA + slot + id).
      - Property-style (node.x = 100) and method-style (node:setPosition(...))
        converge in Node:_set(prop, value).
      - Invalidation uses named categories (DIRTY_LAYOUT etc.) stored as
        boolean flags in node._dirty. No bitmasks exposed.
      - parent/children are managed by methods (setParent/addChild) and read
        as read-only fields.
      - Inheritance is plain prototype inheritance via Node.extend().

    Module has no MTA API dependency — pure Lua 5.1, testable outside the game.
]]

DXUI = DXUI or {}

-- ---------------------------------------------------------------------
-- Configuration and warnings (error handling)
-- ---------------------------------------------------------------------
DXUI.config = DXUI.config or { debug = false }

function DXUI._warn(msg)
    if DXUI.config.debug then
        if outputDebugString then
            outputDebugString("[dxui] " .. msg)
        else
            print("[dxui] " .. msg)
        end
    end
end

-- ---------------------------------------------------------------------
-- Dirty categories (named; internally boolean flags)
-- ---------------------------------------------------------------------
DXUI.DIRTY = {
    LAYOUT     = "layout",     -- position/size/parent/anchor/margin/padding
    RENDER     = "render",     -- color/text/texture/opacity/geometry
    INPUT      = "input",      -- hit-geometry/visibility/enabled/z-order
    STYLE      = "style",      -- style resolution
    CHILDREN   = "children",   -- children composition
    VISIBILITY = "visibility", -- visibility/culling
}

local DIRTY = DXUI.DIRTY

-- ---------------------------------------------------------------------
-- Layers (named)
-- ---------------------------------------------------------------------
DXUI.LAYER = {
    BASE    = 0,
    OVERLAY = 1,
    MODAL   = 2,
    POPUP   = 3,
    TOOLTIP = 4,
    DEBUG   = 5,
}

local LAYER = DXUI.LAYER

-- ---------------------------------------------------------------------
-- Node
-- ---------------------------------------------------------------------
local Node = {}
Node._name = "Node"
Node._super = nil

-- Property declaration: name -> { default, invalidates = {categories} }.
-- Each property knows which subsystems it invalidates.
Node.properties = {
    -- geometry: a change affects both layout and render (world coords)
    x        = { default = 0,    type = "number", invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    y        = { default = 0,    type = "number", invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    width    = { default = 0,    type = "number", min = 0, invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    height   = { default = 0,    type = "number", min = 0, invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    visible  = { default = true, invalidates = { DIRTY.VISIBILITY, DIRTY.INPUT, DIRTY.RENDER } },
    enabled  = { default = true, invalidates = { DIRTY.INPUT },
                 onSet = function(node, value)
                     -- M22: disabled state — recompute via dispatcher
                     if node._context and node._context.dispatcher then
                         node._context.dispatcher:_updateNodeState(node)
                     end
                 end },
    opacity  = { default = 1,    type = "number", invalidates = { DIRTY.RENDER } },
    zIndex   = { default = 0,    type = "number", invalidates = { DIRTY.INPUT, DIRTY.RENDER } },
    layer    = { default = LAYER.BASE, invalidates = { DIRTY.RENDER } },
    -- style: theme style name or inline table. Setting it after creation
    -- switches the style (onSet → Widget.applyStyle, see style/theme.lua).
    style    = { default = nil,  invalidates = { DIRTY.STYLE },
                 onSet = function(node, value)
                     -- late binding: Widget is defined after node.lua
                     if DXUI.Widget and DXUI.Widget._onStyleSet then
                         DXUI.Widget._onStyleSet(node, value)
                     end
                 end },
    userData = { default = nil,  invalidates = {} },
    -- Stage 5: layout. margin/padding — number (all sides) or
    -- table {left, top, right, bottom}. Set whole, don't mutate in-place.
    layoutMode = { default = "absolute", invalidates = { DIRTY.LAYOUT } },
    anchor     = { default = "tl",       invalidates = { DIRTY.LAYOUT } },
    margin     = { default = nil,        invalidates = { DIRTY.LAYOUT } },
    padding    = { default = nil,        invalidates = { DIRTY.LAYOUT } },
    -- Stage 7: clip. true — children clipped to node bounds.
    -- Cheap path — geometric clip in the render list; RT-stack later (masks/blur).
    clip       = { default = false,      invalidates = { DIRTY.RENDER, DIRTY.INPUT } },
    -- Stage 11 (expensive path): clipMode = "rt" — subtree composited into
    -- an offscreen RT: pixel-perfect clip + true group-opacity +
    -- blur/mask on the whole container. Default (nil) — cheap geometric path.
    clipMode   = { default = nil,         invalidates = { DIRTY.RENDER } },
    -- Stage 7b: autosize — size to content (layout calls _measureContent
    -- and writes width/height through the mutation layer).
    autoSize   = { default = false,      invalidates = { DIRTY.LAYOUT } },
}

Node._spec = Node.properties

-- read-only computed fields (managed by methods, not assignment)
local READONLY = {
    parent = true, children = true, id = true,
    context = true, destroyed = true,
    worldX = true, worldY = true, -- Stage 5: computed by the layout pass
}

-- global id counter (debug/events; not node-owned)
local nextId = 1

-- ---------------------------------------------------------------------
-- Instance metatable (shared by all nodes)
-- ---------------------------------------------------------------------
local mt = {
    __index = function(self, key)
        if key == "parent"    then return self._parent end
        if key == "children"  then return self._children end
        if key == "id"        then return self._id end
        if key == "context"   then return self._context end
        if key == "destroyed" then return self._destroyed end
        if key == "worldX"    then return self._worldX end
        if key == "worldY"    then return self._worldY end

        local spec = self._spec[key]
        if spec then
            return self._data[key]
        end

        -- methods via the class chain (Node -> Widget -> Button -> ...)
        local cls = self._class
        while cls do
            local m = rawget(cls, key)
            if m ~= nil then return m end
            cls = cls._super
        end
        return nil
    end,

    __newindex = function(self, key, value)
        if READONLY[key] then
            DXUI._warn("read-only property: " .. key)
            return
        end
        local spec = self._spec and self._spec[key]
        if spec then
            self:_set(key, value)
        else
            rawset(self, key, value) -- arbitrary user fields
        end
    end,
}

-- ---------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------

--- Creates a node. self — the class (Node or a subclass).
function Node:new(props)
    return self:_instantiate(self, props)
end

function Node:_instantiate(cls, props)
    local self = setmetatable({}, mt)
    rawset(self, "_class", cls)
    rawset(self, "_spec", cls._spec)
    rawset(self, "_data", {})
    rawset(self, "_dirty", {})
    rawset(self, "_queued", false)
    rawset(self, "_context", nil)
    rawset(self, "_parent", nil)
    rawset(self, "_children", {})
    rawset(self, "_destroyed", false)
    rawset(self, "_id", nextId)
    rawset(self, "_worldX", 0) -- Stage 5: computed by the layout pass
    rawset(self, "_worldY", 0)
    rawset(self, "_state", "normal") -- M22: visual state (hover/pressed/...)
    rawset(self, "_userSet", {}) -- M23: user-owned properties (theme guard)
    rawset(self, "_themeApplied", {}) -- theme-managed properties (revert list)
    nextId = nextId + 1

    -- default values
    for k, spec in pairs(cls._spec) do
        self._data[k] = spec.default
    end

    -- _building: during construction the style onSet hook does not re-apply
    -- the style — applyThemeDefaults below does the initial application
    rawset(self, "_building", true)

    -- apply props: properties via _set; other keys via rawset,
    -- but don't shadow methods (props.onChange must not override Node:onChange)
    if props then
        for k, v in pairs(props) do
            if self._spec[k] then
                self[k] = v
            else
                local cls = self._class
                local isMethod = false
                while cls do
                    if rawget(cls, k) ~= nil then isMethod = true; break end
                    cls = cls._super
                end
                if isMethod then
                    DXUI._warn("props key shadows a method (skipped): " .. tostring(k))
                else
                    self[k] = v
                end
            end
        end
    end

    -- Stage 7b: theme defaults for properties not given in props.
    -- Lookup is lazy — style/theme.lua loads later, but before runtime.
    if DXUI.Widget and DXUI.Widget.applyThemeDefaults then
        DXUI.Widget.applyThemeDefaults(self, props)
    end

    rawset(self, "_building", nil)
    return self
end

-- ---------------------------------------------------------------------
-- Inheritance (plain prototype inheritance, Lua 5.1)
-- ---------------------------------------------------------------------

--- Creates a subclass. self — the parent class.
function Node:extend(name, properties)
    local Sub = {}
    Sub._name = name
    Sub._super = self
    Sub.properties = properties or {}
    Sub._spec = {}
    for k, v in pairs(self._spec) do Sub._spec[k] = v end
    for k, v in pairs(Sub.properties) do Sub._spec[k] = v end
    setmetatable(Sub, { __index = self })
    return Sub
end

-- ---------------------------------------------------------------------
-- Mutation layer (single point of property changes)
-- ---------------------------------------------------------------------

-- Builds a validator from declarative spec fields (type/min/max) plus an
-- optional explicit validate function. Cached on the spec. Returns nil if
-- there are no constraints.
local function getValidator(spec)
    if spec._validator ~= nil then return spec._validator end
    local checks = {}
    if spec.validate then checks[#checks + 1] = spec.validate end
    if spec.type then
        local t = spec.type
        checks[#checks + 1] = function(v) return type(v) == t end
    end
    if spec.min ~= nil then
        local mn = spec.min
        checks[#checks + 1] = function(v) return v >= mn end
    end
    if spec.max ~= nil then
        local mx = spec.max
        checks[#checks + 1] = function(v) return v <= mx end
    end
    local validator = nil
    if #checks > 0 then
        validator = function(v)
            for i = 1, #checks do
                if not checks[i](v) then return false end
            end
            return true
        end
    end
    spec._validator = validator
    return validator
end

function Node:_set(key, value)
    if self._destroyed then
        DXUI._warn("set on destroyed node: " .. key)
        return self
    end
    local spec = self._spec[key]
    if not spec then
        rawset(self, key, value)
        return self
    end
    local validator = getValidator(spec)
    if validator and not validator(value) then
        error("invalid value for '" .. key .. "': " .. tostring(value), 2)
    end
    if spec.transform then
        value = spec.transform(value)
    end
    -- same value — no invalidation (and no layout↔size loops).
    local old = self._data[key]
    if old == value then return self end
    self._data[key] = value
    -- a manual property write clears its theme origin: a style change
    -- won't overwrite what the user set explicitly
    if self._themeApplied and not self._applyingTheme then
        self._themeApplied[key] = nil
    end
    -- and records user-ownership: a style change won't touch a property
    -- set explicitly (props or manual) or by the system (layout/autosize).
    if not self._applyingTheme then
        self._userSet = self._userSet or {}
        self._userSet[key] = true
    end
    self:_invalidate(spec.invalidates)
    -- M25: property listeners (user-level, any property)
    local pl = self._propListeners and self._propListeners[key]
    if pl then
        for i = 1, #pl do
            pl[i](value, old, self)
        end
    end
    -- property special hook (style → style switch); after invalidation,
    -- since the hook writes properties through the same mutation layer
    if spec.onSet then spec.onSet(self, value) end
    return self
end

function Node:_invalidate(categories)
    for i = 1, #categories do
        self._dirty[categories[i]] = true
    end
    if self._context then
        self._context:_queueDirty(self)
    end
end

function Node:_hasDirty()
    for _, v in pairs(self._dirty) do
        if v then return true end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Method-style setters/getters (same mutation layer)
-- ---------------------------------------------------------------------

function Node:setPosition(x, y)
    self:_set("x", x)
    self:_set("y", y)
    return self
end

function Node:getPosition()
    return self.x, self.y
end

function Node:setSize(w, h)
    self:_set("width", w)
    self:_set("height", h)
    return self
end

function Node:getSize()
    return self.width, self.height
end

function Node:setVisible(v)
    self:_set("visible", v)
    return self
end

function Node:isVisible()
    return self.visible
end

function Node:show() return self:setVisible(true) end
function Node:hide() return self:setVisible(false) end

function Node:setEnabled(v)
    self:_set("enabled", v)
    return self
end

function Node:isEnabled()
    return self.enabled
end

--- M22: sets the visual state (normal/hover/pressed/focused/disabled).
-- Called by the dispatcher (input) and the enabled property. Triggers style
-- re-application via Widget._applyStyleState.
function Node:setState(state)
    if self._state == state then return self end
    self._state = state
    if DXUI.Widget and DXUI.Widget._applyStyleState then
        DXUI.Widget._applyStyleState(self)
    end
    return self
end

function Node:setOpacity(v)
    self:_set("opacity", v)
    return self
end

--- M25: property listener. fn(value, oldValue, node) is called whenever
-- the property changes through the mutation layer (themes/animation included).
function Node:onProperty(key, fn)
    self._propListeners = self._propListeners or {}
    local list = self._propListeners[key]
    if not list then list = {}; self._propListeners[key] = list end
    list[#list + 1] = fn
    return self
end

--- Removes a property listener (all registrations of the same fn).
function Node:offProperty(key, fn)
    local list = self._propListeners and self._propListeners[key]
    if list then
        for i = #list, 1, -1 do
            if list[i] == fn then table.remove(list, i) end
        end
    end
    return self
end

-- ---- Stage 7b: animation -----------------------------------------
-- Changes real properties through the normal mutation layer (no duplicate
-- node.x / animation.x). Single tick in Context:renderFrame. Returns an
-- AnimHandle: :after(...) chain, :onDone(fn), :cancel().

function Node:animate(props, duration, ease)
    if self._context and self._context.animation then
        return self._context.animation:animate(self, props, duration, ease)
    end
    return self -- no context (before mounting) — no-op, keeps chaining
end

function Node:stopAnimations()
    if self._context and self._context.animation then
        self._context.animation:stop(self)
    end
    return self
end

function Node:isAnimating()
    if self._context and self._context.animation then
        return self._context.animation:isAnimating(self)
    end
    return false
end

-- ---- Stage 7b: autosize hook -------------------------------------------
--- Measures content for autoSize. Node-base: current size (stable).
-- Widget overrides (children), Label — text.
function Node:_measureContent()
    return self.width, self.height
end

function Node:setZIndex(z)
    self:_set("zIndex", z)
    return self
end

function Node:setLayer(l)
    self:_set("layer", l)
    return self
end

--- Stage 7: over siblings — zIndex = max(siblings)+1 (no-op if already on top).
function Node:bringToFront()
    local maxZ = -1
    local siblings = self._parent and self._parent._children or nil
    if not siblings then return self end
    for i = 1, #siblings do
        local s = siblings[i]
        if s ~= self and s.zIndex > maxZ then maxZ = s.zIndex end
    end
    if maxZ >= self.zIndex then
        self.zIndex = maxZ + 1
    end
    return self
end

-- ---- Stage 5: layout setters ----------------------------------------
function Node:setLayoutMode(mode)
    self:_set("layoutMode", mode)
    return self
end

function Node:setAnchor(anchor)
    self:_set("anchor", anchor)
    return self
end

function Node:setMargin(l, t, r, b)
    self:_set("margin", { left = l, top = t, right = r, bottom = b })
    return self
end

function Node:setPadding(l, t, r, b)
    self:_set("padding", { left = l, top = t, right = r, bottom = b })
    return self
end

-- ---------------------------------------------------------------------
-- Parent / child
-- ---------------------------------------------------------------------

function Node:addChild(child)
    child:setParent(self)
    return self
end

function Node:setParent(parent)
    if parent == self._parent then return self end
    if parent == self then
        error("cannot set a node as its own parent", 2)
    end
    if parent and parent._destroyed then
        error("cannot set parent to a destroyed node", 2)
    end

    -- cycle guard: parent must not be a descendant of self
    local p = parent
    while p do
        if p == self then
            error("cycle detected in parent chain", 2)
        end
        p = p._parent
    end

    -- detach from the previous parent
    if self._parent then
        self._parent:_removeChild(self)
    end
    self._parent = parent
    if parent then
        parent._children[#parent._children + 1] = self
        -- Layer is NOT mutated on attach: the effective layer (own non-BASE,
        -- else nearest non-BASE ancestor) is computed when collecting lists
        -- (Context:_collectRenderable/_collectInteractive). Fixes children
        -- stuck in MODAL after setModal(false) and avoids implicit property
        -- mutation.
    end

    -- propagate the context to the subtree
    self:_setContextRecursive(parent and parent._context or nil)

    -- invalidation
    self:_invalidate({ DIRTY.LAYOUT })
    if parent then
        parent:_invalidate({ DIRTY.CHILDREN, DIRTY.LAYOUT })
    end
    return self
end

function Node:_removeChild(child)
    local children = self._children
    for i = 1, #children do
        if children[i] == child then
            table.remove(children, i)
            return
        end
    end
end

function Node:_setContextRecursive(ctx)
    self._context = ctx
    if ctx and self:_hasDirty() then
        ctx:_queueDirty(self)
    end
    -- M22: recompute state on mount (e.g. enabled=false set before mounting)
    if ctx and ctx.dispatcher then
        ctx.dispatcher:_updateNodeState(self)
    end
    local children = self._children
    for i = 1, #children do
        children[i]:_setContextRecursive(ctx)
    end
end

-- ---------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------

function Node:destroy()
    if self._destroyed then return end
    self._destroyed = true

    -- cleanup hook for composite widgets (modal overlay, popup stack, etc.)
    -- before children are destroyed — _context is still alive
    if self._onDestroy then
        self:_onDestroy()
    end

    -- children first (parent owns children)
    local children = self._children
    for i = #children, 1, -1 do
        children[i]:destroy()
    end

    -- detach from the parent
    if self._parent then
        self._parent:_removeChild(self)
        self._parent = nil
    end

    -- remove from the context queue
    if self._context then
        self._context:_onNodeDestroyed(self)
    end

    -- clear references (frees node-owned resources in Stage 3+)
    self._context = nil
    self._children = {}
    self._data = {}
    self._dirty = {}
    self._queued = false
    self._listeners = nil -- destroy drops subscriptions (no events from a dead node)
    self._propListeners = nil -- M25: same guarantee for property subscriptions
end

function Node:isDestroyed()
    return self._destroyed
end

function Node:isAlive()
    return not self._destroyed
end

-- ---------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------
DXUI.Node = Node
