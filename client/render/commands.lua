--[[
    commands.lua

    Пул render-команд. Те же принципы, что и в core/storage.lua (ADR-002),
    применённые к render commands (§13, §55, §69 исходного ТЗ — "reusable
    render commands", запрет на unnecessary table creation в hot path):

      - SoA-массивы, индексированные cmdSlot
      - freelist для переиспользования освободившихся cmdSlot
      - НЕТ отдельного id<->slot маппинга, как в Storage: cmdSlot САМ
        является стабильным идентификатором команды на весь срок её жизни
        (в отличие от узлов, команды не переставляются местами при
        освобождении другой команды — переупорядочивание делает Batcher
        отдельным списком "draw order", не трогая сам пул)

    Один узел Storage владеет не более чем одной командой одновременно
    (M2: простые виджеты один-к-одному узел->примитив; составные виджеты
    в M7 будут эмитить несколько команд через несколько внутренних узлов,
    не через "одна команда на несколько типов" — это сохраняет модель простой).
]]

DXUI = DXUI or {}
local C = DXUI.Constants

local RenderCmdPool = {}
RenderCmdPool.__index = RenderCmdPool
DXUI.RenderCmdPool = RenderCmdPool

function RenderCmdPool.new()
    local self = setmetatable({}, RenderCmdPool)

    self.type    = {}
    self.x       = {}
    self.y       = {}
    self.w       = {}
    self.h       = {}
    self.color   = {}
    self.texture = {}
    self.text    = {}
    self.layer   = {}
    self.zIndex  = {}
    self.nodeId  = {} -- обратная ссылка: какой узел владеет командой (для отладки/освобождения)
    -- M5: clip/opacity/blur
    self.clipDepth = {}
    self.opacity   = {}
    self.blur      = {}
    -- M8: clip-регион (world-координаты), 0/0/0/0 если нет
    self.clipX = {}
    self.clipY = {}
    self.clipW = {}
    self.clipH = {}
    -- M10: полный clip-стек (вложенные clip-области).
    for level = 1, C.MAX_CLIP_DEPTH do
        self["clipX" .. level] = {}
        self["clipY" .. level] = {}
        self["clipW" .. level] = {}
        self["clipH" .. level] = {}
    end

    self.freeSlots = {}
    self.freeCount = 0
    self.nextFreshSlot = 1

    -- активный список слотов "в использовании" — нужен Batcher'у, чтобы не
    -- сканировать весь пул (включая дыры) при построении порядка отрисовки
    self.activeSlots = {}
    self.activeCount = 0
    self.activeIndexOf = {} -- [slot] -> позиция в activeSlots, для O(1) удаления по свопу

    return self
end

--- Выделяет новый (или переиспользованный) слот команды, привязанный к nodeId.
function RenderCmdPool:alloc(nodeId)
    local slot
    if self.freeCount > 0 then
        slot = self.freeSlots[self.freeCount]
        self.freeSlots[self.freeCount] = nil
        self.freeCount = self.freeCount - 1
    else
        slot = self.nextFreshSlot
        self.nextFreshSlot = slot + 1
    end

    self.nodeId[slot] = nodeId

    self.activeCount = self.activeCount + 1
    self.activeSlots[self.activeCount] = slot
    self.activeIndexOf[slot] = self.activeCount

    return slot
end

--- Освобождает слот команды (swap-with-last в activeSlots, O(1)).
function RenderCmdPool:free(slot)
    local idx = self.activeIndexOf[slot]
    if not idx then return end -- уже свободен

    local lastIdx = self.activeCount
    local lastSlot = self.activeSlots[lastIdx]

    self.activeSlots[idx] = lastSlot
    self.activeIndexOf[lastSlot] = idx

    self.activeSlots[lastIdx] = nil
    self.activeIndexOf[slot] = nil
    self.activeCount = lastIdx - 1

    self.type[slot] = nil
    self.texture[slot] = nil
    self.text[slot] = nil
    self.nodeId[slot] = nil
    -- M8: clip-регион тоже очищаем, иначе reused слот унаследует stale rect
    self.clipX[slot] = nil
    self.clipY[slot] = nil
    self.clipW[slot] = nil
    self.clipH[slot] = nil
    -- M10: полный clip-стек тоже очищаем.
    for level = 1, C.MAX_CLIP_DEPTH do
        self["clipX" .. level][slot] = nil
        self["clipY" .. level][slot] = nil
        self["clipW" .. level][slot] = nil
        self["clipH" .. level][slot] = nil
    end

    self.freeCount = self.freeCount + 1
    self.freeSlots[self.freeCount] = slot
end
