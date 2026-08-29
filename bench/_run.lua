--[[
    bench/_run.lua (M9)

    Standalone-раннер бенчмарка (вне MTA, через lupa). dofile всех модулей
    в правильном порядке (как meta.xml), no-op драйвер, setScreenSize,
    затем DXUI.Bench.runAll(k).

    Запуск (из корня проекта):
      .venv\\Scripts\\python.exe -c "import lupa; lua=lupa.LuaRuntime(); lua.execute(open('bench/_run.lua', encoding='utf-8').read())"
]]

dofile("client/core/constants.lua")
dofile("client/core/storage.lua")
dofile("client/core/proxy.lua")
dofile("client/render/commands.lua")
dofile("client/render/culling.lua")
dofile("client/render/layout.lua")
dofile("client/render/clip.lua")
dofile("client/render/builder.lua")
dofile("client/render/batcher.lua")
dofile("client/render/state_cache.lua")
dofile("client/render/rt_manager.lua")
dofile("client/render/profiler.lua")
dofile("client/anim/animation.lua")
dofile("client/input/events.lua")
dofile("client/input/hittest.lua")
dofile("client/input/dispatcher.lua")
dofile("client/debug/debug.lua")
dofile("client/core/kernel.lua")
dofile("bench/bench.lua")

local driver = {}
driver.setBlendMode = function() end
driver.pushClip = function() end
driver.popClip = function() end
driver.setOpacity = function() end
driver.setBlur = function() end
driver.drawRect = function() end
driver.drawImage = function() end
driver.drawText = function() end

local k = DXUI.Kernel.new(driver)
k:setScreenSize(1280, 720)

DXUI.Bench.runAll(k)
