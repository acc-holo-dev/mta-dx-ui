--[[
    label.lua — DXUI V2

    Label: текстовая подпись. Не интерактивен (enabled=false по умолчанию).
    autoSize = true — размер по тексту (Text.measure, кэш §43).

    Stage 8 (§41): Label поверх text engine:
      wrap      — word-wrap по ширине (с переносом #RRGGBB color-кодов);
      align     — "left"|"center"|"right";
      valign    — "top"|"middle"|"bottom";
      ellipsis  — обрезка с "..." (без wrap);
      shadow/shadowColor/shadowOffset — тень (дополнительный item);
      scale     — масштаб шрифта.
]]

DXUI = DXUI or {}

local Label = DXUI.Widget:extend("Label", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    -- подпись не участвует в hit-test по умолчанию
    enabled = { default = false, invalidates = { DXUI.DIRTY.INPUT } },
    align = { default = "left", invalidates = { DXUI.DIRTY.RENDER } },
    valign = { default = "top", invalidates = { DXUI.DIRTY.RENDER } },
    wrap = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    ellipsis = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    scale = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    shadow = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    shadowColor = { default = 0xFF000000, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    shadowOffset = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
})

function Label:render(renderer)
    if self.text == nil or self.text == "" then return end
    local x, y, w, h = self.worldX, self.worldY, self.width, self.height
    local font, scale = self.font, self.scale

    -- layout (§41): строки всегда per-line (wrap → word-wrap; иначе по \n)
    local laid
    if self.wrap and w > 0 then
        laid = DXUI.Text.wrap(self.text, font, scale, w)
    elseif self.ellipsis and w > 0 and not self.text:find("\n", 1, true) then
        local line = DXUI.Text.ellipsis(self.text, font, scale, w)
        local _, lh = DXUI.Text.measure("Ag", font, scale)
        laid = { lines = { line }, lineHeight = lh, height = lh }
    else
        laid = DXUI.Text.wrap(self.text, font, scale, nil) -- разбивка по \n
    end

    local lines, lineHeight, contentH = laid.lines, laid.lineHeight, laid.height

    -- valign: смещение блока строк внутри box
    local yOff = 0
    if self.valign == "middle" then
        yOff = (h - contentH) / 2
    elseif self.valign == "bottom" then
        yOff = h - contentH
    end
    if yOff < 0 then yOff = 0 end

    for i = 1, #lines do
        local ly = y + yOff + (i - 1) * lineHeight
        if self.shadow then
            local so = self.shadowOffset
            renderer:text(lines[i], x + so, ly + so, w, lineHeight, self.shadowColor, font, self.align, nil, scale)
        end
        renderer:text(lines[i], x, ly, w, lineHeight, self.color, font, self.align, nil, scale)
    end
end

--- Измерение текста для autoSize (кэшируется, §43).
function Label:_measureContent()
    return DXUI.Text.measure(self.text, self.font, self.scale)
end

--- Билдер: ui:label({ text=, x=, y=, width=, height=, color=, font=,
-- align=, valign=, wrap=, ellipsis=, shadow=, scale=, autoSize=, ... }).
function Label.build(context, props)
    props = props or {}
    local node = Label:new(props)
    if not props.autoSize then
        if props.width == nil then node.width = 100 end
        if props.height == nil then node.height = 20 end
    end
    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Label = Label