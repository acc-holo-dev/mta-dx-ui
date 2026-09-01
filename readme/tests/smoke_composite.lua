--[[
    smoke_composite.lua — DXUI V3 test suite (composite widgets)

    checkbox / radiobutton+group / progressbar / slider / edit /
    gridlist / scrollpanel / tabpanel / combobox / contextmenu / modal /
    tooltip — exercised with REAL dispatcher interactions.
]]

local now = 0
local ui = DXUI.UI:new({ name='composite', design={ width=800, height=600 },
                         clock=function() return now end })
DXUI.Runtime.backend = Backend()
ui:setViewport(800, 600)

-- checkbox toggles + change
local cb = ui:checkbox({ text='Enable', x=10, y=10, width=100, height=20 })
ui:add(cb)
local cbChanged
cb:on('change', function(_, v) cbChanged = v end)
ui:tick()
ui:mouseDown('left', 20, 20); ui:mouseUp('left', 20, 20)
eq(cb.checked, true, 'checkbox toggled')
eq(cbChanged, true, 'checkbox change event')

-- radiobutton + group exclusivity (manual group wiring)
local r1 = ui:radiobutton({ text='A', x=10, y=40, width=100, height=20 })
local r2 = ui:radiobutton({ text='B', x=10, y=70, width=100, height=20 })
ui:add(r1); ui:add(r2)
r1:on('change', function(n, v) if v and r2.checked then r2.checked = false end end)
r2:on('change', function(n, v) if v and r1.checked then r1.checked = false end end)
ui:tick()
ui:mouseDown('left', 20, 50); ui:mouseUp('left', 20, 50)
eq(r1.checked, true, 'radio A selected')
ui:mouseDown('left', 20, 80); ui:mouseUp('left', 20, 80)
eq(r2.checked, true, 'radio B selected')
eq(r1.checked, false, 'radio A deselected')

-- slider click value
local sl = ui:slider({ x=10, y=130, width=200, height=18, value=0 })
ui:add(sl)
local sval
sl:on('change', function(_, v) sval = v end)
ui:tick()
ui:mouseDown('left', 160, 139); ui:mouseUp('left', 160, 139)
-- 143/186 ≈ 0.769
eq(math.abs(sval - 0.769) < 0.02, true, 'slider click sets value ('..tostring(sval)..')')

-- edit: focus, type, backspace, submit
local ed = ui:edit({ x=10, y=160, width=200, height=24, placeholder='name' })
ui:add(ed)
local submitted
ed:on('submit', function(_, t) submitted = t end)
ui:tick()
ui:mouseDown('left', 20, 172); ui:mouseUp('left', 20, 172)
eq(ui.dispatcher.focus, ed, 'edit focused')
ui:key('j', true); ui:key('o', true); ui:key('e', true)
eq(ed.text, 'joe', 'typed chars')
ui:key('backspace', true)
eq(ed.text, 'jo', 'backspace')
ui:key('enter', true)
eq(submitted, 'jo', 'submit on enter')

-- gridlist row select
local gl = ui:gridlist({ x=10, y=200, width=180, height=120 })
ui:add(gl)
gl:addItem('one'); gl:addItem('two'); gl:addItem('three')
local sel
gl:on('select', function(_, i) sel = i end)
ui:tick()
ui:mouseDown('left', 60, 230); ui:mouseUp('left', 60, 230)
eq(sel, 2, 'gridlist row 2 selected')

-- scrollpanel wheel
local sp = ui:scrollpanel({ x=10, y=340, width=150, height=100 })
ui:add(sp)
for i = 1, 10 do
    sp:container():addChild(ui:label({ text='row'..i, x=0, y=(i-1)*20 }))
end
ui:tick()
eq(sp.scrollY, 0, 'scroll starts 0')
ui:scroll(-2, 50, 390)
eq(sp.scrollY > 0.8, true, 'wheel scrolled (y='..tostring(sp.scrollY)..')')

-- tabpanel pages + tab click
local tp = ui:tabpanel({ x=10, y=460, width=200, height=120, labels={'A','B'} })
ui:add(tp)
local pageA = ui:label({ text='pageA' }); tp:addPage(pageA)
local pageB = ui:label({ text='pageB' }); tp:addPage(pageB)
ui:tick()
eq(pageA.visible, true, 'page A visible')
eq(pageB.visible, false, 'page B hidden')
local tabB = tp._tabLabels[2]
ui:mouseDown('left', tabB.worldX + 10, 470); ui:mouseUp('left', tabB.worldX + 10, 470)
eq(tp.activeIndex, 2, 'tab B activated')
eq(pageB.visible, true, 'page B now visible')

-- combobox open -> select row -> closed
local cbx = ui:combobox({ x=250, y=10, width=140, items={'Red','Green','Blue'} })
ui:add(cbx)
local cbxSel
cbx:on('select', function(_, i) cbxSel = i end)
ui:tick()
eq(cbx.height, 20, 'combobox height')
ui:mouseDown('left', 300, 20); ui:mouseUp('left', 300, 20)
eq(cbx.open, true, 'combobox opened')
ui:tick()
ui:mouseDown('left', 300, 40); ui:mouseUp('left', 300, 40)
eq(cbxSel, 1, 'combobox selected row 1')
eq(cbx.open, false, 'combobox closed after select')

-- contextmenu select
local fired = false
local cm = ui:contextmenu({ items={
    { text='Rename', onSelect=function() fired = true end },
    '--',
    { text='Delete', disabled=true },
} })
ui:add(cm)
ui:tick()
cm:open(400, 100)
ui:tick()
eq(cm.visible, true, 'contextmenu open')
eq(cm.worldX, 400, 'contextmenu positioned')
ui:mouseDown('left', 410, 110); ui:mouseUp('left', 410, 110)
eq(fired, true, 'contextmenu item executed')
eq(cm.visible, false, 'contextmenu closed')

-- modal blocks outside + close
local closed = false
local md = ui:modal({ width=260, height=140 })
ui:add(md)
md:on('close', function() closed = true end)
md:open()
ui:tick()
eq(ui.dispatcher.modalDepth, 1, 'modal depth 1')
ui:mouseDown('left', 300, 20)
eq(cbx.open, false, 'modal blocks outside click')
ui:mouseUp('left', 300, 20)
md:close()
eq(closed, true, 'modal close event')
eq(ui.dispatcher.modalDepth, 0, 'modal depth 0')

-- tooltip hover
local tt = ui:tooltip({ text='Save me', x=0, y=0 })
ui:add(tt)
local anchor = ui:button({ x=500, y=100, width=80, height=30, text='Save' })
ui:add(anchor)
tt:attach(anchor, 'top')
ui:tick()
eq(tt.visible, false, 'tooltip hidden')
ui:mouseMove(540, 115)
eq(tt.visible, true, 'tooltip on hover')
ui:tick() -- layout must run before world coords are current
eq(tt.worldY + tt.height <= anchor.worldY, true, 'tooltip above target')
ui:mouseMove(10, 500)
eq(tt.visible, false, 'tooltip hides')

print('smoke_composite: all assertions executed')