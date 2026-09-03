---Panel — a plain styled surface. Default visual surface; theme props:
---color (surface), radius, borderColor. Optional background texture:
---`texture` (path | handle) over the color, `textureSection` crops it;
---theme states apply texture too (states.hover.texture etc.). A failed
--- load falls back to the plain color surface (one warn per value).
---`gradient` (E6) replaces the color surface with a linear gradient
---(ONE shared shader — see render/effects.lua); border still rings it.
---
---    local p = ui:panel({ x=0, y=0, width=200, height=50, style="card" })


DXUI = DXUI or {}

--- Resolves the texture prop (see button.lua for the rationale).
local function bgTexture(self)
    local t = self.texture
    if t == nil or t == "" then return nil end
    if type(t) ~= "string" then return t end
    if self._bgTexKey == t and self._bgTex ~= nil then return self._bgTex end
    local h = DXUI.texture and DXUI.texture(t) or nil
    if h ~= nil then
        self._bgTexKey = t
        self._bgTex = h
        return h
    end
    if self._bgTexWarned ~= t then
        self._bgTexWarned = t
        DXUI.Debug.warn("RESOURCE", "texture not found: " .. tostring(t))
    end
    return nil
end

local Panel = DXUI.Widget:extend("Panel", {
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    borderColor = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- background texture (path | handle; nil = plain color surface)
    texture = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- texture crop {x, y, w, h} in pixels
    textureSection = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- linear gradient fill (E6): { from = 0xAARRGGBB, to = 0xAARRGGBB,
    -- angle = degrees (0 = left→right, 90 = top→bottom) } — replaces the
    -- color surface (square corners); the border still rings it. One
    -- shared shader instance; theme states may swap it (states.hover).
    gradient = { default = nil, invalidates = { DXUI.DIRTY.RENDER }, validate = function(v)
        if v == nil then return true end
        if type(v) ~= "table" then return false end
        if v.from ~= nil and type(v.from) ~= "number" then return false end
        if v.to ~= nil and type(v.to) ~= "number" then return false end
        if v.angle ~= nil and type(v.angle) ~= "number" then return false end
        return true
    end },
})

--- Draws the panel as a bordered rounded rectangle, plus its texture
--- (or the gradient instead of the color fill when set).
function Panel:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    if w <= 0 or h <= 0 then return end
    local grad = self.gradient
    local fx = grad and DXUI.Effects and DXUI.Effects.gradient(w, h, grad) or nil
    if fx then
        -- gradient replaces the fill (square corners; border on top)
        if self.borderColor then
            renderer:outline(wx, wy, w, h, self.borderWidth or 1, self.borderColor)
        end
        -- the shader element IS the quad material (it ignores its input)
        renderer.fx = fx
        renderer:image(fx.shader, wx, wy, w, h, 0xFFFFFFFF)
        renderer.fx = nil
        return
    end
    renderer:borderedRect(wx, wy, w, h, self.radius or 0, self.color, self.borderColor, self.borderWidth)
    local tex = bgTexture(self)
    if tex then
        renderer:image(tex, wx, wy, w, h, 0xFFFFFFFF, self.textureSection)
    end
end

DXUI.Builders.register("Panel", Panel)