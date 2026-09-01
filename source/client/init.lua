--[[
    init.lua — DXUI V3

    MTA bootstrap (loads LAST in meta.xml, when every module is ready):
      1. wires the DX backend (backend_mta) + text measurement hook;
      2. creates the resource's UI instance (lazy, via getUI);
      3. registers the MTA event glue (render loop, resize, input) that
         drives the pure-Lua runtime.

    All MTA-specific event handling lives HERE — core/ and api/ stay pure.
    Idempotent: safe if meta.xml's load order is ever changed.
]]

DXUI = DXUI or {}

-- 1. backend wiring ------------------------------------------------------

if DXUI.backendInitMTA then DXUI.backendInitMTA() end
DXUI.Runtime.backend = DXUI.BackendMTA

-- 2. instance bootstrap ------------------------------------------------

local frameJobs = {} -- ui handles to tick each render
local frameCount = 0

--- Creates (or returns) the resource's UI and schedules it into the frame
-- loop. opts: { name, design, settings }.
-- Call ONCE at resource start from your own code, or rely on dxui:getUI()
-- lazily. The instance is ticked automatically while it exists.
function DXUI.bootstrap(opts)
    opts = opts or {}
    local name = opts.name or "main"
    local ui = DXUI.getUI(name, opts)

    for i = 1, frameCount do
        if frameJobs[i] == ui then return ui end -- already scheduled
    end
    frameCount = frameCount + 1
    frameJobs[frameCount] = ui

    -- render loop
    addEventHandler("onClientRender", resourceRoot, function()
        if #frameJobs == 0 then return end
        for i = 1, #frameJobs do
            frameJobs[i]:tick()
        end
    end)

    -- resize: MTA has no direct resize event; size is read on demand
    -- (the first tick inside onClientRender refresh below is cheap:
    -- setViewport only recomputes on actual size change)
    local lastW, lastH = -1, -1
    local function ensureViewport()
        local w, h = guiGetScreenSize()
        if w ~= lastW or h ~= lastH then
            lastW, lastH = w, h
            for i = 1, #frameJobs do
                frameJobs[i]:setViewport(w, h)
            end
        end
    end
    addEventHandler("onClientRender", resourceRoot, function()
        ensureViewport()
    end, false, 1)

    -- input glue (screen coords -> design coords inside the runtime)
    addEventHandler("onClientMouseMove", resourceRoot, function(rx, ry, absX, absY)
        for i = 1, #frameJobs do
            frameJobs[i]:mouseMove(absX, absY)
        end
    end)
    addEventHandler("onClientClick", resourceRoot, function(button, state, absX, absY)
        for i = 1, #frameJobs do
            if state == "down" then
                frameJobs[i]:mouseDown(button, absX, absY)
            else
                frameJobs[i]:mouseUp(button, absX, absY)
            end
        end
    end)
    addEventHandler("onClientScrollWheel", resourceRoot, function(wheel, absX, absY)
        for i = 1, #frameJobs do
            frameJobs[i]:scroll(wheel, absX, absY)
        end
    end)
    addEventHandler("onClientKey", resourceRoot, function(keyName, pressed)
        for i = 1, #frameJobs do
            frameJobs[i]:key(keyName, pressed)
        end
    end)

    return ui
end

-- 3. resource stop cleanup ---------------------------------------------

addEventHandler("onClientResourceStop", resourceRoot, function()
    for i = 1, #frameJobs do
        frameJobs[i]:destroy()
    end
    frameJobs = {}
    frameCount = 0
    if DXUI.releaseResources then DXUI.releaseResources() end
end)