---StateCache — render state cache: deduplicates expensive native state
---transitions (dxSetBlendMode, dxSetShaderValue). Per-draw bindings
---(texture, font) are per-call MTA args and carry no state — only blend
---mode and effect parameters are global state that must be deduped.
---
---Blend policy (MTA wiki DxSetBlendMode): RT-group CONTENTS draw with
---"modulate_add" (text/alpha keep their quality through a render target);
---a top-level group composites back with "add"; a nested group composites
---with "modulate_add" back into the OUTER RT (the DGS core pattern).
---Everything outside groups runs the default "blend".
---
---Identity rule: effect tables are SHARED via the Effects cache (identical
---inputs → same table), so pointer identity is a valid "unchanged" test.
---Texel sizes are baked into the shared effect table at creation.

DXUI = DXUI or {}

local StateCache = {}
StateCache.__index = StateCache

local BLEND_DEFAULT = "blend"
local BLEND_RT_CONTENT = "modulate_add"

--- Creates a state cache bound to a backend.
function StateCache.new(backend)
    local self = setmetatable({}, StateCache)
    self.backend = backend
    self.currentBlendMode = nil
    -- open RT-group nesting depth (0 = drawing straight to the screen)
    self.groupDepth = 0
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
    -- inside an open RT group the contents run modulate_add (see the
    -- file header); outside — the default blend
    self:setBlendMode(self.groupDepth > 0 and BLEND_RT_CONTENT or BLEND_DEFAULT)
    local kind = item.kind
    local b = self.backend
    if kind == "rect" then
        b.drawRect(item.x, item.y, item.w, item.h, item.color)
    elseif kind == "rrect" then
        b.drawRoundedRect(item.x, item.y, item.w, item.h,
            item.rtl, item.rtr, item.rbr, item.rbl,
            item.color, item.borderColor, item.borderWidth)
    elseif kind == "image" then
        b.drawImage(item.x, item.y, item.w, item.h, item.texture, item.color, item.effect, item.section,
            item.rotation, item.rotCX, item.rotCY)
    elseif kind == "text" then
        b.drawText(item.text, item.x, item.y, item.w, item.h, item.color,
            item.font, item.align, item.valign, item.scaleX, item.scaleY, item.rich)
    elseif kind == "line" then
        b.drawLine(item.x1, item.y1, item.x2, item.y2, item.color, item.width)
    elseif kind == "rtgroup" then
        if item.rtKey then
            -- persistent content cache (cacheContent): the group bakes
            -- into a keyed RT that survives frames. Rebake ONLY when the
            -- node says its content changed (n._rtSigDirty) or the scroll
            -- left the margin window; idle frames composite ONE image.
            local n = item.node
            if n then
                local mTop = (item.rth - item.h) / 2
                local syPix = mTop + (n._rtShift or 0)
                local bake = (n._rtSigDirty ~= false)
                    or syPix < 0 or (syPix + item.h) > item.rth
                if bake then
                    if b.beginPersistentGroup(item.rtKey, item.rtw, item.rth,
                        item.x, item.y - mTop) then
                        self.groupDepth = self.groupDepth + 1
                        local children = item.items
                        for j = 1, item.count do
                            self:draw(children[j])
                        end
                        self.groupDepth = self.groupDepth - 1
                        b.endPersistentGroup()
                        -- commit: the RT now holds this content anchored
                        -- at the current scroll (the node owns base/shift)
                        n._rtSigDirty = false
                    else
                        -- no RT support: draw the contents straight to
                        -- the screen (graceful degradation)
                        local children = item.items
                        for j = 1, item.count do
                            self:draw(children[j])
                        end
                        return
                    end
                end
                -- composite: ONE image section per frame (E4 blend: add
                -- at top level, modulate_add inside an outer RT)
                self:setBlendMode(self.groupDepth > 0 and BLEND_RT_CONTENT or "add")
                if not b.compositePersistentGroup(item.rtKey, item.x, item.y,
                    item.w, item.h, 0, syPix, item.w, item.h) then
                    -- RT vanished between the bake and here (node left
                    -- the tree): degrade to a direct draw this frame
                    local children = item.items
                    for j = 1, item.count do
                        self:draw(children[j])
                    end
                end
            else
                -- node gone mid-cycle: degrade to a direct draw
                local children = item.items
                for j = 1, item.count do
                    self:draw(children[j])
                end
            end
            return
        end
        if b.beginGroup(item.x, item.y, item.w, item.h) then
            self.groupDepth = self.groupDepth + 1
            local children = item.items
            for j = 1, item.count do
                self:draw(children[j])
            end
            self.groupDepth = self.groupDepth - 1
            -- composite: nested content goes modulate_add back into the
            -- OUTER RT; a top-level group composites with "add" (wiki)
            self:setBlendMode(self.groupDepth > 0 and BLEND_RT_CONTENT or "add")
            -- positions are ALREADY screen-space (scale applied at emit);
            -- endGroup must not scale them again
            b.endGroup(item.x, item.y, item.w, item.h, item.effect, item.alpha)
            -- restore is lazy: the next item resets to its group context
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