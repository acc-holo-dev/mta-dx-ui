--[[
    test_m19.lua -- ComboBox + TabPanel + GridList (ADR-023): контейнерные
    виджеты. Паттерн test_m12.
]]

dofile("loader.lua")

local Kernel = DXUI.Kernel
local C = DXUI.Constants
local passed, failed = 0, 0

local function check(name, cond)
    if cond then
        passed = passed + 1
        print("[OK]   " .. name)
    else
        failed = failed + 1
        print("[FAIL] " .. name)
    end
end

local function newUI()
    local k = Kernel.new({
        setBlendMode = function() end,
        pushClip = function() end,
        popClip = function() end,
        setOpacity = function() end,
        setBlur = function() end,
        drawRect = function() end,
        drawImage = function() end,
        drawText = function() end,
    })
    local ui = DXUI.UI.new(k)
    k:setScreenSize(1280, 720)
    return k, ui
end

-- 1. ComboBox: items (строки) + setSelected/getSelected/getValue
do
    local k, ui = newUI()
    local combo = ui:combobox({ items = { "A", "B", "C" } })
    check("combo: getItems 3", #combo:getItems() == 3)
    combo:setSelected(2)
    check("combo: getSelected 2", combo:getSelected() == 2)
    check("combo: getValue 'B'", combo:getValue() == "B")
    combo:setSelected(99) -- clamp к 0
    check("combo: setSelected(99) -> 0", combo:getSelected() == 0)
end

-- 2. ComboBox: items ({text, value}) + onChange
do
    local k, ui = newUI()
    local changed = 0
    local combo = ui:combobox({
        items = { { text = "One", value = 1 }, { text = "Two", value = 2 } },
        onChange = function() changed = changed + 1 end,
    })
    combo:setSelected(2)
    check("combo: getValue 2 (table)", combo:getValue() == 2)
    check("combo: onChange вызван", changed == 1)
end

-- 3. ComboBox: open/close/isOpen
do
    local k, ui = newUI()
    local combo = ui:combobox({ items = { "A", "B" } })
    check("combo: закрыт", not combo:isOpen())
    combo:open()
    check("combo: открыт", combo:isOpen())
    combo:close()
    check("combo: закрыт после close", not combo:isOpen())
end

-- 4. TabPanel: addTab/selectTab/getSelectedIndex/getTabCount
do
    local k, ui = newUI()
    local tabs = ui:tabpanel()
    local p1 = tabs:addTab("Tab 1")
    local p2 = tabs:addTab("Tab 2")
    check("tabs: getTabCount 2", tabs:getTabCount() == 2)
    check("tabs: первая выбрана по умолчанию", tabs:getSelectedIndex() == 1)
    tabs:selectTab(2)
    check("tabs: selectTab 2", tabs:getSelectedIndex() == 2)
    check("tabs: page возвращён", p1 ~= nil and p2 ~= nil)
    tabs:removeTab(1)
    check("tabs: removeTab -> 1", tabs:getTabCount() == 1)
end

-- 5. GridList: addColumn/addRow/selectRow/getSelected/getSelectedCells
do
    local k, ui = newUI()
    local grid = ui:gridlist({ columns = { { text = "Name", width = 100 }, { text = "Val", width = 50 } } })
    grid:addRow({ "a", "1" })
    grid:addRow({ "b", "2" })
    check("grid: getRowCount 2", grid:getRowCount() == 2)
    grid:selectRow(2)
    check("grid: getSelected 2", grid:getSelected() == 2)
    local cells = grid:getSelectedCells()
    check("grid: getSelectedCells", cells[1] == "b" and cells[2] == "2")
    grid:clearRows()
    check("grid: clearRows -> 0", grid:getRowCount() == 0)
    check("grid: selected сброшен", grid:getSelected() == 0)
end

print(string.format("test_m19: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
