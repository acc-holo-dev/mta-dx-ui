--[[
    renderer.lua — DXUI V2

    Публичный renderer API (§72/§73): примитивы, которые виджет вызывает в
    своём render(renderer). Примитивы добавляют items в RenderList.

        function Button:render(renderer)
            renderer:rect(self.x, self.y, self.width, self.height, self.color)
            renderer:text(self.text, self.x, self.y, self.width, self.height)
        end

    Renderer — тонкий сборщик items; он НЕ знает о backend (dxDraw*). Это
    сохраняет оптимизации backend изолированными (§73: public renderer API
    не должен ломать оптимизации backend).
]]

DXUI = DXUI or {}

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(renderList)
    local self = setmetatable({}, Renderer)
    self.list = renderList
    self.node = nil -- текущий узел (для отладки/привязки item к узлу)
    return self
end

function Renderer:rect(x, y, w, h, color)
    self.list:add({ kind = "rect", x = x, y = y, w = w, h = h, color = color, node = self.node })
end

function Renderer:text(text, x, y, w, h, color)
    self.list:add({ kind = "text", text = text, x = x, y = y, w = w, h = h, color = color, node = self.node })
end

function Renderer:image(texture, x, y, w, h, color)
    self.list:add({ kind = "image", texture = texture, x = x, y = y, w = w, h = h, color = color, node = self.node })
end

function Renderer:line(x1, y1, x2, y2, color)
    self.list:add({ kind = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = color, node = self.node })
end

DXUI.Renderer = Renderer
