---Window — Panel + header (Label) + content container + optional close
---button (DXUI Widget).
---
---    local w = ui:window({ title = "Settings", x=0, y=0, width=320, height=220,
---                          closeButtonVisible = true,
---                          children = { someLabel } })
---    w.header.text = "Settings v2"
---    w:on("close", function(n) n:hide() end)
---
---title/titleColor are declarative shorthands routed to the header part;
---content fills below the header strip (header overlays, zIndex 2). The
---header DRAGS the whole window (gated by `draggable`); the clamps keep
---part of the header reachable so a window can never be dragged off-screen.
---The closeButton part emits "close" on click — hiding is the consumer's
---decision (Modal/Window decide differently).

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
    headerHeight = { default = 28, invalidates = { DXUI.DIRTY.LAYOUT }, onSet = function(node)
        -- themed header height may land after build (theme defaults are
        -- applied post-build; live theme switches restyle live windows)
        local header = node:getPart("header")
        if header then header.layoutHeight = { k = "px", v = node.headerHeight } end
        local content = node:getPart("content")
        if content then content.padding = { top = node.headerHeight + 4, left = 10, right = 10, bottom = 10 } end
    end },
    -- header dragging (the window follows the pointer; clamped on-screen)
    draggable = { default = true, invalidates = {} },
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
    content.zIndex = 1

    -- close button: square pinned to the window's top-right corner
    -- (relative x=1 = 100% of the content width, anchor "tr" pulls the
    -- box back by its own width)
    local btnSize = math.max(12, headerH - 10)
    local closeButton = DXUI.Widget:new({})
    closeButton.layoutMode = "relative"
    closeButton.x = 1
    closeButton.y = 0
    closeButton.anchor = "tr"
    closeButton.layoutWidth = { k = "px", v = headerH }
    closeButton.layoutHeight = { k = "px", v = headerH }
    closeButton.zIndex = 3
    closeButton.interactive = true
    closeButton.focusable = false
    closeButton._closeSize = btnSize
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

    -- close button: hover styling + click -> "close"
    closeButton:on("hover-start", function(b) b:setState("hover") end, "dxui-window")
    closeButton:on("hover-end", function(b) b:setState("normal") end, "dxui-window")
    closeButton:on("click", function()
        if node.emit and not node._destroyed then node:emit("close") end
    end, "dxui-window")
end

Window._build = buildWindow

--- Direct access to the content part (children go here usually).
function Window:container()
    return self:getPart("content")
end

--- Draws the close button: hover-tinted square + a cross.
function Window:renderCloseButton(renderer)
    local b = self:getPart("closeButton")
    if not b or not b.visible then return end
    local size = b._closeSize or 18
    local x = b.worldX + (b.width - size) / 2
    local y = b.worldY + (b.height - size) / 2
    if b:getState() == "hover" then
        renderer:rect(x, y, size, size, self.borderColor or 0x22FF0000)
    end
    local c = self.titleColor or 0xFF111827
    local inset = size * 0.28
    renderer:line(x + inset, y + inset, x + size - inset, y + size - inset, c, 1)
    renderer:line(x + size - inset, y + inset, x + inset, y + size - inset, c, 1)
end

--- Draws the window surface, then the close button decoration.
function Window:render(renderer)
    -- Panel draws the surface
    Panel.render(self, renderer)
    self:renderCloseButton(renderer)
end

DXUI.Builders.register("Window", Window)