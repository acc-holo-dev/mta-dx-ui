--[[
    easing.lua — DXUI V2

    Easing-функции для animation (§51). Именованные строки ("linear", "in",
    "out", "inout") — читаемые, как и все константы V2.
]]

DXUI = DXUI or {}

DXUI.EASING = {
    linear = function(t) return t end,
    ["in"] = function(t) return t * t * t end,         -- cubic in
    out = function(t) local u = 1 - t return 1 - u * u * u end, -- cubic out
    inout = function(t) return t * t * (3 - 2 * t) end, -- smoothstep
}