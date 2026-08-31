--[[
    button.lua — DXUI V2

    Button: фон (rect) + подпись (text). Интерактивен. Событие "click"
    эмитится dispatcher'ом; onClick в props — удобный шорткат.

    Stage 7b: hover-состояние из темы (§64) — style.hover.color применяется
    на mouseenter/mouseleave (явные обработчики, читаемые).
]]

DXUI = DXUI or {}

local Button = DXUI.Widget:extend("Button", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- Stage 8: текст кнопки центрирован по умолчанию (нативный dxDrawText align)
    align = { default = "center", invalidates = { DXUI.DIRTY.RENDER } },
    valign = { default = "middle", invalidates = { DXUI.DIRTY.RENDER } },
    scale = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- Stage 9 (§37/§38): скругление и рамка
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    outlineWidth = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    outlineColor = { default = 0xFF000000, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function Button:render(renderer)
    if self.radius > 0 then
        renderer:roundedRect(self.worldX, self.worldY, self.width, self.height, self.radius, self.color)
    else
        renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    end
    if self.outlineWidth > 0 then
        renderer:outline(self.worldX, self.worldY, self.width, self.height, self.outlineWidth, self.outlineColor)
    end
    if self.text ~= "" then
        renderer:text(self.text, self.worldX, self.worldY, self.width, self.height,
            self.textColor, self.font, self.align, self.valign, self.scale)
    end
end

--- Билдер: ui:button({ text=, onClick=, style=, x=, y=, width=, height=,
-- color=, ... }).
function Button.build(context, props)
    props = props or {}
    local node = Button:new(props)
    if props.width == nil then node.width = 100 end
    if props.height == nil then node.height = 30 end
    if props.onClick then node:on("click", props.onClick) end

    -- Stage 7b: hover-стиль из темы (§64). Цвет берётся из ТЕКУЩЕГО стиля
    -- узла в момент входа курсора — переживает смену стиля (§62). Записи
    -- цвета — style-managed: не снимают theme-происхождение свойства.
    node:on("mouseenter", function()
        if not node:isAlive() or node._hoverActive then return end
        local st = DXUI.getStyle("Button", node.style)
        local hc = st and st.hover and st.hover.color
        if hc == nil then return end
        node._hoverColor = DXUI.resolveColor(hc)
        node._colorBeforeHover = node.color
        node._hoverActive = true
        node._applyingTheme = true
        node.color = node._hoverColor
        node._applyingTheme = nil
    end)
    node:on("mouseleave", function()
        if not node:isAlive() or not node._hoverActive then return end
        -- возвращаем прежний цвет, только если его не сменили вручную,
        -- пока курсор был на кнопке
        if node.color == node._hoverColor then
            node._applyingTheme = true
            node.color = node._colorBeforeHover
            node._applyingTheme = nil
        end
        node._hoverActive = false
    end)

    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Button = Button