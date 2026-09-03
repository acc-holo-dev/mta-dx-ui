---Button — themed surface + centered text; interaction states wired to
---the style system (hover/pressed/disabled). Variants via node.style:
---
---    local b = ui:button({ text="Save", x=10, y=100, style="secondary" })
---    b:on("click", function(n) save() end)
---
---Theme props: color, textColor, radius, borderColor. Optional background
---texture: `texture` (path | dx texture handle) drawn over the surface
---color and under the text; `textureSection` crops it ({x,y,w,h} px).
---Theme states apply it too — states.hover.texture swaps on hover. A
---failed load falls back to the plain color surface (one warn per value).
---`gradient` (E6) replaces the color surface with a linear gradient
---(ONE shared shader — see render/effects.lua); border still rings it.


DXUI = DXUI or {}

--- Resolves the texture prop: handles pass through; path strings go
--- through DXUI.texture (shared cache, FAIL_TTL retry). Failed loads are
--- not cached here so the manager's retry window stays effective.
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
        if DXUI._warn then DXUI._warn("texture not found: " .. tostring(t)) end
    end
    return nil
end

local Button = DXUI.Widget:extend("Button", {
    text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    textColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    borderColor = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    borderWidth = { default = 1, invalidates = { DXUI.DIRTY.RENDER } },
    -- background texture (path | handle; nil = plain color surface)
    texture = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- texture crop {x, y, w, h} in pixels
    textureSection = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- linear gradient fill (E6): { from, to, angle } — replaces the color
    -- surface; theme states may swap it. See panel.lua for the full note.
    gradient = { default = nil, invalidates = { DXUI.DIRTY.RENDER }, validate = function(v)
        if v == nil then return true end
        if type(v) ~= "table" then return false end
        if v.from ~= nil and type(v.from) ~= "number" then return false end
        if v.to ~= nil and type(v.to) ~= "number" then return false end
        if v.angle ~= nil and type(v.angle) ~= "number" then return false end
        return true
    end },
    -- buttons are interactive + focusable by default
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
    focusable = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

--- Draws the button surface (color / gradient / texture) and centered text.
function Button:render(renderer)
    local wx, wy, w, h = self.worldX, self.worldY, self.width, self.height
    if w <= 0 or h <= 0 then return end
    local r = self.radius or 0
    local bc = self.borderColor
    local grad = self.gradient
    local fx = grad and DXUI.Effects and DXUI.Effects.gradient(w, h, grad) or nil
    if fx then
        -- gradient replaces the fill; border and text on top
        if bc then
            renderer:outline(wx, wy, w, h, self.borderWidth or 1, bc)
        end
        renderer.fx = fx
        renderer:image(fx.shader, wx, wy, w, h, 0xFFFFFFFF)
        renderer.fx = nil
    else
        renderer:borderedRect(wx, wy, w, h, r, self.color, bc, self.borderWidth)
        local tex = bgTexture(self)
        if tex then
            -- white tint: the texture shows as authored; the surface color
            -- below fills transparent areas
            renderer:image(tex, wx, wy, w, h, 0xFFFFFFFF, self.textureSection)
        end
    end
    if self.text and self.text ~= "" then
        renderer:text(self.text, wx, wy, w, h, self.textColor, self.font, "center", "center", 1)
    end
end

DXUI.Builders.register("Button", Button)