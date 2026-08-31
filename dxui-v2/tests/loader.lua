--[[
    tests/loader.lua — DXUI V2

    Единый манифест загрузки всех модулей DXUI V2 в порядке meta.xml.
    Используется во всех тест-файлах вместо копипаста dofile-списков.
]]

dofile("../client/core/node.lua")
dofile("../client/utils/color.lua")
dofile("../client/core/widget.lua")
dofile("../client/style/theme.lua")
dofile("../client/resources/manager.lua")
dofile("../client/animation/easing.lua")
dofile("../client/animation/animation.lua")
dofile("../client/text/text.lua")
dofile("../client/layout/layout.lua")
dofile("../client/render/render_list.lua")
dofile("../client/render/renderer.lua")
dofile("../client/render/effects.lua")
dofile("../client/render/state.lua")
dofile("../client/render/backend_mta.lua")
dofile("../client/input/events.lua")
dofile("../client/input/hit_test.lua")
dofile("../client/input/dispatcher.lua")
dofile("../client/widgets/panel.lua")
dofile("../client/widgets/label.lua")
dofile("../client/widgets/button.lua")
dofile("../client/widgets/image.lua")
dofile("../client/widgets/window.lua")
dofile("../client/widgets/toggle.lua")
dofile("../client/widgets/checkbox.lua")
dofile("../client/widgets/radiobutton.lua")
dofile("../client/widgets/slider.lua")
dofile("../client/widgets/progressbar.lua")
dofile("../client/widgets/scrollpanel.lua")
dofile("../client/widgets/edit.lua")
dofile("../client/widgets/popup.lua")
dofile("../client/widgets/contextmenu.lua")
dofile("../client/widgets/combobox.lua")
dofile("../client/widgets/tabpanel.lua")
dofile("../client/widgets/gridlist.lua")
dofile("../client/widgets/tooltip.lua")
dofile("../client/widgets/builders.lua")
dofile("../client/api/context.lua")
dofile("../client/api/ui.lua")

return DXUI
