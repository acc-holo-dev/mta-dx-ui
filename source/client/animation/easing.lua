---Easing functions for animation. Named strings are readable:
---"linear", "in", "out", "inout", "back", "elastic", "bounce". Spring is
---a time-based function of (t, omega, damping) — see Anim.spring below.

DXUI = DXUI or {}

local c1 = 1.70158
local c3 = c1 + 1

-- Easing curve families: each entry maps a name t in [0,1] to an eased
-- t' in [0,1] (back/elastic/bounce overshoot or oscillate; in/out/inout
-- shape the motion; linear is identity). Aliases at the bottom expose the
-- most common named strings used by animation specs.
local easing = {
    linear = function(t) return t end,
    -- cubic in
    ["in"]  = function(t) return t * t * t end,
    out     = function(t) local u = 1 - t return 1 - u * u * u end,
    -- smoothstep
    inout   = function(t) return t * t * (3 - 2 * t) end,
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
    elasticInOut = function(t)
        if t == 0 or t == 1 then return t end
        if t < 0.5 then
            local u = 2 * t - 1
            return -0.5 * math.pow(2, 10 * u) * math.sin((u * 1.5 - 0.75) * (2 * math.pi / 3))
        end
        local u = 2 * t - 1
        return 0.5 * math.pow(2, -10 * u) * math.sin((u * 1.5 - 0.75) * (2 * math.pi / 3)) + 1
    end,
    bounceInOut = function(t)
        if t < 0.5 then return easing.bounceIn(2 * t) / 2 end
        return easing.bounceOut(2 * t - 1) / 2 + 0.5
    end,
}

-- Readable aliases (the header names): each resolves to its most common
-- "out" variant, the default for UI entrance animations.
easing.back    = easing.backOut
easing.elastic = easing.elasticOut
easing.bounce  = easing.bounceOut

DXUI.Easing = easing

--- Spring easing over [0,1]: overshoots and settles. omega ~ natural
-- frequency (higher = snappier), damping 0..1 (lower = more overshoot).
function DXUI.spring(t, omega, damping)
    omega = omega or 12
    damping = damping or 0.7
    local exp = math.exp(-damping * omega * t)
    return 1 - exp * math.cos(omega * t)
end