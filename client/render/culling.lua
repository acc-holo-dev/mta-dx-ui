--[[
    culling.lua

    §16 ТЗ: "Culling должен быть дешёвым. Не применять сложные алгоритмы,
    если они дороже пропущенного dxDraw."

    M2 реализует минимальный уровень: effectiveVisible = собственный
    FLAG_VISIBLE узла И effectiveVisible родителя. Экранный/clip-based
    culling (§16 "outside screen", §17 clipping) сознательно вынесен из
    M2 — для этого нужны реальные размеры экрана и layout-система (M4),
    здесь их ещё нет. Помечено как известное ограничение, не забытая часть.

    Обновление происходит только для узлов, у которых установлен
    DIRTY_VISIBILITY (выставляется при setVisible() и при create/reparent),
    и каскадно распространяется на детей, если видимость реально
    изменилась (без каскада, если новое значение совпало со старым —
    иначе смена видимости в корне триггерила бы полный проход по всему
    поддереву без необходимости).
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.Culling = {}
local Culling = DXUI.Culling

local function propagate(storage, id, parentEffectiveVisible)
    local slot = storage.idToSlot[id]
    if not slot then return end

    local ownVisible = storage:hasFlag(id, C.FLAG_VISIBLE)
    local newEffective = ownVisible and parentEffectiveVisible

    local changed = storage.effectiveVisible[slot] ~= newEffective
    storage.effectiveVisible[slot] = newEffective

    if changed then
        storage:markDirty(id, C.DIRTY_RENDER)
        local childId = storage.firstChild[slot]
        while childId ~= C.NIL_ID do
            propagate(storage, childId, newEffective)
            childId = storage.nextSibling[storage.idToSlot[childId]]
        end
    end
end

--- Обрабатывает все узлы с DIRTY_VISIBILITY за текущий кадр.
-- Вызывается Kernel:renderFrame() до Builder'а (см. §E pipeline, шаг 4).
function Culling.update(storage)
    -- M9: итерация по (id, slot) — без idToSlot lookup.
    for id, slot in storage:eachDirtyLive() do
        if storage:hasSlotDirty(slot, C.DIRTY_VISIBILITY) then
            local parentId = storage.parent[slot]
            local parentEffective = true
            if parentId ~= C.NIL_ID then
                local parentSlot = storage.idToSlot[parentId]
                parentEffective = parentSlot and storage.effectiveVisible[parentSlot] or false
            end
            propagate(storage, id, parentEffective)
        end
    end
end
