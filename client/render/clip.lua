--[[
    clip.lua (M5, M10-расширен)

    Clip-глубина: вычисляет для каждого узла число clip-областей, активных
    на момент его рендеринга (clipDepth), и ПОЛНЫЙ clip-стек (M10):
    clipX1/Y1/W1/H1 (outermost) .. clipX4/Y4/W4/H4 (innermost).
    Builder копирует стек в cmd-пул, StateCache передаёт в драйвер
    (MTA DX9: RT-стек, ADR-009/011).

    Ключевые решения:

      1. CLIP-ГЛУБИНА ВЫЧИСЛЯЕТСЯ ТОЛЬКО ИЗ ДЕРЕВА + FLAG_CLIP.
         Область каждого clip-контейнера — его worldX/worldY/w/h (M4 layout
         уже считает их).

      2. DIRTY-DRIVEN (ADR-001/003): пересчёт — только для DIRTY_LAYOUT
         узлов и их потомков. Idle-кадр без layout-изменений = zero work.

      3. ДЕДУП-ПО-КОМПОНЕНТАМ: если dirty узлы образуют связное поддерево,
         поддерево пересчитывается ОДИН раз от верхнего dirty узла.

      4. НАЧАЛЬНЫЙ СЧЁТЧИК = ЧИСЛО FLAG_CLIP-ПРЕДКОВ верхнего dirty узла
         (подъём к корню, O(depth)).

      5. M10: ПОЛНЫЙ СТЕК (вложенные clip-области). Вместо одного innermost
         региона храним цепочку до MAX_CLIP_DEPTH уровней. StateCache
         push/pop по фактической глубине (не 0/1).

    Порядок вызова в Kernel:renderFrame:
      1. Culling.update  -> effectiveVisible
      2. Layout.update   -> worldX/worldY (+ DIRTY_RENDER на посещённых)
      3. Clip.update     -> clipDepth + clip-стек (ЭТОТ МОДУЛЬ)
      4. Builder.update  -> cmd-пул (читает clipDepth + стек)
      5. Batcher / 6. StateCache (выполняет команды)
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.Clip = {}
local Clip = DXUI.Clip

-- Переиспользуемые структуры дедупликации (без аллокаций в hot path).
local topSet = {}   -- [id] = true — верхние dirty узлы, уже обработанные
local topList = {}  -- плоский массив тех же id (для O(1) очистки по count)
local topCount = 0

-- M10: переиспользуемые массивы clip-цепочки (без аллокаций).
local chainX = {}
local chainY = {}
local chainW = {}
local chainH = {}
-- Временные массивы для сбора цепочки предков (подъём, потом разворот).
local tmpX = {}
local tmpY = {}
local tmpW = {}
local tmpH = {}

-- M10: имена полей clip-стека (для записи без string-concat в hot path).
local CLIP_FIELDS = {
    "clipX1", "clipY1", "clipW1", "clipH1",
    "clipX2", "clipY2", "clipW2", "clipH2",
    "clipX3", "clipY3", "clipW3", "clipH3",
    "clipX4", "clipY4", "clipW4", "clipH4",
}

--- Поднимается от id к корню и возвращает id верхнего предка (включая
-- сам id), у которого стоит DIRTY_LAYOUT. O(depth).
local function findTopDirty(storage, id)
    local top = id
    local slot = storage.idToSlot[id]
    local parentId = slot and storage.parent[slot] or C.NIL_ID
    while parentId ~= C.NIL_ID do
        if storage:hasDirty(parentId, C.DIRTY_LAYOUT) then
            top = parentId
            slot = storage.idToSlot[parentId]
            parentId = slot and storage.parent[slot] or C.NIL_ID
        else
            break
        end
    end
    return top
end

--- Собирает полную цепочку FLAG_CLIP-предков id (outermost → innermost)
-- в переиспользуемые chainX/Y/W/H. Возвращает число уровней (count).
-- O(depth) подъём; вызывается один раз на dirty-поддерево (не на узел).
local function clipAncestorChain(storage, id)
    local count = 0
    local slot = storage.idToSlot[id]
    local parentId = slot and storage.parent[slot] or C.NIL_ID
    -- Собираем от innermost к outermost (подъём).
    while parentId ~= C.NIL_ID do
        local pSlot = storage.idToSlot[parentId]
        if storage:hasFlag(parentId, C.FLAG_CLIP) then
            count = count + 1
            tmpX[count] = storage.worldX[pSlot]
            tmpY[count] = storage.worldY[pSlot]
            tmpW[count] = storage.w[pSlot]
            tmpH[count] = storage.h[pSlot]
        end
        parentId = pSlot and storage.parent[pSlot] or C.NIL_ID
    end
    -- Разворачиваем: outermost → innermost.
    for i = 1, count do
        local j = count - i + 1
        chainX[i] = tmpX[j]
        chainY[i] = tmpY[j]
        chainW[i] = tmpW[j]
        chainH[i] = tmpH[j]
    end
    return count
end

--- Рекурсивно вычисляет clipDepth и полный clip-стек для узла и всех его
-- потомков. activeClipCount — число clip-областей ВЫШЕ узла; цепочка —
-- в переиспользуемых chainX/Y/W/H (уровни 1..activeClipCount).
--
-- СЕМАНТИКА: clipDepth[node] = число clip-областей; clipX1..clipX4[node] =
-- полный стек (outermost → innermost). Собственная clip-область узла
-- действует на ДЕТЕЙ, а не на сам узел.
local function buildClipDepth(storage, id, activeClipCount)
    local slot = storage.idToSlot[id]
    if not slot then return end

    storage.clipDepth[slot] = activeClipCount

    -- Полный стек (M10): уровни 1..activeClipCount, остальные 0.
    for level = 1, C.MAX_CLIP_DEPTH do
        local base = (level - 1) * 4
        if level <= activeClipCount then
            storage[CLIP_FIELDS[base + 1]][slot] = chainX[level]
            storage[CLIP_FIELDS[base + 2]][slot] = chainY[level]
            storage[CLIP_FIELDS[base + 3]][slot] = chainW[level]
            storage[CLIP_FIELDS[base + 4]][slot] = chainH[level]
        else
            storage[CLIP_FIELDS[base + 1]][slot] = 0
            storage[CLIP_FIELDS[base + 2]][slot] = 0
            storage[CLIP_FIELDS[base + 3]][slot] = 0
            storage[CLIP_FIELDS[base + 4]][slot] = 0
        end
    end

    -- Innermost (backward-compat: clipX/Y/W/H — то же, что clipX4.. при depth>=4).
    if activeClipCount > 0 then
        storage.clipX[slot] = chainX[activeClipCount]
        storage.clipY[slot] = chainY[activeClipCount]
        storage.clipW[slot] = chainW[activeClipCount]
        storage.clipH[slot] = chainH[activeClipCount]
    else
        storage.clipX[slot] = 0
        storage.clipY[slot] = 0
        storage.clipW[slot] = 0
        storage.clipH[slot] = 0
    end

    local childCount = activeClipCount
    if storage:hasFlag(id, C.FLAG_CLIP) then
        childCount = childCount + 1
        chainX[childCount] = storage.worldX[slot]
        chainY[childCount] = storage.worldY[slot]
        chainW[childCount] = storage.w[slot]
        chainH[childCount] = storage.h[slot]
    end

    local childId = storage.firstChild[slot]
    while childId ~= C.NIL_ID do
        buildClipDepth(storage, childId, childCount)
        childId = storage.nextSibling[storage.idToSlot[childId]]
    end
end

--- Главный clip-проход за кадр (см. порядок в header'е).
function Clip.update(storage)
    -- M9: итерация по (id, slot) — без idToSlot lookup.
    for id, slot in storage:eachDirtyLive() do
        if storage:hasSlotDirty(slot, C.DIRTY_LAYOUT) then
            local top = findTopDirty(storage, id)
            if not topSet[top] then
                topSet[top] = true
                topCount = topCount + 1
                topList[topCount] = top
                -- Полная цепочка clip-предков (outermost → innermost).
                local count = clipAncestorChain(storage, top)
                buildClipDepth(storage, top, count)
            end
        end
    end

    -- Очистка set: только добавленные за кадр записи (bounded by topCount).
    for i = 1, topCount do
        topSet[topList[i]] = nil
    end
    topCount = 0
end