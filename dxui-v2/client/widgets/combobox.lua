--[[
    combobox.lua — DXUI V2

    ComboBox: выпадающий список. node (кнопка с label + arrow) + dropdown
    (popup). items — строки или {text=, value=}. onChange(idx, value).
]]

DXUI = DXUI or {}

local ITEM_H = 24

local ComboBox = DXUI.Widget:extend("ComboBox", {
    items = { default = {}, invalidates = { DXUI.DIRTY.RENDER } },
    selected = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    placeholder = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    placeholderColor = { default = 0xFF888888, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function ComboBox:_itemText(idx)
    local it = self.items[idx]
    if it == nil then return nil end
    if type(it) == "table" then return it.text end
    return tostring(it)
end

function ComboBox:_itemValue(idx)
    local it = self.items[idx]
    if it == nil then return nil end
    if type(it) == "table" then return it.value end
    return it
end

function ComboBox:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    local t = self.selected > 0 and self:_itemText(self.selected) or nil
    if t then
        renderer:text(t, self.worldX + 6, self.worldY, self.width - 20, self.height, self.textColor)
    else
        renderer:text(self.placeholder, self.worldX + 6, self.worldY, self.width - 20, self.height, self.placeholderColor)
    end
    renderer:text("v", self.worldX + self.width - 16, self.worldY, 16, self.height, self.placeholderColor)
end

function ComboBox:setItems(items)
    self.items = items or {}
    if self.selected > #self.items then self.selected = 0 end
    return self
end

function ComboBox:setSelected(idx)
    if idx < 0 then idx = 0 end
    if idx > #self.items then idx = 0 end
    if self.selected == idx then return self end
    self.selected = idx
    if self._onChange then self._onChange(idx, self:_itemValue(idx)) end
    return self
end

function ComboBox:getValue()
    return self:_itemValue(self.selected)
end

function ComboBox:open()
    if not self._dropdown then return self end
    if self:isOpen() then return self end
    self:_rebuildDropdown()
    self._dropdown:setSize(self.width, #self.items * ITEM_H)
    self._dropdown:show(self.worldX, self.worldY + self.height)
    return self
end

function ComboBox:close()
    if self._dropdown then self._dropdown:hide() end
    return self
end

function ComboBox:isOpen()
    return self._dropdown ~= nil and self._dropdown:isShown()
end

function ComboBox:_rebuildDropdown()
    local dd = self._dropdown
    -- очистить старые пункты
    local children = dd._children
    for i = #children, 1, -1 do
        children[i]:destroy()
    end
    for i = 1, #self.items do
        local row = self._context:panel({ x = 0, y = (i - 1) * ITEM_H, width = self.width, height = ITEM_H, color = 0xFF2A2A2A })
        row:setParent(dd)
        local label = self._context:label({ x = 6, y = (ITEM_H - 14) / 2, width = self.width - 12, height = 14, text = self:_itemText(i) or "" })
        label:setParent(row)
        local idx = i
        row:on("mouseenter", function() if row:isAlive() then row.color = 0xFF3A6EA5 end end)
        row:on("mouseleave", function() if row:isAlive() then row.color = 0xFF2A2A2A end end)
        row:on("click", function()
            self:setSelected(idx)
            self:close()
        end)
    end
end

--- Очистка dropdown при destroy (он root-узел — каскад его не сносит).
function ComboBox:_onDestroy()
    if self._dropdown and self._dropdown:isAlive() then
        self._dropdown:destroy()
    end
    self._dropdown = nil
end

--- Билдер: ui:combobox({ items=, selected=, placeholder=, onChange=, ... }).
function ComboBox.build(context, props)
    props = props or {}
    local node = ComboBox:new(props)
    if props.width == nil then node.width = 150 end
    if props.height == nil then node.height = 26 end
    if props.onChange then node._onChange = props.onChange end

    -- dropdown — отдельный popup (root-узел), скрыт; dismiss по клику вне бесплатный
    local dropdown = context:popup({ width = node.width })
    node._dropdown = dropdown

    node:on("click", function()
        if node:isAlive() then
            if node:isOpen() then node:close() else node:open() end
        end
    end)

    return node
end

DXUI.ComboBox = ComboBox
