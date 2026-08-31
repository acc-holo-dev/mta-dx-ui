--[[
    init.lua — DXUI V2

    Resource entry point on the client. Loaded last (see meta.xml).

    Stage 3: render loop (onClientRender → renderFrame of all contexts).
    Stage 4: input bridge (onClientCursorMove/onClientClick/onClientKey →
    all contexts). One global bridge, NOT per-node handlers.
]]

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- Global coordinator: screen size for layout (Stage 5).
    local w, h = getScreenSize()
    DXUI.screenW = w
    DXUI.screenH = h

    -- Single render loop for all contexts.
    addEventHandler("onClientRender", root, function()
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            contexts[i]:renderFrame()
        end
    end)

    -- Single input bridge for all contexts.
    addEventHandler("onClientCursorMove", root, function(_, _, absX, absY)
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

    addEventHandler("onClientKey", root, function(key, state, mods, text)
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            contexts[i]:onKeyDown(key, state, mods, text)
        end
    end)

    if DXUI.config.debug then
        outputChatBox("[dxui-v2] Stage 4 input initialized")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    -- Contexts are plain Lua tables; release cached dx resources.
    DXUI.releaseResources()
end)
