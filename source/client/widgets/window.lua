---Window — Panel + header (Label) + content container + optional close
---button (DXUI Widget).
---
---    local w = ui:window({ title = "Settings", x=0, y=0, width=320, height=220,
---                          closeButtonVisible = true,
---                          children = { someLabel } })
---    w.header.text = "Settings v2"
---    w:on("close", function(n) n:hide() end)
---    w.hotkeys = { f1 = function(win) win:hide() end }   -- window hotkeys (D6)
---
---title/titleColor are declarative shorthands routed to the header part;
---content fills below the header strip (header overlays, zIndex 2). The
---header DRAGS the whole window (gated by `draggable`); the clamps keep
---part of the header reachable so a window can never be dragged off-screen.
---The closeButton part emits "close" on click — hiding is the consumer's
---decision (Modal/Window decide differently).

DXUI = DXUI or {}

-- Panel must resolve at LOAD time (Window extends it below). Label and
-- Button resolve at BUILD time instead (see buildWindow): by then every
-- widget file has loaded, so a meta.xml reorder cannot silently swap the
-- header/close button for plain Widgets via stale load-time upvalues.
local Panel = DXUI.Widgets.Panel or DXUI.Widget:extend("Panel", {})

local Window = Panel:extend("Window", {
    title = {
        default = "", invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
            local h = node:getPart("header")
            if h then h.text = v end
        end,
    },
    -- window hotkeys (D6): { [keyName] = function(window, keyName, isDown) }
    -- — active while the FOCUS sits inside this window's subtree; matched
    -- in Dispatcher:key BEFORE the focus chain. A handler returning false
    -- lets the key fall through; anything else consumes it. No built-in
    -- defaults (bind escape etc. yourself); do not bind plain typing keys
    -- for windows that contain an Edit/Memo.
    hotkeys = { default = nil, invalidates = {}, validate = function(v)
        if v == nil then return true end
        return type(v) == "table"
    end },
    -- frosted backdrop (E5): strength > 0 blurs the world BEHIND the
    -- window rect before the surface draws (shared half-res screen
    -- source, updated once per frame and only while a backdrop node is
    -- visible — see render/effects.lua)
    backdropBlur = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    titleColor = {
        default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER },
        transform = DXUI.resolveColor, onSet = function(node, v)
            local h = node:getPart("header")
            if h then h.textColor = v end
        end,
    },
    headerHeight = { default = 28, invalidates = { DXUI.DIRTY.LAYOUT }, onSet = function(node)
        -- themed header height may land after build (theme defaults are
        -- applied post-build; live theme switches restyle live windows)
        local header = node:getPart("header")
        if header then header.layoutHeight = { k = "px", v = node.headerHeight } end
        local content = node:getPart("content")
        if content then content.padding = { top = node.headerHeight + 4, left = 10, right = 10, bottom = 10 } end
        local closeButton = node:getPart("closeButton")
        if closeButton then
            closeButton.layoutWidth = { k = "px", v = node.headerHeight }
            closeButton.layoutHeight = { k = "px", v = node.headerHeight }
        end
    end },
    -- header dragging (the window follows the pointer; clamped on-screen)
    draggable = { default = true, invalidates = {} },
    -- close glyph (drawn by the closeButton part, a themed Button)
    closeButtonText = {
        default = "\xD7", invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
            local b = node:getPart("closeButton")
            if b then b.text = v end
        end,
    },
    -- close button part visibility (click emits "close")
    closeButtonVisible = { default = true, invalidates = { DXUI.DIRTY.VISIBILITY }, onSet = function(node, v)
        local b = node:getPart("closeButton")
        if b then b.visible = v end
    end },
})

DXUI.Part.declare(Window, { "header", "content", "closeButton" })

--- Builds the header, content and closeButton parts from declarative props.
local function buildWindow(node, props)
    local headerH = props.headerHeight or node.headerHeight
    local LabelClass = DXUI.Widgets and DXUI.Widgets.Label
    local ButtonClass = DXUI.Widgets and DXUI.Widgets.Button

    local header = LabelClass and LabelClass:new({}) or DXUI.Widget:new({})
    header.text = props.title or ""
    if header.textColor then header.textColor = DXUI.resolveColor(props.titleColor or 0xFF111827) end
    header.layoutWidth = DXUI.percent(100)
    header.layoutHeight = { k = "px", v = headerH }
    header.layoutMode = "relative"
    header.zIndex = 2
    header.align = "left"
    header.valign = "center"
    header.padding = { left = 10, right = 10 }
    -- the header must be hit-testable to press and drag the window
    header.interactive = true
    header.focusable = false

    local content = DXUI.Widget:new({})
    content.layoutMode = "relative"
    content.layoutWidth = DXUI.percent(100)
    content.layoutHeight = DXUI.percent(100)
    content.padding = { top = headerH + 4, left = 10, right = 10, bottom = 10 }
    -- zIndex stays 0: the header (2) and closeButton (3) sort above it,
    -- while user children (also 0, later insertion) sort above IT — a
    -- part must never float above its own children in the hit order
    content.zIndex = 0

    -- close button: a real themed Button part pinned to the window's
    -- top-right corner (relative x=1 = 100% of the content width, anchor
    -- "tr" pulls the box back by its own width). Hover/pressed styling
    -- comes from the button theme component's state blocks.
    local closeButton = ButtonClass and ButtonClass:new({}) or DXUI.Widget:new({})
    closeButton.layoutMode = "relative"
    closeButton.x = 1
    closeButton.y = 0
    closeButton.anchor = "tr"
    closeButton.layoutWidth = { k = "px", v = headerH }
    closeButton.layoutHeight = { k = "px", v = headerH }
    closeButton.zIndex = 3
    closeButton.focusable = false
    closeButton.text = props.closeButtonText or "\xD7"
    closeButton.visible = props.closeButtonVisible ~= false

    node:setPart("header", header)
    node:setPart("content", content)
    node:setPart("closeButton", closeButton)
    node._contentPart = content

    -- drag the window by its header (clamped so the header stays reachable)
    header:on("drag-start", function(_, x, y)
        if not node.draggable or node._destroyed then return end
        node._dragOX, node._dragOY = node.x, node.y
        node._dragPX, node._dragPY = x, y
    end, "dxui-window")
    header:on("drag-move", function(_, x, y)
        local px, py = node._dragPX, node._dragPY
        if px == nil or node._destroyed then return end
        local ctx = node._context
        local lw = ctx and ctx.layoutW or 0
        local lh = ctx and ctx.layoutH or 0
        local nx = node._dragOX + (x - px)
        local ny = node._dragOY + (y - py)
        -- keep at least a 60px strip of the header on-screen
        local margin = 60
        if nx < margin - node.width then nx = margin - node.width end
        if nx > lw - margin then nx = lw - margin end
        if ny < 0 then ny = 0 end
        if ny > lh - 24 then ny = lh - 24 end
        node.x, node.y = nx, ny
    end, "dxui-window")
    header:on("drag-end", function()
        node._dragPX, node._dragPY = nil, nil
    end, "dxui-window")

    -- close button: click -> "close" (hiding is the consumer's decision)
    closeButton:on("click", function()
        if node.emit and not node._destroyed then node:emit("close") end
    end, "dxui-window")
end

Window._build = buildWindow

--- Direct access to the content part (children go here usually).
function Window:container()
    return self:getPart("content")
end

--- Frosted backdrop (E5) under the Panel surface (gradient/texture/border).
function Window:render(renderer)
    local b = self.backdropBlur
    if b and b > 0 and DXUI.Effects and DXUI.Effects.renderBackdrop then
        DXUI.Effects.renderBackdrop(renderer, self, b)
    end
    return DXUI.Widgets.Panel.render(self, renderer)
end

DXUI.Builders.register("Window", Window)