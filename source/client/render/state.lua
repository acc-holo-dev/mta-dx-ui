--[[
    state.lua — DXUI V3

    Render state cache: deduplicates expensive native state transitions
    (dxSetBlendMode, dxSetShaderValue). Per-draw bindings (texture, font)
    are per-call MTA args and carry no state — only blend mode and effect
    parameters are global state that must be deduped.

    Identity rule: effect tables are SHARED via the Effects cache (identical
    inputs → same table), so pointer identity is a valid "unchanged" test.
    The V2 flaw (per-item texel clones defeating identity) is gone: texel
    sizes are baked into the shared effect table at creation.
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
    if self.currentBlendMode == mode then return end -- stable: ~1 call total
    self.currentBlendMode = mode
    self.backend.setBlendMode(mode)
end

--- Executes one render item via the backend with deduplicated state.
function StateCache:draw(item)
    self:setBlendMode(BLEND_DEFAULT)
    local kind = item.kind
    local b = self.backend
    if kind == "rect" then
        b.drawRect(item.x, item.y, item.w, item.h, item.color)
    elseif kind == "rrect" then
        b.drawRoundedRect(item.x, item.y, item.w, item.h, item.radius, item.color, item.effect)
    elseif kind == "image" then
        b.drawImage(item.x, item.y, item.w, item.h, item.texture, item.color, item.effect, item.section)
    elseif kind == "text" then
        b.drawText(item.text, item.x, item.y, item.w, item.h, item.color,
            item.font, item.align, item.valign, item.scaleX, item.scaleY)
    elseif kind == "line" then
        b.drawLine(item.x1, item.y1, item.x2, item.y2, item.color, item.width)
    elseif kind == "rtgroup" then
        if b.beginGroup(item.x, item.y, item.w, item.h) then
            local children = item.items
            for j = 1, item.count do
                self:draw(children[j])
            end
            b.endGroup(item.x, item.y, item.w * (item.scaleX or 1), item.h * (item.scaleY or 1), item.effect, item.alpha)
        else
            -- RT unavailable: draw contents directly (graceful degradation)
            local children = item.items
            for j = 1, item.count do
                self:draw(children[j])
            end
        end
        if DXUI.RenderList and item.fromPool then
            DXUI.RenderList.recycle(item.items, item.count)
        end
        if item.releaseArr and DXUI.RenderPass then
            DXUI.RenderPass.releaseArr(item.items)
        end
    end
end

DXUI.RenderState = StateCache