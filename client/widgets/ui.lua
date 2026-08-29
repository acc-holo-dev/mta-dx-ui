--[[
    ui.lua (M7)

    Declarative widget API: "simple outside, complex inside" (§42 ТЗ).

        local ui = DXUI.UI.new(kernel)
        local w = ui.window({
            title = "Settings",
            x = 100, y = 80, w = 320, h = 240,
            children = {
                ui.button({ text = "OK",   x = 10,  y = 10, onClick = fn }),
                ui.label({ text = "Hi", x = 10, y = 60 }),
            },
        })

    Ключевые решения:
      - Виджет = УЗЕЛ ядра + свойства. Нет классов-обёрток, нет состояния
        вне Storage (ADR-002): весь "виджет" — это строки SoA.
      - Строки/таблицы разрешены здесь (cold path — событие пользователя);
        в кадр ничего из этого не утекает.
      - Цвет: 0xRRGGBBAA (packed, MTA-совместимый pass-through в
        dxDraw* — ноль конверсий в hot path).
      - Button c текстом = NODE_BUTTON (фон) + auto-child NODE_TEXT
        (подпись, весь размер родителя) — т.к. ядро рисует узел с text
        как CMD_TEXT (только текст).
      - Window c title = NODE_WINDOW (фон) + title bar (panel) + label.
      - children: массив proxy-объектов (из ui.* builders) — setParent.

    Всё создание — через kernel:create (id freelist, proxy pool) — т.е.
    виджеты полностью совместимы с M6 (animateTo), M5 (clip/opacity),
    M3 (on()), destroy-каскадом.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

local UI = {}
UI.__index = UI
DXUI.UI = UI

-- Дефолтные размеры/цвета (cold path, константы модуля).
local DEFAULTS = {
    window = { w = 320, h = 240 },
    panel  = { w = 100, h = 100 },
    button = { w = 100, h = 30 },
    label  = { w = 100, h = 20 },
    image  = { w = 64, h = 64 },
}

local COLOR_DEFAULT   = 0xFFFFFFFF
local COLOR_TITLEBAR  = 0x334455FF -- тёмный title bar окна
local COLOR_TEXT      = 0xFFFFFFFF

--- Разрешает цвет: number (packed) | "#RRGGBB[AA]" | {r,g,b,a}.
-- Cold path: строки и аллокации допустимы.
local function resolveColor(c)
    if c == nil then return nil end
    if type(c) == "number" then return c end
    if type(c) == "string" then
        local hex = c:match("^#?") and c:sub(2) or c
        local r = tonumber(hex:sub(1, 2), 16) or 0
        local g = tonumber(hex:sub(3, 4), 16) or 0
        local b = tonumber(hex:sub(5, 6), 16) or 0
        local a = #hex >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    if type(c) == "table" then
        local r, g, b = c.r or 0, c.g or 0, c.b or 0
        local a = c.a or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    error("ui.color: unsupported color type: " .. type(c))
end

--- ui.color(r, g, b, a) -> packed 0xAARRGGBB (MTA tocolor).
local function uiColor(r, g, b, a)
    return (a or 255) * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

-- Применяет общие свойства к созданному узлу. Порядок не важен
-- (все независимые set* с dirty-марками).
local function applyCommon(node, props)
    if props.x ~= nil or props.y ~= nil then
        node:setPosition(props.x or 0, props.y or 0)
    end
    if props.w ~= nil or props.h ~= nil then
        node:setSize(props.w or 0, props.h or 0)
    end
    local col = resolveColor(props.color)
    if col then node:setColor(col) end
    if props.layer ~= nil then node:setLayer(props.layer) end
    if props.anchor ~= nil then node:setAnchor(props.anchor) end
    if props.layoutMode ~= nil then node:setLayoutMode(props.layoutMode) end
    if props.margin then node:setMargin(props.margin[1] or 0, props.margin[2] or 0, props.margin[3] or 0, props.margin[4] or 0) end
    if props.padding then node:setPadding(props.padding[1] or 0, props.padding[2] or 0, props.padding[3] or 0, props.padding[4] or 0) end
    if props.clip ~= nil then node:setClip(props.clip) end
    if props.opacity ~= nil then node:setOpacity(props.opacity) end
    if props.blur ~= nil then node:setBlur(props.blur) end
    if props.visible ~= nil then node:setVisible(props.visible) end
    if props.enabled ~= nil then node:setEnabled(props.enabled) end
    if props.static ~= nil then node:setStatic(props.static) end
end

-- Рекурсивный приём children: массив proxy (виджетов).
local function attachChildren(kernel, node, props)
    local children = props.children
    if not children then return end
    for i = 1, #children do
        children[i]:setParent(node)
    end
end

function UI.new(kernel)
    local self = setmetatable({}, UI)
    self.kernel = kernel
    return self
end

function UI:color(r, g, b, a)
    return uiColor(r, g, b, a)
end

--- ui.window(props) — NODE_WINDOW: фон + (опц.) title bar c подписью.
function UI:window(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_WINDOW, nil)
    applyCommon(node, props)
    local w = props.w or DEFAULTS.window.w
    local h = props.h or DEFAULTS.window.h
    if props.w == nil or props.h == nil then
        node:setSize(w, h)
    end
    if props.title then
        -- Title bar: панель по всей ширине + подпись (cold path, 2 узла).
        local bar = k:create(C.NODE_PANEL, node)
        bar:setPosition(0, 0):setSize(w, 24)
        bar:setColor(resolveColor(props.titleColor) or COLOR_TITLEBAR)
        local t = k:create(C.NODE_TEXT, bar)
        t:setPosition(4, 2):setSize(w - 8, 20)
        t:setColor(resolveColor(props.titleTextColor) or COLOR_TEXT)
        t:setText(props.title)
    end
    attachChildren(k, node, props)
    return node
end

--- ui.panel(props) — NODE_PANEL.
function UI:panel(props)
    props = props or {}
    local node = self.kernel:create(C.NODE_PANEL, nil)
    applyCommon(node, props)
    if props.w == nil or props.h == nil then
        node:setSize(props.w or DEFAULTS.panel.w, props.h or DEFAULTS.panel.h)
    end
    attachChildren(self.kernel, node, props)
    return node
end

--- ui.button(props) — NODE_BUTTON (фон) + auto-child NODE_TEXT при props.text.
-- props: text, onClick, color, x, y, w, h, ...
function UI:button(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_BUTTON, nil)
    applyCommon(node, props)
    local w = props.w or DEFAULTS.button.w
    local h = props.h or DEFAULTS.button.h
    if props.w == nil or props.h == nil then
        node:setSize(w, h)
    end
    if props.text then
        -- Ядро рисует узел с text как CMD_TEXT (без фона), поэтому подпись —
        -- отдельный auto-child на весь размер кнопки (M7-решение, см. header).
        local t = k:create(C.NODE_TEXT, node)
        t:setPosition(0, 0):setSize(w, h)
        t:setColor(resolveColor(props.textColor) or COLOR_TEXT)
        t:setText(props.text)
    end
    if props.onClick then
        node:on("click", props.onClick)
    end
    attachChildren(k, node, props)
    return node
end

--- ui.label(props) — NODE_TEXT: только подпись.
function UI:label(props)
    props = props or {}
    local node = self.kernel:create(C.NODE_TEXT, nil)
    applyCommon(node, props)
    if props.w == nil or props.h == nil then
        node:setSize(props.w or DEFAULTS.label.w, props.h or DEFAULTS.label.h)
    end
    if props.text then
        node:setColor(resolveColor(props.color) or COLOR_TEXT)
        node:setText(props.text)
    end
    attachChildren(self.kernel, node, props)
    return node
end

--- ui.image(props) — NODE_IMAGE: props.texture — handle dxImage (pass-through).
function UI:image(props)
    props = props or {}
    local node = self.kernel:create(C.NODE_IMAGE, nil)
    applyCommon(node, props)
    if props.w == nil or props.h == nil then
        node:setSize(props.w or DEFAULTS.image.w, props.h or DEFAULTS.image.h)
    end
    if props.texture then
        node:setTexture(props.texture)
    end
    attachChildren(self.kernel, node, props)
    return node
end
