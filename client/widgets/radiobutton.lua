--[[
    radiobutton.lua — DXUI V2

    RadioButton: radio button (Toggle with a round dot). Grouping via
    props.group (string): selecting one clears the others in the group.
    A selected radio cannot be deselected by click (click is a no-op).
]]

DXUI = DXUI or {}

local RadioButton = DXUI.Toggle:extend("RadioButton", {
    group = { default = nil, invalidates = {} },
})

-- Round dot (smaller than the check mark).
function RadioButton:_drawMark(renderer, bx, by)
    local ms = 8
    renderer:rect(bx + (16 - ms) / 2, by + (16 - ms) / 2, ms, ms, self.markColor)
end

--- setChecked(true) clears the others in the group. Programmatic deselect (false) is allowed.
function RadioButton:setChecked(v)
    v = v == true
    if v then
        local list = self._groupList
        if list then
            for i = 1, #list do
                local other = list[i]
                -- isAlive: the group may hold references to destroyed nodes
                if other ~= self and other:isAlive() and other:isChecked() then
                    other:setChecked(false)
                end
            end
        end
    end
    return DXUI.Toggle.setChecked(self, v)
end

--- Removes itself from the group list on destroy (no dead references left).
function RadioButton:_onDestroy()
    local list = self._groupList
    if list then
        for i = 1, #list do
            if list[i] == self then
                table.remove(list, i)
                break
            end
        end
    end
end

--- Builder: ui:radiobutton({ checked=, text=, group=, onChange=, ... }).
function RadioButton.build(context, props)
    props = props or {}
    local node = RadioButton:new(props)
    if props.width == nil then node.width = 120 end
    if props.height == nil then node.height = 24 end
    if props.onChange then node:onChange(props.onChange) end

    -- register in the group
    if props.group then
        context._radioGroups = context._radioGroups or {}
        local list = context._radioGroups[props.group]
        if not list then
            list = {}
            context._radioGroups[props.group] = list
        end
        list[#list + 1] = node
        node._groupList = list
    end

    node:on("click", function()
        if node:isAlive() then node:setChecked(true) end
    end)

    -- props.checked goes through the mutation layer and misses the group
    -- exclusivity — re-apply via setChecked (clears the rest of the group)
    if props.checked then node:setChecked(true) end
    return node
end

DXUI.RadioButton = RadioButton
