---Engine-wide behavior settings (DXUI.Settings).
---
---Every key here is CONSUMED by the engine; appearance lives in the theme
---system (source/client/style/). `DXUI.applySettings(t)` merges a partial
---table over the defaults at any time.
---
---Keys and their consumers:
---   dev                          node validation, event-handler isolation
---   errorPolicy                  failing event handlers: "error" | "warn" | "ignore"
---   defaultTheme                 theme activated at bootstrap / on apply
---   designResolution             default design space for NEW UI instances
---   defaults.animationDuration   node:animate() default duration (ms)
---   defaults.animationEasing     node:animate() default easing name
---   defaults.scrollWheelStep      ScrollPanel wheel travel (px)
---   defaults.caretBlinkInterval   Edit caret blink half-period (ms)
---   defaults.hoverStayDelay     hover held this long fires one-shot "hover-stay" (ms)
---   defaults.doubleClickInterval double-click pairing window (ms)
---   defaults.clickCooldown      click emission rate limit (ms; 0 = off)
---   defaults.editHistoryLimit   Edit undo/redo depth (0 = off)
---   defaults.scrollInertia    ScrollPanel wheel glide (ms; 0 = off)
---   defaults.cursor         Custom per-type pointer cursor (D4; off)
---   resourcePolicy.autoRelease   release consumer UIs/assets on their stop
---   performance.screenCulling    skip off-screen render items
---   performance.maxInteractiveScan hit-test scan cap (topmost first)
---   performance.renderPriority   MTA onClientRender priority (init.lua)
---   defaults.font                system font for fontless text draws
---   defaults.systemInputGuard   ignore keys/characters while the chatbox/console owns input

DXUI = DXUI or {}

-- node.lua creates DXUI.config later (it loads after settings.lua); make
-- the dev flag available here too so applySettings() never indexes nil,
-- no matter when it is called (see DXUI.applySettings below).
DXUI.config = DXUI.config or { dev = false }
DXUI.config.dev = DXUI.config.dev or false

local Settings = {
    -- Dev mode: validation on every property write, warn on misuse.
    -- Prod: predictable, low overhead, safe.
    dev = false,

    -- What happens when an event handler throws:
    --   "error"  — rethrow (crash the frame; use while developing)
    --   "warn"   — warn and skip that handler (production default)
    --   "ignore" — swallow silently
    errorPolicy = "warn",

    -- Theme name activated at bootstrap and whenever this key is applied
    -- (built-ins: light, dark, green + -compact/-full variants; any
    -- ui:defineTheme'd name works too).
    defaultTheme = "light",

    -- Default design space for NEW UI instances created without an
    -- explicit `design`. nil width/height = lay out in screen pixels.
    -- mode: "stretch" (independent axes) | "fit" (uniform + letterbox).
    designResolution = { width = nil, height = nil, mode = "stretch" },

    -- Defaults for new animations and widgets.
    defaults = {
        -- milliseconds
        animationDuration = 250,
        animationEasing = "inout",
        -- ScrollPanel wheel travel, px
        scrollWheelStep = 48,
        -- Edit caret blink half-period, ms (caretBlinkInterval property
        -- overrides this per widget; 0 = solid)
        caretBlinkInterval = 500,
        -- Hover held this long (ms) fires the one-shot "hover-stay"
        -- event on the hovered node (delayed tooltips show on it).
        -- 0 disables the event. See input/dispatcher.lua.
        hoverStayDelay = 400,
        -- Two clicks on the same node within this window (ms) pair into
        -- a "doubleclick" (the second carries click count 2; the first
        -- stays a plain click). 0 disables pairing.
        doubleClickInterval = 300,
        -- Click emission rate limit (ms): a click closer to the previous
        -- one emits nothing (macro-spam guard). 0 (default) = off —
        -- a double-click pair faster than this is swallowed too, so keep
        -- it 0 while doubleclicks matter.
        clickCooldown = 0,
        -- Edit undo/redo chain depth (user edits; ctrl+z/ctrl+y).
        -- 0 disables history. See widgets/edit.lua.
        editHistoryLimit = 64,
        -- Wheel flick glide (ScrollPanel): ms of continued scrolling
        -- after the last wheel notch, velocity from the recent deltas.
        -- 0 (default) = off. See widgets/scrollpanel.lua.
        scrollInertia = 0,
        -- Custom pointer cursor (D4): a per-type image drawn after the
        -- overlays (api/runtime.lua). No built-in assets: configure per
        -- type — { types = { arrow = { texture="cursors/arrow.png",
        -- hotspot={x=0,y=0} }, text = {...}, hand = {...} } } — a type
        -- without a loaded texture keeps the system cursor; hiding the
        -- OS cursor (showCursor) stays the resource's decision.
        -- enabled=false (default) costs nothing.
        cursor = {
            enabled = false,
            scale = 1,   -- design px multiplier
            color = nil, -- tint, 0xAARRGGBB (nil = white)
            types = {},  -- per-type { texture, hotspot = { x, y } }
        },
        -- System font: used by every text draw whose node has no font set
        -- (node font > themed font > this). Spec "path" or "path:size",
        -- resolved once and cached; nil = the MTA built-in font.
        font = nil,
        -- While the chatbox / console / an MTA window owns the keyboard,
        -- onClientKey and onClientCharacter still fire; block them so a
        -- focused Edit does not eat chat input (init.lua). false restores
        -- the pass-through behavior.
        systemInputGuard = true,
    },

    -- Resource policy: auto-release the UI instances and cached MTA assets
    -- a consumer resource owns when that resource stops (see init.lua).
    resourcePolicy = { autoRelease = true },

    -- Performance guardrails.
    performance = {
        -- skip render items fully outside the screen (render/pass.lua)
        screenCulling = true,
        -- hit-test cap: how many topmost interactive nodes a pointer
        -- lookup may scan (input/hit_test.lua)
        maxInteractiveScan = 2000,
        -- MTA onClientRender priority ("low"|"normal"|"high" or number)
        renderPriority = "normal",
    },
}

---Applies a partial settings table over the defaults (cold path).
---Top-level tables merge one level deep; scalars replace.
function DXUI.applySettings(overrides)
    if not overrides then return end
    local themeChanged = false
    local oldPrio = Settings.performance and Settings.performance.renderPriority
    for k, v in pairs(overrides) do
        if type(v) == "table" and type(Settings[k]) == "table" then
            for k2, v2 in pairs(v) do Settings[k][k2] = v2 end
        else
            if k == "defaultTheme" and v ~= Settings.defaultTheme then
                themeChanged = true
            end
            Settings[k] = v
        end
    end
    DXUI.config.dev = Settings.dev
    -- activating the theme is deferred: settings.lua loads before style/
    if themeChanged and DXUI.Theme and DXUI.Theme.activate then
        DXUI.Theme.activate(Settings.defaultTheme)
    end
    -- re-registering the frame handler is deferred: settings.lua loads
    -- before init.lua wires DXUI.setRenderPriority
    local newPrio = Settings.performance and Settings.performance.renderPriority
    if oldPrio ~= nil and newPrio ~= oldPrio and DXUI.setRenderPriority then
        DXUI.setRenderPriority(newPrio)
    end
end

DXUI.Settings = Settings