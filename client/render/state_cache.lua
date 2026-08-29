--[[
    state_cache.lua

    §63 ТЗ: "Renderer должен отслеживать: current texture, current shader,
    current blend mode, current RT — и избегать redundant state changes."

    Driver — таблица с функциями, реально выполняющими работу (в проде —
    обёртки над dxDraw*/dxSetBlendMode, см. render/backend_mta.lua; в
    тестах — мок, который просто записывает вызовы в лог).

    Ожидаемый интерфейс driver:
      driver.setBlendMode(mode)
      driver.drawRect(x, y, w, h, color)
      driver.drawImage(x, y, w, h, texture, color)
      driver.drawText(text, x, y, w, h, color)
      -- M8 (ADR-011): clip через RT (push/pop), opacity/blur через driver state.
      driver.pushClip(x, y, w, h)
      driver.popClip()
      driver.setOpacity(opacity)
      driver.setBlur(blur)

    M10: ПОЛНЫЙ ВЛОЖЕННЫЙ clip-стек. Вместо single-level (0/1) отслеживаем
    фактическую глубину и push/pop по цепочке clipX1..clipX4 (ADR-009).
    RT Manager (ADR-011) уже поддерживает произвольную вложенность.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

DXUI.StateCache = {}
local StateCache = DXUI.StateCache
StateCache.__index = StateCache

local BLEND_DEFAULT = "blend"

--- Возвращает clip-регион уровня level (1..MAX_CLIP_DEPTH) из cmd-пула.
-- level 1 = outermost, level N = innermost. Без string-concat (hot path).
local function clipRegionAt(pool, cmdSlot, level)
    if level == 1 then
        return pool.clipX1[cmdSlot] or 0, pool.clipY1[cmdSlot] or 0,
               pool.clipW1[cmdSlot] or 0, pool.clipH1[cmdSlot] or 0
    elseif level == 2 then
        return pool.clipX2[cmdSlot] or 0, pool.clipY2[cmdSlot] or 0,
               pool.clipW2[cmdSlot] or 0, pool.clipH2[cmdSlot] or 0
    elseif level == 3 then
        return pool.clipX3[cmdSlot] or 0, pool.clipY3[cmdSlot] or 0,
               pool.clipW3[cmdSlot] or 0, pool.clipH3[cmdSlot] or 0
    else
        return pool.clipX4[cmdSlot] or 0, pool.clipY4[cmdSlot] or 0,
               pool.clipW4[cmdSlot] or 0, pool.clipH4[cmdSlot] or 0
    end
end

function StateCache.new(driver)
    local self = setmetatable({}, StateCache)
    self.driver = driver
    self.currentBlendMode = nil
    -- M8/M10: clip/opacity/blur state tracking.
    self.currentClipDepth = 0
    self.currentClipX = 0
    self.currentClipY = 0
    self.currentClipW = 0
    self.currentClipH = 0
    -- M10: стек запушенных clip-регионов (для корректного восстановления
    -- currentClip* после pop — иначе после pop остаётся stale innermost).
    self.clipStackX = {}
    self.clipStackY = {}
    self.clipStackW = {}
    self.clipStackH = {}
    self.currentOpacity = 255
    self.currentBlur = 0
    return self
end

function StateCache:setBlendMode(mode)
    if self.currentBlendMode == mode then
        return
    end
    self.currentBlendMode = mode
    self.driver.setBlendMode(mode)
end

--- Обновляет currentClip* до вершины стека (или 0/0/0/0 если пуст).
local function refreshClipTop(self)
    local d = self.currentClipDepth
    if d > 0 then
        self.currentClipX = self.clipStackX[d]
        self.currentClipY = self.clipStackY[d]
        self.currentClipW = self.clipStackW[d]
        self.currentClipH = self.clipStackH[d]
    else
        self.currentClipX = 0
        self.currentClipY = 0
        self.currentClipW = 0
        self.currentClipH = 0
    end
end

--- Выполняет один render command через driver, используя дедуплицированные
-- state-переходы. pool/cmdSlot — команда для отрисовки.
function StateCache:execute(pool, cmdSlot)
    self:setBlendMode(BLEND_DEFAULT)

    -- M10: полный вложенный clip-стек. targetDepth — число активных
    -- clip-областей для этой команды; цепочка — clipX1..clipX4.
    local targetDepth = pool.clipDepth[cmdSlot] or 0

    -- 1. Pop до targetDepth (лишние уровни).
    while self.currentClipDepth > targetDepth do
        self.driver.popClip()
        self.currentClipDepth = self.currentClipDepth - 1
        refreshClipTop(self)
    end

    -- 2. Если глубина та же, но innermost-регион изменился — pop + re-push.
    --    (Смена региона при равной глубине = переход между sibling clip-ами.
    --    Полная цепочка при этом совпадает, т.к. clip-предки образуют единый
    --    путь от корня — сравнение innermost достаточно.)
    if self.currentClipDepth == targetDepth and targetDepth > 0 then
        local cx = pool.clipX[cmdSlot] or 0
        local cy = pool.clipY[cmdSlot] or 0
        local cw = pool.clipW[cmdSlot] or 0
        local ch = pool.clipH[cmdSlot] or 0
        if cx ~= self.currentClipX or cy ~= self.currentClipY
           or cw ~= self.currentClipW or ch ~= self.currentClipH then
            self.driver.popClip()
            self.currentClipDepth = self.currentClipDepth - 1
            refreshClipTop(self)
        end
    end

    -- 3. Push до targetDepth (недостающие уровни).
    while self.currentClipDepth < targetDepth do
        local level = self.currentClipDepth + 1
        local cx, cy, cw, ch = clipRegionAt(pool, cmdSlot, level)
        self.driver.pushClip(cx, cy, cw, ch)
        self.currentClipDepth = self.currentClipDepth + 1
        self.clipStackX[self.currentClipDepth] = cx
        self.clipStackY[self.currentClipDepth] = cy
        self.clipStackW[self.currentClipDepth] = cw
        self.clipStackH[self.currentClipDepth] = ch
        self.currentClipX, self.currentClipY, self.currentClipW, self.currentClipH = cx, cy, cw, ch
    end

    -- M8: opacity/blur state dedup
    local opacity = pool.opacity[cmdSlot] or 255
    local blur = pool.blur[cmdSlot] or 0

    if opacity ~= self.currentOpacity then
        self.driver.setOpacity(opacity)
        self.currentOpacity = opacity
    end
    if blur ~= self.currentBlur then
        self.driver.setBlur(blur)
        self.currentBlur = blur
    end

    local cmdType = pool.type[cmdSlot]
    if cmdType == C.CMD_RECT then
        self.driver.drawRect(
            pool.x[cmdSlot], pool.y[cmdSlot], pool.w[cmdSlot], pool.h[cmdSlot],
            pool.color[cmdSlot]
        )
    elseif cmdType == C.CMD_IMAGE then
        self.driver.drawImage(
            pool.x[cmdSlot], pool.y[cmdSlot], pool.w[cmdSlot], pool.h[cmdSlot],
            pool.texture[cmdSlot], pool.color[cmdSlot]
        )
    elseif cmdType == C.CMD_TEXT then
        self.driver.drawText(
            pool.text[cmdSlot], pool.x[cmdSlot], pool.y[cmdSlot],
            pool.w[cmdSlot], pool.h[cmdSlot], pool.color[cmdSlot]
        )
    end
end

--- Вызывается Kernel ПОСЛЕ executeOrder: выгнать все оставшиеся clip-стек
-- (RT не должны переживать кадр — новый кадр начинает с чистого стека).
function StateCache:flushClip()
    while self.currentClipDepth > 0 do
        self.currentClipDepth = self.currentClipDepth - 1
        self.driver.popClip()
    end
    self.currentClipX = 0
    self.currentClipY = 0
    self.currentClipW = 0
    self.currentClipH = 0
end

--- Выполняет весь draw order за кадр.
function StateCache:executeOrder(pool, order)
    for i = 1, #order do
        self:execute(pool, order[i])
    end
end