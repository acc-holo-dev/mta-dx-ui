--[[
    tests/loader.lua (M11)

    Единый манифест загрузки всех модулей DXUI в порядке meta.xml.
    Используется во всех тест-файлах вместо копипаста dofile-списков.
    Порядок строго соответствует meta.xml (client/... + bench/bench.lua).
]]

-- Core
dofile("../client/core/constants.lua")
dofile("../client/core/storage.lua")
dofile("../client/core/proxy.lua")
dofile("../client/core/kernel.lua")
dofile("../client/core/selftest.lua")

-- Render
dofile("../client/render/commands.lua")
dofile("../client/render/culling.lua")
dofile("../client/render/layout.lua")
dofile("../client/render/clip.lua")
dofile("../client/render/builder.lua")
dofile("../client/render/batcher.lua")
dofile("../client/render/state_cache.lua")
dofile("../client/render/rt_manager.lua")
dofile("../client/render/profiler.lua")
dofile("../client/render/backend_mta.lua")

-- Anim
dofile("../client/anim/animation.lua")

-- Input
dofile("../client/input/events.lua")
dofile("../client/input/hittest.lua")
dofile("../client/input/dispatcher.lua")

-- Debug
dofile("../client/debug/debug.lua")

-- Widgets
dofile("../client/widgets/ui.lua")

-- Bench (cold path, опционально)
dofile("../bench/bench.lua")

return DXUI
