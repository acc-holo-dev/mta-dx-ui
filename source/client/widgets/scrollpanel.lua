---ScrollPanel — clipped container whose content scrolls on wheel + via
---drag-scrollbars. Content goes into the `content` part; scroll offsets
---move it inside the viewport.
---
---    local sp = ui:scrollpanel({ x=0, y=0, width=200, height=300 })
---    sp:container():addChild(someRow)
---
---wheel: scrollY (and scrollX with shift); scrollbars: track + thumb by
---scroll fraction; thumb drag re-scrolls. Emits "scroll" (x, y).
---
---Inertia (defaults.scrollInertia, ms; 0 = off): after the last wheel
---notch the scroll GLIDES with an "out"-eased Anim on scrollY — velocity
---estimated from the recent notches; any new notch cancels the glide.
---The glide moves the content but does NOT emit "scroll" events.


DXUI = DXUI or {}

local ScrollPanel = DXUI.Widget:extend("ScrollPanel", {
    scrollX = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node)
        -- direct writes (incl. the inertia Anim) move the content too
        node:_applyScroll()
    end },
    scrollY = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node)
        node:_applyScroll()
    end },
    -- theme colors: color (groove), thumbColor, thumbHoverColor
    thumbSize = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- wheel travel per notch, px; nil = theme metric or engine default
    scrollStep = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
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

--- Creates the content part and wires wheel scrolling (with optional
-- inertia glide — see the file header).
ScrollPanel._build = function(node)
    -- contents never overflow the viewport
    node.clip = true
    local content = DXUI.Widget:new({})
    node:setPart("content", content)
    node:on("scroll", function(n, wheel)
        local step = n:_scrollStep()
        -- a new notch interrupts a running glide (new input always wins)
        local h = n._inertiaAnim
        if h and h.cancel then h:cancel() end
        n._inertiaAnim = nil
        n:scrollBy(0, -wheel * step)
        n:_wheelInertia(wheel, step)
        return true
    end, "dxui-scroll")
end

--- Returns the scrollable content part.
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

--- Scrolls by a pixel delta, clamped to the content extent.
function ScrollPanel:scrollBy(dx, dy)
    local cx, cy = contentExtent(self:getPart("content"))
    local sx = 0
    local sy = 0
    if cx > self.width then sx = cx - self.width end
    if cy > self.height then sy = cy - self.height end
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

--- Effective scrollbar thumb size from prop or theme metric.
function ScrollPanel:_thumbSize()
    return self.thumbSize or self:_metric("thumbSize", 8)
end

--- Effective wheel step from prop, theme metric, or engine default.
function ScrollPanel:_scrollStep()
    return self.scrollStep
        or self:_metric("scrollWheelStep", nil)
        or (DXUI.Settings and DXUI.Settings.defaults and DXUI.Settings.defaults.scrollWheelStep)
        or 48
end

--- Effective inertia window from theme metric or engine default.
function ScrollPanel:_scrollInertia()
    return (DXUI.Settings and DXUI.Settings.defaults and DXUI.Settings.defaults.scrollInertia)
        or self:_metric("scrollInertia", 0)
end

--- Moves the content part to reflect the current scroll fractions.
function ScrollPanel:_applyScroll()
    local content = self:getPart("content")
    if not content then return end
    local cx, cy = contentExtent(content)
    local ox = (cx > self.width) and (self.scrollX * (cx - self.width)) or 0
    local oy = (cy > self.height) and (self.scrollY * (cy - self.height)) or 0
    content:setPosition(-ox, -oy)
end

--- Arms the inertia glide after a wheel notch: velocity from the recent
--- notches (fast bursts average up), continuation distance ∝ velocity,
--- one "out"-eased Anim on scrollY. Off when inertia <= 0.
function ScrollPanel:_wheelInertia(wheel, step)
    local inertia = self:_scrollInertia()
    if inertia <= 0 then return end
    local clock = self._context and self._context.clock
    local now = clock and clock() or 0
    local dy = -wheel * step
    local vel
    local lastT = self._inertiaT
    if lastT and (now - lastT) < 250 then
        -- burst: instantaneous velocity, smoothed toward the last one
        local inst = dy / math.max((now - lastT) / 1000, 0.016)
        vel = (self._inertiaVel or inst) * 0.6 + inst * 0.4
    else
        -- isolated notch: assume a 60 ms notch period
        vel = dy / 0.06
    end
    self._inertiaT = now
    self._inertiaVel = vel
    local _, cy = contentExtent(self:getPart("content"))
    if cy <= self.height then return end
    local sy = cy - self.height
    -- glided distance ∝ velocity × the glide window (px)
    local dist = vel * (inertia / 1000)
    if math.abs(dist) < step * 0.5 then return end
    local targetY = (self.scrollY * sy + dist) / sy
    if targetY < 0 then targetY = 0 elseif targetY > 1 then targetY = 1 end
    if math.abs(targetY - self.scrollY) < 1e-6 then return end
    if not self._context or not self._context.anim then return end
    self._inertiaAnim = self._context.anim:animate(self,
        { scrollY = targetY }, inertia, "out")
end

--- Draws the vertical and horizontal scrollbar thumbs.
function ScrollPanel:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    local cx, cy = contentExtent(self:getPart("content"))
    local thumbSize = self:_thumbSize()
    local thumbRadius = self:_metric("thumbRadius", 999)
    local minThumbSize = self:_metric("minThumbSize", 24)
    -- vertical thumb
    if cy > h then
        local th = h * h / cy
        if th < minThumbSize then th = minThumbSize end
        local travel = h - th
        local ty = wy + travel * self.scrollY
        renderer:roundedRect(wx + w - thumbSize, ty, thumbSize, th,
            thumbRadius, self._thumbHover and self.thumbHoverColor or self.thumbColor)
    end
    if cx > w then
        local tw = w * w / cx
        if tw < minThumbSize then tw = minThumbSize end
        local travel = w - tw
        local tx = wx + travel * self.scrollX
        renderer:roundedRect(tx, wy + h - thumbSize, tw, thumbSize,
            thumbRadius, self.thumbColor)
    end
end

DXUI.Builders.register("ScrollPanel", ScrollPanel)