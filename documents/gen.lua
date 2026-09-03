---documents/gen.lua — static wiki generator (pure Lua 5.1).
---
---Loads the ENGINE (source/, meta.xml order, no MTA backend) and reflects
---the real registries — widget property specs, parts, themes, tokens,
---settings, easings — then emits the whole documents/ site:
---styles.css, nav.js, search.js (embedded index) and 14 pages.
---Property tables can never drift from the code.
---
---Run from the repo root:  lua5.1 documents/gen.lua

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
    return "<h3>Parts (node:getPart / node:container)</h3><p>"
        .. table.concat(codes, " · ") .. "</p>"
end

local PAGES = {
    { "index.html", "Overview" }, { "quickstart.html", "Quick start" },
    { "concepts.html", "Concepts" }, { "widgets.html", "Widgets" },
    { "theme.html", "Themes" }, { "translate.html", "Translate" },
    { "edit.html", "Edit" }, { "settings.html", "Settings" },
    { "layout.html", "Layout" }, { "animation.html", "Animation" },
    { "render.html", "Rendering" }, { "diagnostics.html", "Diagnostics" },
    { "faq.html", "FAQ" }, { "migration.html", "Migration V3 → V4" },
}

local SEARCH_INDEX = {}

local function page(file, title, active, body)
    local html = table.concat({
        '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">',
        "<title>", esc(title), " — DXUI wiki</title>",
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<link rel="stylesheet" href="styles.css">',
        "</head><body>",
        '<div id="nav"></div><main>', body, "</main>",
        '<script src="nav.js"></script><script src="search.js"></script>',
        "</body></html>",
    })
    local out = io.open(OUT .. file, "w")
    if not out then error("cannot write " .. OUT .. file) end
    out:write(html)
    out:close()
    -- strip tags for the search index
    local text = body:gsub("<[^>]+>", " "):gsub("%s+", " ")
    SEARCH_INDEX[#SEARCH_INDEX + 1] = { url = file, title = title, text = text }
    print("wrote " .. file)
end

-- ----------------------------------------------------------------------
-- styles.css
-- ----------------------------------------------------------------------
local CSS = [[
:root { --bg:#0f172a; --panel:#1e293b; --panel2:#273449; --ink:#e2e8f0;
        --dim:#94a3b8; --acc:#38bdf8; --line:#334155; --code:#0b1220; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink);
       font:15px/1.55 "Segoe UI",system-ui,sans-serif; }
#nav { position:fixed; top:0; left:0; bottom:0; width:232px; overflow-y:auto;
       background:var(--panel); border-right:1px solid var(--line);
       padding:18px 14px; }
#nav h1 { font-size:15px; margin:0 0 2px; color:var(--acc); }
#nav .sub { font-size:11px; color:var(--dim); margin-bottom:12px; }
#nav a { display:block; color:var(--ink); text-decoration:none; padding:6px 8px;
         border-radius:6px; font-size:13.5px; }
#nav a:hover, #nav a.on { background:var(--panel2); color:var(--acc); }
#nav .search { width:100%; background:var(--code); color:var(--ink);
        border:1px solid var(--line); border-radius:6px; padding:6px 8px;
        font:12.5px Consolas,monospace; margin:4px 0 12px; }
#nav .hits a { padding:3px 8px; font-size:12px; color:var(--dim); }
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
kbd { font:12px Consolas,monospace; background:var(--panel2); border:1px solid var(--line);
      border-radius:4px; padding:1px 6px; }
]]

-- ----------------------------------------------------------------------
-- nav.js (one shared sidebar for every page)
-- ----------------------------------------------------------------------
local navLinks = {}
for _, p in ipairs(PAGES) do
    navLinks[#navLinks + 1] = ('{ u: "%s", t: "%s" }'):format(p[1], p[2])
end
local NAV_JS = table.concat({
    "// generated by documents/gen.lua — the shared sidebar + search box",
    "var NAV_PAGES = [\n    " .. table.concat(navLinks, ",\n    ") .. "\n];",
    [[
(function () {
    var here = location.pathname.split("/").pop() || "index.html";
    var html = '<h1>DXUI</h1><div class="sub">retained-mode UI for MTA:SA</div>'
        + '<input class="search" id="q" placeholder="search..." autocomplete="off">'
        + '<div class="hits" id="hits"></div>';
    for (var i = 0; i < NAV_PAGES.length; i++) {
        var p = NAV_PAGES[i];
        var on = p.u === here ? ' class="on"' : "";
        html += '<a href="' + p.u + '"' + on + ">" + p.t + "</a>";
    }
    document.getElementById("nav").innerHTML = html;
    var q = document.getElementById("q");
    var hits = document.getElementById("hits");
    q.addEventListener("input", function () {
        var v = q.value.toLowerCase();
        hits.innerHTML = "";
        if (v.length < 2 || typeof WIKI_INDEX === "undefined") return;
        var n = 0;
        for (var i = 0; i < WIKI_INDEX.length && n < 8; i++) {
            var e = WIKI_INDEX[i];
            if (e.t.toLowerCase().indexOf(v) >= 0 || e.x.toLowerCase().indexOf(v) >= 0) {
                hits.innerHTML += '<a href="' + e.u + '">' + e.t + "</a>";
                n++;
            }
        }
    });
})();
]],
})

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
btn:on("click", function() save() end)]] }
W.Image = { summary = "Texture quad with sections, color tint and effects (blur/mask).",
    example = 'local i = ui:image({ x=0, y=0, width=64, height=64, texture="icons/x.png" })' }
W.Window = {
    summary = "Titled panel: the header DRAGS the window (clamped so it stays "
        .. "reachable), a close-button part (a real themed Button) emits "
        .. "\"close\", children live in the content part.",
    events = "close",
    example = [[local w = ui:window({ x=40, y=40, width=360, height=300, title="Settings" })
ui:add(w)
w:on("close", function(n) n.visible = false end)
w:container():addChild(ui:button({ x=10, y=10, width=100, height=28, text="Hi" }))
w.closeButtonText = "×"          -- themeable glyph
w.closeButtonVisible = false     -- hide the chrome button]] }
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
end]] }
W.GridList = {
    summary = "Vertical row list: click selects, wheel scrolls, the hovered row "
        .. "fills (rows are data, hover follows the pointer via the opt-in "
        .. "pointer-move event).",
    events = "select",
    example = [[local gl = ui:gridlist({ x=0, y=0, width=200, height=140 })
gl.items = { "Red", "Green", "Blue" }
gl:on("select", function(_, i, item) print(i, item) end)]] }
W.ComboBox = {
    summary = "Selection box with a dropdown (real surface + hovered-row "
        .. "fill); the <code>open</code> property is the single source of "
        .. "truth — writing it drives the dropdown part and popup registry.",
    events = "select",
    example = [[local cb = ui:combobox({ x=0, y=0, width=160, items={ "a", "b", "c" } })
cb:on("select", function(_, i, item) end)
cb.open = true      -- property-driven (showDropdown/hideDropdown also exist)]] }
W.Edit = {
    summary = "Single-line text input. Caret modes (blink/solid/off), "
        .. "shift-selection, maxLength, readOnly, masked display, alignment; "
        .. "the placeholder hides on focus and the caret appears at once. "
        .. "The caret is a per-frame OVERLAY — blinking never invalidates "
        .. "the cached render list. See the Edit page for the full guide.",
    events = "change, submit, focus, blur",
    example = [[local ed = ui:edit({ x=0, y=0, width=220, height=26, placeholder="Name" })
ed:on("submit", function(_, text) save(text) end)]] }
W.Slider = { summary = "Horizontal range slider (0..1) with drag + wheel control.",
    events = "change, drag-start, drag-end",
    example = [[local s = ui:slider({ x=0, y=0, width=200, value=0.3 })
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
        .. "after a selection. Hovered entries fill; \"--\" separates.",
    events = "popup-close (per-item onSelect callbacks)",
    example = [[local m = ui:contextmenu({ items = {
    { text = "Copy",  onSelect = function() copy() end },
    "--",
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
are documented in <a href="concepts.html">Concepts</a> and omitted here.
Composites expose their content slot via <code>node:container()</code>.</p>]]
    for _, cname in ipairs(WIDGET_ORDER) do
        local cls = DXUI.Widgets[cname]
        if cls then
            local info = W[cname] or {}
            local factory = cname:lower()
            b[#b + 1] = ('<h2 id="%s">ui:%s(props) <span class="tag">%s</span></h2>')
                :format(factory, factory, cname)
            b[#b + 1] = "<p>" .. (info.summary or "") .. "</p>"
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
    page("widgets.html", "Widgets", "", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- index.html
-- ----------------------------------------------------------------------
do
    local themes = DXUI.Theme.list()
    table.sort(themes)
    local b = {}
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
The engine owns the frame loop, input glue and per-resource cleanup —
<a href="quickstart.html">the quick start</a> covers the rest.</div>

<h2>Why this engine</h2>
<ul>
<li><strong>Retained, pooled rendering</strong> — one mutation layer with owner
guards and category dirty flags; idle frames do <em>zero</em> rebuild/layout work
(assert-tested), screen culling, RT compositing only where required.</li>
<li><strong>Theme engine</strong> — design tokens, %d built-in themes (3 palettes
× 3 densities), custom themes with <code>extends</code> from any resource,
per-state styles with opt-in transitions.</li>
<li><strong>Live translation</strong> — per-resource locale tables,
<code>setTextKey</code> bindings, instant switching.</li>
<li><strong>Real inputs</strong> — hover/focus/press/drag/modal/popup dispatcher,
hover states wired for every widget, caret editing with selection, clamped
window drag.</li>
<li><strong>Sane rendering</strong> — one shared SDF rounded-rect shader:
per-corner radii, border+fill in a single draw, square corners bypass the
shader entirely.</li>
<li><strong>Headless tests</strong> — the entire engine runs outside MTA with
an injected backend; the shipped behavior is assert-locked.</li>
</ul>

<h2>Where to read</h2>
<table>
<tr><th>page</th><th>content</th></tr>
<tr><td><a href="quickstart.html">Quick start</a></td><td>install, first window, the 5-minute tour</td></tr>
<tr><td><a href="concepts.html">Concepts</a></td><td>nodes, properties, ownership, events, states, parts</td></tr>
<tr><td><a href="widgets.html">Widgets</a></td><td>every widget: reflected property specs, parts, events, examples</td></tr>
<tr><td><a href="theme.html">Themes</a></td><td>registered themes, token vocabulary, defining your own</td></tr>
<tr><td><a href="translate.html">Translate</a></td><td>locales, bindings, live switching</td></tr>
<tr><td><a href="edit.html">Edit</a></td><td>the text field deep dive: caret, selection, masking</td></tr>
<tr><td><a href="settings.html">Settings</a></td><td>every engine key and what consumes it</td></tr>
<tr><td><a href="layout.html">Layout</a></td><td>positioning modes, dimensions, anchors, flex</td></tr>
<tr><td><a href="animation.html">Animation</a></td><td>animate, easing, transitions, chaining</td></tr>
<tr><td><a href="render.html">Rendering</a></td><td>frame pipeline, primitives, custom widgets, overlays</td></tr>
<tr><td><a href="diagnostics.html">Diagnostics</a></td><td>counters, the zero-work idle contract</td></tr>
<tr><td><a href="faq.html">FAQ</a></td><td>common questions</td></tr>
<tr><td><a href="migration.html">Migration V3 → V4</a></td><td>every breaking change</td></tr>
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
demo/                    standalone showcase resource
meta.xml                 MTA manifest (script order = dependency order)</code></pre>]])
        :format(#themes)
    page("index.html", "Overview", "", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- quickstart.html
-- ----------------------------------------------------------------------
page("quickstart.html", "Quick start", "", [==[
<h1>Quick start</h1>
<p class="lead">From zero to a running window in two files.</p>

<h2>1. Install</h2>
<p>Copy the <code>dxui</code> resource into your server's resources folder and
start it (the engine ships as ONE resource). In YOUR resource's meta declare
the dependency:</p>
<pre><code>&lt;include resource="dxui" /&gt;</code></pre>

<h2>2. First window</h2>
<pre><code>local ui = exports.dxui:getUI("app", { design = { width = 800, height = 600 } })

local win = ui:window({ title = "Hello", x = 40, y = 40, width = 360, height = 300 })
ui:add(win)
win:on("close", function(n) n.visible = false end)

local btn = ui:button({ x = 10, y = 10, width = 100, height = 28, text = "OK" })
win:container():addChild(btn)
btn:on("click", function()
    win:animate({ opacity = 0.4 }, 150)   -- everything is a property
end)</code></pre>
<p>That is the entire setup: the engine owns the frame loop, the input glue,
the design→screen mapping and per-resource cleanup. When your resource stops,
its UI instances and assets are released automatically.</p>

<h2>3. The 5-minute tour</h2>
<ul>
<li><strong>Properties are the API</strong> — <code>btn.text = "Save"</code>,
<code>panel.color = "@color.primary"</code>, <code>win.visible = false</code>.
Every write is validated and coalesced; nothing repaints needlessly.</li>
<li><strong>Events</strong> — <code>node:on("click", fn)</code>; the full
vocabulary lives in <a href="concepts.html">Concepts</a>.</li>
<li><strong>Themes</strong> — <code>ui:setTheme("dark-compact")</code> restyles
every live widget instantly; define your own with
<a href="theme.html"><code>ui:defineTheme</code></a>.</li>
<li><strong>Text</strong> — bind labels to locale keys with
<a href="translate.html"><code>setTextKey</code></a> and switch languages live.</li>
<li><strong>Run the demo</strong> — copy <code>demo/</code> next to dxui, start
it: every widget, live themes, locales and a settings panel.</li>
</ul>
]==])

-- ----------------------------------------------------------------------
-- concepts.html
-- ----------------------------------------------------------------------
page("concepts.html", "Concepts", "", [==[
<h1>Concepts <span class="v">nodes, properties, events, states, parts</span></h1>
<p class="lead">Five ideas carry the whole engine.</p>

<h2>Node tree</h2>
<p>Everything visible is a <code>Node</code> in a tree owned by the UI instance
(<code>ui.root</code>). <code>ui:add(node)</code> mounts a top-level node;
<code>node:addChild(c)</code> nests. Children inherit clipping, opacity and
the translation/theme context. Destroy cascades.</p>

<h2>One mutation layer</h2>
<p>Every property write — <code>node.x = 10</code>, a setter, an animation tick,
the layout pass, a theme switch — funnels through <code>Node:_set</code>:</p>
<ul>
<li><strong>validate</strong> (spec type/min/max/validate), then
<strong>transform</strong> (colors, dimensions);</li>
<li><code>old == value</code> → early out (write-backs and engine writes are
free and recursion-safe);</li>
<li><strong>ownership</strong>: <code>user</code> &gt; <code>system</code> &gt;
<code>theme</code> — a themed value never overwrites something you set;</li>
<li><strong>category invalidation</strong> (LAYOUT / RENDER / ORDER /
VISIBILITY / INPUT), coalesced into instance flags drained once per frame.</li>
</ul>

<h2>Events</h2>
<table>
<tr><th>event</th><th>handler args</th><th>when</th></tr>
<tr><td><code>click</code></td><td>(node, button, x, y)</td><td>press+release on the same node, no drag; button is <code>"left"</code>/<code>"middle"</code>/<code>"right"</code></td></tr>
<tr><td><code>mousedown / mouseup</code>, <code>press / release</code></td><td>(node, button, x, y)</td><td>raw press/release (bubbling)</td></tr>
<tr><td><code>hover-start / hover-end</code></td><td>(node)</td><td>pointer enters/leaves the node</td></tr>
<tr><td><code>pointer-move</code></td><td>(node, x, y)</td><td>opt-in continuous position: set <code>node._hasPointerMove = true</code>; fires while hovered (GridList uses it for row hover)</td></tr>
<tr><td><code>drag-start / drag-move / drag-end</code></td><td>(node, x, y)</td><td>press moved beyond 6px; drag routes to the pressed node</td></tr>
<tr><td><code>scroll</code></td><td>(node, wheel)</td><td>wheel over the node (bubbles to scrollables)</td></tr>
<tr><td><code>key</code></td><td>(node, keyName, isDown, ...)</td><td>focused node receives keys (shift modifier appended)</td></tr>
<tr><td><code>character</code></td><td>(node, ch)</td><td>printable input for the focused node</td></tr>
<tr><td><code>focus / blur</code></td><td>(node)</td><td>focusable nodes gain/lose dispatcher focus</td></tr>
<tr><td><code>change / submit / select / close / popup-close / localeChange</code></td><td>widget-specific</td><td>see <a href="widgets.html">Widgets</a></td></tr>
</table>
<p>Handlers bubble to ancestors; returning <code>DXUI.STOP</code> halts
propagation. <code>node:on(ev, fn, id)</code> tags a group;
<code>node:off(ev, fn)</code> detaches.</p>

<h2>Visual states</h2>
<p>Every widget is wired at construction: hover/press pointer transitions map
to <code>node:setState("hover"/"pressed")</code>, activating the theme's state
blocks. <strong>Focused is sticky</strong> — while a node is focused (an Edit
being edited) hover/pressed transitions skip it until its blur handler runs.
Release keeps <code>hover</code> while the pointer rests on the node.
Disabled nodes map to the themed <code>disabled</code> state automatically.</p>

<h2>Parts and container()</h2>
<p>Composites own named slots: <code>window.header/content/closeButton</code>,
<code>combobox.head/dropdown</code>, <code>contextmenu.list</code>, …
<code>node:getPart(name)</code> reads one; <code>node:container()</code> is the
unified accessor for the content slot — children go there. Window title and
close glyph are properties (<code>title</code>, <code>closeButtonText</code>)
routed to their parts.</p>

<h2>Base property vocabulary</h2>
<table>
<tr><th>property</th><th>meaning</th></tr>
<tr><td><code>x, y, width, height</code></td><td>design-space box (see <a href="layout.html">Layout</a>)</td></tr>
<tr><td><code>visible, opacity</code></td><td>visibility (hiding also leaves the hit-test list), 0..1 alpha</td></tr>
<tr><td><code>color, textColor</code></td><td>packed 0xAARRGGBB or <code>"#hex"</code> or <code>ui:color(r,g,b,a)</code>; <code>node.color.r = 255</code> works</td></tr>
<tr><td><code>font</code></td><td>handle from <code>ui:font(path, size)</code>; nil falls back to the system font then the engine default</td></tr>
<tr><td><code>layer, zIndex</code></td><td>paint order (layer &gt; zIndex &gt; insertion)</td></tr>
<tr><td><code>clip, clipMode</code></td><td>child clipping ("rt" forces the render-target path)</td></tr>
<tr><td><code>margin, padding</code></td><td>outer spacing / inner content inset</td></tr>
<tr><td><code>interactive, focusable, enabled</code></td><td>input surface switches</td></tr>
<tr><td><code>textKey</code></td><td>translation binding (see <a href="translate.html">Translate</a>)</td></tr>
<tr><td><code>style</code></td><td>named theme variant of the widget ("secondary", "ghost", ...)</td></tr>
<tr><td><code>userData</code></td><td>untouched consumer payload</td></tr>
</table>
]==])

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
    b[#b + 1] = "<h2>Registered themes (reflected)</h2><p>"
        .. table.concat(names, " · ") .. "</p>"
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
                local shown
                if type(v) == "number" then
                    shown = ("0x%08X"):format(v)
                elseif type(v) == "table" then
                    -- stable, readable form (e.g. the padding.control box),
                    -- NEVER a memory address: regeneration must be
                    -- byte-identical or the CI wiki-freshness check fails
                    local parts = {}
                    for k2, v2 in pairs(v) do parts[#parts + 1] = tostring(k2) .. "=" .. tostring(v2) end
                    table.sort(parts)
                    shown = "{" .. table.concat(parts, ", ") .. "}"
                else
                    shown = tostring(v)
                end
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
            base    = { textColor = "@color.onPrimary" },  -- @token refs
            states  = { hover = { color = "@color.primaryHover" } },
        },
        window = { props = { radius = 10 } },
    },
})</code></pre>
<ul>
<li><code>props</code>/<code>base</code> are aliases (both accepted; child base wins over parent props).</li>
<li><code>variants</code> = named styles selected with <code>node.style</code> ("secondary", "danger", "ghost").</li>
<li>Asset prefixes: <code>"texture:icons/x.png"</code> and <code>"font:Roboto.ttf:12"</code> load cached resources for themed values.</li>
<li>State sections apply through the pointer wiring (hover/pressed/focused/selected/disabled); an opt-in <code>transition = { duration, easing }</code> animates state changes (colors lerp per channel).</li>
<li><code>ui:setTheme(name)</code> re-applies to every live widget instantly; mounted-later widgets adopt the active theme on mount.</li>
<li>Ownership: user &gt; system &gt; theme — a themed value never overwrites something the consumer set.</li>
</ul>]]
    page("theme.html", "Themes", "", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- translate.html
-- ----------------------------------------------------------------------
page("translate.html", "Translate", "", [==[
<h1>Translate <span class="v">per-resource locales, live switching</span></h1>
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
<li>Fallback chain: exact locale → base locale (<code>ru-RU</code> → <code>ru</code>) → the key itself.</li>
<li>The instance locale (<code>ui:setLocale</code>) overrides the engine locale
(<code>DXUI.setLocale</code>); unset instances follow the engine locale.</li>
<li><code>ui.root:on("localeChange", fn)</code> (or <code>ui:on</code>) reacts to switches.</li>
</ul>
]==])

-- ----------------------------------------------------------------------
-- edit.html
-- ----------------------------------------------------------------------
do
    local Edit = DXUI.Widgets.Edit
    local b = {}
    b[#b + 1] = [[<h1>Edit <span class="v">the text field deep dive</span></h1>
<p class="lead">A single-line input with a real caret: blinking (overlay — never
invalidates the render cache), selection, masking, live constraints.</p>
<pre><code>local ed = ui:edit({ x = 10, y = 10, width = 220, height = 26, placeholder = "Name" })
ed:on("submit", function(_, text) save(text) end)   -- Enter keeps focus
ed:on("change", function(_, text) ... end)
ed:on("blur",   function() ... end)                 -- Escape blurs</code></pre>
<h2>Properties (reflected)</h2>]]
    b[#b + 1] = propsTable(Edit, BASE_PROPS)
    b[#b + 1] = [[<h2>Keyboard model</h2>
<table>
<tr><th>key</th><th>behavior</th></tr>
<tr><td>printable</td><td>insert at the caret (replaces the selection)</td></tr>
<tr><td><kbd>Left</kbd> / <kbd>Right</kbd></td><td>move the caret (Shift extends the selection)</td></tr>
<tr><td><kbd>Home</kbd> / <kbd>End</kbd></td><td>jump to start/end (Shift selects)</td></tr>
<tr><td><kbd>Backspace</kbd> / <kbd>Delete</kbd></td><td>remove before the caret / forward; a selection is removed first</td></tr>
<tr><td><kbd>Enter</kbd></td><td>emits <code>submit</code> with the text; keeps focus</td></tr>
<tr><td><kbd>Escape</kbd></td><td>releases focus</td></tr>
</table>
<h2>Caret details</h2>
<ul>
<li><code>caretMode</code>: <code>"blink"</code> (default, half-period
<code>caretBlinkInterval</code> or the settings default) · <code>"solid"</code> ·
<code>"off"</code>. Blinking is a per-frame OVERLAY: zero render-list rebuilds.</li>
<li>Click positions the caret at the clicked character (byte index); the text
scrolls to keep the caret visible under overflow.</li>
<li><code>masked</code> renders <code>maskChar</code> per byte (the caret/selection
still operate on the real text).</li>
<li><code>placeholder</code> hides on focus by default; opt back in with
<code>placeholderVisibleWhenFocused = true</code>.</li>
<li><code>selectionFrom</code> + <code>caret</code> bracket the selection;
<code>selectionColor</code> is themeable.</li>
</ul>]]
    page("edit.html", "Edit", "", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- settings.html
-- ----------------------------------------------------------------------
do
    local S = DXUI.Settings
    local b = {}
    b[#b + 1] = [[<h1>Settings <span class="v">engine-wide behavior (reflected)</span></h1>
<p class="lead">Appearance lives in themes; behavior lives here. Merge a
partial table at any time — every key below is consumed by the engine.</p>]]
    local rows = {}
    rows[#rows + 1] = ("<tr><td><code>dev</code></td><td>%s</td><td>validation on every property write; warn on misuse</td></tr>")
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
    rows[#rows + 1] = ("<tr><td><code>defaults.caretBlinkInterval</code></td><td>%s</td><td>Edit caret blink half-period (ms; the widget's caretBlinkInterval overrides)</td></tr>"):format(fmtDefault(d.caretBlinkInterval))
    rows[#rows + 1] = ("<tr><td><code>defaults.font</code></td><td>%s</td><td>system font behind every fontless text draw (\"path\" or \"path:size\"; node font &gt; themed font &gt; this)</td></tr>"):format(fmtDefault(d.font))
    rows[#rows + 1] = ("<tr><td><code>resourcePolicy.autoRelease</code></td><td>%s</td><td>release consumer UIs/assets when their resource stops</td></tr>"):format(fmtDefault(S.resourcePolicy.autoRelease))
    rows[#rows + 1] = ("<tr><td><code>performance.screenCulling</code></td><td>%s</td><td>skip render items fully outside the screen</td></tr>"):format(fmtDefault(S.performance.screenCulling))
    rows[#rows + 1] = ("<tr><td><code>performance.maxInteractiveScan</code></td><td>%s</td><td>hit-test scan cap (topmost first)</td></tr>"):format(fmtDefault(S.performance.maxInteractiveScan))
    rows[#rows + 1] = ("<tr><td><code>performance.renderPriority</code></td><td>%s</td><td>onClientRender priority of the frame loop; live re-registration</td></tr>"):format(fmtDefault(S.performance.renderPriority))
    b[#b + 1] = "<table><tr><th>key</th><th>default (reflected)</th><th>consumed by</th></tr>" .. table.concat(rows) .. "</table>"
    b[#b + 1] = [[<pre><code>DXUI.applySettings({
    dev = true,
    defaultTheme = "dark-compact",
    defaults = { caretBlinkInterval = 400, font = "Roboto.ttf:14" },
})</code></pre>
<p><code>ui:applySettings(t)</code> is the per-instance shortcut. Note: the
merge cannot carry <code>nil</code> (Lua table semantics) — reset a raw key
via <code>DXUI.Settings.defaults.font = nil</code> if needed.</p>]]
    page("settings.html", "Settings", "", table.concat(b, "\n"))
end

-- ----------------------------------------------------------------------
-- layout.html
-- ----------------------------------------------------------------------
page("layout.html", "Layout", "", [==[
<h1>Layout <span class="v">boxes, modes, anchors, flex</span></h1>
<p class="lead">Layout runs ONLY when something dirty requires it — a single
two-pass resolve per change.</p>

<h2>Positioning modes (<code>layoutMode</code>)</h2>
<table>
<tr><th>mode</th><th>semantics</th></tr>
<tr><td><code>absolute</code> (default)</td><td>x/y/width/height are design pixels inside the parent's content box</td></tr>
<tr><td><code>relative</code></td><td>x/y are FRACTIONS of the parent content size (0.5 = center); sizes via layoutWidth/Height</td></tr>
<tr><td><code>center</code></td><td>the node centers itself in the parent content box</td></tr>
<tr><td><code>stretch</code></td><td>stretches to the parent content size minus margins</td></tr>
<tr><td><code>fill</code></td><td>participates in flex flow (see below)</td></tr>
</table>

<h2>Dimensions</h2>
<ul>
<li><code>width/height</code> — direct pixels;</li>
<li><code>layoutWidth/layoutHeight</code> — compiled dimensions:
<code>ui:percent(100)</code>, <code>ui:auto()</code> (content-measured),
<code>ui:fill()</code> (flex share);</li>
<li><code>autoSize</code> — text widgets measure themselves (labels, buttons).</li>
</ul>

<h2>Anchors (<code>anchor</code>)</h2>
<p>A two-letter code from <code>t/op/m/c</code> + <code>l/e/m/c</code>:
<code>"tl"</code>, <code>"tr"</code>, <code>"mc"</code>, <code>"me"</code> (middle-end) …
The box is pulled back inside its own footprint along the anchor: a node with
<code>x = 1</code> (relative) and <code>anchor = "tr"</code> pins flush to the
parent's top-right corner (the window close button does exactly this).</p>

<h2>Flex flow</h2>
<p>Set children to <code>layoutMode = "fill"</code> and give the container
<code>flow = "row"</code> (default) / <code>"column"</code> with
<code>gap</code>: siblings share the main axis (weighted by
<code>ui:fill(n)</code>) and stretch on the cross axis.
<code>layoutWidth = ui:fill()</code> without a flow container = share of the
remaining space.</p>

<h2>Spacing</h2>
<p><code>margin</code> (outer) and <code>padding</code> (inner content inset)
are tables: <code>{ left = 10, right = 10, top = 4, bottom = 4 }</code> or a
single number for all sides.</p>

<h2>Examples</h2>
<pre><code>-- a header row pinned under a 28px strip (window pattern)
local content = win:container()
content.padding = { top = 32, left = 10, right = 10 }

-- centered dialog
local md = ui:modal({ width = 280, height = 120 })

-- flush top-right pin
btn.layoutMode, btn.x, btn.y, btn.anchor = "relative", 1, 0, "tr"</code></pre>
]==])

-- ----------------------------------------------------------------------
-- animation.html
-- ----------------------------------------------------------------------
do
    local easings = {}
    if DXUI.Easing then
        for k in pairs(DXUI.Easing) do easings[#easings + 1] = tostring(k) end
        table.sort(easings)
    end
    local names = {}
    for _, e in ipairs(easings) do names[#names + 1] = "<code>" .. esc(e) .. "</code>" end
    local easingLine = table.concat(names, " · ")
    page("animation.html", "Animation", "", [==[
<h1>Animation <span class="v">property tweens through the mutation layer</span></h1>
<p class="lead">Animations write REAL properties through the mutation layer
(owner "system"): validation, ownership and dirty flags apply to every tick.</p>
<pre><code>win:animate({ y = 90 }, 350, "out")        -- duration ms, easing name or fn
      :after({ y = 40 }, 250)             -- chain when the first finishes

local a = panel:animate({ opacity = 0.3 }, 200)
a:pause(); a:resume(); a:cancel()
a:onDone(function() print("done") end)</code></pre>
<ul>
<li>Numbers tween directly; colors lerp PER CHANNEL (0xAARRGGBB packed).</li>
<li>Defaults come from settings: <code>defaults.animationDuration</code>,
<code>defaults.animationEasing</code>.</li>
<li>A user write to an animated property revokes the animation's ownership of
that property (last writer wins).</li>
<li>Theme state transitions (<code>transition = { duration, easing }</code> in
a component) ride the same machinery — opt-in per component, instant by
default.</li>
</ul>
<h2>Easing library (reflected)</h2>
<p>]==] .. easingLine .. [==[</p>
]==])
end

-- ----------------------------------------------------------------------
-- render.html
-- ----------------------------------------------------------------------
page("render.html", "Rendering", "", [==[
<h1>Rendering <span class="v">pipeline, primitives, custom widgets</span></h1>
<p class="lead">One cached, pooled item list; the tree is re-collected ONLY
when dirty. Idle frames draw the cache and do nothing else.</p>

<h2>Frame pipeline</h2>
<pre><code>tick()
  animations update          (early-out when idle)
  layout IF layoutDirty      (walks the tree, writes via _set "system")
  rebuild IF renderDirty     (collect → sort → emit into the pooled list)
  hit-test rebuild IF interactiveDirty
  draw the cached list
  overlays                   (per-frame clock repaints; no invalidation)</code></pre>

<h2>Renderer primitives <span class="tag">inside render(renderer)</span></h2>
<table>
<tr><th>call</th><th>params (design space)</th></tr>
<tr><td><code>renderer:rect(x, y, w, h, color)</code></td><td>solid rectangle</td></tr>
<tr><td><code>renderer:roundedRect(x, y, w, h, radii, color)</code></td><td>radii: number | {lt,tr,br,bl}</td></tr>
<tr><td><code>renderer:borderedRect(x, y, w, h, radii, fill, border, borderWidth)</code></td>
    <td>ONE SDF draw: border ring + fill, per-corner radii, 1px AA; square corners decompose to plain rects</td></tr>
<tr><td><code>renderer:text(str, x, y, w, h, color, font, align, valign, scale)</code></td><td>native text alignment; fontless draws fall back to the system font</td></tr>
<tr><td><code>renderer:image(tex, x, y, w, h, color, rot?, rotX?, rotY?, section?)</code></td><td>texture quad (sections in pixels)</td></tr>
<tr><td><code>renderer:line(x1, y1, x2, y2, color, width)</code></td><td>line segment</td></tr>
</table>

<h2>Rounded corners</h2>
<p>ONE shared SDF shader process-wide (ps_2_0): per-corner radii, border and
fill in a single draw, 1px smoothstep AA. Parameters dedupe on consecutive
draws; square corners bypass the shader entirely. The shader file lives inside
the dxui resource and compiles once at bootstrap.</p>

<h2>Effects</h2>
<p><code>node.blur</code> (px) and <code>node.mask</code> (texture path) on any
widget or container; containers composite into an RT group automatically when
needed. <code>clipMode = "rt"</code> forces the RT path. Identical effect
inputs dedupe to one shader instance (the Effects cache).</p>

<h2>Overlays</h2>
<p>Widgets that must repaint every frame from the clock (the Edit caret blink)
implement <code>node:overlay(renderer)</code> instead of invalidating: the
runtime re-emits overlays right after the cached list through the same
backend. The zero-work idle contract holds — blinking costs zero rebuilds.</p>

<h2>Writing a custom widget</h2>
<p>Extend <code>DXUI.Widget</code>, declare property specs, implement
<code>render(renderer)</code> with primitives only (no dx* calls), and
register it — registration synthesizes the factory automatically.</p>
<pre><code>local Badge = DXUI.Widget:extend("Badge", {
    count = { default = 0, type = "number", min = 0,
              invalidates = { DXUI.DIRTY.RENDER } },
    badgeColor = { default = 0xFFEF4444, invalidates = { DXUI.DIRTY.RENDER },
                   transform = DXUI.resolveColor },
})
function Badge:render(renderer)
    renderer:borderedRect(self.worldX, self.worldY, self.width, self.height,
        self.radius or 0, self.color, self.borderColor, self.borderWidth)
    renderer:text(tostring(self.count), self.worldX, self.worldY,
        self.width, self.height, self.textColor, self.font, "center", "center", 1)
end
DXUI.Builders.register("Badge", Badge)
-- ui:badge({...}) now exists</code></pre>
]==])

-- ----------------------------------------------------------------------
-- diagnostics.html
-- ----------------------------------------------------------------------
page("diagnostics.html", "Diagnostics", "", [==[
<h1>Diagnostics <span class="v">counters + the zero-work idle contract</span></h1>
<p class="lead">The engine measures itself; the test suite assert-locks the
idle behavior.</p>
<pre><code>DXUI.Diagnostics.enableZeroWork(ui, true)   -- HARD-assert idle frames do zero work
local snap = DXUI.Diagnostics.snapshot(ui)  -- frames/layoutRuns/rebuilds/hitRebuilds/items/draws
print(DXUI.Diagnostics.describe(ui))        -- one-line summary
DXUI.Diagnostics.idleRatio(ui)              -- idle frames fraction; >0.9 is healthy
DXUI.Diagnostics.report(ui)                 -- verbose per-counter report</code></pre>

<h2>The zero-work idle contract</h2>
<ul>
<li>An idle frame (no writes, no pointer transitions) performs NO layout, NO
rebuild, NO hit-test rebuild — it draws the cached list and nothing else.</li>
<li>Hover transitions repaint — they are REAL visual changes (themed state
colors) — and coalesce: many transitions inside one frame still cost ONE
rebuild.</li>
<li>The caret blink NEVER rebuilds (overlay path): 100 idle frames of
blinking = zero rebuilds, verified by tests.</li>
<li>One property write = exactly one rebuild; one text write = one layout +
one rebuild.</li>
</ul>

<h2>Reading the numbers</h2>
<table>
<tr><th>counter</th><th>meaning</th></tr>
<tr><td><code>frames</code></td><td>ticks executed</td></tr>
<tr><td><code>layoutRuns</code></td><td>layout passes (dirty-driven)</td></tr>
<tr><td><code>rebuilds</code></td><td>render-list rebuilds</td></tr>
<tr><td><code>hitRebuilds</code></td><td>interactive-list rebuilds</td></tr>
<tr><td><code>items</code></td><td>items in the cached list</td></tr>
<tr><td><code>draws</code></td><td>backend draw calls total</td></tr>
</table>
]==])

-- ----------------------------------------------------------------------
-- faq.html
-- ----------------------------------------------------------------------
page("faq.html", "FAQ", "", [==[
<h1>FAQ</h1>
<p class="lead">Common questions, short answers.</p>

<h2>How do I change the caret blink speed?</h2>
<p>Per widget: <code>ed.caretBlinkInterval = 250</code>. Engine-wide:
<code>ui:applySettings({ defaults = { caretBlinkInterval = 250 } })</code>.
<code>caretMode = "solid"</code> disables blinking entirely.</p>

<h2>How do I change the font everywhere?</h2>
<p><code>ui:applySettings({ defaults = { font = "Roboto.ttf:14" } })</code> —
the system font behind every draw without an explicit font. A themed font on
a component still wins; a per-node <code>font</code> wins over both.</p>

<h2>How do I hide the window close button?</h2>
<p><code>win.closeButtonVisible = false</code>. The glyph is
<code>win.closeButtonText</code> (a themed Button part — restyle it through
the <code>button</code> theme component).</p>

<h2>Why does my themed hover state not show?</h2>
<p>Hover styling comes from the theme's <code>states.hover</code> block —
check it exists for the component and the node is <code>interactive</code>
(or subscribes to input events). Focused nodes deliberately keep their
focused styling until blur.</p>

<h2>Popups vs modals — which one?</h2>
<p><code>Modal</code> blocks ALL outside input (dialog semantics, stacked).
<code>Popup</code>/<code>ContextMenu</code>/the ComboBox dropdown close on the
first outside click. Use modals for confirmations, popups for transient
anchored UI.</p>

<h2>How do row-hover highlights work in GridList?</h2>
<p>GridList rows are data, not child nodes; the list sets
<code>node._hasPointerMove = true</code> and receives continuous
<code>pointer-move</code> events while hovered, invalidating render only when
the hovered ROW index changes. Combobox/contextmenu rows are real child
widgets and hover through the normal hover events.</p>

<h2>Can I run the engine headless / write tests?</h2>
<p>Yes — the engine is pure Lua 5.1 outside two files (backend + init).
Inject a table backend via <code>DXUI.Runtime.backend</code>, a fake clock via
the <code>clock</code> option, and drive input through
<code>ui:mouse*/key/character</code>. The shipped suite works exactly this
way.</p>

<h2>Where is the frame loop?</h2>
<p><code>init.lua</code> registers ONE onClientRender handler (priority from
<code>settings.performance.renderPriority</code>). <code>ui:tick()</code> is
public if you want to drive frames yourself.</p>
]==])

-- ----------------------------------------------------------------------
-- migration.html
-- ----------------------------------------------------------------------
page("migration.html", "Migration V3 → V4", "", [==[
<h1>Migration V3 → V4</h1>
<p class="lead">V4 is a breaking release. Every public change, by area.</p>

<h2>Edit</h2>
<ul>
<li><code>cursor</code> property renamed to <strong><code>caret</code></strong>.</li>
<li>New: <code>caretWidth</code>, <code>caretMode</code> ("blink"|"solid"|"off"),
<code>caretBlinkInterval</code>, <code>selectionFrom</code>/<code>selectionColor</code>,
<code>alignment</code>, <code>maxLength</code>, <code>readOnly</code>,
<code>masked</code>/<code>maskChar</code>, <code>placeholderVisibleWhenFocused</code>.</li>
<li>Click positions the caret (was: focus always moved it to the end). Escape
blurs; Enter submits keeping focus; Delete works; overflow scrolls to keep
the caret visible.</li>
</ul>

<h2>Naming</h2>
<ul>
<li><code>DXUI.EASING</code> → <strong><code>DXUI.Easing</code></strong>.</li>
<li>Key event second parameter <code>pressed2</code> → <strong><code>isDown</code></strong>
(signature <code>(keyName, isDown, ...)</code>; the shift modifier is appended).</li>
<li>Removed dead API: <code>DXUI.Values</code>, <code>Part.themeRole</code>,
<code>Part.replace</code> (use <code>node:setPart</code>).</li>
<li><code>tx_is_separator</code> → <code>isSeparator</code> (internal).</li>
</ul>

<h2>Themes</h2>
<ul>
<li>Built-in theme <code>"default"</code> renamed to <strong><code>"light"</code></strong>;
9 built-ins via density presets (<code>dark-compact</code>, <code>green-full</code>, …).</li>
<li><code>ui:defineTheme(name, tbl)</code> / <code>ui:setTheme(name|table)</code>;
deep-merge <code>extends</code>; asset prefixes (<code>texture:</code>,
<code>font:</code>); opt-in <code>transition</code> blocks per component.</li>
<li>Live switching re-applies to EVERY live widget (better than DGS — created
widgets repaint too); mounted-later widgets adopt on mount.</li>
</ul>

<h2>Factories</h2>
<ul>
<li><code>ui:&lt;widget&gt;()</code> factories are SYNTHESIZED from the widget
registry — every registered class gains one (<code>ui:radiogroup()</code>
appeared). The hardcoded list is gone.</li>
<li>Every composite exposes <code>container()</code> (window, scrollpanel,
tabpanel, combobox, contextmenu, modal, popup).</li>
</ul>

<h2>Window / composites</h2>
<ul>
<li>New <code>closeButton</code> part — a real themed Button — plus
<code>closeButtonText</code> and <code>closeButtonVisible</code> (click emits
<code>"close"</code>).</li>
<li>The header drags the window (clamped on-screen; <code>draggable</code> gates).</li>
<li>TabPanel pages parent to the content part; ComboBox <code>open</code> is a
real driving property (writes sync the dropdown part + popup registry).</li>
</ul>

<h2>Rendering</h2>
<ul>
<li><code>drawRoundedRect(x, y, w, h, rtl, rtr, rbr, rbl, fill, border,
borderWidth)</code> — new signature; render-list <code>rrect</code> items carry
per-corner radii + border fields; ONE SDF shader process-wide.</li>
<li>Removed: <code>Effects.round</code>, <code>Effects.whiteTexture</code>,
<code>Renderer.resolveEffect</code>.</li>
<li>Fontless text draws fall back to the system font
(<code>settings.defaults.font</code>).</li>
</ul>

<h2>Input</h2>
<ul>
<li>Hover/pressed states are wired at construction for every widget (theme
state blocks engage through pointer input); <code>focused</code> is sticky.</li>
<li>New opt-in <code>pointer-move</code> event (continuous position for hovered
opt-ins — row-level hover in data-driven widgets).</li>
<li><code>visible</code> invalidates the input set too — hidden interactive
nodes leave the hit-test list on the next collect.</li>
<li><code>DXUI.setRenderPriority</code> re-registers the frame loop; the mouse
wheel falls back to the screen center when the cursor is disabled.</li>
</ul>
]==])

-- ----------------------------------------------------------------------
-- write styles.css / nav.js / search.js
-- ----------------------------------------------------------------------
local function writeFile(name, content)
    local out = io.open(OUT .. name, "w")
    if not out then error("cannot write " .. OUT .. name) end
    out:write(content)
    out:close()
    print("wrote " .. name)
end

writeFile("styles.css", CSS)
writeFile("nav.js", NAV_JS)

local entries = {}
for _, e in ipairs(SEARCH_INDEX) do
    local text = e.text
    if #text > 4000 then text = text:sub(1, 4000) end
    entries[#entries + 1] = ('{ u: "%s", t: "%s", x: %q }')
        :format(e.url, e.title, text)
end
local SEARCH_JS = table.concat({
    "// generated by documents/gen.lua — the embedded search index",
    "var WIKI_INDEX = [\n    " .. table.concat(entries, ",\n    ") .. "\n];",
})
writeFile("search.js", SEARCH_JS)

print(("done: %d pages + styles.css + nav.js + search.js in %s"):format(#SEARCH_INDEX, OUT))