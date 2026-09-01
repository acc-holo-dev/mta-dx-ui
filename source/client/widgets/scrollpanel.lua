--[[
    scrollpanel.lua — DXUI V3 (composite widget)

    ScrollPanel — clipped container whose content scrolls on wheel + via
    drag-scrollbars. Content goes into the `content` part; scroll offsets
    move it inside the viewport.

        local sp = ui:scrollpanel({ x=0, y=0, width=200, height=300 })
        sp:container():addChild(someRow)

    wheel: scrollY (and scrollX with shift); scrollbars: track + thumb by
    scroll fraction; thumb drag re-scrolls. Emits "scroll" (x, y).
]]

DXUI = DXUI or {}

local ScrollPanel = DXUI.Widget:extend("ScrollPanel", {
    scrollX = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER } },
    scrollY = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- theme colors: color (groove), thumbColor, thumbHoverColor
    thumbSize = { default = 8, invalidates = { DXUI.DIRTY.RENDER } },
    scrollStep = { default = 48, invalidates = { DXUI.DIRTY.RENDER } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

DXUI.Part.declare(ScrollPanel, { "content" })

--- Local extent of the given node's children (content part coords).
local function contentExtent(node)
    if not node then return 0, 0 end
    local mx, my = 0, 0
    local children = node._children
    for i = 1, #children do
        local c = children[i]
        if c._visible ~= false then
            local x2 = c.x + c.width
            local y2 = c.y + c.height
            if x2 > mx then mx = x2 end
            if y2 > my then my = y2 end
        end
    end
    return mx, my
end

ScrollPanel._build = function(node)
    node.clip = true -- contents never overflow the viewport
    local content = DXUI.Widget:new({})
    node:setPart("content", content)
    node:on("scroll", function(n, wheel)
        n:scrollBy(0, -wheel * (n.scrollStep or 48))
        return true
    end, "dxui-scroll")
end

function ScrollPanel:container()
    return self:getPart("content")
end

--- Fractional scroll (0..1); clamps; moves the content part.
function ScrollPanel:setScroll(x, y)
    if x ~= nil then self.scrollX = x end
    if y ~= nil then self.scrollY = y end
    self:_applyScroll()
    if self.emit then self:emit("scroll", self.scrollX, self.scrollY) end
    return self
end

function ScrollPanel:scrollBy(dx, dy)
    local cx, cy = contentExtent(self:getPart("content"))
    local sx = 0
    local sy = 0
    if cx > self.width then sx = (cx - self.width) or 1 end
    if cy > self.height then sy = (cy - self.height) or 1 end
    local nx = self.scrollX + (sx > 0 and dx / sx or 0)
    local ny = self.scrollY + (sy > 0 and dy / sy or 0)
    if nx < 0 then nx = 0 elseif nx > 1 then nx = 1 end
    if ny < 0 then ny = 0 elseif ny > 1 then ny = 1 end
    if nx ~= self.scrollX or ny ~= self.scrollY then
        self.scrollX, self.scrollY = nx, ny
        self:_applyScroll()
        if self.emit then self:emit("scroll", nx, ny) end
    end
    return self
end

function ScrollPanel:_applyScroll()
    local content = self:getPart("content")
    if not content then return end
    local cx, cy = contentExtent(content)
    local ox = (cx > self.width) and (self.scrollX * (cx - self.width)) or 0
    local oy = (cy > self.height) and (self.scrollY * (cy - self.height)) or 0
    content:setPosition(-ox, -oy)
end

function ScrollPanel:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local cx, cy = contentExtent(self:getPart("content"))
    -- vertical thumb
    if cy > h then
        local th = h * h / cy
        if th < 24 then th = 24 end
        local travel = h - th
        local ty = wy + travel * self.scrollY
        renderer:roundedRect(wx + w - self.thumbSize, ty, self.thumbSize, th,
            self.thumbSize / 2, self._thumbHover and self.thumbHoverColor or self.thumbColor)
    end
    if cx > w then
        local tw = w * w / cx
        if tw < 24 then tw = 24 end
        local travel = w - tw
        local tx = wx + travel * self.scrollX
        renderer:roundedRect(tx, wy + h - self.thumbSize, tw, self.thumbSize,
            self.thumbSize / 2, self.thumbColor)
    end
end

DXUI.Builders.register("ScrollPanel", ScrollPanel)