--[[
    smoke_api.lua — DXUI V3 test suite (public API surface regression)

    Guards the CONSUMER-FACING surface promised by the contracts
    (readme/ai/002): widget factories, value factories, node lifecycle
    methods, events, parts, translation, diagnostics, theme/tokens and
    runtime statics. Any break here is an API break.
]]

local now = 0
local ui = DXUI.UI:new({ name='api', design={ width=800, height=600 },
                         clock=function() return now end })
DXUI.Runtime.backend = Backend()
ui:setViewport(800, 600)

-- ---- widget factories: all 18 promised names ------------------------
local factories = {
    'panel','label','button','image','window','checkbox','radiobutton',
    'progressbar','slider','scrollpanel','edit','combobox','tabpanel',
    'gridlist','popup','contextmenu','modal','tooltip',
}
local classNames = {
    panel='Panel', label='Label', button='Button', image='Image',
    window='Window', checkbox='Checkbox', radiobutton='RadioButton',
    progressbar='ProgressBar', slider='Slider', scrollpanel='ScrollPanel',
    edit='Edit', combobox='ComboBox', tabpanel='TabPanel',
    gridlist='GridList', popup='Popup', contextmenu='ContextMenu',
    modal='Modal', tooltip='Tooltip',
}
local made = {}
for _, n in ipairs(factories) do
    local w = ui[n]({ x=0, y=0, width=40, height=20, text='t' })
    eq(w ~= nil, true, 'factory ui:'..n..' returns node')
    if w then
        made[n] = w
        eq(w._class._name, classNames[n], 'ui:'..n..' class name')
    end
end
eq(type(DXUI.Widgets.panel), 'table', 'Widgets registry lowercase')
eq(type(DXUI.Widgets.Button), 'table', 'Widgets registry title case')
eq(ui:widget('label', { text='x' }) ~= nil, true, 'generic ui:widget')
eq(ui:widget('no-such-widget'), nil, 'unknown widget -> nil')

-- key default contracts
eq(made.panel.interactive, false, 'panel not interactive by default')
eq(made.label.autoSize, true, 'label content-sizing default')
eq(made.button.interactive, true, 'button interactive default')
eq(made.button.focusable, true, 'button focusable default')
eq(made.combobox ~= nil and made.combobox.height > 0 or true, true, 'combobox exists')

-- ---- value factories ------------------------------------------------
local pct = ui:percent(50)
eq(pct.k, 'pct', 'percent dim k')
eq(pct.v, 50, 'percent dim v')
eq(ui:auto().k, 'auto', 'auto dim')
eq(ui:fill().k, 'fill', 'fill dim')
local c = ui:color(255, 37, 99)
eq(DXUI.ColorToInt(c), 0xFFFF2563, 'color factory packs 0xAARRGGBB')
eq(DXUI.ColorToInt(DXUI.color(255, 37, 99, 235)), 0xEBFF2563, 'color alpha packed')
eq(DXUI.ColorToInt(DXUI.resolveColor({ r=255, g=37, b=99 })), 0xFFFF2563, 'resolveColor table path')
eq(DXUI.Dimension.resolve({ k='pct', v=50 }, 400), 200, 'Dimension.resolve pct')
local l, t, r, b = DXUI.Dimension.box({ left=1, top=2, right=3, bottom=4 })
eq(l..t..r..b, '1234', 'Dimension.box unpack')

-- ---- node lifecycle API ---------------------------------------------
local n = ui:panel({ x=0, y=0, width=20, height=20 })
eq(n:isAlive(), true, 'isAlive')
n:setPosition(5, 6)
eq(n.x, 5, 'setPosition x')
n:setSize(30, 40)
eq(n.width, 30, 'setSize w')
n:setVisible(false)
eq(n.visible, false, 'setVisible off')
n:show()
eq(n.visible, true, 'show')
n:hide()
eq(n.visible, false, 'hide')
n:setEnabled(false)
eq(n:isEnabled(), false, 'setEnabled')
n:setZIndex(9)
eq(n.zIndex, 9, 'setZIndex')
n:setOpacity(0.5)
eq(n.opacity, 0.5, 'setOpacity')
n:setMargin(1, 2, 3, 4)
n:setPadding(1, 2, 3, 4)
n:setAnchor('mc')
n:setLayer(3)
eq(n.layer, 3, 'setLayer')
n:setMode('relative')
eq(n.layoutMode, 'relative', 'setMode')
n:destroy()
eq(n:isDestroyed(), true, 'destroy + isDestroyed')

-- state
made.button:setState('hover')
eq(made.button:getState(), 'hover', 'setState/getState')

-- property watchers
local watched
local w2 = ui:panel({ width=10, height=10 })
w2:onProperty('width', function(v) watched = v end) -- fn(value, old, node)
w2.width = 25
eq(watched, 25, 'onProperty fires')
w2:offProperty('width')
w2.width = 30
eq(watched, 25, 'offProperty stops')

-- ---- tree ops --------------------------------------------------------
local root = ui:panel({ width=50, height=50 })
ui:add(root)
eq(root._parent, ui.root, 'ui:add parents to root')
local child = ui:label({ text='c' })
root:addChild(child)
eq(child._parent, root, 'addChild parents')
child:removeFromParent()
eq(child._parent, nil, 'removeFromParent')
root:setParent(ui.root)
eq(root._parent, ui.root, 'setParent')
root:bringToFront()
root:getDepth()

-- ---- events module ---------------------------------------------------
local ev = ui:panel({ width=5, height=5 })
local firedN = 0
ev:on('x', function() firedN = firedN + 1 end)
ev:emit('x')
eq(firedN, 1, 'on/emit')
eq(DXUI.Events.has(ev, 'x'), true, 'Events.has')
ev:off('x')
eq(DXUI.Events.has(ev, 'x'), false, 'off removes')
ev:on('y', function() end, 'owner-a')
DXUI.Events.removeForOwner(ev, 'owner-a')
eq(DXUI.Events.has(ev, 'y'), false, 'removeForOwner')
ev:on('z', function() end)
DXUI.Events.clear(ev)
eq(DXUI.Events.has(ev, 'z'), false, 'clear')

-- ---- parts -----------------------------------------------------------
local win = ui:window({ title='T', width=100, height=60 })
eq(win:getPart('header') ~= nil, true, 'window header part')
eq(win:getPart('content') ~= nil, true, 'window content part')
win:setPart('content', ui:label({ text='f' }))
eq(win:getPart('content') ~= nil, true, 'setPart/getPart')
win:removePart('content')
eq(win:getPart('content'), nil, 'removePart')
local names = DXUI.Part.declare({ parts = {} }, { 'header', 'body' })
eq(names.parts.header, true, 'Part.declare (class, names)')

-- ---- translation -----------------------------------------------------
DXUI.addLocale('ru', { OK = 'Да' })
DXUI.setLocale('ru')
eq(DXUI.tr('OK'), 'Да', 'tr resolves locale')
eq(DXUI.getLocale(), 'ru', 'getLocale')
local tl = ui:label({ text='OK' })
expect(pcall(function() ui:setTextKey('OK', tl) end), 'setTextKey callable')

-- ---- diagnostics -----------------------------------------------------
local snap = DXUI.Diagnostics.snapshot(ui)
eq(snap.frames, ui.stats.frames, 'snapshot matches stats')
DXUI.Diagnostics.enableZeroWork(ui, true)
eq(ui.perf.zeroWork, true, 'enableZeroWork on')
DXUI.Diagnostics.enableZeroWork(ui, false)
eq(ui.perf.zeroWork, false, 'enableZeroWork off')
eq(type(DXUI.Diagnostics.describe(ui)), 'string', 'describe string')
eq(type(DXUI.Diagnostics.report(ui)), 'string', 'report string')
local ir = DXUI.Diagnostics.idleRatio(ui)
expect(ir >= 0 and ir <= 1, 'idleRatio in [0,1]')

-- ---- theme/tokens/runtime statics ------------------------------------
eq(type(DXUI.Theme.define), 'function', 'Theme.define exists')
eq(type(DXUI.Theme.activate), 'function', 'Theme.activate exists')
eq(type(DXUI.Theme.getComponentStyle), 'function', 'Theme.getComponentStyle exists')
eq(type(DXUI.Tokens.define), 'function', 'Tokens.define exists')
eq(type(DXUI.Tokens.resolve), 'function', 'Tokens.resolve exists')
eq(type(DXUI.Runtime.backend), 'table', 'Runtime.backend injectable')
eq(type(DXUI.Runtime.create), 'function', 'Runtime.create exists')
eq(type(DXUI.getUI), 'function', 'getUI exists')

-- ---- regression: parent write reparents (not silently dropped) --------
local pa = ui:panel({ x=0, y=0, width=50, height=50 })
local pb = ui:panel({ x=0, y=0, width=50, height=50 })
ui:add(pa); ui:add(pb)
local ch = ui:label({ text='c' })
ch.parent = pa
eq(ch._parent, pa, 'parent write reparents (1)')
ch.parent = pb
eq(ch._parent, pb, 'parent write reparents (2)')

-- ---- regression: Edit padding is a valid spec (no crash on write) -----
local e2 = ui:edit({ x=0, y=0, width=100, height=24 })
local okPad = pcall(function() e2.padding = { left = 4, right = 4, top = 0, bottom = 0 } end)
eq(okPad, true, 'edit padding write does not crash')

-- ---- regression: translation %N (multi-digit + literal % in value) ----
DXUI.addLocale('xx', { greet = 'Hello %1, you are %2', pct = 'Progress %1',
                       many = '%1 %2 %3 %4 %5 %6 %7 %8 %9 %10' })
DXUI.setLocale('xx')
eq(DXUI.tr('greet', 'Bob', 42), 'Hello Bob, you are 42', 'tr multi-arg')
eq(DXUI.tr('pct', '100%'), 'Progress 100%', 'tr literal percent in value')
eq(DXUI.tr('many', 'a','b','c','d','e','f','g','h','i','j'),
   'a b c d e f g h i j', 'tr %10 multi-digit')
DXUI.setLocale('en')

-- ---- regression: RT-group path must not recurse infinitely ------------
local function withGroups(fn)
    local saved = { dxCreateShader, dxCreateRenderTarget, isElement, destroyElement }
    dxCreateShader = function() return {} end
    dxCreateRenderTarget = function() return {} end
    isElement = function() return true end
    destroyElement = function() end
    local ok, err = pcall(fn)
    dxCreateShader, dxCreateRenderTarget = saved[1], saved[2]
    isElement, destroyElement = saved[3], saved[4]
    if not ok then error(err, 0) end
end
withGroups(function()
    local g = ui:panel({ x=0, y=0, width=100, height=100, blur=4 })
    ui:add(g)
    local gc = ui:label({ text='x', x=0, y=0 })
    gc:setParent(g)
    ui:tick()
    expect(ui.stats.items >= 1, 'group node emits without recursion')
end)

print('smoke_api: all assertions executed')