---Renderer — public primitive API: what a widget calls from its own
---`render(renderer)`. Primitives add pooled items to the current list.
---
---    function Button:render(renderer)
---        renderer:borderedRect(self.worldX, self.worldY, self.width,
---                              self.height, self.radius, self.color,
---                              self.borderColor, self.borderWidth)
---        renderer:text(self.text, ..., self.textColor, self.font,
---                      "center", "center")
---    end
---
---Design-space in, screen-space out: the pass loads the design→screen
---mapping (scale/offset) and each node's clip region + effective opacity
---once; primitives apply them at emission. Colors are normalized via
---ColorToInt (works for packed ints and Color proxies alike).
---
---Rounded rects are SINGLE items: per-corner radii (tl,tr,br,bl), the
---border ring and the fill ride one SDF draw (see backend_mta). Square
---corners decompose into plain rect items (no shader round-trip).
---
---The renderer knows NOTHING about the backend (backend_mta) — items only.

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
    -- direct mode: a RenderState; emitted items draw IMMEDIATELY through
    -- the backend instead of joining the cached list (overlay pass — see
    -- Runtime:draw). Blinking overlays repaint per frame without
    -- invalidating the cached list (zero-work idle contract holds).
    self.direct = nil
    return self
end

--- Routes an item: direct mode draws it through the backend immediately
--- (overlay pass); otherwise it joins the cached list.
function Renderer:_emit(it)
    local d = self.direct
    if d then d:draw(it) else self.list:add(it) end
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
    self:_emit(it)
end

--- Emits a filled rounded-rectangle item.
-- `radii`: number (all four corners) or {tl,tr,br,bl} (nil corners = 0).
function Renderer:roundedRect(x, y, w, h, radii, color)
    return self:_rrect(x, y, w, h, radii, color, nil, 0)
end

--- Emits a rounded rectangle with a border ring: ONE draw on the shader
-- path (the SDF fills and borders in the same pass). `radii` follows
-- roundedRect. Square corners with a border decompose into two plain
-- rect items (no shader needed for a square ring).
function Renderer:borderedRect(x, y, w, h, radii, fillColor, borderColor, borderWidth)
    return self:_rrect(x, y, w, h, radii, fillColor, borderColor, borderWidth or 1)
end

--- Shared rrect emitter (pool item; radii resolved to four corners).
function Renderer:_rrect(x, y, w, h, radii, fillColor, borderColor, borderWidth)
    if self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if nx == nil then return end
    local r1, r2, r3, r4 = 0, 0, 0, 0
    if type(radii) == "number" then
        r1, r2, r3, r4 = radii, radii, radii, radii
    elseif type(radii) == "table" then
        -- {tl,tr,br,bl} (array or named)
        r1 = radii[1] or radii.tl or 0
        r2 = radii[2] or radii.tr or 0
        r3 = radii[3] or radii.br or 0
        r4 = radii[4] or radii.bl or 0
    end
    local fill = modulate(DXUI.ColorToInt(fillColor), self.effOpacity)
    local border = nil
    if borderColor ~= nil and borderWidth > 0 then
        border = modulate(DXUI.ColorToInt(borderColor), self.effOpacity)
    end
    if r1 <= 0 and r2 <= 0 and r3 <= 0 and r4 <= 0 then
        -- square corners: plain rect(s), no shader round-trip
        if border == nil then
            return self:rect(nx, ny, nw, nh, fill)
        end
        local bw = borderWidth
        local iw, ih = nw - 2 * bw, nh - 2 * bw
        self:rect(nx, ny, nw, nh, border)
        if iw > 0 and ih > 0 then
            self:rect(nx + bw, ny + bw, iw, ih, fill)
        end
        return
    end
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    local scale = (sx + sy) * 0.5
    local it = DXUI.RenderList.obtain()
    it.kind = "rrect"
    it.x = nx * sx + ox
    it.y = ny * sy + oy
    it.w = nw * sx
    it.h = nh * sy
    it.rtl = r1 * scale
    it.rtr = r2 * scale
    it.rbr = r3 * scale
    it.rbl = r4 * scale
    it.color = fill
    it.borderColor = border
    it.borderWidth = border ~= nil and borderWidth or 0
    self:_emit(it)
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

--- Emits a text item. `rich` (11th arg, optional) renders #RRGGBB codes
--- embedded in the text (colorCoded draw — see backend drawText).
function Renderer:text(text, x, y, w, h, color, font, align, valign, scale, rich)
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
    -- fontless draws fall back to the system font (settings.defaults.font)
    it.font = font or (DXUI.systemFont and DXUI.systemFont()) or nil
    it.align = align or "left"
    it.valign = valign or "top"
    it.scaleX = scale and scale * sx or sx
    it.scaleY = scale and scale * sy or sy
    -- explicit nil: pooled items are reused without a field reset
    it.rich = rich and true or nil
    self:_emit(it)
end

--- Emits an image item (full or section). `rotation` (deg, optional)
--- rotates around (rcx, rcy) — offsets RELATIVE to the quad's top-left,
--- scaled into screen space with the same transform as the position;
--- nil rcx/rcy = the quad's own center.
function Renderer:image(texture, x, y, w, h, color, section, rotation, rcx, rcy)
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
    -- image-path effect (blur/mask) set by the pass for Image nodes
    it.effect = self.fx
    it.section = section
    -- rotation center: ABSOLUTE screen coords (MTA semantics) from the
    -- UNCLIPPED quad geometry; explicit nils keep pooled items clean
    if rotation then
        it.rotation = rotation
        local cx = (rcx ~= nil) and rcx or w / 2
        local cy = (rcy ~= nil) and rcy or h / 2
        it.rotCX = (x + cx) * sx + ox
        it.rotCY = (y + cy) * sy + oy
    else
        it.rotation = nil
        it.rotCX = nil
        it.rotCY = nil
    end
    self:_emit(it)
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
    self:_emit(it)
end

DXUI.Renderer = Renderer