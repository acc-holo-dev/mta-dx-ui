--[[
    test_m18.lua -- Controls (ADR-022): CheckBox, RadioButton (группы),
    ProgressBar, Slider (drag + click-to-jump + vertical, M20).
    Паттерн test_m12.
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

-- 1. CheckBox: toggle/isChecked/setChecked/onChange
do
    local k, ui = newUI()
    local cb = ui:checkbox({ text = "Check" })
    check("checkbox: unchecked", not cb:isChecked())
    cb:toggle()
    check("checkbox: toggle -> checked", cb:isChecked())
    cb:setChecked(false)
    check("checkbox: setChecked(false)", not cb:isChecked())

    local changed = 0
    local cb2 = ui:checkbox({ onChange = function(v) changed = changed + 1 end })
    cb2:setChecked(true)
    check("checkbox: onChange вызван", changed == 1)
    cb2:setChecked(true) -- повторно — no-op (guard)
    check("checkbox: повторный setChecked(true) — no-op", changed == 1)
end

-- 2. RadioButton: группа — выбор одного снимает другой
do
    local k, ui = newUI()
    local r1 = ui:radiobutton({ group = "g", checked = true })
    local r2 = ui:radiobutton({ group = "g" })
    check("radio: r1 checked", r1:isChecked())
    check("radio: r2 unchecked", not r2:isChecked())
    r2:setChecked(true)
    check("radio: r2 checked", r2:isChecked())
    check("radio: r1 unchecked (группа)", not r1:isChecked())
    -- клик по выбранному radio — no-op (не снимается)
    r2:setChecked(true)
    check("radio: повторный выбор — остаётся checked", r2:isChecked())
end

-- 3. ProgressBar: setValue/getValue/setRange + fill
do
    local k, ui = newUI()
    local pb = ui:progressbar({ value = 50 })
    check("progressbar: getValue 50", pb:getValue() == 50)
    pb:setValue(75)
    check("progressbar: setValue 75", pb:getValue() == 75)
    pb:setRange(0, 200)
    local fw = pb._parts.fill:getSize()
    check("progressbar: fill 75px (200*0.375)", fw == 75)
    pb:setValue(300) -- clamp к max
    local fw2 = pb._parts.fill:getSize()
    check("progressbar: clamp к 100% (fill 200)", fw2 == 200)
end

-- 4. Slider: setValue/getValue/setRange + thumb
do
    local k, ui = newUI()
    local sl = ui:slider({ value = 50 })
    check("slider: getValue 50", sl:getValue() == 50)
    sl:setValue(75)
    check("slider: setValue 75", sl:getValue() == 75)
    sl:setRange(0, 200)
    local tx = sl._parts.thumb:getPosition()
    check("slider: thumb x ~71.25 (0.375*190)", math.abs(tx - 71.25) < 0.01)
end

-- 5. Slider: click-to-jump (M20)
do
    local k, ui = newUI()
    local sl = ui:slider({ x = 0, y = 0, w = 200, h = 16 })
    k:renderFrame()
    k:onMouseDown(100, 8, "left")
    k:onMouseUp(100, 8, "left")
    check("slider: click-to-jump ~52.6", math.abs(sl:getValue() - 52.63) < 1)
end

-- 6. Slider: vertical orientation (M20)
do
    local k, ui = newUI()
    local sl = ui:slider({ orientation = "v", w = 16, h = 200, value = 50 })
    local _, ty = sl._parts.thumb:getPosition()
    check("slider: vertical thumb y ~95 (0.5*190)", math.abs(ty - 95) < 0.01)
end

print(string.format("test_m18: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
