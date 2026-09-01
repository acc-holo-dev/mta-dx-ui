--[[
    settings.lua — DXUI V3

    Engine settings: ENGINE BEHAVIOR only — never appearance.
    Theme (style/) owns appearance; settings owns behavior:
      - error policy (dev vs prod);
      - scaling / design resolution / quality;
      - defaults (font, animation);
      - resource policy.
]]

DXUI = DXUI or {}

local Settings = {
    -- Dev mode: validation on every write, warn on misuse, pcall listener
    -- isolation. Prod: predictable, low overhead, safe.
    dev = false,

    -- Error behavior: "error" (dev) | "warn" | "ignore".
    errorPolicy = "warn",

    -- Design resolution for NEW UI instances. nil = layout in screen px.
    -- mode: "stretch" (independent axes, default) | "fit" (uniform + letterbox).
    designResolution = { width = nil, height = nil, mode = "stretch" },

    -- Supersampling / quality preset. "auto" picks per hardware at runtime;
    -- "none" = 1x. Higher presets are future work (a configurable quality
    -- strategy, not an automatic 2x assumption).
    quality = "auto",

    -- Defaults for new widgets/animations.
    defaults = {
        -- nil = MTA default font
        font = nil,
        textColor = 0xFFFFFFFF,
        surfaceColor = 0xFF333333,
        -- milliseconds
        animationDuration = 250,
        animationEasing = "inout",
        scrollWheelStep = 40,
    },

    -- Resource policy: auto-release cached MTA resources on the OWNING
    -- resource stop (instances may share global assets — see resources/).
    resourcePolicy = { autoRelease = true },

    -- Performance guardrails (hypothesis-level; tuned by measurement later).
    performance = {
        -- skip items fully outside the screen
        screenCulling = true,
        -- hit-test bucket scan cap
        maxInteractiveScan = 2000,
    },
}

--- Applies a partial settings table over the defaults (cold path).
function DXUI.applySettings(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        if type(v) == "table" and type(Settings[k]) == "table" then
            for k2, v2 in pairs(v) do Settings[k][k2] = v2 end
        else
            Settings[k] = v
        end
    end
    DXUI.config.dev = Settings.dev
end

DXUI.Settings = Settings