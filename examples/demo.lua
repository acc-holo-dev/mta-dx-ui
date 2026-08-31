--[[
    demo.lua — DXUI v2 minimal demo (consumer resource).

    Add to your resource's meta.xml:
        <include resource="dxui" />
        <script src="demo.lua" type="client" />

    Start order: dxui first, then this resource. The framework renders and
    forwards input automatically (init.lua) — do NOT add an onClientRender
    loop here. Mouse input needs a visible cursor (showCursor), shown below.
]]

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- getUI at resource start may misbehave (MTA note) — use setTimer.
    setTimer(function()
        local ui = exports.dxui:getUI()

        local win = ui:window({
            x = 200, y = 150, width = 340, height = 280,
            title = "DXUI demo", closable = true, draggable = true,
        })

        local clicks = 0
        local counter = win:label({ x = 20, y = 28, width = 200, height = 18, text = "Clicks: 0" })
        win:button({ x = 20, y = 52, width = 120, height = 28, text = "Click me" }):on("click", function()
            clicks = clicks + 1
            counter:setText("Clicks: " .. clicks)
        end)

        local edit = win:edit({ x = 20, y = 96, width = 200, placeholder = "Type here…" })
        edit:onChange(function(text) counter:setText("Edit: " .. text) end)

        local enabled = win:checkbox({ x = 20, y = 136, text = "Enabled", checked = true })
        enabled:onChange(function(v) print("enabled = " .. tostring(v)) end)

        local slider = win:slider({ x = 20, y = 176, width = 200, min = 0, max = 100,
            onChange = function(v) print("value = " .. v) end })

        -- drag & drop: drag src onto tgt
        local src = win:panel({ x = 20, y = 220, width = 60, height = 40, color = 0xFF3A6EA5 })
        src:setDraggable(true):setDragData({ item = "X" })
        local tgt = win:panel({ x = 140, y = 220, width = 80, height = 40, color = 0xFF444444 })
        tgt:setDropTarget(true)
        tgt:on("drop", function(e) outputChatBox("dropped " .. tostring(e.data.item)) end)

        -- translation: key → text, switched by locale
        DXUI.addLocale("en", { ["demo.title"] = "DXUI demo" })
        DXUI.addLocale("ru", { ["demo.title"] = "Демо DXUI" })
        win:setTextKey("demo.title", "title")

        showCursor(true)
    end, 100, 1)
end)