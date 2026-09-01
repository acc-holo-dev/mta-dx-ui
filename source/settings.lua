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
---   resourcePolicy.autoRelease   release consumer UIs/assets on their stop
---   performance.screenCulling    skip off-screen render items
---   performance.maxInteractiveScan hit-test scan cap (topmost first)
---   performance.renderPriority   MTA onClientRender priority (init.lua)

DXUI = DXUI or {}

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