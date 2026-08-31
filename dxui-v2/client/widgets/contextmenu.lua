--[[
    contextmenu.lua — DXUI V2

    ContextMenu: popup со списком пунктов. items = { {text=, onClick=}, ... }.
    hover-highlight, клик → onClick + hide.

    Типовое: node:on("mousedown", function(e) if e.button == "right"
    then menu:show(e.x, e.y) end end).
]]

DXUI = DXUI or {}

local ContextMenu = DXUI.Popup:extend("ContextMenu", {})

function ContextMenu:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

--- Билдер: ui:contextmenu({ items=, width=, ... }).
function ContextMenu.build(context, props)
    props = props or {}
    local ITEM_H = 24
    local width = props.width or 160
    local items = props.items or {}
    local node = ContextMenu:new(props)
    node.width = width
    node.height = #items * ITEM_H

    -- пункты: отдельные интерактивные children
    for i = 1, #items do
        local it = items[i]
        local row = context:panel({ x = 0, y = (i - 1) * ITEM_H, width = width, height = ITEM_H, color = 0xFF2A2A2A })
        row:setParent(node)
        local label = context:label({ x = 8, y = (ITEM_H - 14) / 2, width = width - 16, height = 14, text = it.text or "" })
        label:setParent(row)
        row:on("mouseenter", function() if row:isAlive() then row.color = 0xFF3A6EA5 end end)
        row:on("mouseleave", function() if row:isAlive() then row.color = 0xFF2A2A2A end end)
        row:on("click", function()
            node:hide()
            if it.onClick then it.onClick() end
        end)
    end

    return node
end

DXUI.ContextMenu = ContextMenu
