--[[
    layout.lua — DXUI V2

    Layout-подсистема (§29/§30/§31): вычисляет world-координаты узлов из
    локальных описаний (layoutMode/anchor/margin) + world-координат родителя
    + padding родителя.

    Режимы:
      - absolute — x/y в пикселях (по умолчанию);
      - relative — x/y как доля 0..1 от размера родителя;
      - center   — центрирование в родителе (x/y игнорируются);
      - stretch  — заполнить родителя минус margin (§29). Размер пишется в
                   width/height через mutation layer; _set-guard предотвращает
                   циклы (то же значение — без инвалидации).

    autoSize (§29): размер по содержимому — layout вызывает node:_measureContent
    (Widget: дети; Label: текст) и пишет width/height тем же путём.

    Anchor — 9 точек привязки: какая точка узла «приклеивается» к (x, y).

    Результат (worldX/worldY) хранится на узле как read-only вычисляемые поля.
    Render и hit-test читают worldX/worldY, а не локальные x/y.

    Layout-проход — полный обход дерева, запускается только при DIRTY_LAYOUT
    (context.layoutDirty), НЕ каждый кадр (§90/§91). Idle-кадр = zero work.
]]

DXUI = DXUI or {}

DXUI.LAYOUT_MODE = {
    ABS     = "absolute",
    REL     = "relative",
    CENTER  = "center",
    STRETCH = "stretch",
}

DXUI.ANCHOR = {
    TL = "tl", TC = "tc", TR = "tr",
    ML = "ml", MC = "mc", MR = "mr",
    BL = "bl", BC = "bc", BR = "br",
}

local Layout = {}

-- Нормализует margin/padding в left, top, right, bottom.
-- nil → 0; number → все стороны; table → {left, top, right, bottom}.
local function box(v)
    if v == nil then return 0, 0, 0, 0 end
    if type(v) == "number" then return v, v, v, v end
    return v.left or 0, v.top or 0, v.right or 0, v.bottom or 0
end

-- Применяет anchor: сдвигает world, чтобы точка привязки совпала с позицией.
local function applyAnchor(wx, wy, w, h, anchor)
    if anchor == "tc" then return wx - w / 2, wy end
    if anchor == "tr" then return wx - w, wy end
    if anchor == "ml" then return wx, wy - h / 2 end
    if anchor == "mc" then return wx - w / 2, wy - h / 2 end
    if anchor == "mr" then return wx - w, wy - h / 2 end
    if anchor == "bl" then return wx, wy - h end
    if anchor == "bc" then return wx - w / 2, wy - h end
    if anchor == "br" then return wx - w, wy - h end
    return wx, wy -- tl (по умолчанию)
end

--- Вычисляет world-координаты узла. pwx/pwy — world родителя, pw/ph — размер
-- родителя, ppad — padding родителя.
function Layout.computeWorld(node, pwx, pwy, pw, ph, ppad)
    local mode = node.layoutMode
    local x, y = node.x, node.y
    local w, h = node.width, node.height
    local mL, mT = box(node.margin)
    local pL, pT = box(ppad)

    local wx, wy
    if mode == "relative" then
        wx = pwx + x * pw + mL + pL
        wy = pwy + y * ph + mT + pT
    elseif mode == "center" then
        wx = pwx + (pw - w) / 2
        wy = pwy + (ph - h) / 2
    elseif mode == "stretch" then
        -- позиция: у угла родителя + margin (размер уже записан в _walk)
        wx = pwx + mL + pL
        wy = pwy + mT + pT
    else -- absolute
        wx = pwx + x + mL + pL
        wy = pwy + y + mT + pT
    end

    return applyAnchor(wx, wy, w, h, node.anchor)
end

--- Полный layout-проход: обход дерева от root, вычисление world-координат.
-- Root — специальный: world = (0,0), его дети получают размер layout-пространства
-- (design resolution, если задана — иначе экран; §31–§33).
function Layout.update(context)
    local root = context.root
    rawset(root, "_worldX", 0)
    rawset(root, "_worldY", 0)
    local children = root._children
    local pw = context.layoutW or context.screenW or 0
    local ph = context.layoutH or context.screenH or 0
    for i = 1, #children do
        Layout._walk(children[i], 0, 0, pw, ph, 0)
    end
end

function Layout._walk(node, pwx, pwy, pw, ph, ppad)
    -- Stage 7b: stretch — размер следует за родителем (до computeWorld,
    -- чтобы размещение использовало актуальный размер). _set-guard
    -- предотвращает циклы: то же значение — без инвалидации.
    if node.layoutMode == "stretch" then
        local mL, mT, mR, mB = box(node.margin)
        node:_set("width", pw - mL - mR)
        node:_set("height", ph - mT - mB)
    end

    -- Stage 7b: autoSize — размер по содержимому (Widget: дети; Label: текст).
    if node.autoSize then
        local mw, mh = node:_measureContent()
        node:_set("width", mw)
        node:_set("height", mh)
    end

    local wx, wy = Layout.computeWorld(node, pwx, pwy, pw, ph, ppad)
    rawset(node, "_worldX", wx)
    rawset(node, "_worldY", wy)
    local children = node._children
    for i = 1, #children do
        Layout._walk(children[i], wx, wy, node.width, node.height, node.padding)
    end
end

DXUI.Layout = Layout