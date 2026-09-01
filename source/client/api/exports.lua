---Cross-resource integration point. The documented external API is:
---
---    local ui = exports.dxui:getUI()
---
---getUI() returns the UI handle owned by the CALLING resource: each
---consumer resource owns its own tree, and its nodes are released when
---that resource stops. It is cheap and safe to call from anywhere EXCEPT
---inside onClientRender (create your instance once at startup, not per
---frame).
---
---MTA sets `sourceResource` to the calling resource inside an exported
---function; instances are keyed by that resource's root element so each
---consumer owns its own nodes (see init.lua for the stop cleanup).

DXUI = DXUI or {}

--- Returns the UI handle for `name` (default: "main"), owned by `owner`.
-- A handle is created lazily on first request and reused; `opts` apply only
-- on creation. `owner` defaults to a shared bucket (the dxui resource
-- itself); the exported `getUI` passes the calling resource's root element.
function DXUI.getUI(name, opts, owner)
    local key = name or "main"
    local ownerKey = owner or "default"
    local byOwner = DXUI._uiByOwner
    if not byOwner then
        byOwner = {}
        DXUI._uiByOwner = byOwner
    end
    local bucket = byOwner[ownerKey]
    if not bucket then
        bucket = {}
        byOwner[ownerKey] = bucket
    end
    local ui = bucket[key]
    if not ui then
        local o = { name = key }
        if opts then
            for k, v in pairs(opts) do o[k] = v end
        end
        ui = DXUI.UI:new(o)
        bucket[key] = ui
        local list = DXUI._uis
        if not list then
            list = {}
            DXUI._uis = list
        end
        list[#list + 1] = ui
    end
    return ui
end

--- Destroys every UI instance owned by `ownerKey` and drops them from the
-- flat tick list. Called when a consumer resource stops (see init.lua).
function DXUI.releaseResource(ownerKey)
    local byOwner = DXUI._uiByOwner
    if not byOwner then return end
    local bucket = byOwner[ownerKey]
    if not bucket then return end
    local uis = DXUI._uis
    for _, ui in pairs(bucket) do
        if ui.destroy then ui:destroy() end
        if uis then
            for i = #uis, 1, -1 do
                if uis[i] == ui then table.remove(uis, i) end
            end
        end
    end
    byOwner[ownerKey] = nil
end

--- Cross-resource entry point (exported via meta.xml).
-- MTA sets `sourceResource` to the calling resource inside an exported
-- function; instances are keyed by that resource's root element.
function getUI(name, opts)
    local owner = nil
    if sourceResource ~= nil and getResourceRootElement ~= nil then
        owner = getResourceRootElement(sourceResource)
    end
    return DXUI.getUI(name, opts, owner)
end
