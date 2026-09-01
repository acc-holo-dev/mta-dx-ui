--[[
    tabpanel.lua — DXUI V3 (composite widget)

    TabPanel — pages are children (add via :addPage); `labels` (one per
    page) build an interactive tab strip. Only the active page is visible.

        local tp = ui:tabpanel({ x=0, y=0, width=300, height=200,
                                 labels = { "General", "Advanced" } })
        tp:addPage(pageGeneral)   -- page 1
        tp:addPage(pageAdvanced)  -- page 2
        tp.activeIndex = 1
]]

DXUI = DXUI or {}

--- Rebuilds the tab strip labels from the current labels list.
local function buildTabs(node)
    local tabsPart = node:getPart("tabs")
    if not tabsPart then return end
    -- drop old tab labels
    local old = node._tabLabels
    if old then
        for i = 1, #old do
            if old[i] then old[i]:destroy() end
        end
    end
    node._tabLabels = {}
    local labels = node.labels or {}
    local Label = DXUI.Widgets and DXUI.Widgets.Label
    if not Label then return end
    local th = node.tabHeight or 26
    local cursorX = 0
    for i = 1, #labels do
        local tab = Label:new({ text = labels[i], padding = { left = 10, right = 10 } })
        tab._index = i
        tab:on("click", function(t)
            node.activeIndex = t._index
        end, "dxui-tab")
        tab:setParent(tabsPart)
        tab.x = cursorX
        tab.y = 0
        tab.layoutWidth = DXUI.auto()
        tab.layoutHeight = { k = "px", v = th }
        local mw = (DXUI.Text and DXUI.Text.measure(labels[i], nil, 1))
            or (#labels[i] * 7)
        cursorX = cursorX + mw + 20
        node._tabLabels[i] = tab
    end
    if node._context then node._context.layoutDirty = true end
end

local TabPanel = DXUI.Widget:extend("TabPanel", {
    labels = {
        default = {}, invalidates = { DXUI.DIRTY.RENDER }, onSet = function(node)
            buildTabs(node)
        end,
    },
    activeIndex = {
        default = 1, invalidates = { DXUI.DIRTY.RENDER, DXUI.DIRTY.INPUT }, onSet = function(node, i)
            local pages = node._pages or {}
            for p = 1, #pages do
                pages[p].visible = (p == i)
            end
        end,
    },
    tabHeight = { default = 26, invalidates = { DXUI.DIRTY.LAYOUT } },
    textColor = { default = 0xFF6B7280, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    activeColor = { default = 0xFF2563EB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    borderColor = { default = 0xFFD1D5DB, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

DXUI.Part.declare(TabPanel, { "tabs", "content" })

--- Creates the tabs and content parts.
TabPanel._build = function(node)
    local th = node.tabHeight or 26
    local tabBar = DXUI.Widget:new({})
    tabBar.layoutMode = "relative"
    tabBar.layoutWidth = DXUI.percent(100)
    tabBar.layoutHeight = { k = "px", v = th }
    node:setPart("tabs", tabBar)

    local content = DXUI.Widget:new({})
    content.layoutMode = "relative"
    content.layoutWidth = DXUI.percent(100)
    content.layoutHeight = DXUI.percent(100)
    content.padding = { left = 4, top = th + 4, right = 4, bottom = 4 }
    node:setPart("content", content)

    node._pages = {}
    buildTabs(node)
end

--- Adds a page into the content part; only the active page is visible.
-- Pages fill the content box (its padding clears the tab strip).
function TabPanel:addPage(child)
    local pages = self._pages or {}
    pages[#pages + 1] = child
    self._pages = pages
    child:setParent(self:getPart("content"))
    child.layoutMode = "relative"
    child.layoutWidth = DXUI.percent(100)
    child.layoutHeight = DXUI.percent(100)
    local i = #pages
    local active = self.activeIndex or 1
    child.visible = (i == active)
    return child
end

--- Draws the active tab's underline indicator.
function TabPanel:render(renderer)
    local wx, wy = self.worldX, self.worldY
    local th = self.tabHeight or 26
    local active = self.activeIndex or 1
    local tab = self._tabLabels and self._tabLabels[active]
    if tab then
        local tx = tab.worldX or wx
        local tw = tab.width or 40
        renderer:rect(tx, wy + th - 2, tw, 2, self.activeColor)
    end
end

DXUI.Builders.register("TabPanel", TabPanel)