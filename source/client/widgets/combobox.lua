--[[
    combobox.lua — DXUI V3 (composite widget)

    ComboBox — head showing the selected item + dropdown list. Opens on
    click; registers its dropdown as a popup (outside click closes it).
    items: array of strings (or {text=..., ...}); rows are rebuilt on set.

        local cb = ui:combobox({ x=0, y=0, width=160, items={ "A", "B" } })
        cb:on("select", function(n, index, item) ... end)
]]

DXUI = DXUI or {}

local ComboBox = DXUI.Widget:extend("ComboBox", {
    items = { default = {}, invalidates = { DXUI.DIRTY.RENDER } },
    selectedIndex = { default = 0, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, i)
        if node.emit then node:emit("select", i, node.items and node.items[i]) end
        local head = node:getPart("head")
        if head and node.items and node.items[i] then
            head.text = (type(node.items[i]) == "table") and (node.items[i].text or "") or node.items[i]
        end
    end },
    open = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    headColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    rowHeight = { default = 20, invalidates = { DXUI.DIRTY.LAYOUT } },
    autoSize = { default = true, invalidates = { DXUI.DIRTY.LAYOUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

DXUI.Part.declare(ComboBox, { "head", "dropdown" })

local function rowText(item)
    return (type(item) == "table") and (item.text or "") or tostring(item)
end

local function rebuildRows(node)
    local dd = node:getPart("dropdown")
    if not dd then return end
    -- destroy old rows
    local children = dd._children
    for i = #children, 1, -1 do
        children[i]:destroy()
    end
    local items = node.items or {}
    local Label = DXUI.Widgets and DXUI.Widgets.Label
    if not Label then return end
    for i = 1, #items do
        local row = Label:new({
            text = rowText(items[i]),
            textColor = node.textColor,
            padding = { left = 8, right = 8 },
        })
        row._index = i
        row.y = (i - 1) * (node.rowHeight or 20)
        row.layoutWidth = DXUI.percent(100)
        row.layoutHeight = { k = "px", v = node.rowHeight or 20 }
        row:on("hover-start", function(r)
            r.hoverFill = true
            row:setState("hover")
        end, "dxui-combo")
        row:on("hover-end", function(r)
            r.hoverFill = false
            row:setState("normal")
        end, "dxui-combo")
        row:on("click", function(r)
            node.selectedIndex = r._index
            node:hideDropdown()
        end, "dxui-combo")
        row:setParent(dd)
    end
end

function ComboBox:_measureContent()
    return (self._data and self._data.width) or 140, self.rowHeight or 22
end

ComboBox._build = function(node, props)
    local Label = DXUI.Widgets and DXUI.Widgets.Label or DXUI.Widget
    local headH = node.rowHeight or 22
    local head = Label:new({ text = "", padding = { left = 8, right = 8 } })
    head.layoutWidth = DXUI.percent(100)
    head.layoutHeight = { k = "px", v = headH }
    head.layoutMode = "relative"
    head.align = "left"
    head.valign = "middle"
    node:setPart("head", head)

    local dd = DXUI.Widget:new({})
    dd.layoutMode = "absolute" -- y is a pixel offset below the head
    dd.layoutWidth = DXUI.percent(100)
    dd.layoutHeight = DXUI.auto()
    dd.y = headH -- dropdown hangs below the head
    dd.zIndex = 5
    dd.visible = false
    node:setPart("dropdown", dd)

    node:on("click", function(n, _, _, _, origin)
        -- a click inside the dropdown (row select) must NOT toggle the head
        if origin then
            local dd0 = n:getPart("dropdown")
            local p = origin
            while p and p ~= n do
                if dd0 and p == dd0 then return end
                p = p._parent
            end
        end
        if n.open then n:hideDropdown() else n:showDropdown() end
    end, "dxui-combo")

    node:on("focus", function(n) n._cbFocus = true end, "dxui-combo")
    node:on("blur", function(n) n._cbFocus = false end, "dxui-combo")
    node:on("popup-close", function(n)
        n.open = false
        local dd2 = n:getPart("dropdown")
        if dd2 then dd2.visible = false end
    end, "dxui-combo")
    rebuildRows(node)
end

--- Opens the dropdown (prop `open` stays the source of truth — the prop
-- is named `open`, so the METHODS are showDropdown/hideDropdown).
-- The popup is REGISTERED ON THE DROPDOWN part so outside-click tests the
-- correct region (head + rows), not just the head box.
function ComboBox:showDropdown()
    self.open = true
    local dd = self:getPart("dropdown")
    if dd then
        dd.visible = true
        if self._context and self._context.dispatcher then
            self._context.dispatcher:openPopup(dd)
        end
    end
    return self
end

function ComboBox:hideDropdown()
    self.open = false
    local dd = self:getPart("dropdown")
    if dd then
        dd.visible = false
        if self._context and self._context.dispatcher then
            self._context.dispatcher:closePopup(dd)
        end
    end
    return self
end

function ComboBox:addItem(item)
    self.items[#self.items + 1] = item
    rebuildRows(self)
    return self
end

--- On items being set post-build, rows rebuild (spec onSet + manual).
local origItemsSet = ComboBox._spec.items.onSet
ComboBox._spec.items.onSet = function(node, v)
    if origItemsSet then origItemsSet(node, v) end
    rebuildRows(node)
end

function ComboBox:render(renderer)
    local wx, wy, w = self.worldX, self.worldY, self.width
    local headH = self.rowHeight or 22
    local r = self.radius or 4
    renderer:roundedRect(wx, wy, w, headH, r, self.headColor)
    renderer:roundedRect(wx, wy, w, headH, r, self.borderColor)
    -- caret arrow (two strokes forming a down-triangle)
    local ax = wx + w - 13
    local ay = wy + headH / 2
    renderer:line(ax, ay - 3, ax + 4, ay, self.textColor, 1)
    renderer:line(ax + 4, ay, ax, ay + 3, self.textColor, 1)
end

DXUI.Builders.register("ComboBox", ComboBox)