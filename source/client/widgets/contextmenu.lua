--[[
    contextmenu.lua — DXUI V3 (composite widget)

    ContextMenu — vertical item list; items {text, onSelect, disabled};
    "--" separates; opens at a position, outside-click closes, item click
    executes + closes.

        local m = ui:contextmenu({ items = {
            { text = "Rename", onSelect = function() rename() end },
            "--",
            { text = "Delete", onSelect = function() del() end },
        }})
        m:open(100, 100)
]]

DXUI = DXUI or {}

local rebuildItems

local ContextMenu = DXUI.Widget:extend("ContextMenu", {
    items = { default = {}, invalidates = { DXUI.DIRTY.RENDER } },
    rowHeight = { default = 22, invalidates = { DXUI.DIRTY.LAYOUT }, onSet = function(node)
        -- themed density may land after build; rebuild the rows to match
        if node:getPart("list") then rebuildItems(node) end
    end },
    hoverColor = { default = 0xFFF3F4F6, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    disabledColor = { default = 0xFF6B7280, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

DXUI.Part.declare(ContextMenu, { "list" })

--- Returns the display text for an item (string or {text=...}).
local function rowTextOf(item)
    return (type(item) == "table") and (item.text or "") or tostring(item)
end

--- True when the item is the "--" separator marker.
local function tx_is_separator(item)
    return type(item) == "string" and item == "--"
end

--- Rebuilds the menu rows from the current items and sizes the menu.
rebuildItems = function(node)
    local list = node:getPart("list")
    if not list then return end
    local children = list._children
    for i = #children, 1, -1 do
        children[i]:destroy()
    end
    local items = node.items or {}
    -- measure width: longest row
    local maxW = 120
    for i = 1, #items do
        local tx = rowTextOf(items[i])
        if tx ~= "--" then
            local w = #tx * 7 + 24
            if w > maxW then maxW = w end
        end
    end
    node.width = maxW
    node.height = #items * (node.rowHeight or 22)
    local Label = DXUI.Widgets and DXUI.Widgets.Label
    if not Label then return end
    for i = 1, #items do
        local item = items[i]
        local entry = Label:new({
            text = rowTextOf(item),
            padding = { left = 12, right = 12 },
        })
        entry.y = (i - 1) * (node.rowHeight or 22)
        entry.layoutWidth = DXUI.percent(100)
        entry.layoutHeight = { k = "px", v = node.rowHeight or 22 }
        entry.height = node.rowHeight or 22
        if tx_is_separator(item) then
            entry.text = ""
        elseif item.disabled then
            entry.textColor = node.disabledColor
            entry:setEnabled(false)
        else
            entry._menuItem = item
            entry.textColor = node.textColor
            entry:on("hover-start", function(r)
                r.hoverFill = true
            end, "dxui-menu")
            entry:on("click", function(r)
                local it = r._menuItem
                if it and it.onSelect then it.onSelect(it) end
                node:close()
            end, "dxui-menu")
        end
        entry:setParent(list)
    end
end

--- Creates the list part and hides the menu until opened.
ContextMenu._build = function(node)
    local list = DXUI.Widget:new({})
    list.layoutMode = "relative"
    list.layoutWidth = DXUI.percent(100)
    list.layoutHeight = DXUI.percent(100)
    node:setPart("list", list)
    node.visible = false
    node:on("popup-close", function(n)
        n.visible = false
    end, "dxui-menu")
    rebuildItems(node)
end

--- Rebuilds rows when items are set.
ContextMenu._spec.items.onSet = function(node, v)
    rebuildItems(node)
end

--- Shows the menu at the given position and registers it as a popup.
function ContextMenu:open(x, y)
    self:setPosition(x or self.x, y or self.y)
    self.visible = true
    if self._context and self._context.dispatcher then
        self._context.dispatcher:openPopup(self)
    end
    return self
end

--- Hides the menu and unregisters it from the popup manager.
function ContextMenu:close()
    self.visible = false
    if self._context and self._context.dispatcher then
        self._context.dispatcher:closePopup(self)
    end
    return self
end

--- Draws the menu surface and separator lines.
function ContextMenu:render(renderer)
    if not self.visible then return end
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    renderer:borderedRect(wx, wy, w, h, self.radius or 4, self.color, self.borderColor, self.borderWidth)
    -- separators
    local items = self.items or {}
    local rh = self.rowHeight or 22
    for i = 1, #items do
        if tx_is_separator(items[i]) then
            local y = wy + (i - 1) * rh + rh / 2
            renderer:rect(wx + 8, y, w - 16, 1, 0xFFD1D5DB)
        end
    end
end

DXUI.Builders.register("ContextMenu", ContextMenu)