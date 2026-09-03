---Image — texture quad with tint (color), section cropping and optional
---blur/mask effect (via node.fx properties, rendered with the direct
---shader path — the cheap one).
---
---    local img = ui:image({ texture = "assets/logo.png",
---                           x=0, y=0, width=64, height=64 })


DXUI = DXUI or {}

local Image = DXUI.Widget:extend("Image", {
    texture = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- source crop region in pixels: {x, y, w, h}
    section = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- pixel-perfect hit testing: transparent texels do not catch
    -- hover/click (bit-packed alpha mask, ≤256 per side — see
    -- input/hit_test.lua). rotation is NOT supported (rect fallback).
    pixelHit = { default = false, invalidates = { DXUI.DIRTY.INPUT } },
    -- clockwise rotation (degrees) around rotationCenterX/Y — offsets
    -- relative to the quad's top-left (default = the quad's own center).
    -- NOTE: hit-testing stays AABB — the hit rectangle does not rotate.
    rotation = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    rotationCenterX = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    rotationCenterY = { default = nil, invalidates = { DXUI.DIRTY.RENDER } },
    -- linear gradient fill (E6): { from, to, angle } — replaces the
    -- texture draw entirely (a gradient quad). See panel.lua.
    gradient = { default = nil, invalidates = { DXUI.DIRTY.RENDER }, validate = function(v)
        if v == nil then return true end
        if type(v) ~= "table" then return false end
        if v.from ~= nil and type(v.from) ~= "number" then return false end
        if v.to ~= nil and type(v.to) ~= "number" then return false end
        if v.angle ~= nil and type(v.angle) ~= "number" then return false end
        return true
    end },
})

--- Draws the texture quad with tint and optional crop (or the gradient).
function Image:render(renderer)
    local grad = self.gradient
    if grad then
        local fx = DXUI.Effects and DXUI.Effects.gradient(self.width, self.height, grad)
        if fx then
            renderer.fx = fx
            renderer:image(fx.shader, self.worldX, self.worldY, self.width, self.height,
                self.color)
            renderer.fx = nil
            return
        end
    end
    if not self.texture then return end
    -- pass rotation only when actually rotating: the render path is
    -- byte-for-byte the old one for rotation == 0
    renderer:image(self.texture, self.worldX, self.worldY, self.width, self.height,
        self.color, self.section, (self.rotation ~= 0) and self.rotation or nil,
        self.rotationCenterX, self.rotationCenterY)
end

DXUI.Builders.register("Image", Image)