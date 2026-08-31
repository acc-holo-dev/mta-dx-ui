--[[
    demo.lua — DXUI V2

    Showcase для полевых испытаний в MTA (§111/§113): команда /dxuidemo
    открывает окно со всеми основными возможностями. Проверить в игре:
    скругления/рамку/blur, анимации, drag окна, ввод, скролл, tooltip.

    Загружается ТОЛЬКО в MTA (guard на addEventHandler); в тесты не входит.
]]

if not addCommandHandler or not addEventHandler then return end

local demoWindow = nil

local function buildDemo()
    if demoWindow and demoWindow:isAlive() then
        demoWindow:destroy()
        demoWindow = nil
        return
    end

    DXUI.setTheme({
        Button = {
            primary = { color = "#3A6EA5", hover = { color = "#5588BB" } },
        },
    })

    local ui = DXUI._contexts[1] or DXUI.createContext()
    local win = ui:window({
        x = 120, y = 120, width = 420, height = 360,
        title = "DXUI V2 Demo", draggable = true, closable = true,
        radius = 8, outlineWidth = 1, outlineColor = "#3A3A4A",
    })
    demoWindow = win

    -- blur-панель (RT-группа) + скругления
    win:panel({
        x = 20, y = 40, width = 380, height = 60,
        color = "#1E2836", radius = 6, blur = 2,
    })
    local title = win:label({
        x = 30, y = 50, width = 360, height = 20,
        text = "#55AAFFRounded + blur + outline (RT)", scale = 1.1,
    })

    -- анимированная кнопка
    local btn = win:button({
        x = 20, y = 120, width = 180, height = 40,
        text = "Animate me", style = "primary", radius = 6,
        font = DXUI.font("default-bold", 10),
    })
    btn:on("click", function()
        btn:animate({ x = 220 }, 400, "out")
            :after({ x = 20 }, 400, "inout")
            :onDone(function() title.text = "Animation chain done!" end)
    end)

    -- контролы
    local cb = win:checkbox({ x = 20, y = 175, text = "Enable stuff",
        onChange = function(v) title.text = v and "Checked!" or "Unchecked" end })
    local r1 = win:radiobutton({ x = 20, y = 200, text = "Option A", group = "demo" })
    local r2 = win:radiobutton({ x = 20, y = 224, text = "Option B", group = "demo" })
    r1:setChecked(true)

    local slider = win:slider({ x = 150, y = 210, width = 200, min = 0, max = 100,
        onChange = function(v) title.text = "Slider: " .. math.floor(v) end })

    local edit = win:edit({ x = 20, y = 255, width = 200, height = 26,
        placeholder = "Type here...", font = DXUI.font("default-bold", 9) })
    edit:onEnter(function() title.text = "You typed: " .. edit:getText() end)

    -- scrollpanel с контентом + tooltip
    local sp = win:scrollpanel({ x = 230, y = 255, width = 170, height = 80 })
    for i = 1, 6 do
        local row = ui:label({ x = 4, y = (i - 1) * 22, width = 140, height = 18,
            text = "Scroll row " .. i })
        row:setParent(sp:getContent())
    end
    btn:setTooltip("Click to run the animation chain!")

    win:label({ x = 20, y = 330, width = 380, height = 18,
        text = "Drag title bar • /dxuidemo to close", valign = "middle" })

    outputChatBox("[dxui-v2] Demo window opened — /dxuidemo to toggle")
end

addCommandHandler("dxuidemo", buildDemo)