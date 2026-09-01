---Built-in theme presets (DXUI.Theme registry entries).
---
---Base palettes ("light" from defaults.lua, "dark", "green") combined with
---density presets ("compact" / default / "full") via `extends` inheritance:
---a density preset overrides the `size`/`padding` tokens only, everything
---else (colors, radii, component styles) is inherited from its palette.
---
---Consumers activate any preset by name:
---
---    ui:setTheme("dark-compact")
---
---or define their own in their resource (tokens/components merge over a
---parent the same way):
---
---    ui:defineTheme("brand", { extends = "dark", tokens = { ... } })

DXUI = DXUI or {}

local Theme = DXUI.Theme

if not Theme then return end

-- ----------------------------------------------------------------------
-- palettes
-- ----------------------------------------------------------------------

---Dark palette over the light structure: same components, night colors.
Theme.define("dark", {
    extends = "light",
    tokens = {
        color = {
            primary = 0xFF3B82F6,
            primaryHover = 0xFF2563EB,
            primaryPressed = 0xFF1D4ED8,
            onPrimary = 0xFFFFFFFF,
            surface = 0xFF1F2937,
            surfaceAlt = 0xFF111827,
            text = 0xFFF9FAFB,
            textSecondary = 0xFF9CA3AF,
            border = 0xFF374151,
            danger = 0xFFEF4444,
            success = 0xFF22C55E,
            warning = 0xFFF59E0B,
            overlay = 0x99000000,
            tooltipBg = 0xFF0B1220,
        },
    },
    components = {
        window = { props = { titleColor = "@color.text" } },
        tooltip = { props = { textColor = "@color.text" } },
    },
})

---Green palette: green accents on a light, slightly tinted surface.
Theme.define("green", {
    extends = "light",
    tokens = {
        color = {
            primary = 0xFF16A34A,
            primaryHover = 0xFF15803D,
            primaryPressed = 0xFF166534,
            onPrimary = 0xFFFFFFFF,
            surface = 0xFFF7FBF7,
            surfaceAlt = 0xFFEAF5EA,
            text = 0xFF12291A,
            textSecondary = 0xFF5B7466,
            border = 0xFFC3DBC3,
            danger = 0xFFDC2626,
            success = 0xFF16A34A,
            warning = 0xFFD97706,
            overlay = 0x66000804,
            tooltipBg = 0xFF0F2417,
        },
        radius = {
            sm = 6,
            md = 10,
            lg = 14,
        },
    },
})

-- ----------------------------------------------------------------------
-- density presets (size/padding tokens only)
-- ----------------------------------------------------------------------

---Compact density: denser rows, smaller headers/thumbs, tighter insets.
local COMPACT_TOKENS = {
    size = {
        rowHeight = 18,
        headerHeight = 22,
        thumb = 6,
        sliderThumb = 11,
    },
    padding = {
        control = { left = 6, right = 6, top = 0, bottom = 0 },
    },
}

---Full density: roomier rows, taller headers/thumbs, wider insets.
local FULL_TOKENS = {
    size = {
        rowHeight = 28,
        headerHeight = 34,
        thumb = 11,
        sliderThumb = 18,
    },
    padding = {
        control = { left = 12, right = 12, top = 2, bottom = 2 },
    },
}

for _, palette in ipairs({ "light", "dark", "green" }) do
    Theme.define(palette .. "-compact", { extends = palette, tokens = COMPACT_TOKENS })
    Theme.define(palette .. "-full", { extends = palette, tokens = FULL_TOKENS })
end