--[[
    bootstrap.lua

    Точка входа ресурса на клиенте. Загружается последним (см. meta.xml).

    M3 подключает единый input dispatcher (§25 ТЗ) поверх ДВУХ глобальных
    MTA-событий: onClientCursorMove и onClientClick — не по одному
    обработчику на узел.

    M4 подключает layout-систему (§40/§41 ТЗ): world-координаты вычисляются
    из локальных описаний (layoutMode/anchor/margin) + world-координат
    родителя. Hit-test и рендер работают в world-координатах (storage.worldX/worldY),
    а не в "сырых" экранных координатах. Размер экрана устанавливается через
    Kernel:setScreenSize() для корневых узлов в LAY_REL/LAY_CENTER.
]]

addEventHandler("onClientResourceStart", resourceRoot, function()
    DXUI.instance = DXUI.Kernel.new(DXUI.MtaDriver)
    DXUI.ui = DXUI.UI.new(DXUI.instance) -- M7: декларативный widget API

    -- M4: устанавливает размер экрана для layout-системы (корневые узлы
    -- в LAY_REL/LAY_CENTER используют эти значения как parentW/parentH).
    DXUI.instance:setScreenSize(getScreenSize())

    addEventHandler("onClientRender", root, function()
        DXUI.instance:renderFrame()
    end)

    addEventHandler("onClientResolutionChange", root, function()
        local w, h = getScreenSize()
        DXUI.instance:setScreenSize(w, h)
        -- M8: пул RT пересоздаём — старые RT привязаны к старому разрешению.
        if DXUI.instance.rtManager then DXUI.instance.rtManager:resize() end
    end)

    addEventHandler("onClientCursorMove", root, function(_, _, absX, absY)
        DXUI.instance:onCursorMove(absX, absY)
    end)

    addEventHandler("onClientClick", root, function(button, state, absX, absY)
        if absX == nil then return end -- клик мог прийти без экранных координат (не по элементу мира)
        if state == "down" then
            DXUI.instance:onMouseDown(absX, absY, button)
        elseif state == "up" then
            DXUI.instance:onMouseUp(absX, absY, button)
        end
    end)

    -- M13 (ADR-017): колесо мыши. MTA не имеет отдельного onClientMouseWheel
    -- события -- прокрутка ловится bindKey("mouse_wheel_up"/"mouse_wheel_down").
    -- Координаты курсора -- getCursorPosition() (доступна пока курсор показан).
    if bindKey then
        local function wheel(dz)
            local k = DXUI.instance
            if not k then return end
            local cx, cy = 0, 0
            if getCursorPosition then cx, cy = getCursorPosition() end
            if cx == nil then cx, cy = 0, 0 end
            k:onMouseWheel(cx or 0, cy or 0, dz)
        end
        bindKey("mouse_wheel_up",   "down", function() wheel(1)  end)
        bindKey("mouse_wheel_down", "down", function() wheel(-1) end)
    end

    -- M14/M15 (ADR-018/019): клавиатура. onClientKey даёт (key, state, mods, text).
    -- key -- имя клавиши; mods -- "ctrl"/"shift"/""; text -- символ (для EVENT_TEXT).
    addEventHandler("onClientKey", root, function(key, state, mods, text)
        local k = DXUI.instance
        if k then
            k:onKeyDown(key, state, mods, text)
        end
    end)

    -- M10: Profiler overlay (cold path — только при включённом).
    -- DXUI.toggleProfile() — включает/выключает профилирование + overlay.
    local textNode = DXUI.instance:create(3) -- NODE_TEXT, root
    textNode:setPosition(10, 10)
    textNode:setSize(280, 220)
    textNode:setColor(0x00FF00) -- зелёный монохром (console-style)
    textNode:setVisible(false)
    textNode:setEnabled(false) -- не участвует в hit-test

    DXUI.toggleProfile = function()
        local k = DXUI.instance
        if not k then return false end
        local now = k.profiler:toggle()
        outputChatBox(string.format("[dxui] Profiler: %s", now and "ON" or "OFF"))
        return now
    end

    -- Overlay: этот handler добавлен ПОСЛЕ renderFrame-handler'а выше, значит
    -- MTA вызовет его ПОСЛЕ renderFrame (порядок addEventHandler = порядок
    -- вызова). Видим статистику ТЕКУЩЕГО кадра.
    addEventHandler("onClientRender", root, function()
        local k = DXUI.instance
        if not k then return end
        if k.profiler.enabled then
            textNode:setContent(k.profiler:format())
            if not textNode:isVisible() then textNode:setVisible(true) end
        elseif textNode:isVisible() then
            textNode:setVisible(false)
        end
    end)

    -- M10: Debug-система (cold path — только при включённом).
    -- DXUI.toggleDebug() — включает/выключает bounds-overlay + инспекцию.
    -- DXUI.debug:dumpTree() / DXUI.debug:inspect(id) / DXUI.debug:hitTest(x,y).
    DXUI.debug = DXUI.Debug.new(DXUI.instance)
    DXUI.toggleDebug = function()
        local d = DXUI.debug
        if not d then return false end
        local now = d:toggle()
        outputChatBox(string.format("[dxui] Debug: %s", now and "ON" or "OFF"))
        return now
    end

    -- Bounds-overlay: отдельный onClientRender handler ПОСЛЕ renderFrame
    -- (добавлен позже — вызывается позже). Рисует рамки поверх UI.
    addEventHandler("onClientRender", root, function()
        local d = DXUI.debug
        if d and d.enabled then
            d:drawBounds(DXUI.instance.driver)
        end
    end)

    if DXUI.Constants.DEBUG then
        outputChatBox("[dxui] M20 initialized: polish (opacity-anim, tooltip delay, modal auto-focus, slider click-to-jump/vertical) (ADR-024)")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    -- M3: EventBus/Dispatcher — чистые Lua-таблицы, ничего не требует
    -- явного освобождения сверх того, что уже покрыто в M1/M2.
    DXUI.instance = nil
end)
