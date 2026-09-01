--[[
    exports.lua — DXUI V3

    Cross-resource integration point. The ONLY documented external API is:

        local ui = exports.dxui:getUI()
        ui:panel{...} / ui:label{...} ... ui:tick() ...

    getUI() returns the UI handle of THIS resource (one per resource — the
    resource's own widgets are managed by its own instance). It is cheap and
    safe to call from anywhere EXCEPT inside onClientRender (create your
    instance once at startup, not per frame).
]]

DXUI = DXUI or {}

--- Returns the UI handle for `name` (default: "main").
-- A handle is created lazily on first request and reused (per-resource
-- single instance). opts apply ONLY on creation.
function DXUI.getUI(name, opts)
    local registry = DXUI._uis
    if not registry then
        registry = {}
        DXUI._uis = registry
    end
    local key = name or "main"
    local ui = registry[key]
    if not ui then
        local o = { name = key }
        if opts then
            for k, v in pairs(opts) do o[k] = v end
        end
        ui = DXUI.UI:new(o)
        registry[key] = ui
    end
    return ui
end

DXUI.exports = {
    getUI = function(...)
        return DXUI.getUI(...)
    end,
}