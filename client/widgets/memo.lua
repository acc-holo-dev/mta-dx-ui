--[[
    memo.lua — DXUI

    Memo: scrollable multi-line text (read-only). Wraps text via the text
    engine and scrolls vertically with the mouse wheel. Text is clipped to
    the memo box (clip = true).
]]

DXUI = DXUI or {}

local Memo = DXUI.Label:extend("Memo", {
    scrollY = { default = 0, type = "number", min = 0, invalidates = { DXUI.DIRTY.RENDER } },
    clip = { default = true, invalidates = { DXUI.DIRTY.RENDER, DXUI.DIRTY.INPUT } },
    -- interactive (wheel scroll) — override Label's enabled=false default
    enabled = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

function Memo:render(renderer)
    if self.text == nil or self.text == "" then return end
    local x, y, w, h = self.worldX, self.worldY, self.width, self.height
    local font, scale = self.font, self.scale

    local laid = DXUI.Text.wrap(self.text, font, scale, w)
    local lines, lineHeight = laid.lines, laid.lineHeight
    local contentH = laid.height

    -- clamp scroll to content
    local maxY = contentH - h
    if maxY < 0 then maxY = 0 end
    local sy = self.scrollY or 0
    if sy > maxY then
        sy = maxY
        self.scrollY = sy
    elseif sy < 0 then
        sy = 0
        self.scrollY = 0
    end

    local yOff = 0
    if self.valign == "middle" then
        yOff = (h - contentH) / 2
    elseif self.valign == "bottom" then
        yOff = h - contentH
    end
    if yOff < 0 then yOff = 0 end

    for i = 1, #lines do
        local ly = y + yOff + (i - 1) * lineHeight - sy
        renderer:text(lines[i], x, ly, w, lineHeight, self.textColor, font, self.align, nil, scale)
    end
end

--- Scrolls by dy pixels (clamped on next render).
function Memo:scrollBy(dy)
    self.scrollY = (self.scrollY or 0) + dy
    return self
end

--- Returns scroll offset and max scroll (content height - viewport height).
function Memo:getScroll()
    local laid = DXUI.Text.wrap(self.text, self.font, self.scale, self.width)
    local maxY = laid.height - self.height
    if maxY < 0 then maxY = 0 end
    return self.scrollY or 0, maxY
end

--- Builder: ui:memo({ text=, width=, height=, wheelStep=, ... }).
function Memo.build(context, props)
    props = props or {}
    local node = Memo:new(props)
    if props.width == nil then node.width = 200 end
    if props.height == nil then node.height = 120 end
    if props.wrap == nil then node.wrap = true end
    local wheelStep = props.wheelStep or 30
    node:on("wheel", function(e)
        if node:isAlive() then node:scrollBy(-(e.dz or 0) * wheelStep) end
    end)
    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Memo = Memo
