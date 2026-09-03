---Popup — floating surface registered with the dispatcher popup manager:
---opened with a position, closed by outside clicks or explicit close().
---
---    local p = ui:popup({ width=200, height=120, children = { ... } })
---    p:open(120, 80)
---
---Theme: color, borderColor, radius.


DXUI = DXUI or {}

local Popup = DXUI.Widget:extend("Popup", {
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    radius = { default = 8, invalidates = { DXUI.DIRTY.RENDER } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

DXUI.Part.declare(Popup, { "content" })

--- Returns the content padding from theme metrics.
function Popup:_contentPadding()
    return self:_metric("contentPadding", { left = 8, right = 8, top = 8, bottom = 8 })
end

--- Creates the content part and hides the popup until opened.
Popup._build = function(node)
    node.visible = false
    local content = DXUI.Widget:new({})
    content.layoutMode = "relative"
    content.layoutWidth = DXUI.percent(100)
    content.layoutHeight = DXUI.percent(100)
    local pad = node:_contentPadding()
    content.padding = { left = pad.left, right = pad.right, top = pad.top, bottom = pad.bottom }
    node:setPart("content", content)
    node:on("popup-close", function(n)
        n.visible = false
    end, "dxui-popup")
end

--- Returns the content part.
function Popup:container()
    return self:getPart("content")
end

--- Shows the popup at design coords (top-left).
function Popup:open(x, y)
    self:setPosition(x or self.x, y or self.y)
    self.visible = true
    if self._context and self._context.dispatcher then
        self._context.dispatcher:openPopup(self)
    end
    return self
end

--- Hides the popup and unregisters it from the popup manager.
function Popup:close()
    self.visible = false
    if self._context and self._context.dispatcher then
        self._context.dispatcher:closePopup(self)
    end
    return self
end

--- Draws the popup surface.
function Popup:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    renderer:borderedRect(wx, wy, w, h, self.radius or 8, self.color, self.borderColor, self.borderWidth)
end

DXUI.Builders.register("Popup", Popup)