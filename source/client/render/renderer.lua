--[[
    renderer.lua — DXUI V3

    Public renderer API: the primitives a widget calls from its own
    render(renderer). Primitives add pooled items to the current list.

        function Button:render(renderer)
            renderer:rect(self.worldX, self.worldY, self.width, self.height,
                          self.color)
            renderer:text(self.text, ..., self.textColor, self.font,
                          "center", "center")
        end

    Design-space in, screen-space out: the pass loads the design→screen
    mapping (scale/offset) and each node's clip region + effective opacity
    once; primitives apply them at emission. Colors are normalized via
    ColorToInt (works for packed ints and Color proxies alike).

    Renderer knows NOTHING about the backend (backend_mta) — items only.
]]

DXUI = DXUI or {}

local Renderer = {}
Renderer.__index = Renderer

--- Intersects a rect with the renderer's clip region; nil when fully clipped.
local function clipRect(renderer, x, y, w, h)
    if not renderer.hasClip then return x, y, w, h end
    local cx, cy = renderer.clipX, renderer.clipY
    local cw, ch = renderer.clipW, renderer.clipH
    local x2, y2 = x + w, y + h
    local cx2, cy2 = cx + cw, cy + ch
    local nx = (x > cx) and x or cx
    local ny = (y > cy) and y or cy
    local nx2 = (x2 < cx2) and x2 or cx2
    local ny2 = (y2 < cy2) and y2 or cy2
    if nx2 <= nx or ny2 <= ny then return nil end
    return nx, ny, nx2 - nx, ny2 - ny
end

--- Scales a packed color's alpha by an opacity factor.
local function modulate(color, op)
    if color == nil or op >= 1 then return color end
    if op <= 0 then return 0 end
    local a = math.floor(color / 0x1000000)
    local na = math.floor(a * op)
    if na == a then return color end
    return color - a * 0x1000000 + na * 0x1000000
end

--- Creates a renderer bound to a render list.
function Renderer.new(renderList)
    local self = setmetatable({}, Renderer)
    self.list = renderList
    self.node = nil
    self.hasClip = false
    self.clipX, self.clipY, self.clipW, self.clipH = nil, nil, nil, nil
    self.effOpacity = 1
    self.scaleX, self.scaleY = 1, 1
    self.offsetX, self.offsetY = 0, 0
    -- current effect (blur/mask) set by the pass
    self.fx = nil
    return self
end

--- Resets for a new pass (scale/offset are pass-global, preserved).
function Renderer:reset(list)
    self.list = list
    self.node = nil
    self.hasClip = false
    self.clipX, self.clipY, self.clipW, self.clipH = nil, nil, nil, nil
    self.effOpacity = 1
    return self
end

--- Loads the node's draw state (clip + effective opacity) before render.
function Renderer:_loadClip(node)
    self.hasClip = node._clipX ~= nil
    self.clipX, self.clipY = node._clipX, node._clipY
    self.clipW, self.clipH = node._clipW, node._clipH
    local op = node._effOpacity
    self.effOpacity = (op ~= nil) and op or 1
    self.node = node
end

-- ---------------------------------------------------------------------
-- Primitives (design space; emitted in screen space)
-- ---------------------------------------------------------------------

--- Emits a filled rectangle item.
function Renderer:rect(x, y, w, h, color)
    if self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    -- fully clipped — skip
    if nx == nil then return end
    color = DXUI.ColorToInt(color)
    color = modulate(color, self.effOpacity)
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    local it = DXUI.RenderList.obtain()
    it.kind = "rect"
    it.x = nx * sx + ox
    it.y = ny * sy + oy
    it.w = nw * sx
    it.h = nh * sy
    it.color = color
    self.list:add(it)
end

--- Emits a rounded-rectangle item (SDF effect when radius > 0).
function Renderer:roundedRect(x, y, w, h, radius, color)
    if self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if nx == nil then return end
    color = DXUI.ColorToInt(color)
    color = modulate(color, self.effOpacity)
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    local it = DXUI.RenderList.obtain()
    it.kind = "rrect"
    it.x = nx * sx + ox
    it.y = ny * sy + oy
    it.w = nw * sx
    it.h = nh * sy
    it.radius = radius * (sx + sy) / 2
    it.color = color
    -- rounded corners need the SDF shader; nil degrades to a flat rect
    if it.radius > 0 and DXUI.Effects then
        it.effect = DXUI.Effects.round(it.w, it.h, it.radius)
    else
        it.effect = nil
    end
    self.list:add(it)
end

--- Filled rectangle with a border ring. The border is drawn first and the
-- fill is inset by `borderWidth`, so the border never covers the fill
-- (rounded corners keep a 1px ring). radius == 0 uses the same inset path.
function Renderer:borderedRect(x, y, w, h, radius, fillColor, borderColor, borderWidth)
    local bw = borderWidth or 1
    if borderColor then
        if radius and radius > 0 then
            self:roundedRect(x, y, w, h, radius, borderColor)
        else
            self:rect(x, y, w, h, borderColor)
        end
    end
    local ix, iy, iw, ih = x + bw, y + bw, w - 2 * bw, h - 2 * bw
    if iw <= 0 or ih <= 0 then return end
    local ir = (radius and radius > bw) and (radius - bw) or 0
    if ir > 0 then
        self:roundedRect(ix, iy, iw, ih, ir, fillColor)
    else
        self:rect(ix, iy, iw, ih, fillColor)
    end
end

--- Emits four rects forming a border ring.
function Renderer:outline(x, y, w, h, width, color)
    -- top
    self:rect(x, y, w, width, color)
    -- bottom
    self:rect(x, y + h - width, w, width, color)
    -- left
    self:rect(x, y + width, width, h - 2 * width, color)
    -- right
    self:rect(x + w - width, y + width, width, h - 2 * width, color)
end

--- Emits a text item.
function Renderer:text(text, x, y, w, h, color, font, align, valign, scale)
    if text == nil or text == "" or self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if nx == nil then return end
    color = DXUI.ColorToInt(color)
    color = modulate(color, self.effOpacity)
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    local it = DXUI.RenderList.obtain()
    it.kind = "text"
    it.text = text
    it.x = nx * sx + ox
    it.y = ny * sy + oy
    it.w = nw * sx
    it.h = nh * sy
    it.color = color
    it.font = font
    it.align = align or "left"
    it.valign = valign or "top"
    it.scaleX = scale and scale * sx or sx
    it.scaleY = scale and scale * sy or sy
    self.list:add(it)
end

--- Emits an image item (full or section).
function Renderer:image(texture, x, y, w, h, color, section)
    if texture == nil or self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if nx == nil then return end
    color = DXUI.ColorToInt(color)
    color = modulate(color, self.effOpacity)
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    local it = DXUI.RenderList.obtain()
    it.kind = "image"
    it.x = nx * sx + ox
    it.y = ny * sy + oy
    it.w = nw * sx
    it.h = nh * sy
    it.texture = texture
    it.color = color
    it.effect = self:resolveEffect(self.fx, "image")
    it.section = section
    self.list:add(it)
end

--- Emits a line item.
function Renderer:line(x1, y1, x2, y2, color, width)
    if self.effOpacity <= 0 then return end
    if self.hasClip then
        local minX, maxX = math.min(x1, x2), math.max(x1, x2)
        local minY, maxY = math.min(y1, y2), math.max(y1, y2)
        if maxX < self.clipX or minX > self.clipX + self.clipW
           or maxY < self.clipY or minY > self.clipY + self.clipH then
            return
        end
    end
    color = DXUI.ColorToInt(color)
    color = modulate(color, self.effOpacity)
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    local it = DXUI.RenderList.obtain()
    it.kind = "line"
    it.x1 = x1 * sx + ox
    it.y1 = y1 * sy + oy
    it.x2 = x2 * sx + ox
    it.y2 = y2 * sy + oy
    it.color = color
    it.width = width and width * (sx + sy) / 2 or width
    self.list:add(it)
end

--- Resolves the effect table for an image item (blur/mask fx set by the
-- pass). Returns nil when absent.
function Renderer:resolveEffect(fx, kind)
    if fx == nil then return nil end
    if kind == "image" then return fx end
    return nil
end

DXUI.Renderer = Renderer