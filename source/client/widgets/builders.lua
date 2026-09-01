--[[
    builders.lua — DXUI V3

    Widget registry + shared construction helpers (loads after the widget
    classes; ui.lua factories read DXUI.Widgets).

        Builders.register("Button", ButtonClass)   -- canonical form
        Builders.wireStates(node)                  -- hover/press -> style
        Builders.ensureParts(node, props, partDefs)-- auto-create default parts

    wireStates: the dispatcher emits hover-start/hover-end/press/release;
    the helper translates them into node:setState("hover"/"pressed") so the
    widget's style follows its interaction state (theme states). Disabled
    nodes auto-map to the "disabled" state inside _applyStyleState.
]]

DXUI = DXUI or {}

local Builders = {}

DXUI.Widgets = DXUI.Widgets or {}

function Builders.register(name, cls)
    DXUI.Widgets[name] = cls
    DXUI.Widgets[name:lower()] = cls
    return cls
end

-- ---------------------------------------------------------------------
-- Interaction -> style-state wiring
-- ---------------------------------------------------------------------

local WIRE_ID = "dxui-states"

--- Attaches state-transition handlers once (per node).
function Builders.wireStates(node)
    if node._stateWired then return node end
    node._stateWired = true
    if not node.on then return node end
    node:on("hover-start", function(n)
        if n.enabled then n:setState("hover") end
    end, WIRE_ID)
    node:on("hover-end", function(n)
        if n:getState() == "hover" then n:setState("normal") end
    end, WIRE_ID)
    node:on("press", function(n)
        if n.enabled then n:setState("pressed") end
    end, WIRE_ID)
    node:on("release", function(n)
        if n.enabled then n:setState(n._hover and "hover" or "normal") end
    end, WIRE_ID)
    return node
end

-- ---------------------------------------------------------------------
-- Parts: auto-create default children for declarative props
-- ---------------------------------------------------------------------

--- Creates the default part children (Label/container) for widgets that
-- ship parts, if the consumer did not set them already.
-- partDefs: { name = { cls = LabelClass, props = {...} } }
function Builders.ensureParts(node, props, partDefs)
    for name, def in pairs(partDefs) do
        if not node:getPart(name) then
            local part = def.cls:new(def.props or {})
            node:setPart(name, part)
        end
    end
end

--- Moves matching props into their part (declarative part props):
-- props.onPartName = {...} -> part props (window.header = { title = "X" })
function Builders.routePartProps(node, props, partNames)
    for _, name in ipairs(partNames) do
        local sub = props["on" .. name]
        if sub then
            local part = node:getPart(name)
            if part then
                for k, v in pairs(sub) do
                    part[k] = v
                end
            end
        end
    end
end

DXUI.Builders = Builders