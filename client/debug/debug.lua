--[[
    debug.lua (M10)

    Debug-система: инспекция дерева узлов, bounds-overlay, dirty-визуализация.
    §50 ТЗ: "production: minimal overhead" — Debug ОТКЛЮЧЁН по умолчанию
    (enabled = false), его стоимость в проде = 0. Включение — только вручную:
    DXUI.toggleDebug() (chat/console).

    Возможности (все — cold path, только при enabled):
      - dumpTree(maxDepth): печать иерархии (тип/pos/size/flags/dirty).
      - inspect(id): детальная информация об узле.
      - drawBounds(driver): цветные рамки узлов (по типу) + подсветка dirty.
      - hitTest(px, py): какой узел под курсором (через Dispatcher).

    Никаких per-node обработчиков/таймеров: всё — единый проход по SoA-массивам
    (ADR-002), вызывается вручную или из bootstrap-оверлея.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.Debug = {}
local Debug = DXUI.Debug
Debug.__index = Debug

-- Имена типов (cold path, reverse map — только для вывода).
local NODE_NAMES = {
    [C.NODE_ROOT] = "root",
    [C.NODE_PANEL] = "panel",
    [C.NODE_BUTTON] = "button",
    [C.NODE_TEXT] = "text",
    [C.NODE_IMAGE] = "image",
    [C.NODE_WINDOW] = "window",
    [C.NODE_CUSTOM] = "custom",
}

-- Цвета типов для bounds-overlay (0xAARRGGBB, tocolor-конвенция).
local TYPE_COLORS = {
    [C.NODE_ROOT]   = 0x30808080,
    [C.NODE_PANEL]  = 0x304080FF,
    [C.NODE_BUTTON] = 0x3080FF80,
    [C.NODE_TEXT]   = 0x30FFFF80,
    [C.NODE_IMAGE]  = 0x30FF80FF,
    [C.NODE_WINDOW] = 0x30FF4040,
    [C.NODE_CUSTOM] = 0x30FFFFFF,
}

local DIRTY_COLOR = 0xFFFF0000 -- красная рамка для dirty-узлов

function Debug.new(kernel)
    local self = setmetatable({}, Debug)
    self.kernel = kernel
    self.storage = kernel.storage
    self.enabled = false
    return self
end

function Debug:setEnabled(v)
    self.enabled = v
end

function Debug:toggle()
    self.enabled = not self.enabled
    return self.enabled
end

--- Имя типа узла (cold path).
local function typeName(nodeType)
    return NODE_NAMES[nodeType] or ("type" .. tostring(nodeType))
end

--- Печать иерархии дерева (cold path, только при enabled).
-- maxDepth: 0 = без ограничения, N = глубина.
function Debug:dumpTree(maxDepth)
    local s = self.storage
    local lines = {}
    lines[#lines + 1] = string.format("DXUI tree (%d nodes):", s.count)

    -- Итеративный DFS от корней (parent == NIL_ID).
    -- Стек: { slot, depth }.
    local stkSlot = {}
    local stkDepth = {}
    local top = 0

    -- Находим корни (узлы без родителя).
    for slot = 1, s.count do
        if s.parent[slot] == C.NIL_ID then
            top = top + 1
            stkSlot[top] = slot
            stkDepth[top] = 0
        end
    end

    while top > 0 do
        local slot = stkSlot[top]
        local depth = stkDepth[top]
        top = top - 1

        if maxDepth == nil or depth <= maxDepth then
            local id = s.slotToId[slot]
            local indent = string.rep("  ", depth)
            local dirty = s.dirty[slot] > 0 and " [DIRTY]" or ""
            lines[#lines + 1] = string.format(
                "%s#%d %s pos=(%d,%d) size=(%d,%d) world=(%d,%d) flags=0x%02X%s",
                indent, id, typeName(s.nodeType[slot]),
                s.x[slot] or 0, s.y[slot] or 0,
                s.w[slot] or 0, s.h[slot] or 0,
                s.worldX[slot] or 0, s.worldY[slot] or 0,
                s.flags[slot] or 0, dirty
            )
        end

        -- Пушим детей (firstChild/nextSibling).
        local childId = s.firstChild[slot]
        while childId ~= C.NIL_ID do
            local cs = s.idToSlot[childId]
            top = top + 1
            stkSlot[top] = cs
            stkDepth[top] = depth + 1
            childId = s.nextSibling[cs]
        end
    end

    return table.concat(lines, "\n")
end

--- Детальная информация об узле (cold path).
function Debug:inspect(id)
    local s = self.storage
    local slot = s.idToSlot[id]
    if not slot then
        return string.format("node #%d: NOT FOUND", id)
    end
    local lines = {}
    lines[#lines + 1] = string.format("node #%d (%s):", id, typeName(s.nodeType[slot]))
    lines[#lines + 1] = string.format("  slot=%d parent=#%d", slot, s.parent[slot])
    lines[#lines + 1] = string.format("  local=(%d,%d) size=(%d,%d)", s.x[slot] or 0, s.y[slot] or 0, s.w[slot] or 0, s.h[slot] or 0)
    lines[#lines + 1] = string.format("  world=(%d,%d)", s.worldX[slot] or 0, s.worldY[slot] or 0)
    lines[#lines + 1] = string.format("  flags=0x%02X dirty=0x%03X", s.flags[slot] or 0, s.dirty[slot] or 0)
    lines[#lines + 1] = string.format("  layoutMode=%d anchor=%d margin=%d padding=%d",
        s.layoutMode[slot] or 0, s.anchor[slot] or 0, s.margin[slot] or 0, s.padding[slot] or 0)
    lines[#lines + 1] = string.format("  clipDepth=%d clip=(%d,%d,%d,%d)",
        s.clipDepth[slot] or 0, s.clipX[slot] or 0, s.clipY[slot] or 0, s.clipW[slot] or 0, s.clipH[slot] or 0)
    return table.concat(lines, "\n")
end

--- Рисует цветные рамки узлов (cold path, только при enabled).
-- driver — тот же driver, что у Kernel (drawRect). Вызывается из отдельного
-- onClientRender handler ПОСЛЕ renderFrame (bounds поверх UI).
function Debug:drawBounds(driver)
    if not driver or not driver.drawRect then return end
    local s = self.storage
    for slot = 1, s.count do
        local id = s.slotToId[slot]
        if id then
            local x, y = s.worldX[slot] or 0, s.worldY[slot] or 0
            local w, h = s.w[slot] or 0, s.h[slot] or 0
            if w > 0 and h > 0 then
                local color = TYPE_COLORS[s.nodeType[slot]] or 0x30FFFFFF
                driver.drawRect(x, y, w, h, color)
                -- Dirty-подсветка: красная рамка (4 тонких rect).
                if s.dirty[slot] > 0 then
                    driver.drawRect(x, y, w, 1, DIRTY_COLOR)
                    driver.drawRect(x, y + h - 1, w, 1, DIRTY_COLOR)
                    driver.drawRect(x, y, 1, h, DIRTY_COLOR)
                    driver.drawRect(x + w - 1, y, 1, h, DIRTY_COLOR)
                end
            end
        end
    end
end

--- Какой узел под курсором (cold path, через HitTest.pick).
-- Возвращает id или nil.
function Debug:hitTest(px, py)
    local id = DXUI.HitTest.pick(self.storage, px, py)
    if id == C.NIL_ID then return nil end
    return id
end
