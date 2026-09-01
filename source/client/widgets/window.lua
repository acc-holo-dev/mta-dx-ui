--[[
    window.lua — DXUI V3 (basic widget)

    Window — Panel + two parts: header (Label) and content (container).

        local w = ui:window({ title = "Settings", x=0, y=0, width=320, height=220,
                              onHeader = { textColor = "#FFFFFF" },
                              children = { someLabel } })
        w.header.text = "Settings v2"

    title/titleColor are declarative shorthands routed to the header part;
    content fills below the header strip (header overlays, zIndex 2).
]]

DXUI = DXUI or {}

local Panel = DXUI.Widgets.Panel or DXUI.Widget:extend("Panel", {})
local LabelClass = DXUI.Widgets and DXUI.Widgets.Label

local Window = Panel:extend("Window", {
    title = {
        default = "", invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
            local h = node:getPart("header")
            if h then h.text = v end
        end,
    },
    titleColor = {
        default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER },
        transform = DXUI.resolveColor, onSet = function(node, v)
            local h = node:getPart("header")
            if h then h.textColor = v end
        end,
    },
    headerHeight = { default = 28, invalidates = { DXUI.DIRTY.LAYOUT } },
})

DXUI.Part.declare(Window, { "header", "content" })

local function buildWindow(node, props)
    local headerH = props.headerHeight or node.headerHeight

    local header = LabelClass and LabelClass:new({}) or DXUI.Widget:new({})
    header.text = props.title or ""
    if header.textColor then header.textColor = DXUI.resolveColor(props.titleColor or 0xFF111827) end
    header.layoutWidth = DXUI.percent(100)
    header.layoutHeight = { k = "px", v = headerH }
    header.layoutMode = "relative"
    header.zIndex = 2
    header.align = "left"
    header.valign = "middle"
    header.padding = { left = 10, right = 10 }

    local content = DXUI.Widget:new({})
    content.layoutMode = "relative"
    content.layoutWidth = DXUI.percent(100)
    content.layoutHeight = DXUI.percent(100)
    content.padding = { top = headerH + 4, left = 10, right = 10, bottom = 10 }
    content.zIndex = 1

    node:setPart("header", header)
    node:setPart("content", content)
    node._contentPart = content
end

Window._build = buildWindow

--- Direct access to the content part (children go here usually).
function Window:container()
    return self:getPart("content")
end

DXUI.Builders.register("Window", Window)