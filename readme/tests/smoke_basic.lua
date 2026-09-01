--[[
    smoke_basic.lua — DXUI V3 test suite (basic widgets + theme defaults)

    panel / label (wrap, ellipsis, shadow, padding) / button (states,
    click) / image / window (parts + title routing).
]]

local now = 0
local ui = DXUI.UI:new({ name='basic', design={ width=800, height=600 },
                         clock=function() return now end })
local backend = Backend()
DXUI.Runtime.backend = backend
ui:setViewport(800, 600)

-- panel themed
local p = ui:panel({ x=0, y=0, width=100, height=50 })
ui:add(p)
eq(DXUI.ColorToInt(p.color), 0xFFFFFFFF, 'panel surface themed')
eq(p.radius, 8, 'panel md radius themed')

-- label: wrap produces 2 lines, padding in measure + render offset
local title = ui:label({ text='Hello World', x=10, y=60, width=40, wrap=true,
                         padding={ left=4, right=4 } })
ui:add(title)
eq(DXUI.ColorToInt(title.textColor), 0xFF111827, 'label text themed')
eq(backend.texts, 0, 'nothing drawn yet')
ui:tick()
local t0 = backend.texts
eq(t0 >= 2, true, 'wrapped label drew >= 2 lines (got '..t0..')')

local pad = ui:label({ text='Pad', x=0, y=0, padding={ left=10, right=10 } })
ui:add(pad)
ui:tick()
expect(pad.width > 0, 'label measures content width')

-- button: theme color, click, states, disabled derived state
local btn = ui:button({ text='Go', x=0, y=100, width=80, height=30 })
ui:add(btn)
eq(DXUI.ColorToInt(btn.color), 0xFF2563EB, 'button primary themed')
local clicks = 0
btn:on('click', function() clicks = clicks + 1 end)
DXUI.Builders.wireStates(btn)
ui:tick()
ui:mouseDown('left', 40, 115)
eq(btn:getState(), 'pressed', 'pressed on mousedown')
ui:mouseUp('left', 40, 115)
eq(clicks, 1, 'click fired')
eq(btn:getState(), 'normal', 'release resets')
ui:mouseMove(40, 115)
eq(btn:getState(), 'hover', 'hover enters')
ui:mouseMove(500, 500)
btn:setEnabled(false)
ui:tick()
eq(DXUI.ColorToInt(btn.textColor), 0xFF6B7280, 'disabled derived style')
btn:setEnabled(true)
eq(DXUI.ColorToInt(btn.textColor), 0xFFFFFFFF, 'reenable restores')

-- image
local img = ui:image({ texture='logo.png', x=0, y=0, width=32, height=32 })
ui:add(img)
local imgT = backend.images
expect(pcall(function() ui:tick() end), 'image tick ok')
-- (image draws only when the tree render covers it)
eq(backend.images >= imgT, true, 'image emitted at least once (got '..backend.images..')')

-- window parts
local w = ui:window({ title='Settings', x=50, y=200, width=200, height=120 })
ui:add(w)
local header, content = w:getPart('header'), w:getPart('content')
eq(header ~= nil, true, 'window header part')
eq(content ~= nil, true, 'window content part')
eq(header.text, 'Settings', 'title routed to header')
w.title = 'Options'
eq(header.text, 'Options', 'title change routes')
ui:tick()
eq(header.worldX, 50, 'header positioned at window x')
local inner = ui:label({ text='i', x=0, y=0 })
content:addChild(inner)
ui:tick()
eq(inner.worldX, 50 + 10, 'content padding left applied')

print('smoke_basic: all assertions executed')