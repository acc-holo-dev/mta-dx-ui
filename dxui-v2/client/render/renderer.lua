--[[
    renderer.lua — DXUI V2

    Публичный renderer API (§72/§73): примитивы, которые виджет вызывает в
    своём render(renderer). Примитивы добавляют items в RenderList.

        function Button:render(renderer)
            renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
            renderer:text(self.text, self.worldX, self.worldY, self.width, self.height,
                          self.textColor, self.font, "center", "middle")
        end

    Renderer — тонкий сборщик items; он НЕ знает о backend (dxDraw*).

    Stage 7: geometric clip (§35, дешёвый путь) — примитивы пересекаются с
    clip-регионом узла, целиком невидимые — пропускаются.

    Stage 8: design resolution (§31–§33) — scaleX/scaleY/offset применяются
    к примитивам при эмиссии (rebuild-time); текст несёт font-scale.

    Stage 10: opacity (§34) — inherited alpha-модуляция: collect'ор считает
    эффективную opacity (node.opacity × родительская), renderer модулирует
    альфа-канал цвета при эмиссии. Дешёвый корректный путь без RT; true
    group-opacity (без двойного блендинга пересечений) — RT (future).
]]

DXUI = DXUI or {}

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(renderList)
    local self = setmetatable({}, Renderer)
    self.list = renderList
    self.node = nil -- текущий узел (для отладки/привязки item к узлу)
    self.hasClip = false
    self.clipX, self.clipY, self.clipW, self.clipH = nil, nil, nil, nil
    self.effOpacity = 1 -- эффективная opacity узла (inherited)
    -- design → screen mapping (Context обновляет каждый кадр; 1/0 = identity)
    self.scaleX, self.scaleY = 1, 1
    self.offsetX, self.offsetY = 0, 0
    return self
end

--- Загружает draw-state узла (clip-регион + эффективная opacity).
-- Вызывается collect'ором перед node:render(...).
function Renderer:_loadClip(node)
    self.hasClip = node._clipX ~= nil
    self.clipX, self.clipY = node._clipX, node._clipY
    self.clipW, self.clipH = node._clipW, node._clipH
    local op = node._effOpacity
    self.effOpacity = (op ~= nil) and op or 1
end

--- Пересекает (x, y, w, h) с текущим clip-регионом (design-пространство).
-- Возвращает nx, ny, nw, nh; nil если целиком вне clip.
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

--- Модулирует альфа-канал packed-цвета 0xAARRGGBB на opacity (§34).
local function modulate(color, op)
    if color == nil or op >= 1 then return color end
    if op <= 0 then return 0 end
    local a = math.floor(color / 0x1000000)
    local na = math.floor(a * op)
    return color - a * 0x1000000 + na * 0x1000000
end

function Renderer:rect(x, y, w, h, color)
    if self.effOpacity <= 0 then return end -- полностью прозрачно — не рисуем
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if not nx then return end
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    self.list:add({
        kind = "rect", x = nx * sx + ox, y = ny * sy + oy, w = nw * sx, h = nh * sy,
        color = modulate(color, self.effOpacity), node = self.node,
    })
end

--- Rounded rect (§37): radius в design-px, масштабируется вместе с геометрией.
-- Effect = SDF-шейдер (кэш, один на процесс); без шейдера — плоский rect.
function Renderer:roundedRect(x, y, w, h, radius, color)
    if self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if not nx then return end
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    local qw, qh = nw * sx, nh * sy
    local r = radius * (sx + sy) / 2 -- средний масштаб (stretch искажает круги)
    if r > qw / 2 then r = qw / 2 end
    if r > qh / 2 then r = qh / 2 end
    local effect = DXUI.Effects and DXUI.Effects.rounded(qw, qh, r) or nil
    self.list:add({
        kind = "rrect", x = nx * sx + ox, y = ny * sy + oy, w = qw, h = qh,
        radius = r, color = modulate(color, self.effOpacity),
        effect = effect, node = self.node,
    })
end

--- Outline (§38): рамка из 4 рёбер (T-раскладка — углы не блендятся дважды).
-- Композируется из rect → clipping и opacity работают автоматически.
function Renderer:outline(x, y, w, h, thickness, color)
    self:rect(x + thickness, y, w - thickness * 2, thickness, color)                  -- top
    self:rect(x + thickness, y + h - thickness, w - thickness * 2, thickness, color)  -- bottom
    self:rect(x, y, thickness, h, color)                                              -- left
    self:rect(x + w - thickness, y, thickness, h, color)                              -- right
end

--- text: align — "left"|"center"|"right", valign — "top"|"middle"|"bottom"
-- (нативные параметры dxDrawText), scale — масштаб шрифта (design-пространство).
function Renderer:text(text, x, y, w, h, color, font, align, valign, scale)
    if self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if not nx then return end
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    self.list:add({
        kind = "text", text = text,
        x = nx * sx + ox, y = ny * sy + oy, w = nw * sx, h = nh * sy,
        color = modulate(color, self.effOpacity),
        font = font, align = align, valign = valign,
        scaleX = sx * (scale or 1), scaleY = sy * (scale or 1),
        node = self.node,
    })
end

--- image: effect = { shader, params } (§40); при обрезке clip'ом считается
-- section (uv → пиксели текстуры) — backend рисует через dxDrawImageSection
-- без искажения пропорций (кроп, а не растяжение).
function Renderer:image(texture, x, y, w, h, color, effect)
    if self.effOpacity <= 0 then return end
    local nx, ny, nw, nh = clipRect(self, x, y, w, h)
    if not nx then return end
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY

    -- кроп: видимая часть → секция текстуры (если умеем мерить материал)
    local section
    if (nw < w or nh < h or nx ~= x or ny ~= y) and dxGetMaterialSize then
        local ok, tw, th = pcall(dxGetMaterialSize, texture)
        if ok and tw and tw > 0 and th and th > 0 then
            section = {
                (nx - x) / w * tw, (ny - y) / h * th,
                nw / w * tw, nh / h * th,
            }
        end
    end

    self.list:add({
        kind = "image", texture = texture,
        x = nx * sx + ox, y = ny * sy + oy, w = nw * sx, h = nh * sy,
        color = modulate(color, self.effOpacity),
        effect = effect, section = section, node = self.node,
    })
end

function Renderer:line(x1, y1, x2, y2, color)
    if self.effOpacity <= 0 then return end
    -- clip (§35): линию нельзя разрезать дёшево — консервативный bbox-тест:
    -- целиком вне региона не рисуем, пересекающие рисуются как есть
    -- (задокументированное приближение; точная обрезка — RT-путь)
    if self.hasClip then
        local minX, maxX = math.min(x1, x2), math.max(x1, x2)
        local minY, maxY = math.min(y1, y2), math.max(y1, y2)
        if maxX < self.clipX or minX > self.clipX + self.clipW
           or maxY < self.clipY or minY > self.clipY + self.clipH then
            return
        end
    end
    local sx, ox, sy, oy = self.scaleX, self.offsetX, self.scaleY, self.offsetY
    self.list:add({
        kind = "line",
        x1 = x1 * sx + ox, y1 = y1 * sy + oy,
        x2 = x2 * sx + ox, y2 = y2 * sy + oy,
        color = modulate(color, self.effOpacity), node = self.node,
    })
end

DXUI.Renderer = Renderer