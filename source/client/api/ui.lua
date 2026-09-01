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

local UI = setmetatable({}, { __index = DXUI.Runtime })
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

for _name in pairs({ panel=1, label=1, button=1, image=1, window=1, checkbox=1,
    radiobutton=1, progressbar=1, slider=1, scrollpanel=1, edit=1, combobox=1,
    tabpanel=1, gridlist=1, popup=1, contextmenu=1, modal=1, tooltip=1 }) do
    UI[_name] = widgetFactory(_name)
end

-- ---------------------------------------------------------------------
-- Value factories
-- ---------------------------------------------------------------------

function UI:color(r, g, b, a)
    if DXUI.color then return DXUI.color(r, g, b, a) end
    return 0xFF000000
end

function UI:percent(n) return DXUI.percent and DXUI.percent(n) or n end
function UI:auto() return DXUI.auto and DXUI.auto() or nil end
function UI:fill() return DXUI.fill and DXUI.fill() or nil end

-- ---------------------------------------------------------------------
-- Resources
-- ---------------------------------------------------------------------

function UI:texture(path) return DXUI.texture and DXUI.texture(path) end
function UI:font(name, size) return DXUI.font and DXUI.font(name, size) end
function UI:shader(code) return DXUI.shader and DXUI.shader(code) end

-- ---------------------------------------------------------------------
-- Translation shortcuts
-- ---------------------------------------------------------------------

function UI:setTextKey(key, target, textProp)
    if target and target.setTextKey then
        target:setTextKey(key, textProp)
    end
    return self
end

function UI:addLocale(lang, dict)
    if DXUI.addLocale then DXUI.addLocale(lang, dict) end
    return self
end

function UI:setLocale(lang)
    if DXUI.setLocale then DXUI.setLocale(lang) end
    return self
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

function UI:remove(node)
    if node and node.removeFromParent then node:removeFromParent() end
    return self
end

DXUI.UI = UI