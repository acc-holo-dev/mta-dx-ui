--[[
    export.lua — DXUI

    Cross-resource entry point. Exported functions are declared in meta.xml
    (<export>). Other resources use DXUI via:

        local ui = exports.dxui:getUI()
        local win = ui:window({ title = "X", w = 300, h = 200 })
        win:setTitle("Y")

    getUI() returns a default context, cached per calling resource and
    destroyed when that resource stops (no leaked nodes).
]]

-- Per-resource default context cache (keyed by resource element).
local contextsByResource = {}

--- Returns the default UI context for the calling resource.
-- Lazily created and cached; destroyed on resource stop.
function getUI()
    local res = sourceResource or resource
    local ctx = contextsByResource[res]
    if not ctx then
        ctx = DXUI.createContext()
        contextsByResource[res] = ctx
    end
    return ctx
end

-- Destroy a resource's context when it stops (cleanup, no leaks).
addEventHandler("onClientResourceStop", root, function(stoppedRes)
    local ctx = contextsByResource[stoppedRes]
    if ctx then
        ctx:destroy()
        contextsByResource[stoppedRes] = nil
    end
end)
