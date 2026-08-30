--[[
    builder.lua

    Проходит по dirty-очереди (не по всему дереву) и для каждого узла с
    DIRTY_RENDER либо обновляет существующую команду в пуле, либо выделяет
    новую, либо освобождает её (если узел стал невидим/потерял содержимое).

    Правило эмиссии команды (M2, до появления виджетов в M7):
      - невидимый узел (effectiveVisible == false)               -> нет команды
      - есть text                                                  -> CMD_TEXT
      - иначе есть texture                                         -> CMD_IMAGE
      - иначе                                                      -> CMD_RECT

    Это временное упрощённое правило для базового узла-примитива;
    когда в M7 появятся составные виджеты, эмиссия команд станет
    ответственностью конкретного виджета (через custom renderer hook,
    §53 ТЗ), а не этой универсальной эвристики.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.Builder = {}
local Builder = DXUI.Builder

local function chooseCmdType(storage, slot)
    if storage.text[slot] ~= nil then return C.CMD_TEXT end
    if storage.texture[slot] ~= nil then return C.CMD_IMAGE end
    return C.CMD_RECT
end

local function writeCmd(pool, cmdSlot, storage, nodeSlot, nodeId)
    pool.type[cmdSlot]    = chooseCmdType(storage, nodeSlot)
    pool.x[cmdSlot]       = storage.worldX[nodeSlot]
    pool.y[cmdSlot]       = storage.worldY[nodeSlot]
    pool.w[cmdSlot]       = storage.w[nodeSlot]
    pool.h[cmdSlot]       = storage.h[nodeSlot]
    pool.color[cmdSlot]   = storage.color[nodeSlot]
    pool.texture[cmdSlot] = storage.texture[nodeSlot]
    pool.text[cmdSlot]    = storage.text[nodeSlot]
    pool.layer[cmdSlot]   = storage.layer[nodeSlot]
    pool.zIndex[cmdSlot]  = storage.zIndex[nodeSlot]
    pool.nodeId[cmdSlot]  = nodeId
    -- M5/M8: clip/opacity/blur (ADR-009).
    -- clipDepth вычисляет Clip.update() для ВСЕХ узлов; clipX/Y/W/H —
    -- world-регион ближайшего clip-предка (0/0/0/0 если нет). Builder
    -- копирует в cmd-пул (O(1)); hot path без обхода дерева.
    pool.clipDepth[cmdSlot] = storage.clipDepth[nodeSlot] or 0
    pool.clipX[cmdSlot]   = storage.clipX[nodeSlot] or 0
    pool.clipY[cmdSlot]   = storage.clipY[nodeSlot] or 0
    pool.clipW[cmdSlot]   = storage.clipW[nodeSlot] or 0
    pool.clipH[cmdSlot]   = storage.clipH[nodeSlot] or 0
    -- M10: полный clip-стек (вложенные clip-области).
    for level = 1, C.MAX_CLIP_DEPTH do
        pool["clipX" .. level][cmdSlot] = storage["clipX" .. level][nodeSlot] or 0
        pool["clipY" .. level][cmdSlot] = storage["clipY" .. level][nodeSlot] or 0
        pool["clipW" .. level][cmdSlot] = storage["clipW" .. level][nodeSlot] or 0
        pool["clipH" .. level][cmdSlot] = storage["clipH" .. level][nodeSlot] or 0
    end
    pool.opacity[cmdSlot]   = storage.opacity[nodeSlot]
    pool.blur[cmdSlot]      = storage.blur[nodeSlot]
end

--- Обрабатывает все узлы с DIRTY_RENDER за текущий кадр (после Culling).
-- Возвращает true, если состав активных команд мог измениться (для
-- Batcher'а — сигнал, что порядок отрисовки нужно пересобрать).
function Builder.update(storage, pool)
    local compositionChanged = false

    -- M9: итерация по (id, slot) — без idToSlot lookup.
    for id, slot in storage:eachDirtyLive() do
        if storage:hasSlotDirty(slot, C.DIRTY_RENDER) then
            local nodeSlot = slot
            local visible = storage.effectiveVisible[nodeSlot]
            local hasCmd = storage.cmdSlot[nodeSlot] ~= C.NO_CMD_SLOT

            if visible then
                -- M13 (ADR-017): zero-size RECT не эмитится -- контейнеры-
                -- невидимки (content ScrollPanel и т.п.) не тратят команду
                -- и draw call. TEXT/IMAGE не трогаем (0-размерный текст
                -- может быть валиден для измерения).
                local isRect = storage.text[nodeSlot] == nil and storage.texture[nodeSlot] == nil
                if isRect and (storage.w[nodeSlot] or 0) <= 0 and (storage.h[nodeSlot] or 0) <= 0 then
                    if hasCmd then
                        pool:free(storage.cmdSlot[nodeSlot])
                        storage.cmdSlot[nodeSlot] = C.NO_CMD_SLOT
                        compositionChanged = true
                    end
                else
                    if not hasCmd then
                        local cmdSlot = pool:alloc(id)
                        storage.cmdSlot[nodeSlot] = cmdSlot
                        compositionChanged = true
                    end
                    writeCmd(pool, storage.cmdSlot[nodeSlot], storage, nodeSlot, id)
                end
            else
                if hasCmd then
                    pool:free(storage.cmdSlot[nodeSlot])
                    storage.cmdSlot[nodeSlot] = C.NO_CMD_SLOT
                    compositionChanged = true
                end
            end
        end
    end

    return compositionChanged
end

--- Вызывается из Storage-listener (см. kernel.lua) при уничтожении узла —
-- освобождает его командный слот, если он был выделен. Storage сам не
-- знает о существовании RenderCmdPool (разделение ответственности).
function Builder.onNodeDestroyed(storage, pool, id, cmdSlot)
    if cmdSlot ~= C.NO_CMD_SLOT then
        pool:free(cmdSlot)
    end
end
