--[[
    dimension.lua — DXUI V3

    Human-readable dimensions (§28): ui.percent(50), ui.auto(), ui.fill()
    (plus plain numbers and "50%" strings at the cold path). All forms are
    COMPILED into a small tagged form at the cold path:
        { k = "px", v = n } | { k = "pct", v = n } | { k = "auto" } | { k = "fill" }
    `resolve` turns a compiled form into pixels given the parent size;
    `compile` accepts user input once (cold path).

    layoutW/layoutH node properties hold the COMPILED forms; plain numbers
    are treated as px. Rendering never sees these — the layout pass resolves.
]]

DXUI = DXUI or {}

local Dimension = {}

--- Compiles user input into the internal form (cold path).
-- number -> px; "50%" -> pct; compiled tables pass through; nil -> nil.
function Dimension.compile(v)
    if v == nil then return nil end
    local t = type(v)
    if t == "number" then return { k = "px", v = v } end
    if t == "table" then
        if v.k == "px" or v.k == "pct" or v.k == "auto" or v.k == "fill" then
            return v
        end
        error("dimension: unknown compiled form", 3)
    end
    if t == "string" then
        local pct = v:match("^(%d+%.?%d*)%%$")
        if pct then return { k = "pct", v = tonumber(pct) } end
        local n = tonumber(v)
        if n then return { k = "px", v = n } end
        if v == "auto" then return { k = "auto" } end
        if v == "fill" then return { k = "fill" } end
        error("dimension: cannot parse '" .. v .. "'", 3)
    end
    error("dimension: unsupported type " .. t, 3)
end

--- Public factory forms.
DXUI.percent = function(n) return { k = "pct", v = n } end
DXUI.auto = function() return { k = "auto" } end
DXUI.fill = function() return { k = "fill" } end

--- Resolves a compiled dimension against a parent size (hot-ish path:
-- runs in the layout pass only).
-- Returns nil for auto/fill (the caller decides via measurement/grow).
function Dimension.resolve(v, parentSize)
    if v == nil then return nil end
    if v.k == "px" then return v.v end
    if v.k == "pct" then return parentSize * v.v / 100 end
    return nil -- auto / fill
end

--- Normalizes a margin/padding box: nil | number | {left,top,right,bottom}
-- | {l,t,r,b}. Returns four numbers.
function Dimension.box(v)
    if v == nil then return 0, 0, 0, 0 end
    if type(v) == "number" then return v, v, v, v end
    local l, t, r, b = v.left, v.top, v.right, v.bottom
    if l == nil and t == nil and r == nil and b == nil and v[1] ~= nil then
        return v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0
    end
    return l or 0, t or 0, r or 0, b or 0
end

--- Applies a 9-point anchor: shifts world so the anchor point of the
-- node matches the given position.
function Dimension.anchor(wx, wy, w, h, anchor)
    if anchor == "tc" then return wx - w / 2, wy end
    if anchor == "tr" then return wx - w, wy end
    if anchor == "ml" then return wx, wy - h / 2 end
    if anchor == "mc" then return wx - w / 2, wy - h / 2 end
    if anchor == "mr" then return wx - w, wy - h / 2 end
    if anchor == "bl" then return wx, wy - h end
    if anchor == "bc" then return wx - w / 2, wy - h end
    if anchor == "br" then return wx - w, wy - h end
    return wx, wy
end

DXUI.Dimension = Dimension