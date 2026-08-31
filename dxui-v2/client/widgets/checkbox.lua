--[[
    checkbox.lua — DXUI V2

    CheckBox: флажок (Toggle с квадратной галочкой).
]]

DXUI = DXUI or {}

local CheckBox = DXUI.Toggle:extend("CheckBox", {})

--- Билдер: ui:checkbox({ checked=, text=, onChange=, ... }).
function CheckBox.build(context, props)
    props = props or {}
    local node = CheckBox:new(props)
    if props.width == nil then node.width = 120 end
    if props.height == nil then node.height = 24 end
    if props.onChange then node:onChange(props.onChange) end
    node:on("click", function()
        if node:isAlive() then node:toggle() end
    end)
    return node
end

DXUI.CheckBox = CheckBox
