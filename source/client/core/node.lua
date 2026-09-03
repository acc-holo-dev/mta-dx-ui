---Node — the base public UI object: a plain Lua table whose metatable
---funnels every property write through a single mutation layer
---(validation + transform + owner tracking + invalidation), exposing
---value objects (color/position/size), parts, tree ops and an explicit
---lifecycle.
---
---Both API styles converge here:
---    button.x = 100            --> __newindex --> Node:_set("x", 100)
---    button:setPosition(100,0) --> _set("x",100) + _set("y",0)
---
---Ownership: the parent owns its children (destroy cascades). The UI
---instance owns the tree; the runtime owns the instances.
---
---Pure Lua 5.1 — no MTA API (testable outside the game).

DXUI = DXUI or {}

-- ---------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------
DXUI.config = DXUI.config or { dev = false }

-- DXUI._warn is now provided by api/debug.lua (back-compat shim)

-- ---------------------------------------------------------------------
-- Dirty categories (readable names) and instance frame flags
-- ---------------------------------------------------------------------
DXUI.DIRTY = {
    LAYOUT     = "layout",
    STYLE      = "style",
    RENDER     = "render",
    INPUT      = "input",
    CONTENT    = "content",
    VISIBILITY = "visibility",
    ORDER      = "order",
}
local DIRTY = DXUI.DIRTY

-- Category -> instance frame flags.
local CATEGORY_FLAGS = {
    [DIRTY.LAYOUT]     = { layout = true, render = true, interactive = true },
    [DIRTY.STYLE]      = { render = true },
    [DIRTY.RENDER]     = { render = true },
    [DIRTY.INPUT]      = { interactive = true },
    [DIRTY.CONTENT]    = { layout = true, render = true, order = true, interactive = true },
    [DIRTY.VISIBILITY] = { render = true, interactive = true },
    [DIRTY.ORDER]      = { render = true, order = true, interactive = true },
}

DXUI.LAYER = {
    BASE = 0, OVERLAY = 1, MODAL = 2, POPUP = 3, TOOLTIP = 4, DEBUG = 5,
}

-- ---------------------------------------------------------------------
-- Node class
-- ---------------------------------------------------------------------
local Node = {}
Node._name = "Node"
Node._super = nil

--- onSet hook for the style property: applies the style through the widget
-- contract (late-bound to DXUI.Widget, which loads after node.lua).
local function Node_styleSet(node, value)
    if DXUI.Widget and DXUI.Widget._onStyleSet then
        DXUI.Widget._onStyleSet(node, value)
    end
end

--- Declarative property specs. Each entry: { default, type?, min?, max?,
-- validate?, transform?, invalidates = {categories}, onSet? }.
Node.properties = {
    x        = { default = 0,    type = "number", invalidates = { DIRTY.LAYOUT } },
    y        = { default = 0,    type = "number", invalidates = { DIRTY.LAYOUT } },
    width    = { default = 0,    type = "number", min = 0, invalidates = { DIRTY.LAYOUT } },
    height   = { default = 0,    type = "number", min = 0, invalidates = { DIRTY.LAYOUT } },
    -- visibility affects BOTH the draw set and the input set (hidden
    -- interactive nodes must leave the hit-test list)
    visible  = { default = true, invalidates = { DIRTY.VISIBILITY, DIRTY.INPUT } },
    enabled  = { default = true, invalidates = { DIRTY.INPUT, DIRTY.RENDER }, onSet = function(node)
        if node._class and node._class._applyStyleState then
            -- disabled state visually re-applies
            node:_applyStyleState()
        end
    end },
    opacity  = { default = 1,    type = "number", min = 0, max = 1, invalidates = { DIRTY.RENDER } },
    zIndex   = { default = 0,    type = "number", invalidates = { DIRTY.ORDER } },
    layer    = { default = DXUI.LAYER.BASE, invalidates = { DIRTY.ORDER } },
    -- style: theme style name or inline table; onSet applies the style
    -- through the widget contract (late-bound, see widget.lua).
    style    = { default = nil,  invalidates = { DIRTY.STYLE }, onSet = Node_styleSet },
    -- layout description
    layoutMode = { default = "absolute", invalidates = { DIRTY.LAYOUT },
        validate = function(v)
            return v == "absolute" or v == "relative" or v == "center"
                or v == "stretch" or v == "fill" or v == "flex"
        end },
    anchor   = { default = "tl", invalidates = { DIRTY.LAYOUT },
        validate = function(v)
            return v == "tl" or v == "tc" or v == "tr" or v == "ml" or v == "mc"
                or v == "mr" or v == "bl" or v == "bc" or v == "br"
        end },
    margin   = { default = nil, invalidates = { DIRTY.LAYOUT } },
    padding  = { default = nil, invalidates = { DIRTY.LAYOUT } },
    -- flex (row|column layout)
    flexDirection = { default = nil, invalidates = { DIRTY.LAYOUT },
        validate = function(v) return v == nil or v == "row" or v == "column" end },
    gap      = { default = 0, type = "number", min = 0, invalidates = { DIRTY.LAYOUT } },
    -- start|center|end|stretch
    align    = { default = nil, invalidates = { DIRTY.LAYOUT } },
    -- start|center|end|spaceBetween|spaceAround|spaceEvenly
    justify  = { default = nil, invalidates = { DIRTY.LAYOUT } },
    grow     = { default = 0, type = "number", min = 0, invalidates = { DIRTY.LAYOUT } },
    shrink   = { default = 0, type = "number", min = 0, invalidates = { DIRTY.LAYOUT } },
    wrap     = { default = false, invalidates = { DIRTY.LAYOUT } },
    -- human-readable dimensions (compiled in the cold path; numbers pass
    -- through, ui.percent()/auto()/fill() produce compiled forms).
    -- layoutWidth/layoutHeight override width/height during the place pass.
    -- transform compiles human forms (number, "50%", "auto", "fill") into
    -- the internal tagged form once (see dimension.lua) so the layout and
    -- flex passes always read {k=...} tables.
    layoutWidth  = { default = nil, invalidates = { DIRTY.LAYOUT }, transform = function(v)
        return DXUI.Dimension and DXUI.Dimension.compile(v) or v
    end },
    layoutHeight = { default = nil, invalidates = { DIRTY.LAYOUT }, transform = function(v)
        return DXUI.Dimension and DXUI.Dimension.compile(v) or v
    end },
    -- clipping / compositing
    clip     = { default = false, invalidates = { DIRTY.RENDER, DIRTY.INPUT } },
    -- "rt" (expensive path)
    clipMode = { default = nil,   invalidates = { DIRTY.RENDER } },
    autoSize = { default = false, invalidates = { DIRTY.LAYOUT } },
    interactive = { default = false, invalidates = { DIRTY.INPUT }, onSet = function(node)
        if DXUI.HitTest then DXUI.HitTest.invalidate(node) end
    end },
    focusable = { default = false, invalidates = { DIRTY.INPUT }, onSet = function(node)
        if DXUI.HitTest then DXUI.HitTest.invalidate(node) end
    end },
    -- drag & drop payload (any value): a non-nil dragData turns the node
    -- into a DRAG SOURCE; drop targets bind "drag-over"/"drop" handlers
    -- (see input/dispatcher.lua)
    dragData = { default = nil, invalidates = { DIRTY.INPUT }, onSet = function(node)
        if DXUI.HitTest then DXUI.HitTest.invalidate(node) end
    end },
    -- user data — never touched by the framework
    userData = { default = nil, invalidates = {} },
}

Node._spec = Node.properties

--- Parts declared by the class: { name = true, ... } (see part.lua).
Node.parts = nil

-- read-only computed fields (managed by the engine)
local READONLY = {
    children = true, context = true, destroyed = true,
    worldX = true, worldY = true, parts = true,
}

-- global id counter (debug/events)
local nextId = 1

-- ---------------------------------------------------------------------
-- Instance metatable (shared)
-- ---------------------------------------------------------------------
local mt = {
    --- Resolves property reads: pseudo-properties, value objects, parts, data, methods.
    __index = function(self, key)
        if key == "parent"    then return self._parent end
        if key == "children"  then return self._children end
        if key == "context"   then return self._context end
        if key == "destroyed" then return self._destroyed end
        if key == "worldX"    then return self._worldX end
        if key == "worldY"    then return self._worldY end
        if key == "parts"     then return self._parts end
        -- value objects: cached proxies, never allocated per access
        if key == "position" then return DXUI.PointProxy(self) end
        if key == "size"     then return DXUI.SizeProxy(self) end

        -- parts: named child slots
        local pk = self._partKeys
        if pk and pk[key] then
            -- nil when the part is not set
            return self._parts[key]
        end

        local spec = self._spec[key]
        if spec then
            if key == "color" then return DXUI.ColorProxy(self, key) end
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

    --- Routes property writes: reparent, part replacement, spec writes, raw fields.
    __newindex = function(self, key, value)
        -- parent is a writable pseudo-property: reparents
        if key == "parent" then
            return self:setParent(value)
        end
        if READONLY[key] then
            DXUI.Debug.warn("PROPERTY", "read-only property: " .. key)
            return
        end
        -- part replacement: node.header = customButton
        local pk = self._partKeys
        if pk and pk[key] then
            return self:setPart(key, value)
        end
        local spec = self._spec and self._spec[key]
        if spec then
            return self:_set(key, value)
        end
        -- arbitrary user fields are allowed (raw storage, no framework
        -- interference — but see userData for the documented slot).
        rawset(self, key, value)
    end,
}

-- ---------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------

--- Creates a node. self is the class (Node or a subclass).
function Node:new(props)
    return self:_instantiate(self, props)
end

--- Builds a node instance from a class, applying props and theme defaults.
function Node:_instantiate(cls, props)
    local self = setmetatable({}, mt)
    rawset(self, "_class", cls)
    rawset(self, "_spec", cls._spec)
    rawset(self, "_data", {})
    rawset(self, "_context", nil)
    rawset(self, "_parent", nil)
    rawset(self, "_children", {})
    rawset(self, "_destroyed", false)
    rawset(self, "_id", nextId)
    nextId = nextId + 1
    rawset(self, "_worldX", 0)
    rawset(self, "_worldY", 0)
    rawset(self, "_state", "normal")
    -- who last wrote each property
    rawset(self, "_owner", {})
    -- properties currently owned by the theme
    rawset(self, "_themeApplied", {})
    rawset(self, "_parts", {})
    rawset(self, "_partKeys", cls.parts or {})
    -- lazily created value-object cache
    rawset(self, "_values", nil)

    -- defaults (class chain already merged into _spec)
    for k, spec in pairs(cls._spec) do
        self._data[k] = spec.default
    end

    -- during construction the style onSet hook must not re-apply
    rawset(self, "_building", true)

    if props then
        for k, v in pairs(props) do
            if self._spec[k] then
                self[k] = v
            else
                -- reject keys that shadow methods loudly in dev mode
                local cls2 = self._class
                local isMethod = false
                while cls2 do
                    if rawget(cls2, k) ~= nil then isMethod = true break end
                    cls2 = cls2._super
                end
                if isMethod then
                    error("props key shadows a method: " .. tostring(k), 3)
                end
                -- arbitrary user field
                self[k] = v
            end
        end
    end

    -- theme defaults for properties not given in props (late-bound; Widget
    -- is loaded before any node is created at runtime).
    if DXUI.Widget and DXUI.Widget.applyThemeDefaults then
        DXUI.Widget.applyThemeDefaults(self)
    end

    -- hover/pressed follow the pointer for every widget: theme state
    -- blocks (states.hover etc.) activate through this wiring
    if cls._applyStyleState and DXUI.Builders and DXUI.Builders.wireStates then
        DXUI.Builders.wireStates(self)
    end

    rawset(self, "_building", nil)
    return self
end

-- ---------------------------------------------------------------------
-- Inheritance (plain prototype inheritance, Lua 5.1)
-- ---------------------------------------------------------------------

--- Creates a subclass with merged property specs and optional parts.
function Node:extend(name, properties)
    local Sub = {}
    Sub._name = name
    Sub._super = self
    Sub.properties = properties or {}
    Sub._spec = {}
    for k, v in pairs(self._spec) do Sub._spec[k] = v end
    for k, v in pairs(Sub.properties) do
        -- parts are slot names, not props
        if k ~= "parts" then Sub._spec[k] = v end
    end
    -- parts merge: subclass parts are added to the ancestor's
    Sub.parts = {}
    local anc = self
    while anc do
        if anc.parts then
            for k in pairs(anc.parts) do Sub.parts[k] = true end
        end
        anc = anc._super
    end
    local own = (properties and properties.parts) or nil
    if own then
        for k in pairs(own) do Sub.parts[k] = true end
    end
    setmetatable(Sub, { __index = self })
    return Sub
end

-- ---------------------------------------------------------------------
-- Mutation layer (single point of property changes)
-- ---------------------------------------------------------------------

--- Builds (and caches) the validator for a property spec.
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
            for i = 1, #checks do if not checks[i](v) then return false end end
            return true
        end
    end
    spec._validator = validator
    return validator
end

--- The single mutation entry. Owner: "user" (default) | "system" (engine:
-- layout/animation/lifecycle) | "theme" (theme application, set via the
-- _applyingTheme flag — no owner threading through every call).
function Node:_set(key, value, owner)
    if self._destroyed then
        DXUI.Debug.warn("LIFECYCLE", "set on destroyed node: " .. key)
        return self
    end
    local spec = self._spec[key]
    if not spec then
        DXUI.Debug.warn("PROPERTY", "set on unknown property: " .. key)
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
    local old = self._data[key]
    if old == value then return self end
    self._data[key] = value

    -- owner bookkeeping: theme writes via _applyingTheme; any non-theme
    -- write revokes theme ownership (the next style switch skips it).
    if self._applyingTheme then
        owner = "theme"
    elseif owner == nil then
        owner = "user"
    end
    if owner ~= "theme" and self._themeApplied then
        self._themeApplied[key] = nil
    end
    self._owner[key] = owner
    -- structured property trace (cheap no-op unless PROPERTY debug is on)
    DXUI.Debug.prop(self, key, old, value, owner, spec.invalidates)

    -- invalidate the value-object cache for this property
    if self._values and self._values[key] then
        rawset(self._values[key], "_packed", nil)
    end

    -- invalidation
    self:_invalidate(spec.invalidates)

    -- property listeners (user-level)
    local pl = self._propListeners and self._propListeners[key]
    if pl then
        for i = 1, #pl do pl[i](value, old, self) end
    end
    -- per-property hook
    if spec.onSet then spec.onSet(self, value) end
    -- lifecycle hook
    if key == "visible" and self._onVisibleChanged then
        self:_onVisibleChanged(value)
    end
    return self
end

--- Marks the node dirty for the given categories and propagates the
-- category -> instance frame flags (see CATEGORY_FLAGS above). A spec
-- without `invalidates` (pure behavior properties) passes nil.
function Node:_invalidate(categories)
    if not categories then return end
    local c = self._context
    if c then
        for i = 1, #categories do
            local flags = CATEGORY_FLAGS[categories[i]]
            if flags then
                if flags.layout then c.layoutDirty = true end
                if flags.render then c.renderDirty = true end
                if flags.order then c.orderDirty = true end
                if flags.interactive then c.interactiveDirty = true end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Method-style setters/getters (same mutation layer)
-- ---------------------------------------------------------------------

--- setPosition(10, 20) | setPosition({x,y}) | setPosition(pointProxy).
function Node:setPosition(x, y)
    if type(x) == "table" then
        self:_set("x", x.x or x[1])
        self:_set("y", x.y or x[2])
    else
        self:_set("x", x)
        self:_set("y", y)
    end
    return self
end

--- Returns the node's x, y position.
function Node:getPosition()
    return self.x, self.y
end

--- Sets width/height from a table or two numbers.
function Node:setSize(w, h)
    if type(w) == "table" then
        self:_set("width", w.width or w[1])
        self:_set("height", w.height or w[2])
    else
        self:_set("width", w)
        self:_set("height", h)
    end
    return self
end

--- Returns the node's width, height.
function Node:getSize()
    return self.width, self.height
end

--- Sets visibility (coerces to boolean).
function Node:setVisible(v) self:_set("visible", v and true or false) return self end
--- Returns whether the node is visible.
function Node:isVisible() return self.visible end
--- Shows the node.
function Node:show() return self:setVisible(true) end
--- Hides the node.
function Node:hide() return self:setVisible(false) end
--- Sets the enabled flag (coerces to boolean).
function Node:setEnabled(v) self:_set("enabled", v and true or false) return self end
--- Returns whether the node is enabled.
function Node:isEnabled() return self.enabled end
--- Sets opacity.
function Node:setOpacity(v) self:_set("opacity", v) return self end
--- Returns opacity.
function Node:getOpacity() return self.opacity end
--- Sets the z-order index.
function Node:setZIndex(z) self:_set("zIndex", z) return self end
--- Returns the z-order index.
function Node:getZIndex() return self.zIndex end
--- Sets the render layer.
function Node:setLayer(l) self:_set("layer", l) return self end
--- Returns the render layer.
function Node:getLayer() return self.layer end
--- Sets the layout mode.
function Node:setMode(mode) self:_set("layoutMode", mode) return self end
--- Sets the anchor.
function Node:setAnchor(a) self:_set("anchor", a) return self end
--- Sets margin (one value or per-side).
function Node:setMargin(l, t, r, b)
    if t == nil then t = l end
    if r == nil then r = l end
    if b == nil then b = l end
    self:_set("margin", { left = l, top = t, right = r, bottom = b })
    return self
end
--- Sets padding (one value or per-side).
function Node:setPadding(l, t, r, b)
    if t == nil then t = l end
    if r == nil then r = l end
    if b == nil then b = l end
    self:_set("padding", { left = l, top = t, right = r, bottom = b })
    return self
end

--- Visual state (normal/hover/pressed/focused/selected/disabled).
-- Driven by the dispatcher; triggers the style re-apply when the widget
-- class provides it. State changes may tween themed props when the
-- component declares a transition (see Widget:_applyStyleState).
function Node:setState(state)
    if self._state == state then return self end
    self._state = state
    if self._class and self._class._applyStyleState then
        self:_applyStyleState(true)
    end
    return self
end
--- Returns the current visual state.
function Node:getState() return self._state end

-- ---------------------------------------------------------------------
-- Property listeners
-- ---------------------------------------------------------------------

--- fn(value, oldValue, node) on every write through the mutation layer.
function Node:onProperty(key, fn)
    self._propListeners = self._propListeners or {}
    local list = self._propListeners[key]
    if not list then list = {}; self._propListeners[key] = list end
    list[#list + 1] = fn
    return self
end

--- Removes a property listener (or all for the key).
function Node:offProperty(key, fn)
    local list = self._propListeners and self._propListeners[key]
    if list then
        if fn == nil then
            -- key-only: clear all for the prop
            self._propListeners[key] = nil
        else
            for i = #list, 1, -1 do
                if list[i] == fn then table.remove(list, i) end
            end
        end
    end
    return self
end

-- ---------------------------------------------------------------------
-- Tree: parent / children / context propagation
-- ---------------------------------------------------------------------

--- Adds a child node.
function Node:addChild(child)
    child:setParent(self)
    return self
end

--- Removes the node from its parent (stays alive, mounted state lost).
function Node:removeFromParent()
    if self._parent then
        self:setParent(nil)
    end
    return self
end

--- Reparents the node, propagating context and invalidating both sides.
function Node:setParent(parent)
    if parent == self._parent then return self end
    if parent == self then error("cannot set a node as its own parent", 2) end
    if parent and parent._destroyed then
        error("cannot set parent to a destroyed node", 2)
    end
    -- cycle guard
    local p = parent
    while p do
        if p == self then error("cycle detected in parent chain", 2) end
        p = p._parent
    end

    if self._parent then
        self._parent:_removeChild(self)
    end
    local wasMounted = self._context ~= nil
    self._parent = parent
    if parent then
        parent._children[#parent._children + 1] = self
    end

    -- propagate the context to the subtree
    self:_setContextRecursive(parent and parent._context or nil)

    if wasMounted and self._context == nil and self._onDetached then
        self:_onDetached()
    end

    -- invalidation (content change of BOTH sides)
    self:_invalidate({ DIRTY.LAYOUT })
    if parent then
        parent:_invalidate({ DIRTY.CONTENT })
    end
    return self
end

--- Removes a child from the children list.
-- During a bulk destroy the parent sets `_destroying`, so per-child scans
-- are skipped (the array is cleared wholesale at the end of destroy) —
-- this keeps destroying a large tree O(n), not O(n^2).
function Node:_removeChild(child)
    if self._destroying then return end
    local children = self._children
    for i = 1, #children do
        if children[i] == child then
            table.remove(children, i)
            return
        end
    end
end

--- Propagates the context to the subtree and fires mount hooks.
function Node:_setContextRecursive(ctx)
    local entering = ctx ~= nil and self._context ~= ctx
    self._context = ctx
    if entering then
        DXUI.Debug.lifecycle("mount", self)
    end
    if ctx then
        if ctx.dispatcher then
            ctx.dispatcher:_updateNodeState(self)
        end
        -- a node mounted after a theme switch (or created detached) adopts
        -- the ACTIVE theme on mount; construction sets _building, and the
        -- build-time theme defaults already cover that path
        if entering and not self._building
            and self._class and self._class._applyStyleState then
            self:_applyStyleState()
        end
        -- a translation bound while DETACHED resolved against the engine
        -- locale; on mount the instance locale wins (re-apply)
        if entering and self.textKey ~= nil and self.applyTranslation then
            self:applyTranslation()
        end
    end
    local children = self._children
    for i = 1, #children do
        children[i]:_setContextRecursive(ctx)
    end
    -- children first: composite _onMount hooks may add children
    if entering and self._onMount then
        self:_onMount(ctx)
    end
end

--- zIndex = max(siblings)+1 (no-op if already on top).
function Node:bringToFront()
    local siblings = self._parent and self._parent._children or nil
    if not siblings then return self end
    local maxZ = -1
    for i = 1, #siblings do
        local s = siblings[i]
        if s ~= self and s.zIndex > maxZ then maxZ = s.zIndex end
    end
    if maxZ >= self.zIndex then
        self.zIndex = maxZ + 1
    end
    return self
end

--- Returns the node's depth in the tree.
function Node:getDepth()
    local d = 0
    local p = self._parent
    while p do d = d + 1; p = p._parent end
    return d
end

-- ---------------------------------------------------------------------
-- Parts
-- ---------------------------------------------------------------------

--- Attaches a part node to a named slot. Deterministic replacement:
-- detach old -> destroy it (owned) -> attach replacement.
-- A nil value removes the part (nullable slots).
function Node:setPart(name, partNode)
    if not (self._partKeys and self._partKeys[name]) then
        error("'" .. self._class._name .. "' has no part slot '" .. tostring(name) .. "'", 2)
    end
    local old = self._parts[name]
    if old == partNode then return self end
    if old and not old._destroyed then
        -- the part was owned by this widget
        old:destroy()
    end
    if partNode then
        partNode:setParent(self)
        self._parts[name] = partNode
    else
        self._parts[name] = nil
    end
    self:_invalidate({ DIRTY.CONTENT })
    return self
end

--- Returns the part node in a named slot.
function Node:getPart(name)
    return self._parts[name]
end

--- Removes a part (destroys it) and clears the slot.
function Node:removePart(name)
    local old = self._parts[name]
    if old and not old._destroyed then
        old:destroy()
    end
    self._parts[name] = nil
    self:_invalidate({ DIRTY.CONTENT })
    return self
end

-- ---------------------------------------------------------------------
-- Events (registry on the node; propagation via EventBus, late-bound)
-- ---------------------------------------------------------------------

--- Subscribes to an event. fn(node, ...). Returns self (chaining).
-- The single event registry lives in DXUI.Events (input/hit-test reads
-- it); propagation bubbles up through ancestors. Late-bound so core can
-- load before events.lua. Optional id tags registrations for
-- Events.removeForOwner (widget wiring uses ids like "dxui-states").
-- Attaching a handler can make a previously non-interactive node
-- clickable, so the hit-test list must be rebuilt when that happens
-- (interactiveDirty), not just the cached predicate invalidated.
function Node:on(eventName, fn, id)
    if DXUI.Events then
        local ctx = self._context
        local wasInteractive = DXUI.HitTest and DXUI.HitTest.isInteractive(self) or false
        DXUI.Events.add(self, eventName, fn, id)
        if DXUI.HitTest then DXUI.HitTest.invalidate(self) end
        -- a node that became interactive must re-enter the hit-test list
        -- on the next collect -- merely clearing the predicate cache is
        -- not enough (the list is rebuilt only on interactiveDirty)
        if ctx and DXUI.HitTest then
            local nowInteractive = DXUI.HitTest.isInteractive(self)
            if nowInteractive and not wasInteractive then
                ctx.interactiveDirty = true
            end
        end
    end
    return self
end

--- Removes a listener. With `fn` — all registrations of that fn for the
-- event; with `fn` nil — every handler for the event; with `id` — every
-- handler for the event tagged with that id (see Node:on).
function Node:off(eventName, fn, id)
    if DXUI.Events then
        if id ~= nil then
            DXUI.Events.removeId(self, eventName, id)
        else
            DXUI.Events.remove(self, eventName, fn)
        end
    end
    return self
end

--- Delivers an event starting at this node (bubbles up). Late-bound:
-- Events loads after node.lua but exists at runtime.
function Node:emit(eventName, ...)
    if DXUI.Events then
        return DXUI.Events.bc(self, eventName, ...)
    end
    return false
end

-- ---------------------------------------------------------------------
-- Animation (delegates to the instance's animation manager, late-bound)
-- ---------------------------------------------------------------------

--- Animates properties via the instance's animation manager.
-- Not mounted: the node has no animation manager yet, so the call is a
-- chained no-op -- warned in dev mode so an expected animation is not
-- silently dropped (add the node to a UI before animating it).
function Node:animate(props, duration, ease)
    if self._context and self._context.anim then
        return self._context.anim:animate(self, props, duration, ease)
    end
    if not self._context then
        DXUI.Debug.warn("ANIMATION", "animate: node is not mounted; no animation will run")
    end
    return self
end

--- Stops all animations on this node.
function Node:stopAnimations()
    if self._context and self._context.anim then
        self._context.anim:stop(self)
    end
    return self
end

--- Returns whether the node is currently animating.
function Node:isAnimating()
    if self._context and self._context.anim then
        return self._context.anim:isAnimating(self)
    end
    return false
end

-- ---------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------

--- Destroys the node and its subtree, releasing references.
function Node:destroy()
    if self._destroyed then return end
    self._destroyed = true
    DXUI.Debug.lifecycle("destroy", self)
    -- bulk teardown: children's destroy() calls _removeChild on us; skip
    -- those scans (the array is cleared below) so destroy is O(n), not O(n^2)
    self._destroying = true

    if self._onDestroy then
        -- context still alive here
        self:_onDestroy()
    end

    -- children first (parent owns children)
    local children = self._children
    for i = #children, 1, -1 do
        children[i]:destroy()
    end
    self._destroying = nil

    if self._parent then
        self._parent:_removeChild(self)
        self._parent = nil
    end

    if self._context then
        self._context:_onNodeDestroyed(self)
    end

    -- symmetric teardown: detach hooks (overlay unregister, etc.). A node
    -- already detached via reparent has _onDetached already run (idempotent).
    if self._onDetached then
        self:_onDetached()
    end

    -- clear references (frees node-owned state; subscriptions dropped —
    -- no events from a dead node)
    if DXUI.Events then DXUI.Events.clear(self) end
    self._context = nil
    self._children = {}
    self._data = {}
    self._propListeners = nil
    self._parts = {}
    self._values = nil
end

--- Returns whether the node is destroyed.
function Node:isDestroyed() return self._destroyed end
--- Returns whether the node is alive (not destroyed).
function Node:isAlive() return not self._destroyed end

-- ---------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------
DXUI.Node = Node