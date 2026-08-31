--[[
    theme.lua — DXUI V2

    Style/Theme система (§62–§64). Глобальная тема + стиль узла:

        DXUI.setTheme({
            Button = {
                default = { color = "#444444", textColor = "#FFFFFF" },
                primary = { color = "#3A6EA5",
                            hover  = { color = "#5588BB" } }, -- state style (§64)
            },
        })

        ui:button({ text = "OK" })               -- тема default
        ui:button({ text = "OK", style = "primary" }) -- тема primary
        ui:button({ style = { color = "#FF0000" } })   -- inline-стиль

    Разрешение (build-time, §63 — «Style resolution при invalidation», НЕ
    каждый кадр): theme[КлассУзла][style или "default"] применяется к свойствам,
    которые пользователь НЕ задал явно в props. Values идут через нормальный
    mutation layer — transform цвета ("#RRGGBB" → packed) работает бесплатно.

    Смена стиля ПОСЛЕ создания (§62): node.style = "primary" / node:setStyle(...)
    возвращает theme-свойства узла к дефолтам класса и применяет новый стиль
    (applyStyle); явно заданные пользователем свойства не затрагиваются.
    Отложено (документировано): parent-style inheritance; hover/pressed
    реализованы для Button через события (явные, читаемые), полный
    state-matrix — future.
]]

DXUI = DXUI or {}

--- Устанавливает глобальную тему (§62).
function DXUI.setTheme(theme)
    DXUI.theme = theme
end

--- Возвращает style-таблицу: inline-таблица | theme[className][styleName|"default"].
function DXUI.getStyle(className, styleName)
    if type(styleName) == "table" then return styleName end
    local t = DXUI.theme
    if not t then return nil end
    local classTheme = t[className]
    if not classTheme then return nil end
    return classTheme[styleName or "default"]
end

--- Применяет theme-дефолты к узлу для свойств, не заданных в props явно.
-- Вызывается из Node:_instantiate (после props, до билдер-дефолтов размеров).
-- Применённые свойства помечаются в node._themeApplied: явная запись
-- свойства пользователем снимает пометку (Node:_set), смена стиля
-- возвращает помеченные к дефолтам класса (applyStyle).
function DXUI.Widget.applyThemeDefaults(node, props)
    local style = DXUI.getStyle(node._class._name, props and props.style)
    if not style then return end
    node._applyingTheme = true
    node._themeApplied = node._themeApplied or {}
    for k, v in pairs(style) do
        -- только declared-свойства, не заданные явно (hover/pressed — не свойства)
        if props[k] == nil and node._spec[k] ~= nil then
            node[k] = v
            node._themeApplied[k] = true
        end
    end
    node._applyingTheme = nil
end

--- Переключает стиль УЖЕ созданного узла (§62: button.style = "primary").
-- Свойства, пришедшие из прежнего стиля, возвращаются к дефолтам класса,
-- затем применяется новый стиль. Свойства, заданные явно (в props или вручную
-- после создания), не затрагиваются.
function DXUI.Widget.applyStyle(node, styleName)
    if node._destroyed then return end
    local style = DXUI.getStyle(node._class._name, styleName)
    node._applyingTheme = true
    local applied = node._themeApplied
    if applied then
        for k in pairs(applied) do
            if not node._userSet[k] then
                local spec = node._spec[k]
                if spec then node[k] = spec.default end
            end
        end
    end
    node._themeApplied = {}
    if style then
        for k, v in pairs(style) do
            if node._spec[k] ~= nil and not node._userSet[k] then
                node[k] = v
                node._themeApplied[k] = true
            end
        end
    end
    node._applyingTheme = nil
end

--- onSet-хук свойства style (объявлен в Node.properties): применяет стиль
--- при записи после создания. На стадии построения (_building) начальное
--- применение делает applyThemeDefaults — повтор не нужен.
function DXUI.Widget._onStyleSet(node, styleName)
    if node._building then return end
    DXUI.Widget.applyStyle(node, styleName)
end