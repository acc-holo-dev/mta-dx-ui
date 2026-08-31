--[[
    builders.lua — DXUI V2

    Parent-scoped builders (§15): window:label(...), window:button(...) и т.д.
    Создают виджет как ребёнка узла. Живут в widgets-слое (не в core), чтобы
    core не зависел от конкретных виджетов (§97).

    Требуют, чтобы узел был смонтирован (self.context не nil) — иначе неоткуда
    взять контекст для создания виджета.
]]

DXUI = DXUI or {}

local Node = DXUI.Node

-- name (метод узла) -> класс виджета
local MAP = {
    panel        = "Panel",
    label        = "Label",
    button       = "Button",
    image        = "Image",
    window       = "Window",
    checkbox     = "CheckBox",
    radiobutton  = "RadioButton",
    slider       = "Slider",
    progressbar  = "ProgressBar",
    scrollpanel  = "ScrollPanel",
    edit         = "Edit",
    popup        = "Popup",
    contextmenu  = "ContextMenu",
    combobox     = "ComboBox",
    tabpanel     = "TabPanel",
    gridlist     = "GridList",
}

for name, className in pairs(MAP) do
    Node[name] = function(self, props)
        local class = DXUI[className]
        local node = class.build(self.context, props)
        node:setParent(self)
        return node
    end
end
