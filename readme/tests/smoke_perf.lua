--[[
    smoke_perf.lua — DXUI V3 test suite (performance contract)

    Measures the pipeline contracts on a realistically sized UI
    (~150 nodes): idle frames do ZERO work of any kind, a mutation does
    EXACTLY the work of its dirty category, pointer input alone never
    rebuilds, and theme switches cost one rebuild. Prints benchmark numbers
    for readme/ai/004-v3-perf.md.

    NOTE: zero-work assertions (Diagnostics.enableZeroWork) are ON for the
    whole run — every idle tick PROVES no layout/rebuild happened.
]]

local now = 0
local ui = DXUI.getUI('perfbench', { design={ width=1280, height=720 },
                                     clock=function() return now end })
DXUI.Runtime.backend = Backend()
ui:setViewport(1280, 720)
DXUI.Diagnostics.enableZeroWork(ui, true)

-- ---- build a composite UI -------------------------------------------
local win = ui:window({ title='Bench', x=0.1, y=0.1, width=1000, height=560 })
ui:add(win)
local content = win:container()
local rows = 8
local sliderRef
for r = 1, rows do
    local y = (r - 1) * 48
    content:addChild(ui:label({ x=0, y=y, width=120, height=20, text='row '..r }))
    content:addChild(ui:button({ x=130, y=y, width=70, height=26, text='b'..r }))
    sliderRef = ui:slider({ x=210, y=y+2, width=160, height=16, value=r/rows })
    content:addChild(sliderRef)
    content:addChild(ui:progressbar({ x=380, y=y+6, width=120, height=8, value=r/rows }))
    content:addChild(ui:checkbox({ x=510, y=y, width=90, height=18, text='c'..r }))
end
local gl = ui:gridlist({ x=620, y=0, width=220, height=300 })
for i = 1, 30 do gl:addItem('item '..i) end
content:addChild(gl)
local tp = ui:tabpanel({ x=0, y=400, width=640, height=140, labels={'A','B','C'} })
for i = 1, 3 do tp:addPage(ui:label({ text='page'..i })) end
content:addChild(tp)
local sp = ui:scrollpanel({ x=860, y=0, width=220, height=380 })
for i = 1, 40 do
    sp:container():addChild(ui:label({ x=0, y=(i-1)*18, width=200, height=16, text='scroll '..i }))
end
content:addChild(sp)

-- ---- warm: flush the build ------------------------------------------
now = now + 16; ui:tick()
local warm = DXUI.Diagnostics.snapshot(ui)
expect(warm.items > 40, 'render list populated ('..warm.items..' items)')

-- ---- phase 1: idle frames do ZERO work -------------------------------
local b1 = DXUI.Diagnostics.snapshot(ui)
for _ = 1, 60 do now = now + 16; ui:tick() end
local a1 = DXUI.Diagnostics.snapshot(ui)
eq(a1.rebuilds, b1.rebuilds, '60 idle frames: zero render-list rebuilds')
eq(a1.layoutRuns, b1.layoutRuns, '60 idle frames: zero layout runs')
eq(a1.hitRebuilds, b1.hitRebuilds, '60 idle frames: zero interactive rebuilds')
local idle = DXUI.Diagnostics.idleRatio(ui)
expect(idle > 0.9, 'idleRatio > 0.9 got '..string.format('%.3f', idle))

-- ---- phase 2: one mutation -> exactly its category's work ------------
local b2 = DXUI.Diagnostics.snapshot(ui)
content:addChild(ui:label({ x=0, y=470, width=80, height=16, text='added' }))
now = now + 16; ui:tick()
local a2 = DXUI.Diagnostics.snapshot(ui)
eq(a2.rebuilds - b2.rebuilds, 1, 'add -> exactly one rebuild')
eq(a2.layoutRuns - b2.layoutRuns, 1, 'add -> exactly one layout run')
-- next frame idle again
now = now + 16; ui:tick()
local a2b = DXUI.Diagnostics.snapshot(ui)
eq(a2b.rebuilds, a2.rebuilds, 'frame after mutation: zero rebuilds')
eq(a2b.layoutRuns, a2.layoutRuns, 'frame after mutation: zero layout')

-- ---- phase 3: render-only write (slider value) -----------------------
local b3 = DXUI.Diagnostics.snapshot(ui)
sliderRef.value = 0.7
now = now + 16; ui:tick()
local a3 = DXUI.Diagnostics.snapshot(ui)
eq(a3.rebuilds - b3.rebuilds, 1, 'render-only write -> one rebuild')
eq(a3.layoutRuns - b3.layoutRuns, 0, 'render-only write -> no layout')

-- ---- phase 4: layout+render write (label text) -----------------------
local addedLabel = content._children[#content._children]
local b4 = DXUI.Diagnostics.snapshot(ui)
addedLabel.text = 'changed!'
now = now + 16; ui:tick()
local a4 = DXUI.Diagnostics.snapshot(ui)
eq(a4.rebuilds - b4.rebuilds, 1, 'text write -> one rebuild')
eq(a4.layoutRuns - b4.layoutRuns, 1, 'text write -> one layout run')

-- ---- phase 5: pointer input alone never rebuilds ---------------------
local b5 = DXUI.Diagnostics.snapshot(ui)
ui:mouseMove(145, 130) -- over button row 1
ui:mouseMove(700, 200) -- over gridlist
now = now + 16; ui:tick()
local a5 = DXUI.Diagnostics.snapshot(ui)
eq(a5.rebuilds, b5.rebuilds, 'pointer moves: zero render rebuilds')
eq(a5.layoutRuns, b5.layoutRuns, 'pointer moves: zero layout')
eq(a5.hitRebuilds, b5.hitRebuilds, 'pointer moves: zero interactive rebuilds')

-- ---- phase 6: theme switch -> exactly one rebuild, then idle ---------
DXUI.Theme.define('bench', { extends='default', components={
    button = { base = { color = '#7C3AED' } },
} })
local b6 = DXUI.Diagnostics.snapshot(ui)
DXUI.Theme.activate('bench')
now = now + 16; ui:tick()
local a6 = DXUI.Diagnostics.snapshot(ui)
eq(a6.rebuilds - b6.rebuilds, 1, 'theme switch -> one rebuild')
eq(a6.layoutRuns - b6.layoutRuns, 0, 'theme switch -> no layout (color is render-only)')
now = now + 16; ui:tick()
local a6b = DXUI.Diagnostics.snapshot(ui)
eq(a6b.rebuilds, a6.rebuilds, 'after theme switch: zero rebuilds')

-- ---- benchmark summary (numbers for readme/ai/004) -------------------
local final = DXUI.Diagnostics.snapshot(ui)
local drawsPerFrame = math.floor(final.draws / final.frames)
print('PERF(items='..final.items..' draws/frame~='..drawsPerFrame..
      ' layoutRuns='..final.layoutRuns..' rebuilds='..final.rebuilds..
      ' hitRebuilds='..final.hitRebuilds..' frames='..final.frames..
      ' idleRatio='..string.format('%.3f', DXUI.Diagnostics.idleRatio(ui))..')')

print('smoke_perf: all assertions executed')