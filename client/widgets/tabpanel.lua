--[[
    tabpanel.lua — DXUI V2

    TabPanel: tabs. addTab(title, children) returns a page (PANEL).
    onChange(idx). Tab buttons are panels in the bar; pages are panels below the bar.
]]

DXUI = DXUI or {}

local TAB_BAR_H = 24
local COLOR_ACTIVE = 0xFF3A6EA5
local COLOR_INACTIVE = 0xFF2A2A2A
local PAGE_COLOR = 0xFF222222

local TabPanel = DXUI.Widget:extend("TabPanel", {
    barHeight = { default = TAB_BAR_H, invalidates = { DXUI.DIRTY.RENDER } },
    barColor = { default = 0xFF181818, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    pageColor = { default = PAGE_COLOR, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
})

function TabPanel:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    renderer:rect(self.worldX, self.worldY, self.width, self.barHeight, self.barColor)
end

function TabPanel:_layoutTabs()
    local x = 0
    for i = 1, #self._tabs do
        local entry = self._tabs[i]
        -- tab width from the text engine (exact MTA metrics)
        local tw = DXUI.Text.measure(entry.title, entry.label.font, 1) + 16
        entry.btn:setPosition(x, 0)
        entry.btn:setSize(tw, self.barHeight)
        entry.label:setPosition(6, (self.barHeight - 14) / 2)
        entry.label:setSize(tw - 12, 14)
        entry.btn.color = (i == self.selected) and COLOR_ACTIVE or COLOR_INACTIVE
        x = x + tw
    end
end

function TabPanel:addTab(title, children)
    local k = self._context
    local w, h = self.width, self.height

    local btn = k:panel({ x = 0, y = 0, width = 0, height = self.barHeight, color = COLOR_INACTIVE })
    btn:setParent(self)
    local label = k:label({ x = 6, y = (self.barHeight - 14) / 2, width = 0, height = 14, text = title })
    label:setParent(btn)

    local page = k:panel({ x = 0, y = self.barHeight, width = w, height = h - self.barHeight, color = self.pageColor, visible = false })
    page:setParent(self)

    local entry = { title = title, btn = btn, label = label, page = page }
    self._tabs[#self._tabs + 1] = entry

    btn:on("click", function()
        for i = 1, #self._tabs do
            if self._tabs[i] == entry then
                self:selectTab(i)
                break
            end
        end
    end)

    if children then
        DXUI.Widget.attachChildren(page, { children = children })
    end

    self:_layoutTabs()
    if #self._tabs == 1 then self:selectTab(1) end
    return page
end

function TabPanel:removeTab(idx)
    if idx < 1 or idx > #self._tabs then return self end
    local entry = table.remove(self._tabs, idx)
    entry.btn:destroy()
    entry.page:destroy()
    if self.selected == idx then
        self.selected = 0
        if #self._tabs > 0 then self:selectTab(1) end
    elseif self.selected > idx then
        self.selected = self.selected - 1
    end
    self:_layoutTabs()
    return self
end

function TabPanel:selectTab(idx)
    if idx < 1 or idx > #self._tabs then return self end
    if self.selected == idx then return self end
    if self.selected > 0 and self._tabs[self.selected] then
        self._tabs[self.selected].page.visible = false
    end
    self.selected = idx
    self._tabs[idx].page.visible = true
    self:_layoutTabs()
    if self._onChange then self._onChange(idx) end
    return self
end

function TabPanel:getSelectedIndex()
    return self.selected
end

function TabPanel:getTabCount()
    return #self._tabs
end

function TabPanel:setSize(w, h)
    DXUI.Node.setSize(self, w, h)
    for i = 1, #self._tabs do
        self._tabs[i].page:setSize(w, h - self.barHeight)
    end
    return self
end

--- Builder: ui:tabpanel({ onChange=, ... }).
function TabPanel.build(context, props)
    props = props or {}
    local node = TabPanel:new(props)
    if props.width == nil then node.width = 300 end
    if props.height == nil then node.height = 200 end
    node._tabs = {}
    node.selected = 0
    if props.onChange then node._onChange = props.onChange end
    return node
end

DXUI.TabPanel = TabPanel
