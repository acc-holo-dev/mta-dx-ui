--[[
    tests/loader.lua — DXUI V2

    Единый манифест загрузки всех модулей DXUI V2 в порядке meta.xml.
    Используется во всех тест-файлах вместо копипаста dofile-списков.
]]

dofile("../client/core/node.lua")
dofile("../client/core/widget.lua")
dofile("../client/render/render_list.lua")
dofile("../client/render/renderer.lua")
dofile("../client/render/state.lua")
dofile("../client/render/backend_mta.lua")
dofile("../client/input/events.lua")
dofile("../client/input/hit_test.lua")
dofile("../client/input/dispatcher.lua")
dofile("../client/api/context.lua")
dofile("../client/api/ui.lua")

return DXUI
