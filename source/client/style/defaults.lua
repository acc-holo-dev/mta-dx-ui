---Built-in base theme: "light" (Fluent-Lite). Token sets + component
---styles for the whole widget library. Auto-activates as the current
---theme at load (idempotent; consumers may activate any other built-in
---or define their own — see themes.lua for dark/green/density presets).
---
---Token reference (all component values go through @tokens so themes stay
---data, not code):
---    color:   primary / primaryHover / primaryPressed / onPrimary /
---             surface / surfaceAlt / text / textSecondary / border /
---             danger / success / warning / overlay / tooltipBg
---    radius:  sm / md / lg / full
---    size:    rowHeight / headerHeight / thumb / sliderThumb
---             (density axis — compact/full presets override these)
---    padding: control (edit text inset; density axis)
---
---Component metrics are kept in components.<name>.metrics so density presets
---can scale geometry without touching widget implementation.

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
            metrics = {
                contentPadding = "@padding.control",
            },
        },

        label = {
            props = { textColor = "@color.text" },
            metrics = {
                shadowOffsetX = 1,
                shadowOffsetY = 1,
            },
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
            metrics = {
                contentPadding = "@padding.control",
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
            -- switch variant example (D5): style="switch" opts a mounted
            -- checkbox into the animated toggle track
            variants = {
                switch = {
                    checkedColor = "@color.primary",
                    switchThumbColor = "@color.onPrimary",
                    indent = 34,
                    transition = { duration = 150, easing = "out" },
                    metrics = { thumbPadding = 2 },
                },
            },
            states = { hover = { borderColor = "@color.primary" }, disabled = {} },
            metrics = {
                boxSize = 18,
                textOffset = 6,
                checkInset = 0.22,
                checkMid = 0.42,
                checkEnd = 0.78,
                checkThickness = 2,
            },
        },

        radiobutton = {
            props = {
                color = "@color.primary",
                boxColor = "@color.surface",
                borderColor = "@color.border",
                checkedColor = "@color.onPrimary",
            },
            states = { hover = { borderColor = "@color.primary" } },
            metrics = {
                dotSize = 18,
                textOffset = 6,
                dotFillRatio = 0.42,
            },
        },

        progressbar = {
            props = {
                color = "@color.primary",
                bgColor = "@color.surfaceAlt",
                radius = "@radius.sm",
            },
            metrics = {
                minFillWidth = 0.5,
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
            metrics = {
                trackHeight = 4,
                filledCutoff = 0.02,
                defaultStep = 0.05,
            },
        },

        edit = {
            props = {
                bgColor = "@color.surface",
                borderColor = "@color.border",
                focusBorderColor = "@color.primary",
                textColor = "@color.text",
                placeholderColor = "@color.textSecondary",
                selectionColor = 0x332563EB,
                radius = "@radius.sm",
                padding = "@padding.control",
            },
            states = { focused = { borderColor = "@color.primary" }, disabled = { bgColor = "@color.surfaceAlt" } },
            metrics = {
                lineHeight = 15,
                caretBlinkInterval = 500,
                caretWidth = 1,
                autoCompleteMax = 8,
                undoCoalesceMs = 300,
            },
        },

        memo = {
            props = {
                bgColor = "@color.surface",
                borderColor = "@color.border",
                focusBorderColor = "@color.primary",
                textColor = "@color.text",
                placeholderColor = "@color.textSecondary",
                selectionColor = 0x332563EB,
                radius = "@radius.sm",
                padding = "@padding.control",
            },
            states = { focused = { borderColor = "@color.primary" }, disabled = { bgColor = "@color.surfaceAlt" } },
            metrics = {
                lineHeight = 15,
                caretBlinkInterval = 500,
                caretWidth = 1,
                scrollStepLines = 3,
                undoCoalesceMs = 300,
            },
        },

        window = {
            props = {
                color = "@color.surfaceAlt",
                radius = "@radius.lg",
                titleColor = "@color.text",
                borderColor = "@color.border",
                headerHeight = "@size.headerHeight",
            },
            metrics = {
                contentPadding = { left = 10, right = 10, top = 10, bottom = 10 },
                closeButtonSize = "@size.headerHeight",
                dragHeaderClamp = 40,
            },
        },

        scrollpanel = {
            props = {
                color = "@color.surfaceAlt",
                thumbColor = "@color.border",
                thumbHoverColor = "@color.textSecondary",
                thumbSize = "@size.thumb",
            },
            metrics = {
                thumbRadius = 999,
                minThumbSize = 24,
                scrollWheelStep = 48,
                scrollInertia = 0,
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
            metrics = {
                caretOffset = 13,
                caretSize = 3,
                caretStroke = 1,
            },
        },

        tabpanel = {
            props = {
                color = "@color.surface",
                textColor = "@color.textSecondary",
                activeColor = "@color.primary",
                borderColor = "@color.border",
            },
            metrics = {
                tabHeight = 26,
                tabPaddingX = 10,
                tabGap = 0,
                indicatorHeight = 2,
                indicatorOffsetY = 2,
            },
        },

        gridlist = {
            props = {
                color = "@color.surface",
                hoverColor = "@color.surfaceAlt",
                selectedColor = "@color.primary",
                selectedTextColor = "@color.onPrimary",
                textColor = "@color.text",
                borderColor = "@color.border",
                rowHeight = "@size.rowHeight",
            },
            metrics = {
                rowTextPadX = 6,
                headerTextPadX = 4,
                headerTextPadRight = 8,
                cellPadX = 4,
                minThumbSize = 20,
                thumbWidth = 6,
                thumbRadius = 3,
                thumbInset = 8,
                sortIconSize = 8,
                rtMarginFactor = 0.5,
            },
        },

        popup = {
            props = {
                color = "@color.surface",
                borderColor = "@color.border",
                radius = "@radius.md",
            },
            metrics = {
                contentPadding = { left = 8, right = 8, top = 8, bottom = 8 },
            },
        },

        contextmenu = {
            props = {
                color = "@color.surface",
                hoverColor = "@color.surfaceAlt",
                textColor = "@color.text",
                disabledColor = "@color.textSecondary",
                borderColor = "@color.border",
                radius = "@radius.sm",
                rowHeight = "@size.rowHeight",
            },
            metrics = {
                itemPadding = { left = 12, right = 12, top = 0, bottom = 0 },
                minWidth = 120,
                separatorInset = 8,
                separatorHeight = 1,
            },
        },

        modal = {
            props = {
                color = "@color.surface",
                overlay = "@color.overlay",
                radius = "@radius.lg",
            },
            metrics = {
                contentWidthPct = 80,
                contentPadding = { left = 12, right = 12, top = 12, bottom = 12 },
            },
        },

        tooltip = {
            props = {
                color = "@color.tooltipBg",
                textColor = "@color.onPrimary",
                radius = "@radius.sm",
            },
            metrics = {
                padX = 8,
                padY = 4,
                anchorGap = 6,
                zIndex = 1000,
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
