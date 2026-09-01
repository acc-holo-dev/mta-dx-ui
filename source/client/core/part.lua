--[[
    part.lua — DXUI V3

    Part: a named child slot of a composite widget.

    A part is a REAL Node/Widget with its own visual state, layout, input
    and theme section. Slots are declared per widget class:

        local Window = DXUI.Widget:extend("Window", {
            ...
        }, { parts = { header = true, content = true } })  -- via properties.parts
        -- or: Window.parts = { header = true, content = true }

    Runtime:
        node:setPart("header", headerNode)   -- replace (destroys the old)
        node:getPart("header")
        node:removePart("header")            -- nullable slots
        node.header = customButton           -- property-style replacement
        node.header.icon = ui:texture(...)   -- part is a real node

    Theme role: a part's style is resolved under
    `components.<Class>.parts.<roleName>` — the part itself is a normal
    widget whose class style may be overridden by the role section.
]]

DXUI = DXUI or {}

local Part = {}

--- Declares part slots on a widget class (idempotent; merged on extend).
function Part.declare(class, names)
    class.parts = class.parts or {}
    for _, name in ipairs(names) do
        class.parts[name] = true
    end
    return class
end

--- Iterates a node's currently attached parts: fn(roleName, partNode).
function Part.each(node, fn)
    for name, partNode in pairs(node._parts) do
        if partNode and not partNode._destroyed then
            fn(name, partNode)
        end
    end
end

DXUI.Part = Part