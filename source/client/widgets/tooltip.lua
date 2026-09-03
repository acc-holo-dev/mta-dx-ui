---Tooltip — small floating label; attach to a node to auto-show on hover:
---
---    local tt = ui:tooltip({ text = "Click to save" })
---    tt:attach(button, "right")     -- shows near the button on hover
---    tt:attach(button, "top", { delay = 400 }) -- delayed (hover-stay)
---
---Positioning anchors: top|bottom|left|right around the target.


DXUI = DXUI or {}

local Tooltip = DXUI.Widget:extend("Tooltip", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    padX = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    padY = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    autoSize = { default = true, invalidates = { DXUI.DIRTY.LAYOUT } },
})

--- Returns padding from explicit prop or theme metrics.
function Tooltip:_padX() return self.padX or self:_metric("padX", 8) end
function Tooltip:_padY() return self.padY or self:_metric("padY", 4) end

--- Returns the anchor gap from theme metrics.
function Tooltip:_anchorGap() return self:_metric("anchorGap", 6) end

--- Intrinsic size while autoSize is on (measured with the real font; the
--- old #text*7 estimate broke with every non-monospace font).
function Tooltip:_measureContent()
    local tw, th
    if DXUI.Text then
        tw, th = DXUI.Text.measure(self.text or "", self.font, 1)
    else
        tw, th = #(self.text or "") * 7, 15
    end
    return tw + 2 * self:_padX(), th + 2 * self:_padY()
end

--- Positions the tooltip in WORLD coords and brings it to the front.
-- The tooltip is PARENTED to its target, so setPosition expects local
-- coords; the intended world anchor point is converted back through the
-- parent's origin (same rule as Tooltip:reposition).
function Tooltip:showAt(x, y)
    local p = self._parent
    local lx = (p and p.worldX) or 0
    local ly = (p and p.worldY) or 0
    self:setPosition(x - lx, y - ly)
    self.visible = true
    self:bringToFront()
    return self
end

--- Hides the tooltip; the node stays mounted (next showAt re-reveals it).
function Tooltip:hide()
    self.visible = false
    return self
end

--- Initial build: tooltips start hidden and float above everything else.
Tooltip._build = function(node)
    node.visible = false
    -- tooltips float above everything else
    node.zIndex = node:_metric("zIndex", 1000)
end

--- Detaches the hover hooks from the target. The handlers live on the
--- TARGET's event map, so Node:destroy's Events.clear(self) cannot reach
--- them — without this the target keeps firing into a dead tooltip.
function Tooltip:_onDestroy()
    local t = self._target
    if t and not t._destroyed and t.off then
        t:off("hover-start", nil, "dxui-tooltip")
        t:off("hover-end", nil, "dxui-tooltip")
        t:off("hover-stay", nil, "dxui-tooltip")
    end
end

--- Binds to a target node: shows near it on hover, hides on hover-end.
--- opts: { delay = ms }. delay 0 (default) shows instantly on
--- hover-start; delay > 0 shows on the one-shot "hover-stay" instead —
--- the dispatcher fires it once the target has been held >=
--- settings.defaults.hoverStayDelay (default 400 ms).
--- Idempotent: a previous binding (same or other target) is removed first —
--- the hooks are id-tagged, so re-attach never stacks duplicate handlers.
function Tooltip:attach(target, anchor, opts)
    Tooltip._onDestroy(self)
    self._target = target
    self._anchor = anchor or "top"
    local delay = (type(opts) == "table" and opts.delay) or 0
    if type(delay) ~= "number" or delay < 0 then delay = 0 end
    self._delay = delay
    self:setParent(target)
    local function show()
        self:reposition()
        self.visible = true
    end
    if delay > 0 then
        target:on("hover-stay", show, "dxui-tooltip")
    else
        target:on("hover-start", show, "dxui-tooltip")
    end
    target:on("hover-end", function()
        self:hide()
    end, "dxui-tooltip")
    return self
end

--- Recomputes position around the attached target for the current anchor.
-- The tooltip is PARENTED to its target, so setPosition expects local
-- coords; the intended world anchor point is converted back through the
-- parent's origin.
function Tooltip:reposition()
    self.autoSize = true
    local t = self._target
    if not t then return end
    -- own height from the same measure the layout uses (_measureContent),
    -- so the anchor math matches the drawn box
    local _, th = self:_measureContent()
    local tw = self.width or 40
    local anchor = self._anchor or "top"
    local tx, ty = t.worldX or 0, t.worldY or 0
    -- the tooltip is PARENTED to its target, so setPosition expects local
    -- coords; convert the intended world anchor point back through the parent
    local p = self._parent
    local lx = (p and p.worldX) or 0
    local ly = (p and p.worldY) or 0
    local wx, wy
    local gap = self:_anchorGap()
    if anchor == "top" then
        wx, wy = tx + (t.width - tw) / 2, ty - th - gap
    elseif anchor == "bottom" then
        wx, wy = tx + (t.width - tw) / 2, ty + t.height + gap
    elseif anchor == "left" then
        wx, wy = tx - tw - gap, ty + (t.height - th) / 2
    else
        wx, wy = tx + t.width + gap, ty + (t.height - th) / 2
    end
    self:setPosition(wx - lx, wy - ly)
end

--- Paints the rounded background + centered text at the current position.
-- Only draws while visible (hidden tooltips emit nothing).
function Tooltip:render(renderer)
    if not self.visible then return end
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local r = self.radius or 4
    renderer:roundedRect(wx, wy, w, h, r, self.color)
    renderer:text(self.text or "", wx, wy, w, h, self.textColor, self.font, "center", "center", 1)
end

DXUI.Builders.register("Tooltip", Tooltip)