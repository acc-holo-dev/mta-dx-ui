--[[
    rt_manager.lua (M8)

    ADR-011: Render Target менеджер — единая владелец offscreen RT.
    Никаких per-node RT: пул RT по размерам, стек активных clip-регионов.

    Ответственность:
      - acquire/release RT по размеру (свободный список, M9-оптимизация).
      - pushClip(x,y,w,h): создать/получить RT, dxSetRenderTarget(rt).
      - popClip(): нарисовать верхний RT в предыдущий target/экран.
      - offsetX/Y — смещение текущего target'а; драйвер вычитает из coords.
      - resize(): очистка пула при смене разрешения (onClientResolutionChange).

    Вложенность: каждый push создаёт свой RT размером clip-региона.
    Координаты внутри RT'а относительны его левого-верхнего угла, поэтому
    driver.drawRect вычитает offset. При pop рисуем quad RT в родительском
    target'е по (x - parentOffsetX, y - parentOffsetY).

    Вне MTA (тесты) RT Manager не инстанциируется — backend_mta.lua
    создаёт его только в игре.
]]

local RTManager = {}
RTManager.__index = RTManager
DXUI = DXUI or {}
DXUI.RTManager = RTManager

function RTManager.new()
    local self = setmetatable({}, RTManager)
    self.pool = {}          -- [key] = { rt1, rt2, ... }
    self.stack = {}         -- активные clip-регионы: { x,y,w,h,rt }
    self.offsetX = 0
    self.offsetY = 0
    return self
end

local function key(w, h)
    return w .. "x" .. h
end

function RTManager:acquire(w, h)
    local k = key(w, h)
    local list = self.pool[k]
    if list and #list > 0 then
        local rt = list[#list]
        list[#list] = nil
        return rt
    end
    return dxCreateRenderTarget(w, h)
end

function RTManager:release(rt)
    if not rt then return end
    local w, h = dxGetMaterialSize(rt)
    local k = key(w, h)
    self.pool[k] = self.pool[k] or {}
    table.insert(self.pool[k], rt)
end

function RTManager:_updateOffset()
    local top = self.stack[#self.stack]
    if top then
        self.offsetX = top.x
        self.offsetY = top.y
    else
        self.offsetX = 0
        self.offsetY = 0
    end
end

--- Возвращает текущий RT (верх стека) или nil (экран).
-- M10: нужен для blur-fallback (rect/text) — временно переключиться на
-- blur-RT и вернуться к текущему target (который может быть clip-RT).
function RTManager:getCurrentRT()
    local top = self.stack[#self.stack]
    return top and top.rt or nil
end

function RTManager:pushClip(x, y, w, h)
    local rt = self:acquire(w, h)
    table.insert(self.stack, { x = x, y = y, w = w, h = h, rt = rt })
    dxSetRenderTarget(rt, true) -- true = очистить при установке
    self:_updateOffset()
end

function RTManager:popClip()
    local top = table.remove(self.stack)
    if not top then return end

    local parent = self.stack[#self.stack]
    dxSetRenderTarget(parent and parent.rt or nil)

    -- Рисуем top.rt в родителе/экране с учётом смещения родителя
    local px, py = 0, 0
    if parent then
        px = parent.x
        py = parent.y
    end
    dxDrawImage(top.x - px, top.y - py, top.w, top.h, top.rt)

    self:release(top.rt)
    self:_updateOffset()
end

--- Уничтожает все RT в пуле (например, при смене разрешения экрана).
function RTManager:resize()
    for k, list in pairs(self.pool) do
        for i = 1, #list do
            if isElement(list[i]) then destroyElement(list[i]) end
        end
        self.pool[k] = nil
    end
    -- Активный стек очищается — на следующем кадре push/pop восстановятся.
    for i = #self.stack, 1, -1 do
        local top = self.stack[i]
        if isElement(top.rt) then destroyElement(top.rt) end
        self.stack[i] = nil
    end
    self.offsetX = 0
    self.offsetY = 0
end
