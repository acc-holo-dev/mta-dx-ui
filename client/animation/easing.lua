--[[
    easing.lua — DXUI V2

    Easing functions for animation. Named strings ("linear", "in",
    "out", "inout") are readable, like all V2 constants.
]]

DXUI = DXUI or {}

DXUI.EASING = {
    linear = function(t) return t end,
    ["in"] = function(t) return t * t * t end,         -- cubic in
    out = function(t) local u = 1 - t return 1 - u * u * u end, -- cubic out
    inout = function(t) return t * t * (3 - 2 * t) end, -- smoothstep
}