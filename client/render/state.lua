--[[
    state.lua — DXUI V2

    State cache: deduplicates redundant state transitions (blend mode, later
    texture/shader/render target) so expensive dxSetBlendMode and similar
    calls are skipped when unnecessary.

    The backend is a table of functions that do the real work (in
    production — wrappers over dxDraw*/dxSetBlendMode; in tests — a mock).

    Backend interface:
        backend.setBlendMode(mode)
        backend.drawRect(x, y, w, h, color)
        backend.drawRoundedRect(x, y, w, h, radius, color, effect)
        backend.drawImage(x, y, w, h, texture, color, effect, section)
        backend.drawText(text, x, y, w, h, color, font, align, valign, scaleX, scaleY)
        backend.drawLine(x1, y1, x2, y2, color, width)
        backend.beginGroup(x, y, w, h)   -- returns true when an RT was acquired
        backend.endGroup(x, y, w, h, effect, alpha)
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

--- Executes one render item via the backend with deduplicated state.
function StateCache:draw(item)
    self:setBlendMode(BLEND_DEFAULT)

    local kind = item.kind
    if kind == "rect" then
        self.backend.drawRect(item.x, item.y, item.w, item.h, item.color)
    elseif kind == "rrect" then
        self.backend.drawRoundedRect(item.x, item.y, item.w, item.h, item.radius, item.color, item.effect)
    elseif kind == "image" then
        self.backend.drawImage(item.x, item.y, item.w, item.h, item.texture, item.color, item.effect, item.section)
    elseif kind == "text" then
        self.backend.drawText(item.text, item.x, item.y, item.w, item.h,
            item.color, item.font, item.align, item.valign, item.scaleX, item.scaleY)
    elseif kind == "line" then
        self.backend.drawLine(item.x1, item.y1, item.x2, item.y2, item.color, item.width)
    elseif kind == "rtgroup" then
        -- group contents → offscreen RT → drawn as one quad.
        -- alpha (true group opacity) applies to the whole quad.
        -- Nested groups are supported (groupStack in the backend).
        if self.backend.beginGroup(item.x, item.y, item.w, item.h) then
            local children = item.items
            for j = 1, item.count do
                self:draw(children[j])
            end
            local sX = item.scaleX or 1
            local sY = item.scaleY or 1
            self.backend.endGroup(item.x, item.y, item.w * sX, item.h * sY, item.effect, item.alpha)
        else
            -- RT unavailable: draw contents directly, no effect (graceful)
            local children = item.items
            for j = 1, item.count do
                self:draw(children[j])
            end
        end
    end
end

DXUI.StateCache = StateCache
