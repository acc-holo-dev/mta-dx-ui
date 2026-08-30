--[[
    hit_test.lua — DXUI V2

    Hit-test (§46): обычный прямоугольный узел — максимально дешёвый AABB-тест
    (x >= left, x <= right, y >= top, y <= bottom). Без сложной геометрии.

    Проходит по плоскому списку интерактивных узлов (context.interactiveList,
    derived cache, перестраивается при DIRTY_INPUT), НЕ по всему дереву.
    Список отсортирован по (layer, zIndex, id) — тот же порядок, что и render,
    поэтому «визуально сверху» = «получает клик». Итерация в обратном порядке
    даёт верхний узел первым.
]]

DXUI = DXUI or {}

local HitTest = {}

--- Возвращает верхний интерактивный узел под точкой (x, y), или nil.
function HitTest.pick(context, x, y)
    local list = context.interactiveList
    for i = context.interactiveCount, 1, -1 do
        local node = list[i]
        if x >= node.x and x <= node.x + node.width
           and y >= node.y and y <= node.y + node.height then
            return node
        end
    end
    return nil
end

DXUI.HitTest = HitTest
