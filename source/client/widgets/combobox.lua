---ComboBox — head showing the selected item + dropdown list. Opens on
---click; registers its dropdown as a popup (outside click closes it).
---items: array of strings (or {text=..., ...}); rows are rebuilt on set.
---
---    local cb = ui:combobox({ x=0, y=0, width=160, items={ "A", "B" } })
---    cb:on("select", function(n, index, item) ... end)


DXUI = DXUI or {}

local rebuildRows

--- Updates the built head/dropdown geometry to the current rowHeight.
--- The theme may set rowHeight AFTER the parts exist (theme defaults land
--- post-build; live theme switches restyle mounted nodes), so every write
--- path funnels here.
local function syncRowHeight(node)
    local headH = node.rowHeight or 20
    local head = node:getPart("head")
    if head then
        head.layoutHeight = { k = "px", v = headH }
    end
    local dd = node:getPart("dropdown")
    if dd then
        dd.y = headH
    end
    rebuildRows(node)
end

local ComboBox = DXUI.Widget:extend("ComboBox", {
    items = { default = {}, invalidates = { DXUI.DIRTY.RENDER } },
    selectedIndex = { default = 0, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, i)
        if node.emit then node:emit("select", i, node.items and node.items[i]) end
        local head = node:getPart("head")
        if head and node.items and node.items[i] then
            head.text = (type(node.items[i]) == "table") and (node.items[i].text or "") or node.items[i]
        end
    end },
    -- the open PROP is the single source of truth: writing it drives the
    -- dropdown part (visibility + popup registration)
    open = { default = false, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node, v)
        local dd = node:getPart("dropdown")
        if not dd or dd.visible == v then return end
        dd.visible = v
        local d = node._context and node._context.dispatcher
        if not d then return end
        if v then
            d:openPopup(dd)
        else
            d:closePopup(dd)
        end
    end },
    textColor = { default = 0xFF111827, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    headColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    radius = { default = 4, invalidates = { DXUI.DIRTY.RENDER } },
    -- hovered-row fill in the dropdown (the dropdown surface + fills are
    -- drawn by the dropdown part, under the row text)
    hoverColor = { default = 0xFFF3F4F6, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    rowHeight = { default = 20, invalidates = { DXUI.DIRTY.LAYOUT }, onSet = function(node)
        -- parts may not exist yet (constructor opts phase runs pre-build)
        if node:getPart("head") then syncRowHeight(node) end
    end },
    autoSize = { default = true, invalidates = { DXUI.DIRTY.LAYOUT } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

DXUI.Part.declare(ComboBox, { "head", "dropdown" })

--- Returns the display text for an item (string or {text=...}).
local function rowText(item)
    return (type(item) == "table") and (item.text or "") or tostring(item)
end

--- Rebuilds the dropdown rows from the current items.
rebuildRows = function(node)
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
        -- the dropdown part floats at zIndex 5 (above neighbors); the rows
        -- must paint (and hit) above ITS surface
        row.zIndex = 6
        -- hover state comes from the central interaction wiring; the
        -- dropdown surface reads it to paint the row fill
        row:on("click", function(r)
            node.selectedIndex = r._index
            node:hideDropdown()
        end, "dxui-combo")
        row:setParent(dd)
    end
end

--- Measures the head width and row height for autoSize.
function ComboBox:_measureContent()
    return (self._data and self._data.width) or 140, self.rowHeight or 22
end

--- Builds the head and dropdown parts and wires open/close behavior.
ComboBox._build = function(node, props)
    local Label = DXUI.Widgets and DXUI.Widgets.Label or DXUI.Widget
    local headH = node.rowHeight or 22
    local head = Label:new({ text = "", padding = { left = 8, right = 8 } })
    head.layoutWidth = DXUI.percent(100)
    head.layoutHeight = { k = "px", v = headH }
    head.layoutMode = "relative"
    head.align = "left"
    head.valign = "center"
    node:setPart("head", head)

    local dd = DXUI.Widget:new({})
    -- y is a pixel offset below the head
    dd.layoutMode = "absolute"
    dd.layoutWidth = DXUI.percent(100)
    dd.layoutHeight = DXUI.auto()
    -- dropdown hangs below the head
    dd.y = headH
    dd.zIndex = 5
    dd.visible = false
    -- the dropdown draws its own surface (over whatever is behind) and
    -- the hovered-row fill, both UNDER the row text (children render
    -- after the parent)
    function dd:render(renderer)
        local combo = self._parent
        if not combo or not self.visible then return end
        local wx, wy = self.worldX, self.worldY
        local w, h = self.width, self.height
        if w <= 0 or h <= 0 then return end
        renderer:borderedRect(wx, wy, w, h, combo.radius or 4,
            combo.color, combo.borderColor, combo.borderWidth)
        local rows = self._children
        for i = 1, #rows do
            local r = rows[i]
            if r:getState() == "hover" then
                renderer:rect(r.worldX, r.worldY, r.width, r.height,
                    combo.hoverColor)
            end
        end
    end
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
    end, "dxui-combo")
    rebuildRows(node)
end

--- Opens the dropdown. The popup is registered ON THE DROPDOWN part so
--- outside-click tests the correct region (head + rows), not just the
--- head box. The `open` prop drives the part (single source of truth).
function ComboBox:showDropdown()
    self.open = true
    return self
end

--- Closes the dropdown and unregisters it from the popup manager.
function ComboBox:hideDropdown()
    self.open = false
    return self
end

--- Appends an item and rebuilds the rows.
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

--- Direct access to the dropdown part (the rows live here).
function ComboBox:container()
    return self:getPart("dropdown")
end

--- Draws the head box and the caret arrow.
function ComboBox:render(renderer)
    local wx, wy, w = self.worldX, self.worldY, self.width
    local headH = self.rowHeight or 22
    local r = self.radius or 4
    renderer:borderedRect(wx, wy, w, headH, r, self.headColor, self.borderColor, self.borderWidth)
    -- caret arrow (two strokes forming a down-triangle)
    local ax = wx + w - 13
    local ay = wy + headH / 2
    renderer:line(ax, ay - 3, ax + 4, ay, self.textColor, 1)
    renderer:line(ax + 4, ay, ax, ay + 3, self.textColor, 1)
end

DXUI.Builders.register("ComboBox", ComboBox)