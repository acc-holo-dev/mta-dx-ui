--[[
    init.lua — DXUI

    Resource entry point on the client. Loaded last (see meta.xml).

    Bridges MTA client events to all contexts (DXUI._contexts):
      onClientRender        → renderFrame
      onClientCursorMove    → onCursorMove (absolute px)
      onClientClick         → onMouseDown/onMouseUp
      onClientKey           → onKeyDown (bool press → "down"/"up")
      onClientKey wheel     → onMouseWheel (mouse_wheel_up/down, ±1)
      onClientCharacter     → onCharacter (text input for edit)

    Modifier keys (lctrl/rctrl/lshift/rshift/lalt/ralt) are tracked into a
    "ctrl"/"ctrl+shift"/... mods string (Edit shortcuts rely on it). Wheel
    uses the last cursor position (wheel events carry no coords).
    Mouse buttons are delivered via onClientClick — onClientKey skips them.

    One global bridge, NOT per-node handlers. The cursor must be shown by
    the consumer (showCursor(true)) for the mouse events to fire.
]]

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- Global coordinator: screen size for layout.
    local w, h = guiGetScreenSize()
    DXUI.screenW = w
    DXUI.screenH = h

    -- Last cursor position (screen px): wheel events carry no coords.
    local lastX, lastY = w / 2, h / 2

    -- Held modifier keys (onClientKey reports raw key names; the dispatcher
    -- expects a "ctrl"/"ctrl+shift"/... mods string for Edit shortcuts).
    local MODIFIERS = {
        lctrl = "ctrl", rctrl = "ctrl",
        lshift = "shift", rshift = "shift",
        lalt = "alt", ralt = "alt",
    }
    local held = {}
    local function modsString()
        local out = ""
        if held.ctrl then out = out .. "ctrl" end
        local suffix = ""
        if held.shift then suffix = suffix .. "shift" end
        if held.alt then
            if suffix ~= "" then suffix = suffix .. "+" end
            suffix = suffix .. "alt"
        end
        if suffix ~= "" then
            if out ~= "" then out = out .. "+" end
            out = out .. suffix
        end
        return out
    end

    -- Single render loop for all contexts.
    addEventHandler("onClientRender", root, function()
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            contexts[i]:renderFrame()
        end
    end)

    -- Single input bridge for all contexts.
    addEventHandler("onClientCursorMove", root, function(_, _, absX, absY)
        lastX, lastY = absX, absY
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            contexts[i]:onCursorMove(absX, absY)
        end
    end)

    addEventHandler("onClientClick", root, function(button, state, absX, absY)
        if absX == nil then return end -- click without screen coords (world)
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            local ctx = contexts[i]
            if state == "down" then
                ctx:onMouseDown(absX, absY, button)
            elseif state == "up" then
                ctx:onMouseUp(absX, absY, button)
            end
        end
    end)

    addEventHandler("onClientKey", root, function(key, press)
        -- MTA passes a bool; the dispatcher speaks "down"/"up".
        local state = press and "down" or "up"

        -- modifiers are tracked, never forwarded as widget key events
        local mod = MODIFIERS[key]
        if mod then
            held[mod] = press
            return
        end

        -- The mouse wheel arrives here too (mouse_wheel_up/down).
        if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
            if state == "down" then
                local dz = (key == "mouse_wheel_up") and 1 or -1
                local contexts = DXUI._contexts
                for i = 1, #contexts do
                    contexts[i]:onMouseWheel(lastX, lastY, dz)
                end
            end
            return
        end

        -- Mouse buttons are delivered via onClientClick; skip them here.
        if key:sub(1, 5) == "mouse" then return end

        local contexts = DXUI._contexts
        for i = 1, #contexts do
            -- text input comes via onClientCharacter, not onClientKey
            contexts[i]:onKeyDown(key, state, modsString(), nil)
        end
    end)

    -- Character input (typing): goes to the focused node.
    addEventHandler("onClientCharacter", root, function(char)
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            contexts[i]:onCharacter(char)
        end
    end)

    if DXUI.config and DXUI.config.debug then
        outputChatBox("[dxui] input initialized")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    -- Contexts are plain Lua tables; release cached dx resources.
    DXUI.releaseResources()
end)
