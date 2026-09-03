---Checkbox — box + optional label; toggles on click; emits "change"
---(checked) and keeps `checked` as a real property.
---
---    local cb = ui:checkbox({ text="Enable X", x=0, y=0 })
---    cb:on("change", function(n, checked) ... end)
---
---Switch variant (D5): `variant = "switch"` (or the theme variant via
---`style = "switch"`) renders a toggle track with an animated thumb —
---the position tweens over the component's theme transition duration
---(Theme transition; 150 ms default). The plain box look is unchanged.


DXUI = DXUI or {}

--- Whether the node renders as a switch track (either opt-in prop).
local function isSwitch(node)
    return node.variant == "switch" or node.style == "switch"
end

local Checkbox = DXUI.Widget:extend("Checkbox", {
    checked = {
        default = false, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
            if node.emit then node:emit("change", v) end
            if isSwitch(node) then
                node:_switchGlide(v and 1 or 0)
            end
        end,
    },
    -- "box" (default) | "switch": the switch track drawing (the theme
    -- may also opt in per style variant; colors via checkedColor etc.)
    variant = { default = "box", invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node)
        if isSwitch(node) then
            node:_switchGlide(node.checked and 1 or 0)
        end
    end },
    -- switch thumb position 0..1 (animated by _switchGlide; render-only)
    switchT = { default = 0, min = 0, max = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- switch thumb fill
    switchThumbColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    boxColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    checkedColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- box size (read from theme metrics when nil; kept as an explicit override)
    indent = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    autoSize = { default = true, invalidates = { DXUI.DIRTY.LAYOUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

--- Returns the effective box/indent size from explicit prop or theme metric.
function Checkbox:_boxSize()
    return self.indent or self:_metric("boxSize", 18)
end

--- Returns the text-to-box gap from theme metrics.
function Checkbox:_textOffset()
    return self:_metric("textOffset", 6)
end

--- Measures the box plus label text for autoSize.
function Checkbox:_measureContent()
    -- measure with the REAL font (the #text*7 estimate is wrong for every
    -- non-monospace font); the box side stays the height floor
    local tw, th
    if DXUI.Text then
        tw, th = DXUI.Text.measure(self.text, self.font, 1)
    else
        tw, th = #self.text * 7, 15
    end
    local box = self:_boxSize()
    local offset = self:_textOffset()
    return box + tw + offset, (th > box) and th or box
end

--- Tweens the switch thumb position toward `target` (0..1) through the
--- instance Anim layer, over the component's theme transition duration
--- (Theme.getComponentStyle; 150 ms default). Instant pre-mount, and a
--- running tween is cancelled by a state flip (new input always wins).
function Checkbox:_switchGlide(target)
    if self._switchAnim then
        local h = self._switchAnim
        if h and h.cancel then h:cancel() end
        self._switchAnim = nil
    end
    if (self.switchT or 0) == target then
        self.switchT = target
        return
    end
    if not self._context or not self._context.anim then
        self.switchT = target
        return
    end
    local dur = 150
    local cs = DXUI.Theme and DXUI.Theme.getComponentStyle
        and DXUI.Theme.getComponentStyle("Checkbox", self.style)
    if cs and cs.transition and tonumber(cs.transition.duration) then
        dur = tonumber(cs.transition.duration)
    end
    if dur <= 0 then
        self.switchT = target
        return
    end
    self._switchAnim = self._context.anim:animate(self,
        { switchT = target }, dur, "out")
end

--- Draws the box, the check mark when checked, and the label.
function Checkbox:render(renderer)
    local wx, wy, h = self.worldX, self.worldY, self.height
    local box = self:_boxSize()
    local offset = self:_textOffset()
    if isSwitch(self) then
        -- switch track: full node height, `indent` wide; the active fill
        -- grows with the thumb position, the thumb slides 0..1
        local tw = box
        local r = h / 2
        local t = self.switchT or 0
        renderer:borderedRect(wx, wy, tw, h, r, self.boxColor, self.borderColor, self.borderWidth)
        if t > 0 then
            local fw = h + (tw - h) * t
            renderer:roundedRect(wx, wy, fw, h, r, self.checkedColor)
        end
        local thumbPadding = self:_metric("thumbPadding", 2)
        local bw = (self.borderWidth or 1) * 2
        local td = h - bw - thumbPadding * 2
        if td < 2 then td = 2 end
        local tx = wx + (tw - td - thumbPadding) * t + thumbPadding / 2
        local ty = wy + (h - td) / 2
        renderer:roundedRect(tx, ty, td, td, td / 2, self.switchThumbColor)
        if self.text and self.text ~= "" then
            renderer:text(self.text, wx + tw + offset, wy, self.width - tw - offset, h,
                self.textColor, self.font, "left", "center", 1)
        end
        return
    end
    -- box: border ring drawn under the inset fill
    local r = self.radius or 4
    renderer:borderedRect(wx, wy, box, box, r, self.boxColor, self.borderColor, self.borderWidth)
    -- check mark (two thick strokes)
    if self.checked then
        local c = self.checkedColor or 0xFFFFFFFF
        local inset = self:_metric("checkInset", 0.22)
        local mid = self:_metric("checkMid", 0.42)
        local tail = self:_metric("checkEnd", 0.78)
        local thick = self:_metric("checkThickness", 2)
        renderer:line(wx + box * inset, wy + box * 0.52, wx + box * mid, wy + box * 0.72, c, thick)
        renderer:line(wx + box * mid, wy + box * 0.72, wx + box * tail, wy + box * 0.28, c, thick)
    end
    if self.text and self.text ~= "" then
        renderer:text(self.text, wx + box + offset, wy, self.width - box - offset, h,
            self.textColor, self.font, "left", "center", 1)
    end
end

DXUI.Builders.register("Checkbox", Checkbox)

--- Toggles `checked` on click (per-instance handler; users may add their own).
Checkbox._build = function(node, props)
    -- deterministic thumb start regardless of the opts pairs order
    if isSwitch(node) then
        node.switchT = node.checked and 1 or 0
    end
    node:on("click", function(n)
        n.checked = not n.checked
    end, "dxui-toggle")
end