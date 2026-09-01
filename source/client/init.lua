--[[
    init.lua — DXUI V3

    MTA bootstrap (loads LAST in meta.xml, when every module is ready):
      1. wires the DX backend (backend_mta) + text measurement hook;
      2. registers the MTA event glue (render loop, resize, input) that
         drives every UI instance in DXUI._uis;
      3. cleans up instances on resource stop.

    All MTA-specific event handling lives HERE — core/ and api/ stay pure.
    Handlers are registered ONCE at load time; the frame loop ticks every
    instance in DXUI._uis, both the dxui resource's own and consumer-owned
    instances created via exports.dxui:getUI().

    Input events (verified against the MTA wiki):
      - onClientCursorMove  — raw cursor movement (no GUI element needed);
                              params 3-4 are absolute screen pixels.
      - onClientClick       — button, state ("down"/"up"), absX, absY.
      - onClientKey         — keys AND the mouse wheel ("mouse_wheel_up" /
                              "mouse_wheel_down", which never send a release).
      - onClientCharacter   — printable characters (respects layout/shift).
]]

DXUI = DXUI or {}

-- 1. backend wiring ------------------------------------------------------

if DXUI.backendInitMTA then DXUI.backendInitMTA() end
DXUI.Runtime.backend = DXUI.BackendMTA

-- 2. instance bootstrap --------------------------------------------------

-- activate the configured default theme (style/ is loaded by now; an
-- unknown name warns and keeps the current theme — see Theme.activate)
if DXUI.Theme and DXUI.Settings then
    DXUI.Theme.activate(DXUI.Settings.defaultTheme)
end

--- Creates (or returns) the resource's UI and schedules it into the frame
-- loop. opts: { name, design, settings }. The instance is ticked
-- automatically while it exists (the frame loop walks DXUI._uis).
function DXUI.bootstrap(opts)
    opts = opts or {}
    return DXUI.getUI(opts.name or "main", opts)
end

-- 3. MTA event glue (registered once at load) ----------------------------

-- render loop: tick every instance
addEventHandler("onClientRender", resourceRoot, function()
    local uis = DXUI._uis
    if not uis then return end
    for i = 1, #uis do
        uis[i]:tick()
    end
end)

-- viewport: MTA has no resize event, so read the size each frame and
-- recompute the design->screen mapping only on an actual change.
local lastW, lastH = -1, -1
addEventHandler("onClientRender", resourceRoot, function()
    local w, h = guiGetScreenSize()
    if w ~= lastW or h ~= lastH then
        lastW, lastH = w, h
        local uis = DXUI._uis
        if uis then
            for i = 1, #uis do
                uis[i]:setViewport(w, h)
            end
        end
    end
end)

-- mouse movement (absolute screen pixels)
addEventHandler("onClientCursorMove", resourceRoot, function(_, _, absX, absY)
    local uis = DXUI._uis
    if not uis then return end
    for i = 1, #uis do
        uis[i]:mouseMove(absX, absY)
    end
end)

-- clicks
addEventHandler("onClientClick", resourceRoot, function(button, state, absX, absY)
    local uis = DXUI._uis
    if not uis then return end
    for i = 1, #uis do
        if state == "down" then
            uis[i]:mouseDown(button, absX, absY)
        else
            uis[i]:mouseUp(button, absX, absY)
        end
    end
end)

-- keys + mouse wheel (wheel has no dedicated raw-dx event; onClientKey
-- delivers "mouse_wheel_up"/"mouse_wheel_down" with no release).
addEventHandler("onClientKey", resourceRoot, function(keyName, pressed)
    local uis = DXUI._uis
    if not uis then return end
    if keyName == "mouse_wheel_up" or keyName == "mouse_wheel_down" then
        local wheel = (keyName == "mouse_wheel_up") and 1 or -1
        local cx, cy = getCursorPosition()
        local sw, sh = guiGetScreenSize()
        local ax, ay = (cx or 0) * sw, (cy or 0) * sh
        for i = 1, #uis do
            uis[i]:scroll(wheel, ax, ay)
        end
    else
        -- shift state rides the event so widgets can extend selections
        local shift = getKeyState ~= nil
            and (getKeyState("lshift") or getKeyState("rshift")) or false
        for i = 1, #uis do
            uis[i]:key(keyName, pressed, shift)
        end
    end
end)

-- printable characters (text input for Edit and friends)
addEventHandler("onClientCharacter", resourceRoot, function(ch)
    local uis = DXUI._uis
    if not uis then return end
    for i = 1, #uis do
        uis[i]:character(ch)
    end
end)

-- this resource stopping: destroy its own instances + release assets
addEventHandler("onClientResourceStop", resourceRoot, function()
    DXUI.releaseResource("default")
    if DXUI.releaseResources then DXUI.releaseResources() end
end)

-- a CONSUMER resource stopping: release the instances it owns, unless the
-- owner opted out of auto-release (DXUI.Settings.resourcePolicy)
local rootEl = root or (getRootElement and getRootElement() or nil)
if rootEl then
    addEventHandler("onClientResourceStop", rootEl, function()
        local stopped = source
        if stopped and stopped ~= resourceRoot then
            local auto = not (DXUI.Settings and DXUI.Settings.resourcePolicy
                and DXUI.Settings.resourcePolicy.autoRelease == false)
            if auto then
                DXUI.releaseResource(stopped)
            end
        end
    end)
end
