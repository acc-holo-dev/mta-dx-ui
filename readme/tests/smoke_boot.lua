--[[
    smoke_boot.lua — DXUI V3 test suite (MTA boot integration)

    Runs with init.lua loaded UNDER THE FAKED MTA environment (run.py
    prelude) — verifies DXUI.bootstrap, the onClientRender frame loop,
    viewport from guiGetScreenSize, input glue routing (screen->design),
    diagnostics zero-work contract, and resource-stop cleanup.
]]

local mta = __MTA

-- the boot UI must use the OBSERVABLE test backend (init.lua assigns the
-- real MTA backend by default; tests override before bootstrap)
DXUI.Runtime.backend = Backend()

local ui = DXUI.bootstrap({ name='main', design={ width=800, height=600 } })
eq(ui ~= nil, true, 'bootstrap returns UI')
eq(ui.name, 'main', 'bootstrap name')
eq(ui.layoutW, 800, 'design width')
eq(DXUI.getUI('main') == ui, true, 'getUI singleton')

local function renderFrames(n)
    local hs = mta.handlers['onClientRender'] or {}
    for _ = 1, n do
        mta.now = mta.now + 16
        for i = 1, #hs do hs[i]() end
    end
end

renderFrames(1)
eq(ui.stats.frames >= 1, true, 'frame loop ticks')
eq(ui.screenW, 1920, 'viewport from guiGetScreenSize')

local btn = ui:button({ text='Go', x=100, y=100, width=80, height=30 })
ui:add(btn)
local clicks = 0
btn:on('click', function() clicks = clicks + 1 end)
local lbl = ui:label({ text='Hello', x=10, y=10, width=60 })
ui:add(lbl)
renderFrames(1)
eq(ui.stats.items >= 3, true, 'render list populated (got '..ui.stats.items..')')

-- screen (240,180) maps to design (100,100) under 1920x1080 -> 800x600
local clickHandlers = mta.handlers['onClientClick'] or {}
clickHandlers[1]('left', 'down', 240, 180)
clickHandlers[1]('left', 'up', 240, 180)
eq(clicks, 1, 'click routed via onClientClick glue')
renderFrames(1)

-- diagnostics: zero-work on idle frames
DXUI.Diagnostics.enableZeroWork(ui, true)
renderFrames(3)
local rBefore = ui.stats.rebuilds
renderFrames(3)
eq(ui.stats.rebuilds == rBefore, true, 'idle frames zero rebuilds')
expect(DXUI.Diagnostics.idleRatio(ui) > 0.5, 'idle ratio healthy')
eq(type(DXUI.Diagnostics.describe(ui)) == 'string', true, 'describe returns string')

-- one mutation -> exactly one rebuild
local b2 = ui:button({ text='Two', x=400, y=10, width=60, height=24 })
ui:add(b2)
local r2 = ui.stats.rebuilds
renderFrames(1)
eq(ui.stats.rebuilds == r2 + 1, true, 'single mutation -> single rebuild')

-- resource stop cleanup
local released = false
local base = DXUI.releaseResources
DXUI.releaseResources = function(...) released = true; return base(...) end
local stopHandlers = mta.handlers['onClientResourceStop'] or {}
for i = 1, #stopHandlers do stopHandlers[i]() end
eq(ui._destroyed, true, 'resource stop destroys UI')
eq(released, true, 'resource stop releases resources')

print('smoke_boot: all assertions executed')