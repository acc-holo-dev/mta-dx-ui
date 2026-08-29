--[[
    batcher.lua

    §15/§60 ТЗ: не делать дорогостоящую полную сортировку каждый кадр.
    Порядок отрисовки (массив cmdSlot) пересобирается ТОЛЬКО когда
    storage.orderDirty == true (взводится в точках, где порядок реально мог
    измениться — см. комментарий у поля orderDirty в core/storage.lua).

    Группировка по texture/blend ради минимизации state-change (§14) в M2
    сведена к тому, что сортировка вторичным ключом идёт по типу команды
    (CMD_RECT/IMAGE/TEXT), т.к. на этом этапе именно тип определяет, какой
    dx-вызов и какое состояние понадобится (§62 blend, §64 render target).
    Полноценная группировка по конкретной текстуре — доработка M9
    (Optimization), когда будет из чего выбирать реальным бенчмарком.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.Batcher = {}
local Batcher = DXUI.Batcher

local function compareCmds(pool, slotA, slotB)
    if pool.layer[slotA] ~= pool.layer[slotB] then
        return pool.layer[slotA] < pool.layer[slotB]
    end
    if pool.zIndex[slotA] ~= pool.zIndex[slotB] then
        return pool.zIndex[slotA] < pool.zIndex[slotB]
    end
    if pool.type[slotA] ~= pool.type[slotB] then
        return pool.type[slotA] < pool.type[slotB]
    end
    -- финальный тай-брейк по nodeId — делает сортировку детерминированной
    -- (стабильной между кадрами при равных ключах), что важно для
    -- предсказуемых снапшотов в тестах и для debug-инструментов (§34).
    return pool.nodeId[slotA] < pool.nodeId[slotB]
end

--- Возвращает актуальный порядок отрисовки (массив cmdSlot). Пересобирает
-- его, только если storage.orderDirty; иначе отдаёт закэшированный массив.
function Batcher.getDrawOrder(storage, pool, cachedOrder)
    if not storage.orderDirty and cachedOrder then
        return cachedOrder, false
    end

    local order = {}
    local n = pool.activeCount
    for i = 1, n do
        order[i] = pool.activeSlots[i]
    end

    table.sort(order, function(a, b) return compareCmds(pool, a, b) end)

    storage.orderDirty = false
    return order, true
end
