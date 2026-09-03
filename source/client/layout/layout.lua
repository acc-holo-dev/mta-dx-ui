---Layout subsystem: resolves sizes (px / percent / auto / fill / stretch /
---flex-grow) and computes node worldX/worldY from local descriptions plus
---the parent context. Runs ONLY on layoutDirty (never every frame).
---
---Modes: absolute | relative | center | stretch | fill, plus anchors (9)
---and margin/padding boxes; flex containers (flexDirection row|column)
---delegate child sizing AND placement to Flex.flex.
---
---Sizes that the ENGINE computes (autoSize, stretch, flex, layoutWidth/
---Height) are written via _set(..., "system") so width/height always
---reflect reality; the same-value guard prevents invalidation loops.

DXUI = DXUI or {}

local Layout = {}
local Dimension = DXUI.Dimension

--- One node's size resolve: returns w, h (design units) given the parent
-- content box. Writes nothing; callers write via _set.
-- "free" dimension = no explicit user/theme/system-owner value AND raw
-- default (nil or 0) — autoSize measures only then (props win over
-- content measure; explicit layoutWidth/Height win over both).
local function freeDim(node, k)
    local owner = node._owner and node._owner[k]
    if owner ~= nil then return false end
    local v = rawget(node._data, k)
    return v == nil or v == 0
end

--- Resolves a node's width/height from its layout mode and content box.
local function resolveSize(node, contentW, contentH)
    local w, h = node.width, node.height
    local lwC, lhC = node.layoutWidth, node.layoutHeight
    local mL, mT, mR, mB = Dimension.box(node.margin)
    -- content measure is shared by both axes (label/checkbox return w,h);
    -- only measure when a free/auto/fill dimension actually needs it, so a
    -- fixed-size node never pays for content measurement on a layout pass
    local mw, mh
    local needW = (lwC and (lwC.k == "auto" or lwC.k == "fill"))
        or (node.autoSize and freeDim(node, "width"))
    local needH = (lhC and (lhC.k == "auto" or lhC.k == "fill"))
        or (node.autoSize and freeDim(node, "height"))
    if node._measureContent and (needW or needH) then
        mw, mh = node:_measureContent()
    end

    if node.layoutMode == "stretch" then
        w = contentW - mL - mR
        h = contentH - mT - mB
    else
        if lwC then
            local rw = Dimension.resolve(lwC, contentW)
            if rw then w = rw
            elseif lwC.k == "fill" then w = contentW - mL - mR
            elseif mw then w = mw end
        elseif mw and node.autoSize and freeDim(node, "width") then w = mw end
        if lhC then
            local rh = Dimension.resolve(lhC, contentH)
            if rh then h = rh
            elseif lhC.k == "fill" then h = contentH - mT - mB
            elseif mh then h = mh end
        elseif mh and node.autoSize and freeDim(node, "height") then h = mh end
    end
    if w < 0 then w = 0 end
    if h < 0 then h = 0 end
    return w, h
end

--- Local x/y -> world, applying the anchor.
local function place(node, px, py)
    local wx, wy = Dimension.anchor(px + node.x, py + node.y, node.width, node.height, node.anchor)
    rawset(node, "_worldX", wx)
    rawset(node, "_worldY", wy)
end

--- Walks a node: resolve size -> write size -> place -> recurse.
-- pw/ph = parent SIZE (world units); ppad = parent padding.
function Layout._walk(node, pwx, pwy, pw, ph, ppad)
    local mL, mT, _r, _b = Dimension.box(node.margin)
    local pL, pT, pR, pB = Dimension.box(ppad)
    local contentW = pw - pL - pR
    local contentH = ph - pT - pB
    if contentW < 0 then contentW = 0 end
    if contentH < 0 then contentH = 0 end

    local w, h = resolveSize(node, contentW, contentH)
    -- engine-computed sizes flow through the mutation layer (system owner;
    -- the same-value guard makes repeated writes free)
    if node.width ~= w then node:_set("width", w, "system") end
    if node.height ~= h then node:_set("height", h, "system") end

    local mode = node.layoutMode
    local x, y = node.x, node.y
    local wx, wy
    if mode == "relative" then
        wx = pwx + x * contentW + mL + pL
        wy = pwy + y * contentH + mT + pT
    elseif mode == "center" then
        wx = pwx + pL + (contentW - w) / 2
        wy = pwy + pT + (contentH - h) / 2
    elseif mode == "stretch" or mode == "fill" or mode == "flex" then
        wx = pwx + mL + pL
        wy = pwy + mT + pT
    -- absolute
    else
        wx = pwx + x + mL + pL
        wy = pwy + y + mT + pT
    end
    wx, wy = Dimension.anchor(wx, wy, w, h, node.anchor)
    rawset(node, "_worldX", wx)
    rawset(node, "_worldY", wy)

    -- children
    local children = node._children
    if node.flexDirection then
        -- the flex content box subtracts THIS node's own padding (not the
        -- parent's — a flex container lays out inside its own box)
        local nL, nT, nR, nB = Dimension.box(node.padding)
        local cw = w - nL - nR
        local ch = h - nT - nB
        if cw < 0 then cw = 0 end
        if ch < 0 then ch = 0 end
        DXUI.Flex.flex(node, children, cw, ch)
        for i = 1, #children do
            Layout._place(children[i], wx + nL, wy + nT, cw, ch)
        end
        return
    end
    for i = 1, #children do
        Layout._walk(children[i], wx, wy, w, h, node.padding)
    end
end

--- Places a FLEX-PLACED child (its x/y already wrote main/cross positions;
-- no re-measure — _walk is NOT used, so compiled dims don't fight Flex).
-- px/py = the container's CONTENT origin.
function Layout._place(node, px, py, pw, ph)
    place(node, px, py)
    local children = node._children
    if node.flexDirection then
        local nL, nT, nR, nB = Dimension.box(node.padding)
        local cw = node.width - nL - nR
        local ch = node.height - nT - nB
        if cw < 0 then cw = 0 end
        if ch < 0 then ch = 0 end
        DXUI.Flex.flex(node, children, cw, ch)
        for i = 1, #children do
            Layout._place(children[i], node.worldX + nL, node.worldY + nT, cw, ch)
        end
    else
        for i = 1, #children do
            Layout._walk(children[i], node.worldX, node.worldY, node.width, node.height, node.padding)
        end
    end
end

--- Full pass: root is a synthetic origin; its children lay out in the
-- instance layout space (design resolution if set, else screen).
function Layout.resolve(instance)
    local root = instance.root
    rawset(root, "_worldX", 0)
    rawset(root, "_worldY", 0)
    local lw = instance.layoutW or instance.screenW or 0
    local lh = instance.layoutH or instance.screenH or 0
    local children = root._children
    for i = 1, #children do
        Layout._walk(children[i], 0, 0, lw, lh, 0)
    end
end

DXUI.Layout = Layout