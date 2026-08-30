--[[
    init.lua — DXUI V2

    Точка входа ресурса на клиенте. Загружается последним (см. meta.xml).

    Stage 3: render loop (onClientRender → renderFrame всех контекстов).
    Stage 4: input bridge (onClientCursorMove/onClientClick/onClientKey →
    все контексты). Один глобальный bridge, НЕ per-node обработчики (§44).
]]

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- Глобальный coordinator: screen size для layout (Stage 5).
    local w, h = getScreenSize()
    DXUI.screenW = w
    DXUI.screenH = h

    -- Единый render loop для всех контекстов.
    addEventHandler("onClientRender", root, function()
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            contexts[i]:renderFrame()
        end
    end)

    -- Единый input bridge для всех контекстов.
    addEventHandler("onClientCursorMove", root, function(_, _, absX, absY)
        local contexts = DXUI._contexts
        for i = 1, #contexts do
            contexts[i]:onCursorMove(absX, absY)
        end
    end)

    addEventHandler("onClientClick", root, function(button, state, absX, absY)
        if absX == nil then return end -- клик без экранных координат (мир)
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
    -- Контексты — чистые Lua-таблицы; явного освобождения не требуют.
end)
