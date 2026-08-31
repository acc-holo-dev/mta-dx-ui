--[[
    layout.lua — DXUI V2

    Layout subsystem: computes node world coords from local descriptions
    (layoutMode/anchor/margin) plus the parent's world coords and
    padding.

    Modes:
      - absolute — x/y in pixels (default);
      - relative — x/y as a fraction 0..1 of the parent's size;
      - center   — centered within the parent (x/y ignored);
      - stretch  — fill the parent minus margin. Size is written to
                   width/height through the mutation layer; the _set-guard
                   prevents cycles (same value → no invalidation).

    autoSize: size from content — layout calls node:_measureContent
    (Widget: children; Label: text) and writes width/height the same way.

    Anchor — 9 anchor points: which point of the node "sticks" to (x, y).

    The result (worldX/worldY) is stored on the node as read-only computed
    fields. Render and hit-test read worldX/worldY, not local x/y.

    The layout pass is a full tree walk, run only on DIRTY_LAYOUT
    (context.layoutDirty), not every frame. Idle frame = zero work.
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

-- Normalizes margin/padding into left, top, right, bottom.
-- nil → 0; number → all sides; table → {left, top, right, bottom}.
local function box(v)
    if v == nil then return 0, 0, 0, 0 end
    if type(v) == "number" then return v, v, v, v end
    return v.left or 0, v.top or 0, v.right or 0, v.bottom or 0
end

-- Applies anchor: shifts world so the anchor point matches the position.
local function applyAnchor(wx, wy, w, h, anchor)
    if anchor == "tc" then return wx - w / 2, wy end
    if anchor == "tr" then return wx - w, wy end
    if anchor == "ml" then return wx, wy - h / 2 end
    if anchor == "mc" then return wx - w / 2, wy - h / 2 end
    if anchor == "mr" then return wx - w, wy - h / 2 end
    if anchor == "bl" then return wx, wy - h end
    if anchor == "bc" then return wx - w / 2, wy - h end
    if anchor == "br" then return wx - w, wy - h end
    return wx, wy -- tl (default)
end

--- Computes world coords of a node. pwx/pwy — parent's world, pw/ph —
-- parent's size, ppad — parent's padding.
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
        -- position: at the parent's corner + margin (size already written in _walk)
        wx = pwx + mL + pL
        wy = pwy + mT + pT
    else -- absolute
        wx = pwx + x + mL + pL
        wy = pwy + y + mT + pT
    end

    return applyAnchor(wx, wy, w, h, node.anchor)
end

--- Full layout pass: walk the tree from root, computing world coords.
-- Root is special: world = (0,0); its children get the layout-space size
-- (design resolution if set, otherwise the screen).
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
    -- Stage 7b: stretch — size follows the parent (before computeWorld
    -- so placement uses the actual size). The _set-guard prevents
    -- cycles: same value → no invalidation.
    if node.layoutMode == "stretch" then
        local mL, mT, mR, mB = box(node.margin)
        node:_set("width", pw - mL - mR)
        node:_set("height", ph - mT - mB)
    end

    -- Stage 7b: autoSize — size from content (Widget: children; Label: text).
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