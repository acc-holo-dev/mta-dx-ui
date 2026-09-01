--[[
    defaults.lua — DXUI V4

    Built-in base theme: "light" (Fluent-Lite). Token sets + component
    styles for the whole widget library. Auto-activates as the current
    theme at load (idempotent; consumers may activate any other built-in
    or define their own — see themes.lua for dark/green/density presets).

    Token reference (all component values go through @tokens so themes stay
    data, not code):
        color:   primary / primaryHover / primaryPressed / onPrimary /
                 surface / surfaceAlt / text / textSecondary / border /
                 danger / success / warning / overlay / tooltipBg
        radius:  sm / md / lg / full
        size:    rowHeight / headerHeight / thumb / sliderThumb
                 (density axis — compact/full presets override these)
        padding: control (edit text inset; density axis)
]]

DXUI = DXUI or {}

local theme = {
    tokens = {
        color = {
            primary = 0xFF2563EB,
            primaryHover = 0xFF1D4ED8,
            primaryPressed = 0xFF1E40AF,
            onPrimary = 0xFFFFFFFF,
            surface = 0xFFFFFFFF,
            surfaceAlt = 0xFFF3F4F6,
            text = 0xFF111827,
            textSecondary = 0xFF6B7280,
            border = 0xFFD1D5DB,
            danger = 0xFFDC2626,
            success = 0xFF16A34A,
            warning = 0xFFD97706,
            overlay = 0x66000000,
            tooltipBg = 0xFF111827,
        },
        radius = {
            sm = 4,
            md = 8,
            lg = 12,
            full = 999,
        },
        size = {
            rowHeight = 22,       -- gridlist / contextmenu / combobox rows
            headerHeight = 28,    -- window header strip
            thumb = 8,            -- scrollpanel scrollbar thumb
            sliderThumb = 14,     -- slider handle
        },
        padding = {
            control = { left = 8, right = 8, top = 0, bottom = 0 },
        },
    },

    components = {
        -- structural surface
        panel = {
            props = { color = "@color.surface", radius = "@radius.md" },
        },

        label = {
            props = { textColor = "@color.text" },
        },

        button = {
            base = {
                color = "@color.primary",
                textColor = "@color.onPrimary",
                radius = "@radius.md",
                borderColor = "@color.primary",
            },
            variants = {
                secondary = {
                    color = "@color.surfaceAlt",
                    textColor = "@color.text",
                    borderColor = "@color.border",
                },
                danger = {
                    color = "@color.danger",
                    textColor = "@color.onPrimary",
                    borderColor = "@color.danger",
                },
                ghost = {
                    -- transparent fill
                    color = 0x00000000,
                    textColor = "@color.text",
                    borderColor = 0x00000000,
                },
            },
            states = {
                hover = { color = "@color.primaryHover" },
                pressed = { color = "@color.primaryPressed" },
                disabled = { textColor = "@color.textSecondary", color = "@color.surfaceAlt" },
            },
        },

        checkbox = {
            props = {
                color = "@color.primary",
                boxColor = "@color.surface",
                borderColor = "@color.border",
                checkedColor = "@color.onPrimary",
                radius = "@radius.sm",
            },
            states = { hover = { borderColor = "@color.primary" }, disabled = {} },
        },

        radiobutton = {
            props = {
                color = "@color.primary",
                boxColor = "@color.surface",
                borderColor = "@color.border",
                checkedColor = "@color.onPrimary",
            },
            states = { hover = { borderColor = "@color.primary" } },
        },

        progressbar = {
            props = {
                color = "@color.primary",
                bgColor = "@color.surfaceAlt",
                radius = "@radius.sm",
            },
        },

        slider = {
            props = {
                color = "@color.primary",
                bgColor = "@color.border",
                thumbColor = "@color.surface",
                thumbBorderColor = "@color.primary",
                thumbSize = "@size.sliderThumb",
            },
        },

        edit = {
            props = {
                bgColor = "@color.surface",
                borderColor = "@color.border",
                focusBorderColor = "@color.primary",
                textColor = "@color.text",
                placeholderColor = "@color.textSecondary",
                radius = "@radius.sm",
                padding = "@padding.control",
            },
            states = { focused = { borderColor = "@color.primary" }, disabled = { bgColor = "@color.surfaceAlt" } },
        },

        window = {
            props = {
                color = "@color.surfaceAlt",
                radius = "@radius.lg",
                titleColor = "@color.text",
                borderColor = "@color.border",
                headerHeight = "@size.headerHeight",
            },
        },

        scrollpanel = {
            props = {
                color = "@color.surfaceAlt",
                thumbColor = "@color.border",
                thumbHoverColor = "@color.textSecondary",
                thumbSize = "@size.thumb",
            },
        },

        combobox = {
            props = {
                color = "@color.surface",
                borderColor = "@color.border",
                textColor = "@color.text",
                radius = "@radius.sm",
                rowHeight = "@size.rowHeight",
            },
            states = { hover = { borderColor = "@color.primary" } },
        },

        tabpanel = {
            props = {
                color = "@color.surface",
                textColor = "@color.textSecondary",
                activeColor = "@color.primary",
                borderColor = "@color.border",
            },
        },

        gridlist = {
            props = {
                color = "@color.surface",
                rowColor = 0x00000000,
                hoverColor = "@color.surfaceAlt",
                selectedColor = "@color.primary",
                selectedTextColor = "@color.onPrimary",
                textColor = "@color.text",
                borderColor = "@color.border",
                rowHeight = "@size.rowHeight",
            },
        },

        popup = {
            props = {
                color = "@color.surface",
                borderColor = "@color.border",
                radius = "@radius.md",
            },
        },

        contextmenu = {
            props = {
                color = "@color.surface",
                hoverColor = "@color.surfaceAlt",
                textColor = "@color.text",
                disabledColor = "@color.textSecondary",
                radius = "@radius.sm",
                rowHeight = "@size.rowHeight",
            },
        },

        modal = {
            props = {
                color = "@color.surface",
                overlay = "@color.overlay",
                radius = "@radius.lg",
            },
        },

        tooltip = {
            props = {
                color = "@color.tooltipBg",
                textColor = "@color.onPrimary",
                radius = "@radius.sm",
            },
        },

        separator = {
            props = { color = "@color.border" },
        },
    },
}

if DXUI.Theme then
    DXUI.Theme.define("light", theme)
    if not DXUI.Theme._currentName then
        DXUI.Theme.activate("light")
    end
end