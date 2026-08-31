--[[
    radiobutton.lua — DXUI V2

    RadioButton: радио-кнопка (Toggle с круглой точкой). Группа через
    props.group (строка): выбор одного снимает остальные в той же группе.
    Выбранное радио нельзя снять кликом (клик по выбранному — no-op).
]]

DXUI = DXUI or {}

local RadioButton = DXUI.Toggle:extend("RadioButton", {
    group = { default = nil, invalidates = {} },
})

-- Круглая точка (меньше галочки).
function RadioButton:_drawMark(renderer, bx, by)
    local ms = 8
    renderer:rect(bx + (16 - ms) / 2, by + (16 - ms) / 2, ms, ms, self.markColor)
end

--- setChecked(true) снимает остальных в группе. Программное снятие (false) — разрешено.
function RadioButton:setChecked(v)
    v = v == true
    if v then
        local list = self._groupList
        if list then
            for i = 1, #list do
                local other = list[i]
                -- isAlive: группа может держать ссылки на уничтоженные узлы
                if other ~= self and other:isAlive() and other:isChecked() then
                    other:setChecked(false)
                end
            end
        end
    end
    return DXUI.Toggle.setChecked(self, v)
end

--- Убирает себя из списка группы при destroy (не оставляем мёртвых ссылок).
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

--- Билдер: ui:radiobutton({ checked=, text=, group=, onChange=, ... }).
function RadioButton.build(context, props)
    props = props or {}
    local node = RadioButton:new(props)
    if props.width == nil then node.width = 120 end
    if props.height == nil then node.height = 24 end
    if props.onChange then node:onChange(props.onChange) end

    -- регистрация в группе
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
    return node
end

DXUI.RadioButton = RadioButton
