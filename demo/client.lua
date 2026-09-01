---demo/client.lua — a standalone runnable DXUI V4 showcase.
---
---Copy `dxui/` and `demo/` into a server's resources folder, start
---`dxui`, then start `demo`. Everything below uses ONLY the public API
---of the `ui` handle returned by `exports.dxui:getUI()` — no engine
---internals, no globals from the dxui resource.
---
---Showcased: windows (drag, close button), buttons/checkbox/radio,
---slider -> progressbar, gridlist, combobox, scrollpanel, tabpanel,
---edit (placeholder, submit, caret modes, masked), context menu, modal
---stack, tooltips, animations, built-in themes + density presets + a
---custom theme defined RIGHT HERE, live locale switching, a live
---settings panel (caret blink, field flags) and engine settings.

local ui = exports.dxui:getUI("demo", {
    design = { width = 800, height = 600, mode = "stretch" },
})

-- --------------------------------------------------------------------------
-- demo-owned locale tables (each resource carries its own)
-- --------------------------------------------------------------------------
ui:addLocale("en", {
    title    = "DXUI V4 demo",
    name_ph  = "Write a review",
    name_lbl = "Review:",
    submit   = "Send",
    hello    = "Hello!",
    language = "Language",
    theme    = "Theme",
    open     = "Open window",
    density  = "Presets",
    modal    = "Dialog",
    settings = "Settings",
    caret    = "Caret blink",
    ro       = "Read-only field",
    mk       = "Mask field",
    phfocus  = "Placeholder under caret",
})
ui:addLocale("ru", {
    title    = "Демонстрация DXUI V4",
    name_ph  = "Напишите отзыв",
    name_lbl = "Отзыв:",
    submit   = "Отправить",
    hello    = "Привет!",
    language = "Язык",
    theme    = "Тема",
    open     = "Открыть окно",
    density  = "Пресеты",
    modal    = "Диалог",
    settings = "Настройки",
    caret    = "Мигание каретки",
    ro       = "Только чтение",
    mk       = "Маскировать поле",
    phfocus  = "Плейсхолдер при каретке",
})
ui:setLocale("ru")

-- --------------------------------------------------------------------------
-- a CUSTOM theme defined by THIS resource (extends the built-in dark
-- theme; tokens cascade, components override)
-- --------------------------------------------------------------------------
ui:defineTheme("neon", {
    extends = "dark",
    tokens = {
        color = {
            primary = 0xFF22D3EE,
            onPrimary = 0xFF06283A,
        },
    },
    components = {
        window = { props = { radius = 10 } },
        progressbar = { props = { color = "@color.primary" } },
    },
})

-- --------------------------------------------------------------------------
-- main window
-- --------------------------------------------------------------------------
local win = ui:window({ x = 60, y = 40, width = 420, height = 440 })
ui:add(win)
win:on("close", function(n) n.visible = false end)

-- title + a label react to live locale switches
local titleLbl = ui:label({ x = 0, y = 4, width = 200, height = 20 })
win:container():addChild(titleLbl)
local helloLbl = ui:label({ x = 0, y = 30, width = 200, height = 20 })
win:container():addChild(helloLbl)
titleLbl:setTextKey("title")
helloLbl:setTextKey("hello")

-- counter button + slider-driven progressbar
local clicks = 0
local btn = ui:button({ x = 0, y = 56, width = 120, height = 28, text = "+1" })
local count = ui:label({ x = 130, y = 60, width = 80, height = 20, text = "0" })
win:container():addChild(btn)
win:container():addChild(count)
btn:on("click", function() clicks = clicks + 1; count.text = tostring(clicks) end)

local bar = ui:progressbar({ x = 0, y = 96, width = 210, height = 8 })
local slider = ui:slider({ x = 0, y = 108, width = 210, height = 18 })
win:container():addChild(bar)
win:container():addChild(slider)
slider:on("change", function(_, v) bar.value = v end)

-- checkbox gates a panel; radio group picks the caret mode
local panel = ui:panel({ x = 0, y = 140, width = 210, height = 26, radius = 4 })
win:container():addChild(panel)
local box = ui:checkbox({ x = 0, y = 134, width = 210, height = 18, text = "panel", checked = true })
win:container():addChild(box)
box:on("change", function(_, v) panel.visible = v end)

local caretMode
local radios = ui:radiogroup({ x = 220, y = 56, width = 180, gap = 2 })
win:container():addChild(radios)
for _, mode in ipairs({ "blink", "solid", "off" }) do
    local r = ui:radiobutton({ width = 160, text = mode, checked = mode == "blink" })
    radios:addRadio(r)
    r:on("change", function(_, on) if on then caretMode = mode end end)
end

-- --------------------------------------------------------------------------
-- edit: placeholder (hidden on focus), submit, live settings
-- --------------------------------------------------------------------------
local ed = ui:edit({ x = 0, y = 200, width = 210, height = 26 })
ed:setTextKey("name_ph", "placeholder")
win:container():addChild(ed)
local edOut = ui:label({ x = 0, y = 230, width = 210, height = 18, text = "..." })
win:container():addChild(edOut)
ed:on("submit", function(_, text) edOut.text = "> " .. text end)

-- combobox
local combo = ui:combobox({ x = 220, y = 200, width = 160, height = 26,
                             items = { "alpha", "beta", "gamma" } })
win:container():addChild(combo)
combo:on("select", function(_, i, item) edOut.text = "#" .. i .. " " .. tostring(item) end)

-- masked edit (a password-style field)
local pass = ui:edit({ x = 220, y = 232, width = 160, height = 26, masked = true,
                       placeholder = "•••" })
win:container():addChild(pass)

-- --------------------------------------------------------------------------
-- gridlist + scrollpanel + tabs
-- --------------------------------------------------------------------------
local grid = ui:gridlist({ x = 0, y = 262, width = 210, height = 140 })
grid.items = { "Red", "Green", "Blue", "Cyan", "Magenta", "Yellow", "White", "Black" }
win:container():addChild(grid)
grid:on("select", function(_, i, item) edOut.text = tostring(item) end)

local scroll = ui:scrollpanel({ x = 220, y = 262, width = 160, height = 140 })
win:container():addChild(scroll)
for i = 1, 12 do
    scroll:container():addChild(ui:label({
        x = 4, y = (i - 1) * 24, width = 150, height = 20,
        text = "row " .. i, textColor = ui:color(160, 160, 160),
    }))
end

local tabs = ui:tabpanel({ x = 0, y = 410, width = 380, height = 60,
                           labels = { "One", "Two" } })
win:container():addChild(tabs)
tabs:addPage(ui:label({ text = "page one" }))
tabs:addPage(ui:label({ text = "page two" }))

-- --------------------------------------------------------------------------
-- context menu (opens on RIGHT click inside the gridlist)
-- --------------------------------------------------------------------------
local menu = ui:contextmenu({ items = {
    { text = "Reset counter", onSelect = function() clicks = 0; count.text = "0" end },
    { text = "Scroll top",    onSelect = function() scroll.scrollY = 0 end },
    { text = "Select first",  onSelect = function() grid.selectedIndex = 1 end },
} })
ui:add(menu)
grid:on("click", function(_, button, x, y)
    if button ~= "right" then return end
    menu:open(x, y)
end)

-- --------------------------------------------------------------------------
-- modal stack: a confirmation dialog on top of the window
-- --------------------------------------------------------------------------
local modal = ui:modal({ width = 260, height = 110 })
ui:add(modal)
local mText = ui:label({ x = 0, y = 0, width = 240, height = 20, text = "Close the demo window?" })
local mYes = ui:button({ x = 40, y = 44, width = 80, height = 26, text = "Yes" })
local mNo = ui:button({ x = 140, y = 44, width = 80, height = 26, text = "No" })
modal:container():addChild(mText)
modal:container():addChild(mYes)
modal:container():addChild(mNo)
mYes:on("click", function() win.visible = false; modal:close() end)
mNo:on("click", function() modal:close() end)

-- --------------------------------------------------------------------------
-- settings panel (a second window: live property + settings reconfiguration)
-- --------------------------------------------------------------------------
local cfg = ui:window({ x = 500, y = 120, width = 240, height = 200 })
ui:add(cfg)
cfg.visible = false
cfg:on("close", function(n) n.visible = false end)
cfg:setTextKey("settings", "title")

-- caret blink interval: slider (0..1) -> 0..1000ms, applied engine-wide
local blinkVal = ui:label({ x = 10, y = 30, width = 220, height = 16, text = "400 ms" })
local blink = ui:slider({ x = 10, y = 10, width = 220, height = 18, value = 0.4 })
cfg:container():addChild(blink)
cfg:container():addChild(blinkVal)
local blinkCap = ui:label({ x = 10, y = 52, width = 220, height = 16 })
cfg:container():addChild(blinkCap)
blinkCap:setTextKey("caret")
blink:on("change", function(_, v)
    ui:applySettings({ defaults = { caretBlinkInterval = math.floor(v * 1000 + 0.5) } })
    blinkVal.text = math.floor(v * 1000 + 0.5) .. " ms"
end)

-- live property flips on the review field
local function cfgCheck(y, key, apply)
    local cb = ui:checkbox({ x = 10, y = y, width = 220, height = 18 })
    cb:setTextKey(key)
    cb:on("change", function(_, on) apply(on) end)
    cfg:container():addChild(cb)
    return cb
end
cfgCheck(78, "ro", function(on) ed.readOnly = on end)
cfgCheck(100, "mk", function(on) ed.masked = on end)
cfgCheck(122, "phfocus", function(on) ed.placeholderVisibleWhenFocused = on end)

-- --------------------------------------------------------------------------
-- control strip (below the window): language, themes, density, modal
-- --------------------------------------------------------------------------
local function stripBtn(x, w, key, onClick)
    local b = ui:button({ x = x, y = 500, width = w, height = 24 })
    b:setTextKey(key)
    b:on("click", onClick)
    ui:add(b)
    return b
end

local langBtn = stripBtn(60, 70, "language", function()
    ui:setLocale(ui:getLocale() == "ru" and "en" or "ru")
end)

stripBtn(136, 80, "theme", function()
    -- custom theme defined by THIS resource <-> built-in light
    ui:setTheme(ui:getTheme() == "neon" and "light" or "neon")
end)

stripBtn(222, 60, "open", function() win.visible = true end)

stripBtn(288, 70, "density", function()
    -- cycle the built-ins + density presets
    local order = { "light", "dark", "green", "light-compact", "dark-full", "green-full" }
    local cur = ui:getTheme()
    for i = 1, #order do
        if order[i] == cur then
            ui:setTheme(order[(i % #order) + 1])
            return
        end
    end
    ui:setTheme(order[1])
end)

stripBtn(364, 90, "modal", function()
    modal:open() -- dimmed overlay + centered dialog; blocks outside input
end)

stripBtn(460, 90, "settings", function()
    cfg.visible = not cfg.visible -- the settings panel window
end)

-- tooltip on the language button
local tip = ui:tooltip({ text = "RU / EN" })
ui:add(tip)
tip:attach(langBtn, "bottom")

-- --------------------------------------------------------------------------
-- intro animation + engine settings from the consumer side
-- --------------------------------------------------------------------------
win:animate({ y = 90 }, 350, "out"):after({ y = 40 }, 250)
ui:applySettings({ defaults = { caretBlinkInterval = 400 } })

outputChatBox("DXUI V4 demo running — close window via ×, themes/languages top-right.")