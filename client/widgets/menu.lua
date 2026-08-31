--[[
    menu.lua — DXUI

    Menu: vertical item list. items = { {text=, onClick=}, ... }. Click
    selects the item (menu.selected = index) and emits "select".
]]

DXUI = DXUI or {}

local Menu = DXUI.Widget:extend("Menu", {
    color = { default = 0xFF2A2A2A, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    selected = { default = 0, type = "number", min = 0, invalidates = { DXUI.DIRTY.RENDER } },
    itemHeight = { default = 24, type = "number", min = 1, invalidates = { DXUI.DIRTY.RENDER } },
    itemColor = { default = 0xFF2A2A2A, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    itemHoverColor = { default = 0xFF3A6EA5, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function Menu:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

--- Builder: ui:menu({ items=, width=, itemHeight=, ... }).
function Menu.build(context, props)
    props = props or {}
    local items = props.items or {}
    local node = Menu:new(props)
    local ITEM_H = node.itemHeight or 24
    if props.width == nil then node.width = 160 end
    node.height = #items * ITEM_H

    for i = 1, #items do
        local it = items[i]
        local row = context:panel({ x = 0, y = (i - 1) * ITEM_H, width = node.width, height = ITEM_H, color = node.itemColor })
        row:setParent(node)
        row._menuIndex = i
        local label = context:label({ x = 8, y = (ITEM_H - 14) / 2, width = node.width - 16, height = 14, text = it.text or "", color = node.textColor })
        label:setParent(row)
        row:on("mouseenter", function()
            if row:isAlive() and row._menuIndex ~= node.selected then row.color = node.itemHoverColor end
        end)
        row:on("mouseleave", function()
            if row:isAlive() and row._menuIndex ~= node.selected then row.color = node.itemColor end
        end)
        row:on("click", function()
            if not node:isAlive() then return end
            node.selected = i
            node:emit("select", { index = i, item = it, text = it.text })
            if it.onClick then it.onClick(i, it) end
        end)
    end

    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Menu = Menu
