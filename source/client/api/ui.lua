--[[
    ui.lua — DXUI V3

    Public UI handle: the ONLY object consumers see (never the context).
    `exports.dxui:getUI(...)` returns this; every method is consumer-facing.

    Factories (widget classes are late-bound from the widgets/ tree via
    DXUI.Widgets[name] — ui.lua loads before widgets):
        ui:panel(props) / label / button / image / window / checkbox / ...
        ui:widget(name, props)            -- generic
        ui:color(r,g,b[,a])               -- packed 0xAARRGGBB int / proxy
        ui:percent(n) / ui:auto() / ui:fill()
        ui:texture(path) / font(name,size) / shader(code)
        ui:setTextKey(key, target, textProp)
        ui:addLocale(lang, dict) / setLocale(lang)

    Lifecycle/frame:
        ui:setViewport(w, h)              -- once per resource, on resize
        ui:tick()                         -- once per onClientRender
        ui:mouseMove/Down/Up(...), scroll, key
        ui:destroy()
]]

DXUI = DXUI or {}

-- UI doubles as the class table and the instance metatable; per-widget
-- factories + Runtime methods resolve through the metatable below.
local UI = {}
UI.__index = UI

--- Creates a UI instance and returns the public handle.
-- opts: { name, design = {width,height}, settings = {...} }
function UI:new(opts)
    local inst = DXUI.Runtime.create(opts or {})
    return setmetatable(inst, UI)
end

-- ---------------------------------------------------------------------
-- Widget factories (late-bound to widgets.lua registry)
-- ---------------------------------------------------------------------

--- Returns a factory that builds a widget of the given class name.
local function widgetFactory(name)
    return function(self, props)
        local cls = DXUI.Widgets and DXUI.Widgets[name]
        if not cls then
            if DXUI._warn then DXUI._warn("ui:" .. name .. ": widget not registered yet") end
            return nil
        end
        local inst = cls:new(props or {})
        if cls._build then cls._build(inst, props or {}) end
        return inst
    end
end

--- Builds a widget by class name (generic factory).
function UI:widget(name, props)
    local cls = DXUI.Widgets and DXUI.Widgets[name]
    if not cls then
        if DXUI._warn then DXUI._warn("ui:widget(" .. tostring(name) .. "): not registered") end
        return nil
    end
    local inst = cls:new(props or {})
    if cls._build then cls._build(inst, props or {}) end
    return inst
end

-- Per-widget factories (ui:panel(props), ui:window(props), ...) are
-- SYNTHESIZED from the widget registry: ui.lua loads before widgets/, so
-- the names are not known yet — every Builders.register'ed class (both
-- spellings) gains a factory automatically, and anything else falls
-- through to the Runtime methods.
setmetatable(UI, {
    __index = function(_, key)
        if type(key) == "string" and DXUI.Widgets and rawget(DXUI.Widgets, key) then
            local factory = widgetFactory(key)
            UI[key] = factory -- cache: later lookups hit the table
            return factory
        end
        return DXUI.Runtime[key]
    end,
})

-- ---------------------------------------------------------------------
-- Value factories
-- ---------------------------------------------------------------------

--- Packs an RGBA color into a 0xAARRGGBB integer (or proxy).
function UI:color(r, g, b, a)
    if DXUI.color then return DXUI.color(r, g, b, a) end
    return 0xFF000000
end

--- Returns a percent sizing value.
function UI:percent(n) return DXUI.percent and DXUI.percent(n) or n end
--- Returns the auto sizing value.
function UI:auto() return DXUI.auto and DXUI.auto() or nil end
--- Returns the fill sizing value.
function UI:fill() return DXUI.fill and DXUI.fill() or nil end

-- ---------------------------------------------------------------------
-- Resources
-- ---------------------------------------------------------------------

--- Loads (or returns the cached) texture for a path.
function UI:texture(path) return DXUI.texture and DXUI.texture(path) end
--- Loads (or returns the cached) font for a file path and size.
function UI:font(name, size) return DXUI.font and DXUI.font(name, size) end
--- Compiles (or returns the cached) shader for source code.
function UI:shader(code) return DXUI.shader and DXUI.shader(code) end

--- Applies a partial engine-settings table (see source/settings.lua).
function UI:applySettings(t)
    if DXUI.applySettings then DXUI.applySettings(t) end
    return self
end

-- ---------------------------------------------------------------------
-- Themes (engine-wide registry; see source/client/style/)
-- ---------------------------------------------------------------------

--- Defines a custom theme in the calling resource (merged over its
--- `extends` parent when given). Theme tables never touch engine state
--- until activated.
function UI:defineTheme(name, tbl)
    if DXUI.Theme then DXUI.Theme.define(name, tbl) end
    return self
end

--- Activates a theme: a registered name ("dark", "green-full", a custom
--- one) or an INLINE table (registered under an auto name, then
--- activated). Re-styles every mounted widget live.
function UI:setTheme(nameOrTable)
    if DXUI.Theme then DXUI.Theme.setTheme(nameOrTable) end
    return self
end

--- Returns the active theme's name.
function UI:getTheme()
    return DXUI.Theme and DXUI.Theme.getCurrent() or nil
end

-- ---------------------------------------------------------------------
-- Translation shortcuts
-- ---------------------------------------------------------------------

--- Binds a translation key to a target's text property.
function UI:setTextKey(key, target, textProp)
    if target and target.setTextKey then
        target:setTextKey(key, textProp)
    end
    return self
end

--- Registers a locale dictionary (engine-wide).
function UI:addLocale(lang, dict)
    if DXUI.Translate then
        DXUI.Translate.addLocale(lang, dict)
    elseif DXUI.addLocale then
        DXUI.addLocale(lang, dict)
    end
    return self
end

--- Sets THIS instance's locale (nil = follow the engine locale) and
--- re-translates this instance's bindings. Emits "localeChange" on the
--- UI root. The engine-wide switch is DXUI.setLocale.
function UI:setLocale(lang)
    self._locale = lang
    if DXUI.Translate then DXUI.Translate.applyFor(self) end
    if self.root and self.root.emit then
        self.root:emit("localeChange", self:getLocale())
    end
    return self
end

--- Returns this instance's locale (the engine locale when unset).
function UI:getLocale()
    return self._locale
        or (DXUI.Translate and DXUI.Translate.locale)
        or "en"
end

--- Translates a key in THIS instance's locale, substituting %1..%N.
function UI:tr(key, ...)
    if DXUI.Translate then
        return DXUI.Translate.trFor(self:getLocale(), key, ...)
    end
    return key
end

--- Subscribes to a UI-level event on the root (e.g. "localeChange").
function UI:on(eventName, fn)
    return self.root:on(eventName, fn)
end

--- Emits a UI-level event on the root.
function UI:emit(eventName, ...)
    return self.root:emit(eventName, ...)
end

-- ---------------------------------------------------------------------
-- Tree shortcuts
-- ---------------------------------------------------------------------

--- Places a node directly on the root (screen-level layer ordering via
-- zIndex on the node).
function UI:add(node)
    if node and node.setParent then node:setParent(self.root) end
    return node
end

--- Removes a node from its parent.
function UI:remove(node)
    if node and node.removeFromParent then node:removeFromParent() end
    return self
end

DXUI.UI = UI