--[[
    state.lua — DXUI V2

    State cache (§24): дедуплицирует redundant state-переходы (blend mode,
    позже — texture/shader/render target), чтобы не вызывать дорогие
    dxSetBlendMode и т.п. без необходимости.

    Backend — таблица функций, реально выполняющих работу (в проде — обёртки
    над dxDraw*/dxSetBlendMode, см. backend_mta.lua; в тестах — мок).

    Интерфейс backend:
        backend.setBlendMode(mode)
        backend.drawRect(x, y, w, h, color)
        backend.drawImage(x, y, w, h, texture, color)
        backend.drawText(text, x, y, w, h, color)
        backend.drawLine(x1, y1, x2, y2, color)
]]

DXUI = DXUI or {}

local StateCache = {}
StateCache.__index = StateCache

local BLEND_DEFAULT = "blend"

function StateCache.new(backend)
    local self = setmetatable({}, StateCache)
    self.backend = backend
    self.currentBlendMode = nil
    return self
end

function StateCache:setBlendMode(mode)
    if self.currentBlendMode == mode then return end
    self.currentBlendMode = mode
    self.backend.setBlendMode(mode)
end

--- Выполняет один render item через backend с дедуплицированным состоянием.
function StateCache:draw(item)
    self:setBlendMode(BLEND_DEFAULT)

    local kind = item.kind
    if kind == "rect" then
        self.backend.drawRect(item.x, item.y, item.w, item.h, item.color)
    elseif kind == "image" then
        self.backend.drawImage(item.x, item.y, item.w, item.h, item.texture, item.color)
    elseif kind == "text" then
        self.backend.drawText(item.text, item.x, item.y, item.w, item.h, item.color)
    elseif kind == "line" then
        self.backend.drawLine(item.x1, item.y1, item.x2, item.y2, item.color)
    end
end

DXUI.StateCache = StateCache
