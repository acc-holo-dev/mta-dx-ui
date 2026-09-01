--[[
    easing.lua — DXUI V3

    Easing functions for animation (§44). Named strings are readable:
    "linear", "in", "out", "inout", "back", "elastic", "bounce". Spring is
    a time-based function of (t, omega, damping) — see Anim.spring below.
]]

DXUI = DXUI or {}

local c1 = 1.70158
local c3 = c1 + 1

local easing = {
    linear = function(t) return t end,
    ["in"]  = function(t) return t * t * t end,           -- cubic in
    out     = function(t) local u = 1 - t return 1 - u * u * u end,
    inout   = function(t) return t * t * (3 - 2 * t) end,  -- smoothstep
    backIn  = function(t) return c3 * t * t * t - c1 * t * t end,
    backOut = function(t) local u = t - 1 return 1 + c3 * u * u * u + c1 * u * u end,
    backInOut = function(t)
        if t < 0.5 then
            local u = 2 * t
            return (u * u * (3.5 * u - 2.5)) / 2
        else
            local u = 2 * t - 2
            return (u * u * (3.5 * u + 2.5) + 2) / 2
        end
    end,
    elasticOut = function(t)
        if t == 0 or t == 1 then return t end
        return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
    end,
    elasticIn = function(t)
        if t == 0 or t == 1 then return t end
        return math.pow(2, 10 * (t - 1)) * math.sin((t * 10 - 10.75) * (2 * math.pi / 3))
    end,
    bounceOut = function(t)
        if t < 1 / 2.75 then return 7.5625 * t * t
        elseif t < 2 / 2.75 then
            local u = t - 1.5 / 2.75
            return 7.5625 * u * u + 0.75
        elseif t < 2.5 / 2.75 then
            local u = t - 2.25 / 2.75
            return 7.5625 * u * u + 0.9375
        else
            local u = t - 2.625 / 2.75
            return 7.5625 * u * u + 0.984375
        end
    end,
    bounceIn = function(t) return 1 - easing.bounceOut(1 - t) end,
}

DXUI.EASING = easing

--- Spring easing over [0,1]: overshoots and settles. omega ~ natural
-- frequency (higher = snappier), damping 0..1 (lower = more overshoot).
function DXUI.spring(t, omega, damping)
    omega = omega or 12
    damping = damping or 0.7
    local exp = math.exp(-damping * omega * t)
    return 1 - exp * math.cos(omega * t)
end