--[[
    popup.lua — DXUI V2

    Popup: всплывающая панель (LAYER_POPUP), скрыта по умолчанию. Dismiss по
    клику вне — через Dispatcher.popupStack (§59).

    Показ: popup:show(x, y) (или show() — текущая позиция).
]]

DXUI = DXUI or {}

local Popup = DXUI.Widget:extend("Popup", {
    layer = { default = DXUI.LAYER.POPUP, invalidates = { DXUI.DIRTY.RENDER } },
    visible = { default = false, invalidates = { DXUI.DIRTY.VISIBILITY, DXUI.DIRTY.INPUT, DXUI.DIRTY.RENDER } },
})

function Popup:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

function Popup:show(x, y)
    if x ~= nil then self:setPosition(x, y) end
    self.visible = true
    if self._context and not self._shown then
        self._context.dispatcher:pushPopup(self, function() self:hide() end)
        self._shown = true
    end
    return self
end

function Popup:hide()
    self.visible = false
    if self._context and self._shown then
        self._context.dispatcher:popPopup(self)
        self._shown = false
    end
    return self
end

function Popup:isShown()
    return self.visible
end

function Popup:toggle(x, y)
    if self:isShown() then return self:hide() end
    return self:show(x, y)
end

--- Очистка popup-стека при destroy.
function Popup:_onDestroy()
    if self._shown and self._context then
        self._context.dispatcher:popPopup(self)
        self._shown = false
    end
end

--- Билдер: ui:popup({ x=, y=, width=, height=, children=, ... }). Скрыт по умолчанию.
function Popup.build(context, props)
    props = props or {}
    local node = Popup:new(props)
    if props.width == nil then node.width = 160 end
    if props.height == nil then node.height = 40 end
    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Popup = Popup
