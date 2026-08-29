--[[
    layout.lua (M4, M9-оптимизирован)

    Layout-проход: вычисляет world-координаты узлов из локальных описаний
    (layoutMode/anchor/margin) + world-координат родителя + padding родителя.

    Ключевые решения (ADR-007):

      1. LAY_ABS (режим M1–M3, backward-compat): world = parentWorld + local.
      2. LAY_REL: local x,y — доли 0..1 от родительского контейнера (w,h).
      3. LAY_CENTER: узел центрируется в родителе. local x,y игнорируются.
      4. ANCHOR: точка привязки узла к вычисленной позиции (ADR-008).
      5. MARGIN: отступ от границ родительского контейнера.

    M9-оптимизации (бенчмарк bench/bench.lua):
      A. ИТЕРАТИВНЫЙ каскад (была рекурсия): один переиспользуемый stack,
         без аллокаций, без ограничения глубины Lua.
      B. Кэш margin/padding: 4 деления на 256-е → 2 + табличное хит.
      C. Итерация dirtyList по SLOTS (eachDirtyLive возвращает (id, slot))
         — без idToSlot lookup на каждом dirty-узле.
      D. markSlotDirty (по slot) — без idToSlot lookup в каскаде.
      E. Каскад только по НЕ-DIRTY поддеревьям: если узел сам DIRTY_LAYOUT,
         его поддерево будет пересчитано САМЫМ ЭТИМ узлом как отдельным
         каскадом (порядок dirtyList — от старых к новым, т.е. родители
         раньше детей). Это снимает visited-set и делает каскад O(поддерева).

    Dirty propagation (ADR-007 §B):
      - setPosition/setSize/setMargin/setPadding/setLayoutMode/setAnchor на
        узле помечают DIRTY_POS (M9: единый бит layout+transform+render).
      - Каскад: layout-проход пересчитывает ВСЁ поддерево dirty-узла
        (world детей зависит от world родителя), помечая DIRTY_RENDER
        на каждом узле (Builder перегенерирует команды).
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.Layout = {}
local Layout = DXUI.Layout

-- =======================================================================
-- Кэш margin/padding (M9)
-- =======================================================================
-- Пакет: mL=bits 0-7, mT=8-15, mR=16-23, mB=24-31.
-- Layout использует только mL и mT (mR/mB — для растягивания, M8+).
-- Кэш по packed number: число различных значений в реальном UI мало
-- (напр., 5-20 типовых отступов), не число узлов.
local marginCache = {}

--- Возвращает mL, mT из packed margin/padding (кэшировано, M9).
local function unpackMarginTL(packed)
    local cached = marginCache[packed]
    if cached then
        return cached[1], cached[2]
    end
    local mL = packed % 256
    local mT = (packed - mL) % 65536 // 256
    marginCache[packed] = { mL, mT }
    return mL, mT
end

-- =======================================================================
-- Ядро layout-вычислений
-- =======================================================================

--- Вычисляет world-координаты узла по его layout-описанию и world-координатам
-- родителя. Возвращает worldX, worldY.
local function computeWorld(storage, slot, parentWorldX, parentWorldY, parentW, parentH, parentPadding)
    local mode = storage.layoutMode[slot]
    local localX, localY = storage.x[slot], storage.y[slot]
    local w, h = storage.w[slot], storage.h[slot]
    local anchor = storage.anchor[slot]
    local mL, mT = unpackMarginTL(storage.margin[slot])

    local worldX, worldY

    if mode == C.LAY_ABS then
        worldX = parentWorldX + localX + mL
        worldY = parentWorldY + localY + mT
    elseif mode == C.LAY_REL then
        worldX = parentWorldX + localX * parentW + mL
        worldY = parentWorldY + localY * parentH + mT
    else -- C.LAY_CENTER
        worldX = parentWorldX + (parentW - w) / 2
        worldY = parentWorldY + (parentH - h) / 2
    end

    -- Якорь: сдвигаем world, чтобы точка привязки совпала с позицией.
    if anchor == C.ANCHOR_TC then
        worldX = worldX - w / 2
    elseif anchor == C.ANCHOR_TR then
        worldX = worldX - w
    elseif anchor == C.ANCHOR_ML then
        worldY = worldY - h / 2
    elseif anchor == C.ANCHOR_MC then
        worldX = worldX - w / 2
        worldY = worldY - h / 2
    elseif anchor == C.ANCHOR_MR then
        worldX = worldX - w
        worldY = worldY - h / 2
    elseif anchor == C.ANCHOR_BL then
        worldY = worldY - h
    elseif anchor == C.ANCHOR_BC then
        worldX = worldX - w / 2
        worldY = worldY - h
    elseif anchor == C.ANCHOR_BR then
        worldX = worldX - w
        worldY = worldY - h
    end
    -- ANCHOR_TL (0) — без сдвига.

    local pML, pMT = unpackMarginTL(parentPadding)
    worldX = worldX + pML
    worldY = worldY + pMT

    return worldX, worldY
end

-- =======================================================================
-- Итеративный каскадный layout-проход (M9)
-- =======================================================================

-- Переиспользуемый stack для итеративного DFS (без аллокаций).
local stkSlot = {}
local stkPX = {}
local stkPY = {}
local stkPW = {}
local stkPH = {}
local stkPP = {}

--- Итеративный каскад: пересчитывает world-координаты узла slot и ВСЕХ
-- его НЕ-DIRTY потомков (DIRTY-узлы пересчитаются сами как отдельные
-- каскады — порядок dirtyList гарантирует, что родитель раньше ребёнка).
-- parent* — world-координаты/размер/padding родителя slot.
local function cascadeFrom(storage, slot, parentWorldX, parentWorldY, parentW, parentH, parentPadding)
    local top = 0
    top = top + 1
    stkSlot[top] = slot
    stkPX[top] = parentWorldX
    stkPY[top] = parentWorldY
    stkPW[top] = parentW
    stkPH[top] = parentH
    stkPP[top] = parentPadding

    while top > 0 do
        local s = stkSlot[top]
        local pvx, pvy, pvw, pvh, pvp = stkPX[top], stkPY[top], stkPW[top], stkPH[top], stkPP[top]
        top = top - 1

        local worldX, worldY, thisW, thisH, thisPad
        local isDirtyLayout = storage:hasSlotDirty(s, C.DIRTY_LAYOUT)

        if not isDirtyLayout then
            -- НЕ-DIRTY узел: пересчитываем world.
            worldX, worldY = computeWorld(storage, s, pvx, pvy, pvw, pvh, pvp)
            storage.worldX[s] = worldX
            storage.worldY[s] = worldY
            -- M9: hot-вариант — без idToSlot lookup.
            storage:markSlotDirty(s, C.DIRTY_RENDER)
            thisW, thisH = storage.w[s], storage.h[s]
            thisPad = storage.padding[s]
        else
            -- DIRTY узел: пересчитываем world (он сам DIRTY_LAYOUT), но
            -- НЕ каскадируем в детей (они будут обработаны самим узлом).
            worldX, worldY = computeWorld(storage, s, pvx, pvy, pvw, pvh, pvp)
            storage.worldX[s] = worldX
            storage.worldY[s] = worldY
            -- НЕ markDirty(RENDER): узел уже DIRTY_LAYOUT (включает RENDER
            -- через DIRTY_POS в M9), Builder обработает его.
            thisW, thisH = storage.w[s], storage.h[s]
            thisPad = storage.padding[s]
        end

        -- Пушим детей ВСЕГДА: world-координаты детей зависят от world
        -- родителя, и если ребёнок сам DIRTY_LAYOUT, он будет пересчитан
        -- СВОИМ каскадом (порядок dirtyList — родитель раньше ребёнка).
        -- Если ребёнок НЕ-DIRTY, каскад пересчитывает его world.
        local childId = storage.firstChild[s]
        local cs = childId ~= C.NIL_ID and storage.idToSlot[childId] or nil
        while cs do
            top = top + 1
            stkSlot[top] = cs
            stkPX[top] = worldX
            stkPY[top] = worldY
            stkPW[top] = thisW
            stkPH[top] = thisH
            stkPP[top] = thisPad
            childId = storage.nextSibling[cs]
            cs = childId ~= C.NIL_ID and storage.idToSlot[childId] or nil
        end
    end
end

-- =======================================================================
-- Публичный API
-- =======================================================================

--- Главный layout-проход за кадр. Вызывается Kernel:renderFrame() после
-- Culling и до Builder (см. порядок в header'е).
-- M9: итерация по (id, slot); каскад — итеративный, только по НЕ-DIRTY
-- поддеревьям (DIRTY-узлы пересчитываются сами).
-- Возвращает true, если хотя бы один узел был пересчитан.
function Layout.update(storage)
    local anyLayouted = false

    for id, slot in storage:eachDirtyLive() do
        if storage:hasSlotDirty(slot, C.DIRTY_LAYOUT) then
            local parentWorldX, parentWorldY, parentW, parentH, parentPadding
            local parentId = storage.parent[slot]
            if parentId == C.NIL_ID then
                parentWorldX, parentWorldY = 0, 0
                parentW = storage.screenW or 1024
                parentH = storage.screenH or 768
                parentPadding = 0
            else
                local pSlot = storage.idToSlot[parentId]
                parentWorldX, parentWorldY = storage.worldX[pSlot], storage.worldY[pSlot]
                parentW, parentH = storage.w[pSlot], storage.h[pSlot]
                parentPadding = storage.padding[pSlot]
            end

            cascadeFrom(storage, slot, parentWorldX, parentWorldY, parentW, parentH, parentPadding)
            anyLayouted = true
        end
    end

    return anyLayouted
end

--- Устанавливает размер экрана (вызывается Kernel:setScreenSize).
function Layout.setScreenSize(storage, w, h)
    storage.screenW = w
    storage.screenH = h
    for i = 1, storage.count do
        local id = storage.slotToId[i]
        if id then
            storage:markDirty(id, C.DIRTY_LAYOUT)
        end
    end
end