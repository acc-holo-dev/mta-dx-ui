--[[
    diagnostics.lua — DXUI V3

    DXUI.Diagnostics: tools over the per-instance frame counters
    (instance.stats). Read-only helpers — never part of the hot path.

      local summary = DXUI.Diagnostics.describe(ui)
      print(DXUI.Diagnostics.report(ui))

    `enableZeroWork(ui)` turns on the idle-frame assertion: every tick
    with nothing dirty must perform zero layout/rebuild work (the
    persistent render-list contract). Useful in debug builds and tests.
]]

DXUI = DXUI or {}

local Diagnostics = {}

--- Copies today's counters (cheap, for tooling snapshots).
function Diagnostics.snapshot(instance)
    local s = instance.stats
    return {
        frames = s.frames,
        layoutRuns = s.layoutRuns,
        rebuilds = s.rebuilds,
        hitRebuilds = s.hitRebuilds,
        items = s.items,
        draws = s.draws,
    }
end

--- Human summary of the instance's frame behaviour.
function Diagnostics.describe(instance)
    local s = instance.stats
    return string.format(
        "DXUI[%s] frames=%d layoutRuns=%d rebuilds=%d hitRebuilds=%d " ..
        "| last list items=%d draws=%d",
        instance.name, s.frames, s.layoutRuns, s.rebuilds, s.hitRebuilds,
        s.items, s.draws)
end

--- One-line string (console-friendly).
function Diagnostics.report(instance)
    return Diagnostics.describe(instance)
end

--- Enables (or disables) the zero-work idle assertion on an instance.
-- Syncing the baseline counters here avoids a false positive on the
-- first asserted frame (previous work predates the mode).
function Diagnostics.enableZeroWork(instance, on)
    instance.perf = instance.perf or {}
    instance.perf.zeroWork = on ~= false
    instance._prevLayoutRuns = instance.stats.layoutRuns
    instance._prevRebuilds = instance.stats.rebuilds
    return instance
end

--- Idle efficiency: frames where the render list was NOT rebuilt, as a
-- fraction of total frames (1.0 = perfect caching).
function Diagnostics.idleRatio(instance)
    local s = instance.stats
    if s.frames < 2 then return 1 end
    local dirtyFrames = s.layoutRuns + s.rebuilds
    if dirtyFrames >= s.frames then return 0 end
    return (s.frames - dirtyFrames) / s.frames
end

DXUI.Diagnostics = Diagnostics