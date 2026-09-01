--[[
    smoke_style.lua — DXUI V3 test suite (style: tokens/theme/defaults)

    Defaults theme auto-activates at load; suites here additionally define
    a custom theme + variant to prove compile, fallback and switching.
]]

local now = 0
local ui = DXUI.UI:new({ name='style', design={ width=800, height=600 },
                         clock=function() return now end })
DXUI.Runtime.backend = Backend()
ui:setViewport(800, 600)

-- ---- tokens ---------------------------------------------------------
DXUI.Tokens.define('testtokens', {
    brand = { accent = 0xFF22C55E, chain = '@brand.accent', loop = '@brand.loop' },
})
eq(DXUI.Tokens.get('testtokens', 'brand.accent'), 0xFF22C55E, 'token get dotted path')
eq(DXUI.ColorToInt(DXUI.Tokens.resolve('testtokens', '@brand.accent')), 0xFF22C55E, 'token resolve')
eq(DXUI.ColorToInt(DXUI.Tokens.resolve('testtokens', '@brand.chain')), 0xFF22C55E, 'token @alias chain')
eq(DXUI.Tokens.resolve('testtokens', '@brand.loop'), nil, 'cycle returns nil (guarded)')

-- ---- custom theme (shape matches the engine contract: base/variants/
-- states are FLAT prop maps; variants keyed by node.style) -------------
DXUI.Theme.define('test', {
    extends = 'default',
    tokens = { color = { accent = 0xFF22C55E, btnBg = '#7C3AED' } },
    components = {
        button = {
            base = { color = '@color.btnBg', radius = 6 },
            variants = { wide = { radius = 2 } },
            states = { hover = { color = '#6D28D9' }, pressed = { color = '#5B21B6' } },
        },
        label = { base = { textColor = '@color.accent' } },
    },
})

-- case-insensitive component lookup (class "Button" -> component "button")
local btnBefore = ui:button({ text='T', x=0, y=0, width=40, height=20 })
ui:add(btnBefore)
local colorBefore = DXUI.ColorToInt(btnBefore.color)
eq(colorBefore, 0xFF2563EB, 'default theme primary before switch')

DXUI.Theme.activate('test')

local btn = ui:button({ text='A', x=0, y=0, width=40, height=20 })
ui:add(btn)
eq(DXUI.ColorToInt(btn.color), 0xFF7C3AED, 'custom component color after switch')
eq(btn.radius, 6, 'custom radius prop applied')

-- variant style
local wbtn = ui:button({ text='W', x=0, y=30, width=40, height=20, style='wide' })
ui:add(wbtn)
eq(wbtn.radius, 2, 'variant radius overrides base')

-- label adopts accent token
local lb = ui:label({ text='Hi', x=0, y=60, width=20 })
ui:add(lb)
eq(DXUI.ColorToInt(lb.textColor), 0xFF22C55E, 'label token via custom theme')

-- state override (hover) via wireStates + dispatcher
DXUI.Builders.wireStates(btn)
ui:tick()
ui:mouseMove(5, 5) -- over btn (0,0,40,20)
eq(btn:getState(), 'hover', 'hover state entered')
eq(DXUI.ColorToInt(btn.color), 0xFF6D28D9, 'hover color from theme state')
ui:mouseDown('left', 5, 5)
eq(btn:getState(), 'pressed', 'pressed state entered')
eq(DXUI.ColorToInt(btn.color), 0xFF5B21B6, 'pressed color from theme state')
ui:mouseUp('left', 5, 5)
ui:mouseMove(400, 400)

-- theme switch back: previously built nodes re-apply (reapplyAll walks
-- DXUI._uis trees; this suite's ui was created directly via UI:new, so
-- re-apply explicitly — the mounted-widget path is covered by smoke_boot)
DXUI.Theme.activate('default')
btn:_applyStyleState()
wbtn:_applyStyleState()
lb:_applyStyleState()
eq(DXUI.ColorToInt(btn.color), 0xFF2563EB, 'switch back re-applies default theme')

-- fallback chain: theme extends default -> missing component falls back
local pb = ui:progressbar({ x=0, y=0, width=100, height=10 })
ui:add(pb)
eq(pb.radius, 4, 'progressbar falls back to default theme component')

-- asset keep sweep is wired
DXUI.Theme.markAssetUsed('assets/x.png')
expect(pcall(function() DXUI.releaseObsolete({}) end), 'releaseObsolete callable')

print('smoke_style: all assertions executed')