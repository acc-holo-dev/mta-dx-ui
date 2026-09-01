---documents/gen.lua — static wiki generator (pure Lua 5.1).
---
---Loads the ENGINE (source/, meta.xml order, no MTA backend) and reflects
---the real registries — widget property specs, parts, themes, tokens,
---settings — then emits documents/*.html. The property tables can never
---drift from the code: they are read from the live spec tables.
---
---Run from the repo root:  lua5.1 documents/gen.lua
---Output: documents/{index,api,widgets,theme,translate,settings,advanced}.html

local arg0 = arg and arg[0] or "gen.lua"
-- resolve the REPO root: <root>documents/gen.lua from anywhere, or the
-- parent when invoked as "gen.lua" from inside documents/
local ROOT = arg0:match("^(.*)documents[/\\]gen%.lua$") or ""
if ROOT == "" then
    local f0 = io.open("meta.xml", "r")
    if f0 then f0:close() ROOT = "./" else ROOT = "../" end
else
    ROOT = ROOT:gsub("\\$", "/")
end
local OUT = ROOT .. "documents/"

-- ----------------------------------------------------------------------
-- engine load (meta.xml order, minus init.lua — no MTA backend here)
-- ----------------------------------------------------------------------
local f = io.open(ROOT .. "meta.xml", "r")
if not f then error("run from the repo root (cannot read meta.xml)") end
local meta = f:read("*a")
f:close()
for src in meta:gmatch('<script%s+src="([^"]+)"') do
    if src:find("init%.lua$") == nil then
        local chunk, err = loadfile(ROOT .. "/" .. src)
        if not chunk then error(("load %s: %s"):format(src, tostring(err))) end
        local ok, runErr = pcall(chunk)
        if not ok then error(("run %s: %s"):format(src, tostring(runErr))) end
    end
end
if DXUI.Text and DXUI.Text.setMeasurer then
    DXUI.Text.setMeasurer(function(text) return #text * 7, 15 end)
end

-- ----------------------------------------------------------------------
-- helpers
-- ----------------------------------------------------------------------
local function esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function fmtDefault(v)
    if v == nil then return "<em>nil</em>" end
    local t = type(v)
    if t == "table" then
        local parts = {}
        for k2, v2 in pairs(v) do
            parts[#parts + 1] = tostring(k2) .. "=" .. tostring(v2)
        end
        table.sort(parts)
        return "{" .. esc(table.concat(parts, ", ")) .. "}"
    end
    if t == "string" then return esc('"' .. v .. '"') end
    if t == "number" then return tostring(v) end
    return esc(tostring(v))
end

local function specType(spec)
    local t = {}
    if spec.type then t[#t + 1] = spec.type end
    if spec.min ~= nil then t[#t + 1] = "min " .. tostring(spec.min) end
    if spec.max ~= nil then t[#t + 1] = "max " .. tostring(spec.max) end
    if spec.validate then t[#t + 1] = "validate" end
    if spec.transform then t[#t + 1] = "transform" end
    if spec.onSet then t[#t + 1] = "onSet" end
    return table.concat(t, ", ")
end

local function colorTag(v)
    if type(v) == "number" and v > 0xFF000000 then
        return ' <span class="tag">' .. ("0x%08X"):format(v) .. "</span>"
    end
    return ""
end

local function propsTable(cls, skip)
    local names = {}
    for k in pairs(cls._spec or {}) do
        if not (skip and skip[k]) then names[#names + 1] = k end
    end
    table.sort(names)
    if #names == 0 then return "" end
    local rows = {}
    for _, k in ipairs(names) do
        local spec = cls._spec[k]
        rows[#rows + 1] = ("<tr><td><code>%s</code></td><td>%s</td><td>%s%s</td></tr>")
            :format(k, specType(spec), fmtDefault(spec.default), colorTag(spec.default))
    end
    return "<table><tr><th>property</th><th>spec</th><th>default</th></tr>"
        .. table.concat(rows) .. "</table>"
end

local function partList(cls)
    local names = {}
    for k in pairs(cls.parts or {}) do names[#names + 1] = k end
    table.sort(names)
    if #names == 0 then return "" end
    local codes = {}
    for _, n in ipairs(names) do codes[#codes + 1] = "<code>" .. esc(n) .. "</code>" end
    return "<h3>Parts (node:getPart)</h3><p>" .. table.concat(codes, " · ") .. "</p>"
end

-- ----------------------------------------------------------------------
-- CSS + page frame (standalone file:// site, no external assets)
-- ----------------------------------------------------------------------
local CSS = [[
:root { --bg:#0f172a; --panel:#1e293b; --panel2:#273449; --ink:#e2e8f0;
        --dim:#94a3b8; --acc:#38bdf8; --line:#334155; --code:#0b1220; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink);
       font:15px/1.55 "Segoe UI",system-ui,sans-serif; }
nav { position:fixed; top:0; left:0; bottom:0; width:232px; overflow-y:auto;
      background:var(--panel); border-right:1px solid var(--line); padding:18px 14px; }
nav h1 { font-size:15px; margin:0 0 2px; color:var(--acc); }
nav .sub { font-size:11px; color:var(--dim); margin-bottom:14px; }
nav a { display:block; color:var(--ink); text-decoration:none; padding:6px 8px;
        border-radius:6px; font-size:13.5px; }
nav a:hover, nav a.on { background:var(--panel2); color:var(--acc); }
main { margin-left:232px; padding:30px 44px 80px; max-width:980px; }
h1 { font-size:26px; margin:0 0 6px; } h1 .v { color:var(--acc); font-size:15px; }
h2 { font-size:19px; margin:34px 0 8px; color:var(--acc);
     border-bottom:1px solid var(--line); padding-bottom:6px; }
h3 { font-size:16px; margin:22px 0 6px; }
p { margin:8px 0; } p.lead { color:var(--dim); margin-bottom:18px; }
code { font:12.5px/1.5 Consolas,"Cascadia Mono",monospace; }
code { background:var(--code); color:#93c5fd; padding:1.5px 5px; border-radius:4px; }
pre { background:var(--code); border:1px solid var(--line); border-radius:8px;
      padding:12px 14px; overflow-x:auto; color:#dbeafe; }
pre code { background:transparent; padding:0; color:inherit; }
table { border-collapse:collapse; width:100%; margin:10px 0 18px; font-size:13.5px; }
th, td { border:1px solid var(--line); padding:6px 10px; text-align:left; vertical-align:top; }
th { background:var(--panel2); color:var(--acc); font-weight:600; }
tr:nth-child(even) td { background:var(--panel); }
td code, th code { background:transparent; padding:0; color:#7dd3fc; }
.ev { color:#fbbf24; }
.tag { display:inline-block; background:var(--panel2); border:1px solid var(--line);
       color:var(--dim); font-size:11px; border-radius:10px; padding:1px 8px; margin-left:6px; }
.card { background:var(--panel); border:1px solid var(--line); border-radius:10px;
        padding:14px 18px; margin:10px 0; }
ul { padding-left:22px; } li { margin:4px 0; }
]]

local function page(file, title, active, body)
    local nav = {}
    local links = {
        { "index.html", "Overview" }, { "api.html", "ui handle API" },
        { "widgets.html", "Widgets" }, { "theme.html", "Themes" },
        { "translate.html", "Translate" }, { "settings.html", "Settings" },
        { "advanced.html", "Advanced" },
    }
    for _, l in ipairs(links) do
        nav[#nav + 1] = ('<a href="%s"%s>%s</a>'):format(
            l[1], l[1] == active and ' class="on"' or "", l[2])
    end
    local html = table.concat({
        "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">",
        "<title>", esc(title), " — DXUI wiki</title>",
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
        "<style>", CSS, "</style></head><body>",
        "<nav><h1>DXUI</h1><div class=\"sub\">retained-mode UI for MTA:SA</div>",
        table.concat(nav), "</nav><main>", body, "</main></body></html>",
    })
    local out = io.open(OUT .. file, "w")
    if not out then error("cannot write " .. OUT .. file) end
    out:write(html)
    out:close()
    print("wrote " .. file)
end

-- ----------------------------------------------------------------------
-- curated widget prose (props/parts are REFLECTED; prose is curated)
-- ----------------------------------------------------------------------
local W = {}
W.Panel = { summary = "Static surface — the base of every bordered widget.",
    example = "local p = ui:panel({ x=0, y=0, width=100, height=60, radius=8 })" }
W.Label = { summary = "Auto-sizing text with wrap/ellipsis and translation binding.",
    example = 'local l = ui:label({ x=0, y=0, text="Hello" })\nl:setTextKey("greeting")' }
W.Button = {
    summary = "Clickable surface with hover/pressed/focused states and themed colors.",
    events = "click",
    example = [[local btn = ui:button({ x=0, y=0, width=100, height=28, text="OK" })
btn:on("click", function() save() end)]],
}
W.Image = { summary = "Texture quad with sections, color tint and effects (blur/mask).",
    example = 'local i = ui:image({ x=0, y=0, width=64, height=64, texture="icons/x.png" })' }
W.Window = {
    summary = "Titled panel: the header DRAGS the window (clamped so it stays "
        .. "reachable), a close-button part emits \"close\", children live in "
        .. "the content part.",
    events = "close",
    example = [[local w = ui:window({ x=40, y=40, width=360, height=300, title="Settings" })
ui:add(w)
w:on("close", function(n) n.visible = false end)
w:container():addChild(ui:button({ x=10, y=10, width=100, height=28, text="Hi" }))]],
}
W.Checkbox = { summary = "Toggling checkbox with a square indicator and a label.",
    events = "change",
    example = [[local cb = ui:checkbox({ x=0, y=0, width=160, height=20, text="Remember" })
cb:on("change", function(_, on) intro = not on end)]] }
W.RadioButton = {
    summary = "Radio option; use a RadioGroup for mutual exclusivity.",
    events = "change",
    example = [[local grp = ui:radiogroup({ x=0, y=0, gap=4 })
for _, name in ipairs({ "Easy", "Hard" }) do
    grp:addRadio(ui:radiobutton({ width=120, text=name }))
end]],
}
W.GridList = {
    summary = "Vertical row list: click selects, wheel scrolls; rows come from "
        .. "the items table, height follows the themed rowHeight.",
    events = "select",
    example = [[local gl = ui:gridlist({ x=0, y=0, width=200, height=140 })
gl.items = { "Red", "Green", "Blue" }
gl:on("select", function(_, i, item) print(i, item) end)]],
}
W.ComboBox = {
    summary = "Selection box with a dropdown; opens on click, closes on "
        .. "outside click or selection.",
    events = "select",
    example = [[local cb = ui:combobox({ x=0, y=0, width=160, items={ "a", "b", "c" } })
cb:on("select", function(_, i, item) end)]] }
W.Edit = {
    summary = "Single-line text input. Caret modes (blink/solid/off), "
        .. "shift-selection, maxLength, readOnly, masked display, alignment; "
        .. "the placeholder hides on focus and the caret appears at once. "
        .. "The caret is a per-frame OVERLAY — blinking never invalidates "
        .. "the cached render list.",
    events = "change, submit, focus, blur",
    example = [[local ed = ui:edit({ x=0, y=0, width=220, height=26, placeholder="Name" })
ed:on("submit", function(_, text) save(text) end)
ed.caretMode = "solid"   -- "blink" (default) | "solid" | "off"
ed.maxLength = 24        -- 0 = unlimited]],
}
W.Slider = { summary = "Horizontal range slider (0..100) with drag + wheel control.",
    events = "change, drag-start, drag-end",
    example = [[local s = ui:slider({ x=0, y=0, width=200, value=30 })
s:on("change", function(_, v) print(v) end)]] }
W.ProgressBar = { summary = "Fill bar showing 0..100 progress.",
    example = "local bar = ui:progressbar({ x=0, y=0, width=200, height=8, value=50 })" }
W.ScrollPanel = {
    summary = "Scrollable viewport over tall content; wheel + drag scroll.",
    events = "scroll",
    example = [[local sp = ui:scrollpanel({ x=0, y=0, width=200, height=150 })
sp:container():addChild(ui:panel({ x=0, y=0, width=180, height=600 }))]] }
W.TabPanel = {
    summary = "Tab strip + pages; only the active page is visible. Pages "
        .. "parent to the content part.",
    example = [[local tp = ui:tabpanel({ x=0, y=0, width=300, height=200, labels={ "A", "B" } })
tp:addPage(ui:label({ text="page A" }))]] }
W.Popup = { summary = "Floating anchored container; outside clicks close it.",
    events = "popup-close", example = [[local pp = ui:popup({ x=100, y=100, width=180, height=90 })
pp:open()]] }
W.ContextMenu = {
    summary = "Popup menu; opens at a point, closes on outside click or "
        .. "after a selection.",
    events = "popup-close (per-item onSelect callbacks)",
    example = [[local m = ui:contextmenu({ items = {
    { text = "Copy",  onSelect = function() copy() end },
    { text = "Paste", onSelect = function() paste() end },
} })
ui:add(m)
m:open(120, 80)]] }
W.Modal = {
    summary = "Dimmed full-screen overlay + centered dialog. Blocks input "
        .. "outside; closing a mid-stack modal removes only THAT modal.",
    events = "close",
    example = [[local md = ui:modal({ width=280, height=120 })
md:container():addChild(ui:label({ text="Sure?" }))
md:open()   -- pushes the dispatcher modal stack
md:close()  -- emits "close"]] }
W.Tooltip = {
    summary = "Floating label attached to a target; shows on hover, anchored "
        .. "top/bottom/left/right.",
    example = [[local tip = ui:tooltip({ text="Click to save" })
ui:add(tip)
tip:attach(button, "bottom")]] }

local WIDGET_ORDER = { "Panel", "Label", "Button", "Image", "Window", "Checkbox",
    "RadioButton", "GridList", "ComboBox", "Edit", "Slider", "ProgressBar",
    "ScrollPanel", "TabPanel", "Popup", "ContextMenu", "Modal", "Tooltip" }

-- base Node props to exclude from every widget's table (documented once)
local BASE_PROPS = {
    x = true, y = true, width = true, height = true, visible = true,
    opacity = true, color = true, font = true, layer = true, zIndex = true,
    anchor = true, margin = true, padding = true, clip = true, clipMode = true,
    layoutMode = true, layoutWidth = true, layoutHeight = true, wrap = true,
    autoSize = true, align = true, valign = true, textKey = true,
    interactive = true, focusable = true, enabled = true, userData = true,
    style = true, name = true, id = true, text = true,
}

-- ----------------------------------------------------------------------
-- widgets.html
-- ----------------------------------------------------------------------
do
    local b = {}
    b[#b + 1] = [[<h1>Widgets <span class="v">factory reference</span></h1>
<p class="lead">Every widget is created through its <code>ui:&lt;name&gt;(props)</code>
factory. Factories are synthesized from the widget registry: any registered
class gains one automatically. Property tables below are REFLECTED from the
live spec tables — they are always exact. Inherited base properties
(x, y, width, height, visible, opacity, color, font, layer, zIndex, clip,
margin, padding, layoutMode, interactive, focusable, enabled, textKey ...)
are documented in the ui handle page and omitted here.</p>]]
    for _, cname in ipairs(WIDGET_ORDER) do
        local cls = DXUI.Widgets[cname]
        if cls then
            local info = W[cname] or {}
            local factory = cname:lower()
            b[#b + 1] = ('<h2 id="%s">ui:%s(props) <span class="tag">%s</span></h2>')
                :format(factory, factory, cname)
            b[#b + 1] = "<p>" .. esc(info.summary or "") .. "</p>"
            if info.events and info.events ~= "" then
                b[#b + 1] = ('<p><strong>Events:</strong> <span class="ev">%s</span></p>')
                    :format(esc(info.events))
            end
            b[#b + 1] = propsTable(cls, BASE_PROPS)
            b[#b + 1] = partList(cls)
            if info.example then
                b[#b + 1] = "<pre><code>" .. esc(info.example) .. "</code></pre>"
            end
        end
    end
    page("widgets.html", "Widgets", "widgets.html", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- api.html
-- ----------------------------------------------------------------------
do
    local M = {
        { "ui = exports.dxui:getUI(name, opts)",
          "name: string · opts: { design = {width,height,mode}, settings, backend?, clock? }",
          "UI handle — the ONLY object consumers touch. One instance per (owner, name); "
          .. "instances of a consumer resource are released when that resource stops.",
          [[local ui = exports.dxui:getUI("app", { design = { width = 800, height = 600 } })]] },
        { "ui:add(node)",
          "node: mounted top-level node",
          "Mounts a node (shortcut for node:setParent(ui.root)).",
          "ui:add(window)" },
        { "ui:<widget>(props)",
          "props: constructor table (any widget properties)",
          "Creates a widget of the factory name; parts are built, themed defaults applied.",
          "local btn = ui:button({ text = \"OK\", x = 0, y = 0, width = 100, height = 28 })" },
        { "ui:widget(name, props)",
          "name: class name (any spelling)",
          "Generic factory for registered classes.",
          "local l = ui:widget('label', { text = 'Hi' })" },
        { "ui:color(r, g, b, a)",
          "0-255 components, a default 255",
          "Packs a 0xAARRGGBB integer (consumers can also write hex ints directly).",
          "btn.textColor = ui:color(255, 90, 90)" },
        { "ui:percent(n) / ui:auto() / ui:fill()",
          "dimension helpers",
          "Compiled dimension forms for layoutWidth/layoutHeight.",
          "panel.layoutWidth = ui:percent(100)" },
        { "ui:texture(path) / ui:font(path, size) / ui:shader(code)",
          "asset sources",
          "Cached resource loads; identical inputs return the SAME resource.",
          "img.texture = ui:texture('icons/x.png')" },
        { "ui:setViewport(w, h)",
          "screen pixels",
          "Recomputes the design->screen mapping (call on resolution changes).",
          "ui:setViewport(1920, 1080)" },
        { "ui:tick()",
          "one per frame",
          "Advances the frame: animations, layout if dirty, rebuild if dirty, "
              .. "draw the cached list. Idle frames do zero rebuild/layout work.",
          "addEventHandler('onClientRender', root, function() ui:tick() end)" },
        { "ui:mouseMove(x, y) / ui:mouseDown(button, x, y) / ui:mouseUp(button, x, y)",
          "SCREEN pixels (mapped to design internally)",
          "Feeds the dispatcher; hit-testing runs over the last collect.",
          "ui:mouseDown('left', 240, 120)" },
        { "ui:scroll(wheel, x, y)",
          "wheel: 1 | -1; screen pixels",
          "Routes the wheel to the topmost scrollable at the point.",
          "ui:scroll(-1, 400, 300)" },
        { "ui:key(keyName, isDown, ...)",
          "MTA key name; extra args ride to handlers (shift modifier)",
          "Routes a key event to the focused node.",
          "ui:key('enter', true)" },
        { "ui:character(ch)",
          "one printable character",
          "Text input for the focused Edit.",
          "ui:character('h')" },
        { "ui:applySettings(t)",
          "partial settings table",
          "Merges over the defaults; every key is consumed by the engine "
              .. "(theme activation and frame priority changes apply live).",
          "ui:applySettings({ defaults = { caretBlinkInterval = 400 } })" },
        { "ui:defineTheme(name, tbl) / ui:setTheme(name|tbl) / ui:getTheme()",
          "theme name or table (tbl.extends names a parent)",
          "Defines/activates themes. setTheme re-applies to every live "
              .. "widget (opt-in transitions animate) and accepts inline tables.",
          "ui:setTheme('dark-compact')" },
        { "ui:addLocale(lang, dict) / ui:setLocale(lang) / ui:getLocale()",
          "lang: 'en' ...; dict: key -> text",
          "Registers/switches THIS instance's locale; re-translates "
              .. "textKey bindings and emits localeChange.",
          "ui:setLocale('ru')" },
        { "ui:tr(key, ...)",
          "key; %1..%N substitution",
          "Returns the translated string for this instance's locale.",
          "label.text = ui:tr('greeting', 'World')" },
        { "ui:setTextKey(key, target, textProp)",
          "binds ANOTHER node from the handle",
          "Sugar: routes to target:setTextKey(key, textProp).",
          "ui:setTextKey('title', win, 'title')" },
        { "ui:destroy()",
          "",
          "Destroys the instance: tree, caches, animations, assets.",
          "ui:destroy()" },
    }
    local b = {}
    b[#b + 1] = [[<h1>ui handle <span class="v">the complete public API</span></h1>
<p class="lead">Everything a consumer touches lives on the handle returned by
<code>exports.dxui:getUI()</code>. No engine globals, no context leakage.
In MTA the dxui resource drives the frame loop automatically — the frame/input
methods below are for roll-your-own setups and tests.</p>]]
    for _, m in ipairs(M) do
        b[#b + 1] = "<h2>" .. esc(m[1]) .. "</h2>"
        b[#b + 1] = "<p><strong>Params:</strong> " .. esc(m[2] or "—") .. "</p>"
        b[#b + 1] = "<p>" .. esc(m[3]) .. "</p>"
        if m[4] then b[#b + 1] = "<pre><code>" .. esc(m[4]) .. "</code></pre>" end
    end
    b[#b + 1] = [[<h2>Node base API <span class="v">every widget</span></h2>
<p class="lead">Common methods/properties shared by all nodes. Property writes are
funneled through one mutation layer: validation, transforms, owner tracking and
category invalidation happen there. <code>node.prop = v</code> and setters are
equivalent.</p>
<table>
<tr><th>call / property</th><th>meaning</th></tr>
<tr><td><code>node:on(event, fn, id?) / node:off(event, fn)</code></td>
    <td>Bubbling event subscription (id tags an owner group). Handlers may return
    <code>DXUI.STOP</code> to halt propagation.</td></tr>
<tr><td><code>node:emit(event, ...)</code></td><td>Emits to the node, then ancestors.</td></tr>
<tr><td><code>node:setParent(parent) / node:addChild(c) / node:removeChild(c)</code></td>
    <td>Tree moves (mount re-applies theme + translation).</td></tr>
<tr><td><code>node:destroy()</code></td><td>Cascades to children; releases overlays/hit entries.</td></tr>
<tr><td><code>node:setPosition(x,y) / node:getPosition() / node.size / node.position</code></td>
    <td>Position/size sugar + proxied value objects (<code>node.color.r = 255</code> works).</td></tr>
<tr><td><code>node:setState(s) / node:getState()</code></td>
    <td>Visual state machine: normal, hover, pressed, focused, disabled, selected.</td></tr>
<tr><td><code>node:setEnabled(false)</code></td><td>Disables input + applies the disabled style state.</td></tr>
<tr><td><code>node:animate(props, duration?, ease?)</code></td>
    <td>Animates real properties through the mutation layer (owner "system").
    Returns an AnimHandle: <code>:after()</code>, <code>:onDone()</code>, <code>:pause/resume/cancel</code>.</td></tr>
<tr><td><code>node:bringToFront() / node:setZIndex(z) / node:setLayer(l)</code></td>
    <td>Paint-order controls (layer > zIndex > insertion).</td></tr>
<tr><td><code>node:getPart(name) / node:setPart(name, node)</code></td>
    <td>Composite slots (window header/content/closeButton, ...).</td></tr>
<tr><td><code>node.textKey = 'key'</code></td><td>Translation binding on the text (or a target) property.</td></tr>
<tr><td><code>node.userData = anything</code></td><td>Untouched consumer payload.</td></tr>
</table>]]
    b[#b + 1] = [[<h2>Events <span class="v">the full vocabulary</span></h2>
<table>
<tr><th>event</th><th>handler args</th><th>when</th></tr>
<tr><td><code>click</code></td><td>(node, button, x, y)</td><td>press+release on the same node, no drag</td></tr>
<tr><td><code>mousedown / mouseup</code></td><td>(node, button, x, y)</td><td>raw press/release (bubbles)</td></tr>
<tr><td><code>hover-start / hover-end</code></td><td>(node)</td><td>pointer enters/leaves the node</td></tr>
<tr><td><code>drag-start / drag-move / drag-end</code></td><td>(node, x, y)</td><td>press moved beyond 6px; drag routes to the pressed node</td></tr>
<tr><td><code>scroll</code></td><td>(node, wheel)</td><td>wheel over the node (bubbles to scrollables)</td></tr>
<tr><td><code>key</code></td><td>(node, keyName, isDown, ...)</td><td>focused node receives keys (shift modifier appends)</td></tr>
<tr><td><code>character</code></td><td>(node, ch)</td><td>printable input for the focused node</td></tr>
<tr><td><code>focus / blur</code></td><td>(node)</td><td>focusable nodes gain/lose dispatcher focus</td></tr>
<tr><td><code>change / submit / select / close / popup-close / localeChange</code></td><td>widget-specific</td><td>see the widget pages</td></tr>
</table>]]
    page("api.html", "ui handle API", "api.html", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- theme.html
-- ----------------------------------------------------------------------
do
    local b = {}
    b[#b + 1] = [[<h1>Themes <span class="v">tokens, presets, custom themes</span></h1>
<p class="lead">Themes are DATA, not code: a token table (referenced as
<code>@color.primary</code>) plus per-component styles. Built-ins ship in three
palettes (light, dark, green) and three densities (normal, -compact, -full).
Any resource can define its own theme and extend a built-in.</p>]]
    local list = DXUI.Theme.list()
    table.sort(list)
    local names = {}
    for _, n in ipairs(list) do names[#names + 1] = "<code>" .. esc(n) .. "</code>" end
    b[#b + 1] = "<h2>Registered themes (reflected)</h2><p>" .. table.concat(names, " · ") .. "</p>"
    -- reflect the light token table (the base vocabulary)
    local light = DXUI.Tokens.registry["light"]
    if light then
        local rows = {}
        for cat, vals in pairs(light) do
            local keys = {}
            for k in pairs(vals) do keys[#keys + 1] = k end
            table.sort(keys)
            local cells = {}
            for _, k in ipairs(keys) do
                local v = vals[k]
                local shown = type(v) == "number" and ("0x%08X"):format(v) or tostring(v)
                cells[#cells + 1] = "<code>" .. esc(k) .. "</code> <span class=\"tag\">"
                    .. esc(shown) .. "</span>"
            end
            rows[#rows + 1] = ("<tr><td><code>%s</code></td><td>%s</td></tr>")
                :format(cat, table.concat(cells, " "))
        end
        table.sort(rows)
        b[#b + 1] = "<h2>Base token vocabulary <span class=\"tag\">light, reflected</span></h2>"
            .. "<table><tr><th>category</th><th>tokens</th></tr>" .. table.concat(rows) .. "</table>"
    end
    b[#b + 1] = [[<h2>Component styles</h2>
<p>Every widget has a themed section. Inside a theme table:</p>
<pre><code>ui:defineTheme("brand", {
    extends = "dark",                    -- optional parent (deep merge)
    tokens = { color = { primary = 0xFF22D3EE } },
    components = {
        button = {
            props  = { textColor = "@color.onPrimary" },  -- @token refs
            states = { hover = { color = "@color.primaryHover" } },
        },
        window = { props = { radius = 10 } },
    },
})</code></pre>
<ul>
<li><code>props</code>/<code>base</code> are aliases (both accepted; child base wins over parent props).</li>
<li>Asset prefixes: <code>"texture:icons/x.png"</code> and <code>"font:Roboto.ttf:12"</code> load cached resources for themed values.</li>
<li>State sections apply on set-state; with an opt-in <code>transition = { duration, easing }</code> they animate (colors lerp per channel).</li>
<li><code>ui:setTheme(name)</code> re-applies to every live widget instantly; mounted-later widgets adopt the active theme on mount.</li>
<li>Ownership: user &gt; system &gt; theme — a themed value never overwrites something the consumer set.</li>
</ul>]]
    page("theme.html", "Themes", "theme.html", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- translate.html
-- ----------------------------------------------------------------------
do
    local b = {}
    b[#b + 1] = [[<h1>Translate <span class="v">per-resource locales, live switching</span></h1>
<p class="lead">Each resource registers its OWN dictionaries and switches its
instance locale at runtime — no engine-wide dictionary, no restart.</p>
<pre><code>ui:addLocale("en", { greeting = "Hello, %1!", save = "Save" })
ui:addLocale("ru", { greeting = "Привет, %1!", save = "Сохранить" })
ui:setLocale("ru")

local l = ui:label({ x = 10, y = 10 })
l:setTextKey("greeting")        -- auto re-translated on every switch

label.text = ui:tr("greeting", "World")   -- one-off lookup, %1 substituted</code></pre>
<ul>
<li><code>node:setTextKey(key, target?)</code> binds the <code>text</code> property by default
(<code>target</code> picks another text property, e.g. the Edit <code>placeholder</code> or the Window <code>title</code>).</li>
<li>Bindings re-resolve on <code>ui:setLocale</code> and on MOUNT (a binding made before
attach resolves against the instance locale as soon as the node mounts).</li>
<li>The instance locale (<code>ui:setLocale</code>) overrides the engine locale
(<code>DXUI.setLocale</code>); unset instances follow the engine locale.</li>
<li><code>ui.root:on("localeChange", fn)</code> (or <code>ui:on</code>) reacts to switches.</li>
</ul>]]
    page("translate.html", "Translate", "translate.html", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- settings.html (reflected from the live Settings table)
-- ----------------------------------------------------------------------
do
    local S = DXUI.Settings
    local b = {}
    b[#b + 1] = [[<h1>Settings <span class="v">engine-wide behavior (reflected)</span></h1>
<p class="lead">Appearance lives in themes; behavior lives here. Merge a
partial table at any time — every key below is consumed by the engine.</p>]]
    local rows = {}
    rows[#rows + 1] = ("<tr><td><code>dev</code></td><td>%s</td><td>validation on every property write; warn on misuse (prod: low overhead)</td></tr>")
        :format(fmtDefault(S.dev))
    rows[#rows + 1] = ("<tr><td><code>errorPolicy</code></td><td>%s</td><td>\"error\" | \"warn\" | \"ignore\" — failing event handlers</td></tr>")
        :format(fmtDefault(S.errorPolicy))
    rows[#rows + 1] = ("<tr><td><code>defaultTheme</code></td><td>%s</td><td>theme activated at bootstrap and when this key is applied</td></tr>")
        :format(fmtDefault(S.defaultTheme))
    rows[#rows + 1] = ("<tr><td><code>designResolution</code></td><td>%s</td><td>default design space for new UI instances; mode stretch|fit</td></tr>")
        :format(fmtDefault(S.designResolution))
    local d = S.defaults
    rows[#rows + 1] = ("<tr><td><code>defaults.animationDuration</code></td><td>%s</td><td>node:animate() default duration (ms)</td></tr>"):format(fmtDefault(d.animationDuration))
    rows[#rows + 1] = ("<tr><td><code>defaults.animationEasing</code></td><td>%s</td><td>default easing name</td></tr>"):format(fmtDefault(d.animationEasing))
    rows[#rows + 1] = ("<tr><td><code>defaults.scrollWheelStep</code></td><td>%s</td><td>ScrollPanel wheel travel (px)</td></tr>"):format(fmtDefault(d.scrollWheelStep))
    rows[#rows + 1] = ("<tr><td><code>defaults.caretBlinkInterval</code></td><td>%s</td><td>Edit caret blink half-period (ms; 0 = solid; the widget's caretBlinkInterval overrides)</td></tr>"):format(fmtDefault(d.caretBlinkInterval))
    rows[#rows + 1] = ("<tr><td><code>resourcePolicy.autoRelease</code></td><td>%s</td><td>release consumer UIs/assets when their resource stops</td></tr>"):format(fmtDefault(S.resourcePolicy.autoRelease))
    rows[#rows + 1] = ("<tr><td><code>performance.screenCulling</code></td><td>%s</td><td>skip render items fully outside the screen</td></tr>"):format(fmtDefault(S.performance.screenCulling))
    rows[#rows + 1] = ("<tr><td><code>performance.maxInteractiveScan</code></td><td>%s</td><td>hit-test scan cap (topmost first)</td></tr>"):format(fmtDefault(S.performance.maxInteractiveScan))
    rows[#rows + 1] = ("<tr><td><code>performance.renderPriority</code></td><td>%s</td><td>onClientRender priority of the frame loop; live re-registration</td></tr>"):format(fmtDefault(S.performance.renderPriority))
    b[#b + 1] = "<table><tr><th>key</th><th>default (reflected)</th><th>consumed by</th></tr>" .. table.concat(rows) .. "</table>"
    b[#b + 1] = [[<pre><code>DXUI.applySettings({
    dev = true,
    defaultTheme = "dark-compact",
    defaults = { caretBlinkInterval = 400 },
})</code></pre>]]
    page("settings.html", "Settings", "settings.html", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- advanced.html
-- ----------------------------------------------------------------------
do
    local b = {}
    b[#b + 1] = [[<h1>Advanced <span class="v">custom widgets, rendering, diagnostics</span></h1>

<h2>Writing a custom widget</h2>
<p>Extend <code>DXUI.Widget</code>, declare property specs, implement
<code>render(renderer)</code> with primitives only (no dx* calls — the renderer
normalizes clip/opacity/design mapping), and register it: registration
synthesizes the factory automatically.</p>
<pre><code>local Badge = DXUI.Widget:extend("Badge", {
    count = { default = 0, type = "number", min = 0,
              invalidates = { DXUI.DIRTY.RENDER } },
    badgeColor = { default = 0xFFEF4444, invalidates = { DXUI.DIRTY.RENDER },
                   transform = DXUI.resolveColor },
})
DXUI.Part.declare(Badge, { "inner" })
function Badge:render(renderer)
    renderer:borderedRect(self.worldX, self.worldY, self.width, self.height,
        self.radius, self.color, self.borderColor, self.borderWidth)
    renderer:text(tostring(self.count), self.worldX, self.worldY,
        self.width, self.height, self.textColor, self.font, "center", "center", 1)
end
DXUI.Builders.register("Badge", Badge)
-- ui:badge({...}) now exists</code></pre>

<h2>Renderer primitives <span class="tag">inside render(renderer)</span></h2>
<table>
<tr><th>call</th><th>params (design space)</th></tr>
<tr><td><code>renderer:rect(x, y, w, h, color)</code></td><td>solid rectangle</td></tr>
<tr><td><code>renderer:roundedRect(x, y, w, h, radii, color)</code></td><td>radii: number | {tl,tr,br,bl}</td></tr>
<tr><td><code>renderer:borderedRect(x, y, w, h, radii, fill, border, borderWidth)</code></td>
    <td>one SDF draw: border ring + fill, per-corner radii, 1px AA; square corners decompose to plain rects</td></tr>
<tr><td><code>renderer:text(str, x, y, w, h, color, font, align, valign, scale)</code></td><td>native text align/valign</td></tr>
<tr><td><code>renderer:image(tex, x, y, w, h, color, rot?, rotX?, rotY?, section?)</code></td><td>texture quad (sections in pixels)</td></tr>
<tr><td><code>renderer:line(x1, y1, x2, y2, color, width)</code></td><td>line segment</td></tr>
</table>

<h2>Overlays <span class="tag">per-frame repaints without invalidation</span></h2>
<p>Widgets that must repaint every frame from the clock (the Edit caret blink)
implement <code>node:overlay(renderer)</code> instead of invalidating: the runtime
draws overlays right after the cached list through the same backend. The
zero-work idle contract holds — 100 idle frames do zero layout/rebuild.</p>

<h2>Effects</h2>
<p><code>node.blur</code> (px) and <code>node.mask</code> (texture path) on any widget or
container; containers composite into an RT group. <code>clipMode = "rt"</code> forces
the RT path. Images accept blur/mask through the shared effects cache —
identical inputs dedupe to one shader instance.</p>

<h2>Diagnostics</h2>
<pre><code>DXUI.Diagnostics.enableZeroWork(ui, true)   -- assert idle frames do zero work
print(DXUI.Diagnostics.describe(ui))        -- per-frame counters summary
local snap = DXUI.Diagnostics.snapshot(ui)  -- frames/layoutRuns/rebuilds/items/draws
DXUI.Diagnostics.idleRatio(ui)              -- >0.5 means a healthy cache</code></pre>

<h2>Easing library</h2>
<p><code>DXUI.Easing</code>: linear, in, out, inout, backIn, backOut, backInOut,
elasticOut, bounceOut (+aliases). Pass a name or a function to
<code>node:animate()</code> and theme transitions.</p>

<h2>Test harness</h2>
<p>The whole engine is pure Lua 5.1 and runs headless: the test harness injects
a table backend and a fake MTA environment, loads meta.xml in dependency
order and drives real dispatcher interactions. The suite lives outside the
shipped resource; the demo smoke suite executes the real demo/client.lua
end-to-end.</p>]]
    page("advanced.html", "Advanced", "advanced.html", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- index.html
-- ----------------------------------------------------------------------
do
    local b = {}
    local themes = DXUI.Theme.list()
    table.sort(themes)
    b[#b + 1] = ([[
<h1>DXUI <span class="v">V4 · retained-mode UI for MTA:SA</span></h1>
<p class="lead">Widgets, a real theme engine, live translations, pooled
retained-mode rendering and headless tests — pure Lua 5.1 on DirectX 9.</p>

<div class="card"><strong>Quick start</strong>
<pre><code>local ui = exports.dxui:getUI("app", { design = { width = 800, height = 600 } })

local win = ui:window({ title = "Hello", x = 40, y = 40, width = 360, height = 300 })
ui:add(win)
win:on("close", function(n) n.visible = false end)
win:container():addChild(ui:button({ x = 10, y = 10, width = 100, height = 28, text = "OK" }))

ui:setTheme("dark-compact")   -- any time, live re-apply
ui:setLocale("ru")            -- your own dictionaries, live re-translate</code></pre>
The engine owns the frame loop, input glue and per-resource cleanup — this
page and the demo resource cover everything else.</div>

<h2>Why this engine</h2>
<ul>
<li><strong>Retained, pooled rendering</strong> — one mutation layer with owner
guards and category dirty flags; idle frames do <em>zero</em> rebuild/layout work
(assert-tested), screen culling, RT compositing only where required.</li>
<li><strong>Theme engine</strong> — design tokens, three palettes × three
densities (%d built-in themes), custom themes with <code>extends</code> from any
resource, per-state styles with opt-in transitions.</li>
<li><strong>Live translation</strong> — per-resource locale tables,
<code>setTextKey</code> bindings, instant switching.</li>
<li><strong>Real inputs</strong> — hover/focus/pressed/drag/modal/popup
dispatcher, caret editing with selection, clamped window drag.</li>
<li><strong>Sane rendering</strong> — one shared SDF rounded-rect shader:
per-corner radii, border+fill in a single draw, square corners bypass the
shader entirely.</li>
<li><strong>Headless tests</strong> — the entire engine runs outside MTA with
an injected backend; the shipped behavior is assert-locked.</li>
</ul>

<h2>Where to read</h2>
<table>
<tr><th>page</th><th>content</th></tr>
<tr><td><a href="api.html">ui handle API</a></td><td>every public method: what it takes, what it returns</td></tr>
<tr><td><a href="widgets.html">Widgets</a></td><td>every widget: reflected property specs, parts, events, examples</td></tr>
<tr><td><a href="theme.html">Themes</a></td><td>registered themes, token vocabulary, defining your own</td></tr>
<tr><td><a href="translate.html">Translate</a></td><td>locales, bindings, live switching</td></tr>
<tr><td><a href="settings.html">Settings</a></td><td>every engine key and what consumes it</td></tr>
<tr><td><a href="advanced.html">Advanced</a></td><td>custom widgets, renderer primitives, overlays, diagnostics</td></tr>
</table>

<h2>Repository layout</h2>
<pre><code>source/settings.lua      engine-wide behavior keys
source/client/core/      node, widget, parts, value objects
source/client/style/     tokens, theme engine, built-in themes
source/client/render/    renderer, pass, backend (the ONLY dx* calls), effects
source/client/input/     dispatcher, hit-test, events
source/client/layout/    dimension/flex/absolute layout passes
source/client/api/       runtime, ui handle, exports, diagnostics
source/client/widgets/   the widget library
source/client/text/      measurement + text layout
demo/                    standalone showcase resource
meta.xml                 MTA manifest (script order = dependency order)</code></pre>]])
        :format(#themes)
    page("index.html", "Overview", "index.html", table.concat(b, "\n"))
end

print("done: 7 pages in " .. OUT)