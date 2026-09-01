---StateCache — render state cache: deduplicates expensive native state
---transitions (dxSetBlendMode, dxSetShaderValue). Per-draw bindings
---(texture, font) are per-call MTA args and carry no state — only blend
---mode and effect parameters are global state that must be deduped.
---
---Identity rule: effect tables are SHARED via the Effects cache (identical
---inputs → same table), so pointer identity is a valid "unchanged" test.
---Texel sizes are baked into the shared effect table at creation.

DXUI = DXUI or {}

local StateCache = {}
StateCache.__index = StateCache

local BLEND_DEFAULT = "blend"

--- Creates a state cache bound to a backend.
function StateCache.new(backend)
    local self = setmetatable({}, StateCache)
    self.backend = backend
    self.currentBlendMode = nil
    return self
end

--- Sets the blend mode, skipping the native call when unchanged.
function StateCache:setBlendMode(mode)
    -- stable: ~1 call total
    if self.currentBlendMode == mode then return end
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
        b.drawRoundedRect(item.x, item.y, item.w, item.h,
            item.rtl, item.rtr, item.rbr, item.rbl,
            item.color, item.borderColor, item.borderWidth)
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
            -- positions are ALREADY screen-space (scale applied at emit);
            -- endGroup must not scale them again
            b.endGroup(item.x, item.y, item.w, item.h, item.effect, item.alpha)
        else
            -- RT unavailable: draw contents directly (graceful degradation)
            local children = item.items
            for j = 1, item.count do
                self:draw(children[j])
            end
        end
        -- NOTE: item.items is NOT recycled here. The cached draw list still
        -- references it until the next rebuild (RenderPass.recyclePrevGroupArrs).
    end
end

DXUI.RenderState = StateCache