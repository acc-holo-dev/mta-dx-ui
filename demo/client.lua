--[[
    demo.lua — DXUI V3 example (MTA:SA resource usage)

    A small live app: window with a counter button, a checkbox toggling a
    panel, a slider driving a progress bar, tabbed panels and a context
    menu. Copy the pattern into your own MTA client script after
    `<script src="dxui.lua" />`-style loading of this resource.

    Requires: dxui resource loaded first (exports.dxui:getUI), then run
    DXUI.bootstrap exactly once per resource instance.
]]

local ui = exports.dxui:getUI("demo", {
    design = { width = 800, height = 600 }, -- design space mapped to screen
    mode   = "stretch",                     -- or "fit"
})

DXUI.bootstrap({ name = "demo", design = { width = 800, height = 600 } })

-- ---- window with a click counter -------------------------------------
local clicks
local win = ui:window({
    title = "DXUI V3 demo",
    x = 0.5, y = 0.5,           -- relative layout: fractions of the screen
    width = 360, height = 300,
    style = "primary",          -- theme variant (node.style)
})
ui:add(win)

clicks = 0
win:container():addChild(ui:button({
    x = 0, y = 0, width = 140, height = 32,
    text = "Click me",
    onSet = function(self) self:on("click", function() clicks = clicks + 1 end) end,
}))

local label = ui:label({ x = 150, y = 6, text = "clicks: 0" })
win:container():addChild(label)
win:container():on("click", function(_, x, y, bx, by) end)

-- ---- checkbox -> panel toggle ----------------------------------------
local panelVisible = true
local box = ui:checkbox({
    x = 0, y = 44, width = 200, height = 20,
    text = "Show panel",
    checked = true,
})
box:on("change", function(_, v) panelVisible = v end)
win:container():addChild(box)

local panel = ui:panel({ x = 0, y = 70, width = 200, height = 60 })
win:container():addChild(panel)

-- ---- slider -> progressbar -------------------------------------------
local bar = ui:progressbar({ x = 0, y = 140, width = 200, height = 10 })
local slider = ui:slider({ x = 0, y = 156, width = 200, height = 18, value = 0 })
slider:on("change", function(_, v) bar.value = v end)
win:container():addChild(bar)
win:container():addChild(slider)

-- ---- tabs ------------------------------------------------------------
local tabs = ui:tabpanel({
    x = 0, y = 180, width = 320, height = 90,
    labels = { "A", "B" },
})
local pageA = ui:label({ text = "Tab A content" })
local pageB = ui:label({ text = "Tab B content" })
tabs:addPage(pageA)
tabs:addPage(pageB)
win:container():addChild(tabs)

-- ---- context menu (right-ish click opens it anywhere) ----------------
local menu = ui:contextmenu({ items = {
    { text = "Reset counter", onSelect = function() clicks = 0 end },
    "—",
    { text = "Close", onSelect = function() win.visible = false end },
} })
ui:add(menu)

win:on("click", function(_, x, y, sx, sy)
    if sx and sx ~= 1 then return end -- left button = 1
    menu:open(x, y)
end)

-- ---- a tooltip -------------------------------------------------------
local tt = ui:tooltip({ text = "Left-click the panel" })
ui:add(tt)
tt:attach(panel, "top")

-- ---- per-frame glue (leave frame scheduling to init.lua bootstrap; this
-- is only needed if you drive the frame loop yourself) -----------------
-- addEventHandler("onClientRender", resourceRoot, function() ui:tick() end, false, 1)

outputChatBox("DXUI V3 demo running — click the button.")