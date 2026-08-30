--[[
    test_m20.lua -- M20 polish (ADR-024): ANIM_OPACITY (fade), Kernel:schedule
    (отложенные колбэки), setDisabled/isDisabled. Паттерн test_m12.
    (tooltip delay — test_m17; modal auto-focus — test_m16; slider
    click-to-jump/vertical — test_m18.)
]]

dofile("loader.lua")

local Kernel = DXUI.Kernel
local C = DXUI.Constants
local passed, failed = 0, 0

local function check(name, cond)
    if cond then
        passed = passed + 1
        print("[OK]   " .. name)
    else
        failed = failed + 1
        print("[FAIL] " .. name)
    end
end

local function newUI()
    local k = Kernel.new({
        setBlendMode = function() end,
        pushClip = function() end,
        popClip = function() end,
        setOpacity = function() end,
        setBlur = function() end,
        drawRect = function() end,
        drawImage = function() end,
        drawText = function() end,
    })
    local ui = DXUI.UI.new(k)
    k:setScreenSize(1280, 720)
    return k, ui
end

-- 1. ANIM_OPACITY: animateTo({opacity=}) fade
do
    local k, ui = newUI()
    local tick = 0
    k:setClock(function() return tick end)
    local p = ui:panel({ x = 0, y = 0, w = 100, h = 100 })
    p:animateTo({ opacity = 0 }, 100, C.EASE_OUT)
    check("opacity: isAnimating", p:isAnimating())
    tick = tick + 200 -- > 100ms -> комплит
    k:renderFrame()
    check("opacity: анимация завершена", not p:isAnimating())
    local slot = k.storage.idToSlot[p.id]
    check("opacity: storage.opacity == 0", k.storage.opacity[slot] == 0)
    check("opacity: FLAG_OPACITY установлен", k.storage:hasFlag(p.id, C.FLAG_OPACITY))
end

-- 2. ANIM_OPACITY: fade-in (0 -> 255) снимает флаг
do
    local k, ui = newUI()
    local tick = 0
    k:setClock(function() return tick end)
    local p = ui:panel({ x = 0, y = 0, w = 100, h = 100 })
    p:setOpacity(0)
    p:animateTo({ opacity = 255 }, 100, C.EASE_OUT)
    tick = tick + 200
    k:renderFrame()
    local slot = k.storage.idToSlot[p.id]
    check("opacity: fade-in -> 255", k.storage.opacity[slot] == 255)
    check("opacity: FLAG_OPACITY снят", not k.storage:hasFlag(p.id, C.FLAG_OPACITY))
end

-- 3. Kernel:schedule — отложенный колбэк (единый clock)
do
    local k, ui = newUI()
    local tick = 0
    k:setClock(function() return tick end)
    local fired = 0
    k:schedule(100, function() fired = fired + 1 end)
    k:renderFrame() -- tick=0, ещё рано
    check("schedule: не сработал до задержки", fired == 0)
    tick = tick + 150
    k:renderFrame()
    check("schedule: сработал после задержки", fired == 1)
    k:renderFrame() -- повторно не срабатывает (удалён)
    check("schedule: не повторяется", fired == 1)
end

-- 4. setDisabled/isDisabled
do
    local k, ui = newUI()
    local p = ui:panel({ x = 0, y = 0, w = 100, h = 100 })
    check("disabled: изначально enabled", not p:isDisabled())
    p:setDisabled(true)
    check("disabled: isDisabled true", p:isDisabled())
    check("disabled: isEnabled false", not p:isEnabled())
    local slot = k.storage.idToSlot[p.id]
    check("disabled: opacity 120", k.storage.opacity[slot] == 120)
    p:setDisabled(false)
    check("disabled: isDisabled false", not p:isDisabled())
    check("disabled: opacity 255", k.storage.opacity[slot] == 255)
end

print(string.format("test_m20: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
