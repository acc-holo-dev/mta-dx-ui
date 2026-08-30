--[[
    render_list.lua — DXUI V2

    Плоский список render items — производный кэш дерева (§5 ARCHITECTURE.md).

    Рендер НЕ обходит дерево каждый кадр. Runtime держит плоский список
    items, который перестраивается только при инвалидации (orderDirty), а в
    idle-кадре просто отрисовывается без пересборки (zero work, §27).

    Каждый item — обычная таблица:
        { kind = "rect"|"image"|"text"|"line", x, y, w, h, color, ... }
]]

DXUI = DXUI or {}

local RenderList = {}
RenderList.__index = RenderList

function RenderList.new()
    local self = setmetatable({}, RenderList)
    self.items = {}   -- плоский массив items
    self.count = 0
    return self
end

--- Очищает список (переиспользует массив, без аллокаций).
function RenderList:clear()
    for i = 1, self.count do
        self.items[i] = nil
    end
    self.count = 0
end

--- Добавляет item в конец списка.
function RenderList:add(item)
    self.count = self.count + 1
    self.items[self.count] = item
end

DXUI.RenderList = RenderList
