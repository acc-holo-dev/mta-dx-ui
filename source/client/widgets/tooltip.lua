--[[
    tooltip.lua — DXUI V3 (composite widget)

    Tooltip — small floating label; attach to a node to auto-show on hover:

        local tt = ui:tooltip({ text = "Click to save" })
        tt:attach(button, "right")     -- shows near the button on hover

    Positioning anchors: top|bottom|left|right around the target.
]]

DXUI = DXUI or {}

local Tooltip = DXUI.Widget:extend("Tooltip", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    padX = { default = 8, invalidates = { DXUI.DIRTY.RENDER } },
    padY = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    autoSize = { default = true, invalidates = { DXUI.DIRTY.LAYOUT } },
})

function Tooltip:_measureContent()
    local w = #(self.text or "") * 7 + 2 * (self.padX or 8)
    return w, 15 + 2 * (self.padY or 4)
end

function Tooltip:showAt(x, y)
    self:setPosition(x, y)
    self.visible = true
    self:bringToFront()
    return self
end

function Tooltip:hide()
    self.visible = false
    return self
end

Tooltip._build = function(node)
    node.visible = false
    node.zIndex = 1000 -- topmost layer for tooltips
end

--- Binds to a target node: shows near it on hover-start, hides on hover-end.
function Tooltip:attach(target, anchor)
    self._target = target
    self._anchor = anchor or "top"
    target:setZIndex(0)
    self:setParent(target)
    target:on("hover-start", function()
        self:refresh()
        self.visible = true
    end, "dxui-tooltip")
    target:on("hover-end", function()
        self:hide()
    end, "dxui-tooltip")
    return self
end

function Tooltip:refresh()
    self.autoSize = true
    local t = self._target
    if not t then return end
    local th = 15 + 2 * (self.padY or 4)
    local tw = self.width or 40
    local anchor = self._anchor or "top"
    local tx, ty = t.worldX or 0, t.worldY or 0
    -- the tooltip is PARENTED to its target, so setPosition expects local
    -- coords; convert the intended world anchor point back through the parent
    local p = self._parent
    local lx = (p and p.worldX) or 0
    local ly = (p and p.worldY) or 0
    local wx, wy
    if anchor == "top" then
        wx, wy = tx + (t.width - tw) / 2, ty - th - 6
    elseif anchor == "bottom" then
        wx, wy = tx + (t.width - tw) / 2, ty + t.height + 6
    elseif anchor == "left" then
        wx, wy = tx - tw - 6, ty + (t.height - th) / 2
    else
        wx, wy = tx + t.width + 6, ty + (t.height - th) / 2
    end
    self:setPosition(wx - lx, wy - ly)
end

function Tooltip:render(renderer)
    if not self.visible then return end
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local r = self.radius or 4
    renderer:roundedRect(wx, wy, w, h, r, self.color)
    renderer:text(self.text or "", wx, wy, w, h, self.textColor, self.font, "center", "middle", 1)
end

DXUI.Builders.register("Tooltip", Tooltip)