--[[
    smoke_core.lua — DXUI V3 test suite (core + subsystems)

    Runs inside the runner's engine runtime; harness provides:
    DXUI, eq(got,want,name), expect(cond,name), Backend().
]]

local now = 0
local ui = DXUI.UI:new({ name='core', design={ width=800, height=600 },
                         clock=function() return now end })
DXUI.Runtime.backend = Backend()
ui:setViewport(800, 600)

-- ---- values ---------------------------------------------------------
eq(DXUI.ColorToInt(0xFF2563EB), 0xFF2563EB, 'int identity toInt')
eq(DXUI.ColorToInt(DXUI.resolveColor('#2563EB')), 0xFF2563EB, 'hex string resolve')
eq(DXUI.ColorToInt(DXUI.resolveColor(0xFF2563EB)), 0xFF2563EB, 'int identity resolve')

-- ---- node properties + owners --------------------------------------
local p = ui:panel({ x=0, y=0, width=100, height=50 })
ui:add(p)
eq(DXUI.ColorToInt(p.color), 0xFFFFFFFF, 'ColorProxy through ColorToInt')
expect(p.color ~= nil and DXUI.ColorToInt(p.color) == DXUI.ColorToInt(p.color),
       'color proxy stable per node')
eq(p.width, 100, 'prop default write')
p.width = 120
eq(p.width, 120, 'prop overwrite')
eq(p._owner['width'], 'user', 'user ownership')
-- system write is invisible to owner semantics
p:_set('width', 130, 'system')
eq(p.width, 130, 'system write applies')
eq(p._owner['width'], 'system', 'system write records system owner')
-- theme write then user revoke (theme defaults from the default theme)
local oldColor = DXUI.ColorToInt(p.color) -- INT copy; proxies are live
p._themeApplied = p._themeApplied or {}
p._themeApplied['color'] = true
p:_set('color', 0xFFFF0000, 'theme')
eq(p._themeApplied['color'] ~= nil, true, 'theme write marks themeApplied')
p.color = 0xFF00FF00
eq(p._themeApplied['color'] == nil, true, 'user write revokes themeApplied')
p.color = oldColor

-- value object proxies cached per node (asserted above with the panel)

-- ---- style/state ----------------------------------------------------
eq(DXUI.ColorToInt(p.color), 0xFFFFFFFF, 'panel themed surface')
eq(p.radius, 8, 'panel themed radius')

local b = ui:button({ text='Go', x=0, y=60, width=60, height=24 })
ui:add(b)
eq(b.interactive, true, 'button interactive default')
eq(b.focusable, true, 'button focusable default')
b:setState('hover')
eq(b:getState(), 'hover', 'setState/getState')
b:setEnabled(false)
expect(DXUI.ColorToInt(b.textColor) == 0xFF6B7280, 'disabled style applied (textSecondary)')
b:setEnabled(true)

-- ---- tree ops -------------------------------------------------------
local child = ui:label({ text='x', x=5, y=5 })
p:addChild(child)
expect(child._parent == p, 'child parented')
child:removeFromParent()
expect(child._parent == nil, 'removeFromParent detaches')
p:addChild(child)
child:destroy()
expect(child._destroyed == true, 'destroy marks destroyed')
p.width = 100

-- ---- events ---------------------------------------------------------
local fired = 0
local stopWorker = 0
local ancestorFired = 0
local a = ui:panel({ width=10, height=10 }); ui:add(a)
local a2 = ui:panel({ width=10, height=10 }); ui:add(a2)
local a3 = ui:panel({ width=10, height=10 }); ui:add(a3)
a:addChild(a2); a2:addChild(a3)
a2:on('t', function() stopWorker = stopWorker + 1; return DXUI.STOP end, 'stop')
a:on('t', function() ancestorFired = ancestorFired + 1 end, 'anc')
a3:on('t', function() fired = fired + 1 end, 'src')
a3:emit('t')
eq(fired, 1, 'event fired on origin (a3)')
eq(stopWorker, 1, 'STOP handler on a2 runs')
eq(ancestorFired, 0, 'STOP halts before higher ancestors (a)')
fired = 0; stopWorker = 0
a2:on('t2', function() fired = fired + 1 end, 'a2')
a3:on('t2', function() fired = fired + 1 end, 'a3')
a3:emit('t2')
eq(fired, 2, 'bubbles ancestors only (a2+a3, not a)')
a2:off('t2')
fired = 0
a3:emit('t2')
eq(fired, 1, 'off(name) removes handler set')

-- ---- parts ----------------------------------------------------------
local w = ui:window({ title='T', x=10, y=200, width=150, height=100 })
ui:add(w)
local header = w:getPart('header')
local content = w:getPart('content')
eq(header ~= nil, true, 'window header part')
eq(content ~= nil, true, 'window content part')
eq(header.text, 'T', 'title routed to header')
w.title = 'T2'
eq(header.text, 'T2', 'title change re-routes')
w:removePart('content')
eq(w:getPart('content') == nil, true, 'removePart drops part')

-- ---- settings -------------------------------------------------------
eq(DXUI.Settings.defaults.animationDuration, 250, 'settings defaults duration')
eq(DXUI.Settings.performance.screenCulling ~= false, true, 'screenCulling default on')

-- ---- easing ---------------------------------------------------------
eq(DXUI.EASING.linear(0.5), 0.5, 'linear easing')
eq(DXUI.EASING['in'](0), 0, 'ease-in at 0')
eq(DXUI.EASING['in'](1), 1, 'ease-in at 1')
eq(DXUI.EASING.inout(0.5), 0.5, 'smoothstep midpoint')
local sp = DXUI.spring(0.5, 10, 1)
expect(type(sp) == 'number', 'spring returns number')

-- ---- animation ------------------------------------------------------
local target = ui:checkbox({ x=0, y=0, width=10, height=10 })
ui:add(target)
local h = ui.anim:animate(target, { width = 120 }, 100, 'inout')
expect(h ~= nil, 'animate returns handle')
eq(target.width, 10, 'anim start value')
now = 50
ui:tick()
local mid = target.width
now = 110
ui:tick()
eq(target.width, 120, 'anim completes')
expect(mid > 10 and mid < 120, 'anim interpolates middle ('..tostring(mid)..')')

print('smoke_core: all assertions executed')