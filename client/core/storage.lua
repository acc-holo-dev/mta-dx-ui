--[[
    storage.lua

    Единственный владелец данных узлов интерфейса (см. ADR §4 обзор архитектуры).
    Все остальные подсистемы читают/пишут через функции этого модуля, не трогая
    массивы напрямую (кроме самого рендер/layout конвейера в hot path, которому
    разрешён прямой доступ к столбцам ради скорости — см. §D "Data structures").

    Реализует:
      ADR-002 — Structure-of-Arrays + косвенная адресация id -> slot,
                 swap-with-last compaction при destroy.
      ADR-003 — Дедупликация dirty-очереди через QUEUED-бит.

    Модуль не зависит от MTA API — это чистая структура данных, поэтому
    полностью тестируема обычным Lua 5.1 интерпретатором вне игры.
]]

DXUI = DXUI or {}
local C = DXUI.Constants -- публикуется constants.lua, загружаемым раньше (см. meta.xml)

-- Lua 5.1 не имеет побитовых операторов — переносимая реализация bitor/band
-- для чисел, укладывающихся в диапазон масок из constants.lua (<= 9 бит).
-- Определены как локальные upvalue-функции модуля, а не глобальные, чтобы
-- не засорять глобальное пространство имён (§68). В сборках MTA, где доступна
-- нативная bit32/bit-библиотека, эти две функции можно заменить прямым
-- проксированием без изменения остального модуля.
local function bitor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit == 1 or bbit == 1 then
            result = result + bitval
        end
        a = (a - abit) / 2
        b = (b - bbit) / 2
        bitval = bitval * 2
    end
    return result
end

local function bitand(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit == 1 and bbit == 1 then
            result = result + bitval
        end
        a = (a - abit) / 2
        b = (b - bbit) / 2
        bitval = bitval * 2
    end
    return result
end

local Storage = {}
Storage.__index = Storage
DXUI.Storage = Storage

function Storage.new()
    local self = setmetatable({}, Storage)

    -- ---- SoA columns, индексированы SLOT-ом (1..count), НЕ id -------
    self.x         = {}
    self.y         = {}
    self.w         = {}
    self.h         = {}
    -- M4: layout-описание (ADR-007). x/y/w/h — ЛОКАЛЬНЫЕ значения узла;
    -- world-координаты вычисляет render/layout.lua при DIRTY_LAYOUT.
    self.layoutMode = {} -- C.LAY_ABS | C.LAY_REL | C.LAY_CENTER
    self.anchor     = {} -- C.ANCHOR_*
    -- M4: margin/padding — packed number 0x00FFFFFF: mL=bits 0-7, mT=8-15,
    -- mR=16-23, mB=24-31. Четыре числа в одном — экономия 3 table-lookup
    -- в hot path layout (ADR-007 §D). Поддержка 0..255 px на сторону —
    -- более чем достаточно для UI.
    self.margin     = {} -- отступ узла от границ родителя (свойство узла)
    self.padding    = {} -- внутренний отступ контейнера (свойство контейнера)
    self.worldX     = {} -- M4: вычисленные world-координаты (layout pass)
    self.worldY     = {} -- M4: вычисленные world-координаты (layout pass)
    self.opacity    = {} -- M5: 0..255, 255 = fully opaque (default)
    self.blur       = {} -- M5: 0..32, 0 = no blur (default)
    self.clipDepth  = {} -- M5: depth in clip stack (0 = no clip)
    -- M8: эффективный clip-регион узла (world bounds ближайшего clip-предка)
    self.clipX = {}
    self.clipY = {}
    self.clipW = {}
    self.clipH = {}
    -- M10: полный clip-стек (вложенные clip-области, ADR-009).
    -- clipX1/Y1/W1/H1 — outermost, clipX4/Y4/W4/H4 — innermost.
    -- Уровни сверх MAX_CLIP_DEPTH сводятся к innermost (ограничение).
    for level = 1, C.MAX_CLIP_DEPTH do
        self["clipX" .. level] = {}
        self["clipY" .. level] = {}
        self["clipW" .. level] = {}
        self["clipH" .. level] = {}
    end
    -- M6: активные анимации узла. Значение — slot в AnimationPool или
    -- C.NO_ANIM_SLOT (0). Один узел может одновременно анимировать
    -- до 5 свойств (x/y/w/h/opacity) — отдельных pool-slot'ов.
    self.animX = {}
    self.animY = {}
    self.animW = {}
    self.animH = {}
    self.animOpacity = {} -- M20 (ADR-024)
    self.zIndex    = {}
    self.nodeType  = {}
    self.flags     = {}
    self.dirty     = {}
    -- M2: render-релевантные поля (Renderer читает их, Storage только хранит)
    self.color        = {} -- packed RGBA number, семантика формата — забота backend'а (M2 не вызывает dx* напрямую)
    self.texture      = {} -- opaque handle/nil, интерпретируется backend'ом
    self.text         = {} -- string/nil
    self.layer        = {} -- C.LAYER_*
    self.cmdSlot      = {} -- индекс в RenderCmdPool, C.NO_CMD_SLOT если ещё не выделен
    self.effectiveVisible = {} -- кэш культинга: FLAG_VISIBLE узла И всех предков (см. render/culling.lua)
    -- родственные связи хранятся как ID (стабильны при перемещении slot'ов)
    self.parent      = {}
    self.firstChild  = {}
    self.nextSibling = {}
    self.prevSibling = {}

    -- ---- id <-> slot индирекция (ADR-002) ----------------------------
    self.idToSlot = {}   -- [id]   -> slot
    self.slotToId = {}   -- [slot] -> id

    self.count = 0        -- число живых узлов == последний занятый slot
    self.nextFreshId = 1  -- следующий никогда не использованный id
    self.freeIds = {}     -- стек id, освобождённых после destroy, для переиспользования
    self.freeIdsCount = 0

    -- ---- dirty-очередь за текущий кадр (ADR-003) ----------------------
    self.dirtyList  = {}  -- плоский массив id, без дублей за кадр
    self.dirtyCount = 0

    -- M2: глобальный флаг "порядок отрисовки мог измениться" — дешёвая
    -- альтернатива полной пересортировке команд каждый кадр (§60 ТЗ).
    -- Взводится точечно там, где порядок реально мог поменяться:
    -- create/destroy render-эмиттера, смена layer. Смена zIndex внутри
    -- одного layer вынесена за скобки M2 (виджеты со своим z есть в M4+).
    self.orderDirty = true -- на самом первом кадре порядок точно нужно построить

    -- M3: плоский список интерактивных узлов (§27 ТЗ — "для большинства UI
    -- достаточно optimized flat interactive list", не полный обход дерева
    -- на каждое движение мыши). Индексирован по id (не по slot — id стабилен),
    -- с обратным индексом для O(1) удаления через swap-with-last.
    self.interactiveIds = {}
    self.interactiveIndexOf = {} -- [id] -> позиция в interactiveIds
    self.interactiveCount = 0

    return self
end

-- =======================================================================
-- id allocation / release
-- =======================================================================

local function allocId(self)
    if self.freeIdsCount > 0 then
        local id = self.freeIds[self.freeIdsCount]
        self.freeIds[self.freeIdsCount] = nil
        self.freeIdsCount = self.freeIdsCount - 1
        return id
    end
    local id = self.nextFreshId
    self.nextFreshId = id + 1
    return id
end

local function releaseId(self, id)
    self.freeIdsCount = self.freeIdsCount + 1
    self.freeIds[self.freeIdsCount] = id
end

-- =======================================================================
-- interactive registry (§27 ТЗ, M3) — internal, поддерживается автоматически
-- =======================================================================

local function addInteractive(self, id)
    if self.interactiveIndexOf[id] then return end -- уже зарегистрирован
    self.interactiveCount = self.interactiveCount + 1
    self.interactiveIds[self.interactiveCount] = id
    self.interactiveIndexOf[id] = self.interactiveCount
end

local function removeInteractive(self, id)
    local idx = self.interactiveIndexOf[id]
    if not idx then return end
    local lastIdx = self.interactiveCount
    local lastId = self.interactiveIds[lastIdx]
    self.interactiveIds[idx] = lastId
    self.interactiveIndexOf[lastId] = idx
    self.interactiveIds[lastIdx] = nil
    self.interactiveIndexOf[id] = nil
    self.interactiveCount = lastIdx - 1
end

-- =======================================================================
-- node creation
-- =======================================================================

--- Создаёт узел и возвращает его стабильный числовой id.
-- @param nodeType числовая константа из constants.lua (C.NODE_*)
-- @param parentId id родителя, либо C.NIL_ID для узла без родителя (root/detached)
function Storage:createNode(nodeType, parentId)
    parentId = parentId or C.NIL_ID

    local id = allocId(self)
    local slot = self.count + 1
    self.count = slot

    self.idToSlot[id] = slot
    self.slotToId[slot] = id

    self.x[slot] = 0
    self.y[slot] = 0
    self.w[slot] = 0
    self.h[slot] = 0
    self.zIndex[slot] = 0
    self.nodeType[slot] = nodeType
    self.flags[slot] = C.FLAG_DEFAULT
    self.dirty[slot] = 0
    self.parent[slot] = C.NIL_ID
    self.firstChild[slot] = C.NIL_ID
    self.nextSibling[slot] = C.NIL_ID
    self.prevSibling[slot] = C.NIL_ID
    self.color[slot] = 0xFFFFFFFF
    self.texture[slot] = nil
    self.text[slot] = nil
    self.layer[slot] = C.LAYER_BASE
    self.cmdSlot[slot] = C.NO_CMD_SLOT
    self.effectiveVisible[slot] = true
    -- M4: layout defaults (ADR-007)
    self.layoutMode[slot] = C.LAY_ABS
    self.anchor[slot]     = C.ANCHOR_TL
    self.margin[slot]     = 0
    self.padding[slot]    = 0
    self.worldX[slot]     = 0
    self.worldY[slot]     = 0
    self.opacity[slot]    = 255
    self.blur[slot]       = 0
    self.clipDepth[slot]  = 0
    -- M8: эффективная clip-область узла (world bounds ближайшего
    -- FLAG_CLIP-предка; 0/0/0/0 если clip-нет). Заполняется Clip.update.
    self.clipX[slot]      = 0
    self.clipY[slot]      = 0
    self.clipW[slot]      = 0
    self.clipH[slot]      = 0
    -- M10: полный clip-стек (вложенные clip-области).
    for level = 1, C.MAX_CLIP_DEPTH do
        self["clipX" .. level][slot] = 0
        self["clipY" .. level][slot] = 0
        self["clipW" .. level][slot] = 0
        self["clipH" .. level][slot] = 0
    end
    self.animX[slot]      = C.NO_ANIM_SLOT
    self.animY[slot]      = C.NO_ANIM_SLOT
    self.animW[slot]      = C.NO_ANIM_SLOT
    self.animH[slot]      = C.NO_ANIM_SLOT
    self.animOpacity[slot] = C.NO_ANIM_SLOT -- M20

    if bitand(self.flags[slot], C.FLAG_ENABLED) > 0 then
        addInteractive(self, id)
    end

    if parentId ~= C.NIL_ID then
        self:setParent(id, parentId)
    end

    self:markDirty(id, C.DIRTY_LAYOUT + C.DIRTY_RENDER)
    self.orderDirty = true
    return id
end

-- =======================================================================
-- parent / child linking (doubly-linked list через id, O(1) unlink)
-- =======================================================================

--- Отвязывает узел от текущего родителя, не трогая его собственных детей.
function Storage:_unlinkFromParent(id)
    local slot = self.idToSlot[id]
    local parentId = self.parent[slot]
    if parentId == C.NIL_ID then return end

    local prevId = self.prevSibling[slot]
    local nextId = self.nextSibling[slot]

    if prevId ~= C.NIL_ID then
        self.nextSibling[self.idToSlot[prevId]] = nextId
    else
        -- id был firstChild у родителя
        self.firstChild[self.idToSlot[parentId]] = nextId
    end

    if nextId ~= C.NIL_ID then
        self.prevSibling[self.idToSlot[nextId]] = prevId
    end

    self.parent[slot] = C.NIL_ID
    self.prevSibling[slot] = C.NIL_ID
    self.nextSibling[slot] = C.NIL_ID

    self:markDirty(parentId, C.DIRTY_CHILDREN + C.DIRTY_LAYOUT)
end

--- Переподвешивает узел под нового родителя (в конец списка детей).
function Storage:setParent(id, parentId)
    local slot = self.idToSlot[id]
    assert(slot, "setParent: unknown id")

    if self.parent[slot] ~= C.NIL_ID then
        self:_unlinkFromParent(id)
    end

    if parentId == C.NIL_ID then
        self:markDirty(id, C.DIRTY_LAYOUT)
        return
    end

    local parentSlot = self.idToSlot[parentId]
    assert(parentSlot, "setParent: unknown parentId")

    local oldFirst = self.firstChild[parentSlot]
    self.nextSibling[slot] = oldFirst
    self.prevSibling[slot] = C.NIL_ID
    if oldFirst ~= C.NIL_ID then
        self.prevSibling[self.idToSlot[oldFirst]] = id
    end
    self.firstChild[parentSlot] = id
    self.parent[slot] = parentId

    -- M16 (ADR-020): наследование layer — дети рендерятся в том же слое,
    -- что и родитель (modal-окно + его дети выше overlay). Новые дети
    -- modal-окна автоматически получают LAYER_MODAL.
    self.layer[slot] = self.layer[parentSlot]

    self:markDirty(parentId, C.DIRTY_CHILDREN + C.DIRTY_LAYOUT)
    self:markDirty(id, C.DIRTY_LAYOUT)
end

--- M4: возвращает world-координаты родителя узла (parentWorldX, parentWorldY).
-- Для корневых узлов (без родителя) возвращает (0, 0).
-- Используется layout-проходом, чтобы избежать циклической зависимости
-- "layout → storage → layout".
function Storage:getParentWorld(id)
    local slot = self.idToSlot[id]
    if not slot then return 0, 0 end
    local parentId = self.parent[slot]
    if parentId == C.NIL_ID then
        return 0, 0
    end
    local pSlot = self.idToSlot[parentId]
    return self.worldX[pSlot], self.worldY[pSlot]
end

--- Возвращает массив id всех прямых детей (используется только в cold path —
-- destroy, отладка; в рендер-hot-path обход идёт через firstChild/nextSibling
-- напрямую, без аллокации массива).
function Storage:getChildren(id)
    local slot = self.idToSlot[id]
    assert(slot, "getChildren: unknown id")
    local result = {}
    local n = 0
    local childId = self.firstChild[slot]
    while childId ~= C.NIL_ID do
        n = n + 1
        result[n] = childId
        childId = self.nextSibling[self.idToSlot[childId]]
    end
    return result
end

-- =======================================================================
-- destroy (swap-with-last compaction, ADR-002)
-- =======================================================================

local ARRAY_FIELDS = {
    "x", "y", "w", "h", "zIndex", "nodeType", "flags", "dirty",
    "parent", "firstChild", "nextSibling", "prevSibling",
    "color", "texture", "text", "layer", "cmdSlot", "effectiveVisible",
    "layoutMode", "anchor", "margin", "padding", "worldX", "worldY",
    "opacity", "blur", "clipDepth", "clipX", "clipY", "clipW", "clipH",
    "clipX1", "clipY1", "clipW1", "clipH1",
    "clipX2", "clipY2", "clipW2", "clipH2",
    "clipX3", "clipY3", "clipW3", "clipH3",
    "clipX4", "clipY4", "clipW4", "clipH4",
    "animX", "animY", "animW", "animH", "animOpacity",
}

--- Уничтожает узел и рекурсивно всех его потомков.
-- Компенсирует "дыру" в SoA-массивах переносом данных последнего активного
-- slot'а на освободившееся место (ADR-002), поэтому массивы всегда плотные.
function Storage:destroyNode(id)
    local slot = self.idToSlot[id]
    if not slot then return end -- уже уничтожен / неизвестен

    -- Сносим детей первыми: собираем список заранее, т.к. дерево мутирует
    -- по ходу рекурсивного destroy (getChildren делает копию).
    local children = self:getChildren(id)
    for i = 1, #children do
        self:destroyNode(children[i])
    end

    -- slot мог поменяться после уничтожения детей (compaction), перечитываем
    slot = self.idToSlot[id]

    -- Захватываем данные, нужные внешним подписчикам (Renderer), ДО того как
    -- compaction их сотрёт — иначе к моменту вызова listener'а cmdSlot узла
    -- уже недоступен (idToSlot[id] == nil).
    local capturedCmdSlot = self.cmdSlot[slot]

    removeInteractive(self, id)

    self:_unlinkFromParent(id)

    local lastSlot = self.count
    if slot ~= lastSlot then
        local movedId = self.slotToId[lastSlot]
        for i = 1, #ARRAY_FIELDS do
            local field = ARRAY_FIELDS[i]
            self[field][slot] = self[field][lastSlot]
        end
        self.idToSlot[movedId] = slot
        self.slotToId[slot] = movedId
    end

    -- очищаем последний (теперь неиспользуемый) slot
    for i = 1, #ARRAY_FIELDS do
        self[ARRAY_FIELDS[i]][lastSlot] = nil
    end
    self.slotToId[lastSlot] = nil
    self.idToSlot[id] = nil
    self.count = lastSlot - 1

    releaseId(self, id)
    self.orderDirty = true

    if self.destroyListeners then
        for i = 1, #self.destroyListeners do
            self.destroyListeners[i](id, capturedCmdSlot)
        end
    end
end

--- Регистрирует функцию, вызываемую с (id, cmdSlot) сразу после уничтожения
-- узла, где cmdSlot — значение поля Storage.cmdSlot узла на момент, ПОКА
-- ОНО ЕЩЁ БЫЛО ДОСТУПНО (после compaction id уже не резолвится в slot).
-- Используется подсистемами вне Storage (например Renderer в M2), чтобы
-- освобождать СВОИ ресурсы, привязанные к id, не заставляя Storage знать
-- об их существовании (разделение ответственности, §5 обзор архитектуры).
function Storage:onNodeDestroyed(listener)
    self.destroyListeners = self.destroyListeners or {}
    self.destroyListeners[#self.destroyListeners + 1] = listener
end

-- =======================================================================
-- dirty system (ADR-001, ADR-003)
-- =======================================================================

--- Помечает узел изменённым указанными битами. Дедуплицирует попадание
-- в dirtyList через служебный бит DIRTY_QUEUED — O(1), без повторов.
function Storage:markDirty(id, bits)
    local slot = self.idToSlot[id]
    if not slot then return end -- узел уже уничтожен — не ошибка, просто no-op
    self:markSlotDirty(slot, bits)
end

--- M9: hot-вариант markDirty по slot (без idToSlot lookup).
-- dirtyList хранит slot (см. комментарий у eachDirty).
function Storage:markSlotDirty(slot, bits)
    local current = self.dirty[slot]
    if bitand(current, C.DIRTY_QUEUED) == 0 then
        self.dirtyCount = self.dirtyCount + 1
        self.dirtyList[self.dirtyCount] = slot
        current = current + C.DIRTY_QUEUED
    end
    self.dirty[slot] = bitor(current, bits)
end

--- Возвращает true, если у узла установлен указанный dirty-бит (или любой
-- бит из маски bits).
function Storage:hasDirty(id, bits)
    local slot = self.idToSlot[id]
    if not slot then return false end
    return bitand(self.dirty[slot], bits) > 0
end

--- Вызывается один раз в конце кадра рендер-конвейером (§E pipeline, шаг 7).
-- Полностью очищает dirty-очередь и содержательные+служебный биты
-- у всех узлов, которые были в очереди.
function Storage:clearFrameDirty()
    for i = 1, self.dirtyCount do
        local slot = self.dirtyList[i]
        self.dirty[slot] = 0
        self.dirtyList[i] = nil
    end
    self.dirtyCount = 0
end

-- M9: dirtyList хранит SLOTS (не id) — hot-итераторы работают напрямую
-- по slot (SoA-индекс), без idToSlot lookup на каждом шаге. clearFrameDirty
-- тоже работает по slot. ВНИМАНИЕ: dirtyList — ВНУТРЕННЯЯ структура кадра;
-- destroy() между созданием итератора и концом кадра может оставить в
-- списке "дыру" slot, которую занял новый узел (swap-with-last). Это
-- безопасно: каждый проход проверяет hasFlag/hasSlotDirty ДО обработки,
-- а новый узел с этим slot сам будет обработан (у него тоже биты стоят).
--- Итератор по узлам, ожидающим обработки в текущем кадре (hot path).
-- Возвращает id (для совместимости API), но итерация идёт по slot.
function Storage:eachDirty()
    local i = 0
    local n = self.dirtyCount
    local list = self.dirtyList
    local slotToId = self.slotToId
    return function()
        i = i + 1
        if i > n then return nil end
        return slotToId[list[i]]
    end
end

--- Итератор, который дополнительно пропускает мёртвые id (M4: layout-pass
-- использует его, т.к. layout-проход может быть прерван destroy из
-- пользовательского колбэка — см. ADR-007 §Edge cases).
-- M9: возвращает (id, slot) — второй аргумент снимает idToSlot lookup.
function Storage:eachDirtyLive()
    local i = 0
    local n = self.dirtyCount
    local list = self.dirtyList
    local slotToId = self.slotToId
    return function()
        local id, slot
        repeat
            i = i + 1
            if i > n then return nil, nil end
            slot = list[i]
            id = slotToId[slot]
        until id ~= nil
        return id, slot
    end
end

--- M9: hot-вариант hasDirty по slot (без idToSlot lookup).
-- Проверяет биты в маске bits (0 — любой бит).
function Storage:hasSlotDirty(slot, bits)
    if bits == 0 then
        return self.dirty[slot] > 0x100
    end
    return bitand(self.dirty[slot], bits) > 0
end

-- =======================================================================
-- flags helpers
-- =======================================================================

function Storage:setFlag(id, flagBits, on)
    local slot = self.idToSlot[id]
    assert(slot, "setFlag: unknown id")
    if on then
        self.flags[slot] = bitor(self.flags[slot], flagBits)
    else
        -- снять бит: XOR с текущим значением там, где он установлен
        local cur = self.flags[slot]
        if bitand(cur, flagBits) > 0 then
            self.flags[slot] = cur - flagBits
        end
    end

    -- M3: держим interactive-реестр синхронизированным с FLAG_ENABLED.
    -- Проверяем через bitand с самим flagBits (а не просто "flagBits ==
    -- FLAG_ENABLED"), т.к. вызывающая сторона может передать составную маску.
    if bitand(flagBits, C.FLAG_ENABLED) > 0 then
        if bitand(self.flags[slot], C.FLAG_ENABLED) > 0 then
            addInteractive(self, id)
        else
            removeInteractive(self, id)
        end
    end
end

function Storage:hasFlag(id, flagBits)
    local slot = self.idToSlot[id]
    if not slot then return false end
    return bitand(self.flags[slot], flagBits) > 0
end

-- =======================================================================
-- debug / introspection (cold path only)
-- =======================================================================

function Storage:isAlive(id)
    return self.idToSlot[id] ~= nil
end

function Storage:stats()
    return {
        liveNodes = self.count,
        dirtyQueued = self.dirtyCount,
        freeIdsPooled = self.freeIdsCount,
        nextFreshId = self.nextFreshId,
    }
end
