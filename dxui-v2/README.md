# DXUI V2 — MTA:SA UI Framework (Lua 5.1)

DXUI V2 — это редизайн клиентской UI-библиотеки для MTA:SA (Multi Theft Auto: San Andreas).
Цель: сохранить поведение legacy-реализации, но заменить внутреннее
представление на читаемый, расширяемый и тестируемый код.

## Быстрый старт

    local ui = DXUI.createContext()
    ui:setScreenSize(1280, 720)
    
    local btn = ui:button({ x = 100, y = 100, text = "Click me" })
    btn:on("click", function()
        print("clicked!")
    end)
    
    function onClientRender()
        ui:renderFrame()
    end
    addEventHandler("onClientRender", root, onClientRender)

## Архитектура (кратко)

- **AoS Node** — публичный API: обычные Lua-таблицы (node.x, node.width, node.color).
- **Property system** — __newindex/__index сходятся в единый _set(), который
  валидирует и инвалидирует нужные подсистемы.
- **Dirty categories** — именованные флаги (DIRTY_LAYOUT, DIRTY_RENDER,
  DIRTY_INPUT, DIRTY_STYLE, DIRTY_CHILDREN, DIRTY_VISIBILITY).
- **Flat lists** — interactiveList и renderList строятся из дерева по
  необходимости, а не обходят дерево каждый кадр.
- **Layer + _effLayer** — слой вычисляется рекурсивно при сборе, не мутируется
  через setParent (исключает "застревание" в MODAL).
- **Style ownership** — applyThemeDefaults при build + applyStyle runtime
  с защитой _userSet (ручные настройки не затираются).
- **Isolated contexts** — ui.createContext() создаёт независимый мир
  (дерево, фокус, слои).

## Структура проекта

    dxui-v2/
    ├── client/
    │   ├── api/          -- Context, UI coordinator
    │   ├── core/         -- Node, Widget (property system, lifecycle)
    │   ├── input/        -- Dispatcher, hit-test, events
    │   ├── layout/       -- absolute/relative/anchor/center/stretch/autosize
    │   ├── render/       -- Renderer, RenderList, state cache, backend
    │   ├── resources/    -- Texture/font/shader cache
    │   ├── animation/    -- Tween manager + easing
    │   ├── style/        -- Theme, applyThemeDefaults, applyStyle
    │   ├── text/         -- Text.measure, wrap, align
    │   ├── utils/        -- color resolution
    │   └── widgets/      -- 16+ виджетов (button, edit, window, ...)
    ├── tests/            -- Python+Lupa test suite (12 файлов, ~300 assertions)
    ├── docs/adr/         -- Architecture Decision Records
    ├── ARCHITECTURE.md   -- полное описание архитектуры
    └── meta.xml          -- MTA resource manifest

## Тесты

Тесты запускаются через Python + lupa (Lua 5.1 embedded):

    python tests/run.py

Все тесты используют mock backend (без MTA) и покрывают:
- Core (Node lifecycle, property system, dirty invalidation)
- Input (dispatcher, hit-test, focus, events, drag)
- Layout (world coords, anchors, stretch, autosize)
- Render (primitives, clip cull, state cache, design resolution)
- Widgets (button, edit, window, popup, modal, radiobutton, ...)
- Advanced (animation, style switching, clipboard, multi-row selection)

## Контракт виджета

Чтобы добавить новый виджет, нужно:

1. Создать файл client/widgets/mywidget.lua
2. Описать свойства (properties) с defaults и invalidates
3. Реализовать :render(renderer)
4. Зарегистрировать builder в client/widgets/builders.lua

Подробнее — см. ARCHITECTURE.md §8.

## Лицензия

MIT (сохраняйте attribution при форках).
