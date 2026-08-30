--[[
    hittest.lua

    §29 ТЗ: "Не использовать дорогую геометрию там, где достаточно
    x >= left, x <= right, y >= top, y <= bottom". M3 не поддерживает
    повёрнутые/кастомные хитбоксы — это отдельный path для будущих версий,
    если понадобится (см. §29 "для rotated/custom elements отдельный path").

    Проходит только по storage.interactiveIds (§27 — плоский список), не по
    всему дереву. Среди всех узлов, чей AABB содержит точку, побеждает
    "самый верхний" — используется ТА ЖЕ приоритетность (layer, zIndex, id),
    что и в render/batcher.lua для сортировки отрисовки, чтобы то, что
    визуально нарисовано поверх, было и тем, что реально получает клик.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.HitTest = {}
local HitTest = DXUI.HitTest

-- true, если (a) имеет более высокий приоритет отрисовки/клика, чем (b)
-- (тот же порядок ключей, что compareCmds в render/batcher.lua)
local function higherPriority(storage, slotA, slotB)
    if storage.layer[slotA] ~= storage.layer[slotB] then
        return storage.layer[slotA] > storage.layer[slotB]
    end
    if storage.zIndex[slotA] ~= storage.zIndex[slotB] then
        return storage.zIndex[slotA] > storage.zIndex[slotB]
    end
    return storage.slotToId[slotA] > storage.slotToId[slotB]
end

--- Возвращает id самого верхнего интерактивного узла под точкой (px, py),
-- либо C.NIL_ID если ни один узел не подходит.
function HitTest.pick(storage, px, py)
    local bestId = C.NIL_ID
    local bestSlot = nil

    local ids = storage.interactiveIds
    for i = 1, storage.interactiveCount do
        local id = ids[i]
        local slot = storage.idToSlot[id]
        if slot and storage.effectiveVisible[slot] then
            local x, y, w, h = storage.worldX[slot], storage.worldY[slot], storage.w[slot], storage.h[slot]
            if px >= x and px <= x + w and py >= y and py <= y + h then
                -- M13 (ADR-017): узел под clip-контейнером хитается только
                -- ВНУТРИ clip-региона (иначе клик "за краем" панели попадал
                -- бы в визуально обрезанный элемент). Регион 0/0/0/0 = ещё
                -- не вычислен (первый кадр) -- проверку пропускаем.
                local inClip = true
                local cw = storage.clipW[slot]
                if cw ~= nil and cw > 0 then
                    local ch = storage.clipH[slot]
                    if px < storage.clipX[slot] or px > storage.clipX[slot] + cw
                        or py < storage.clipY[slot] or py > storage.clipY[slot] + ch then
                        inClip = false
                    end
                end
                if inClip and (bestSlot == nil or higherPriority(storage, slot, bestSlot)) then
                    bestId = id
                    bestSlot = slot
                end
            end
        end
    end

    return bestId
end
