# DXUI V2 — Architecture

> **Принцип:** SIMPLE OUTSIDE, ENGINEERED INSIDE.
> Публичный API — обычный объектный Lua. Внутри — контроллируемые оптимизации,
> изолированные от пользователя.

Этот документ — результат Stage 0 (аудит legacy) и Stage 1 (архитектурный
redesign). Legacy (client/, docs/adr/, tests/) остаётся reference
implementation: его **поведение** сохраняем, **реализацию** — нет.

---

## 1. Почему redesign, а не rewrite

Legacy достиг функциональной полноты (M20, ~300 тестов), но его архитектура
оптимизирована под внутреннее представление данных, а не под человека:

| Проблема legacy | Следствие |
|---|---|
| SoA + slot + id-индирекция | виджеты читают s.worldX[slot], s.w[slot] — автор виджета обязан знать SoA |
| Нет property-style API | только setPosition(...), нет button.x = 100 |
| ui.lua = 2929 строк | все 16 виджетов в одном файле |
| _parts, _win, _sp и т.д. | параллельная система состояния вне Storage, ручной cleanup |
| 10+ почти одинаковых makeXxxMt | дублирование метатабличной логики |

V2 решает эти проблемы, **не** выбрасывая то, что legacy сделал правильно:
dirty-инвалидация, zero-work idle, централизованный input, data-driven
анимацию, RT-clip, composite-концепцию, layer-архитектуру.

---

## 2. Слои

PUBLIC API          (ui.*, node.*, context.*)
    ↓
UI OBJECTS          (Node, Widget, composite)
    ↓
UI RUNTIME          (Context: layout / input / render / style / resources)
    ↓
MTA DX              (backend_mta)

Зависимости идут только вниз. Core не знает о конкретных виджетах.
Renderer не знает о внутреннем состоянии сложных виджетов.

---

## 3. Node — публичный объект (AoS)

Node — **обычная Lua-таблица**, которую держит пользователь. Это source of
truth состояния узла. Никаких slot/id/SoA в публичном представлении.

    node = {
        id        = number,
        x = 0, y = 0,
        width = 0, height = 0,
        visible = true,
        enabled = true,
        opacity = 1,
        parent = nil,
        children = {},
        zIndex = 0,
        layer = LAYER_BASE,
        style = nil,
        userData = nil,
    }

### 3.1 Property system (единый mutation layer)

Метатаблица Node перехватывает запись через __newindex и чтение через
__index. **Оба стиля** — property и method — сходятся в один внутренний
слой node:_set(prop, value):

    button.x = 100            -- __newindex -> _set("x", 100)
    button:setPosition(100, 0) -- метод -> _set("x", 100) + _set("y", 0)

_set делает ровно три вещи:
1. валидация значения (в dev-режиме);
2. запись в поле;
3. инвалидация ровно тех подсистем, которые зависят от свойства.

Свойства объявляются **декларативно** (см. §8 Widget contract), поэтому
_set не содержит гигантского if/elseif — таблица свойств генерирует
getter/setter/invalidation один раз при определении виджета.

### 3.2 Invalidation (читаемые категории)

Вместо 0x091 — именованные категории. Внутри допустим boolean-флаги,
но наружу они никогда не выходят:

    DIRTY_LAYOUT      -- позиция/размер/родитель/якорь/margin/padding
    DIRTY_RENDER      -- цвет/текст/текстура/opacity/геометрия
    DIRTY_INPUT       -- hit-геометрия/видимость/enabled/z-order
    DIRTY_STYLE       -- разрешение стиля
    DIRTY_CHILDREN    -- состав детей
    DIRTY_VISIBILITY  -- видимость/culling

Каждое свойство знает, какие категории оно инвалидирует (объявлено в его
описании). Изменение x -> DIRTY_LAYOUT; изменение color -> DIRTY_RENDER.

### 3.3 Lifecycle (явный)

    created → mounted → updated → hidden → detached → destroyed

- **created** — ui.panel(...) / context:create(...).
- **mounted** — узел (или его предок) прикреплён к корню контекста.
- **updated** — изменение свойства (через _set).
- **hidden** — visible = false (узел жив, не рисуется, не хитается).
- **detached** — parent = nil (узел жив, вне дерева).
- **destroyed** — node:destroy(); рекурсивно сносит детей, снимает
  подписки, освобождает node-owned ресурсы.

Ownership: **родитель владеет детьми**. Destroy родителя уничтожает поддерево.
События/ресурсы/анимации узла освобождаются в destroy.

---

## 4. Context

    local hud  = ui.createContext()
    local menu = ui.createContext()

Каждый context владеет:
- своим корнем (root node);
- своим focus manager;
- своими layers;
- своим lifecycle (renderFrame).

Глобальный coordinator (screen size, input bridge) живёт в api/ui.lua.
Контексты изолированы: фокус/слои/дерево одного не влияют на другой.

---

## 5. Rendering

### 5.1 Модель: per-node emit (Stage 0–11)

Renderer в текущей реализации не держит persistent derived flat cache на
уровне контекста. Вместо этого renderFrame обходит dirty-узлы и
вызывает node:render(renderer) — виджет сам эмитит примитивы в
RenderList. Это O(N) в худшем случае, но достаточно для текущего scope.

Полноценный flat render list (постоянный derived cache с partial update)
запланирован на следующий этап; текущий подход обеспечивает zero-work idle
(только dirty-узлы рендерятся) и читаемость.

### 5.2 Pipeline кадра

    renderFrame
      → processDirty           (layout, style, render)
      → rebuildInteractiveList   (если dirtyCount > 0)
      → clearDirty
      → drawRenderList           (flat items → backend)

Каждый этап **conditional**: если ничего не изменилось, этап пропускается.

### 5.3 Ordering

Сортировка render items и interactive nodes по (_effLayer, zIndex, id).
_effLayer вычисляется рекурсивно при сборе (ADR-003), а не
мутируется через setParent.

### 5.4 Clipping: cheap path

- **Cheap path (реализован, Stage 7/9)** — geometric clip: узел с clip=true
  задаёт clip-регион; renderer пересекает примитивы с регионом, целиком
  невидимые — пропускаются. Без RT.
- **Expensive path (эффекты)** — effects.lua содержит заготовки для
  blur/mask/RT-групп, но полноценная RT-compositing pipeline — future work.

### 5.5 Opacity

opacity — float 0..1 на любом визуальном узле, **наследуется мультипликативно**
(parent 0.5 × child 0.5 → 0.25): layout вычисляет effectiveOpacity,
renderer модулирует альфа-канал цвета.

---

## 6. Input

Централизованный dispatcher (один на context), **не** per-node MTA handlers.

    MTA events (bootstrap bridge)
      → Context.dispatcher
        → hit test (flat interactive list)
        → target
        → event dispatch (bubble)

Состояния: hovered, focused, pressed, captured.

Hit-test использует **плоский список интерактивных узлов** (derived cache,
перестраивается при DIRTY_INPUT и **немедленно при destroy** (ADR-005)).
Обычный прямоугольный узел — дешёвый AABB-тест.

### 6.1 Event model

target → bubble (вверх по parent). event:stopPropagation(),
event:preventDefault().

### 6.2 Focus

Единый focus manager на context (focusedNode). Используется Edit, keyboard,
modal, popup. Escape сбрасывает фокус (nil).

---

## 7. Layout

Подсистема layout вычисляет world-координаты из локальных описаний.
Инвалидируется при изменении position/size/parent/layoutMode.

Поддерживаемые режимы:
- absolute — x/y в пикселях;
- relative — x/y как доля 0..1 от родителя;
- anchor — 9 точек привязки;
- center — центрирование в родителе;
- stretch — растягивание по осям;
- autosize — размер по содержимому.

### 7.1 Design resolution

    DXUI.setDesignResolution(1920, 1080)

Реализовано (Stage 8): UI проектируется в design-пространстве; renderer
масштабирует примитивы (scale+offset при rebuild). Dispatcher
конвертирует экранные координаты в design (toLocal) — hit-test и события
согласованы.

---

## 8. Widget contract

Каждый виджет — отдельный файл widgets/<name>.lua. Контракт:

    local Widget = require("core.widget")
    local Button = Widget:extend("Button")
    Button.properties = {
        text  = { default = "", invalidates = { DIRTY.RENDER } },
        color = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER } },
    }
    function Button:render(renderer)
        renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    end

Новый виджет пишется **без изменения** core/kernel — только через
существующие интерфейсы.

### 8.1 Inheritance (Lua 5.1 prototype)

    Widget → Node
    Button → Widget

Простое prototype-наследование через setmetatable.

### 8.2 Composite widgets

Composite логически — один объект для пользователя. Внутри владеет
скрытыми child-узлами (frame, title bar, close button...).

---

## 9. Style / Theme

    DXUI.setTheme(theme)
    button.style = "primary"

Разрешение стиля (Stage 11):

1. **Build-time**: applyThemeDefaults при монтировании применяет
   theme[Class][style or "default"] к пустым свойствам.
2. **Runtime**: applyStyle(name) или node.style = name пересчитывает
   значения, но **не затирает** поля, явно установленные пользователем
   (_userSet guard, ADR-004).

Parent style inheritance и state-driven style chains (hover/pressed/focused
как first-class стили) — **не реализованы**; hover обрабатывается через
события mouseenter/mouseleave внутри виджета (dynamic hover color).

---

## 10. Resources

Единый Resource Manager (resources/manager.lua) кэширует textures/fonts.
Ownership — global: ресурсы живут до releaseResources (resource stop);
node destroy их не трогает.

---

## 11. Text engine

Подсистема (text/text.lua, Stage 8):
- **measurement** — измерение (кэш с ключом text+font+scale+wrap);
  вне MTA — monospace-оценка (fallback для тестов);
- **layout** — word-wrap, ellipsis, разбивка по \n;
- **rendering** — align/valign через параметры dxDrawText.

**Edit** (Stage 11): реализован multiline, vertical navigation с goal column,
drag-select, clipboard (внутренний + MTA bridge), курсор/выделение через
Text.measure для позиционирования.

---

## 12. Animation

Централизованный manager (animation/animation.lua): animate, easing
(linear/in/out), stop, isAnimating. Timeline chains (:after) —
не реализованы в текущем scope.

---

## 13. Файловая структура (фактическая)

    dxui-v2/
    ├── meta.xml
    ├── README.md
    ├── ARCHITECTURE.md
    ├── docs/adr/
    │   ├── 001-aos-public-nodes.md
    │   ├── 002-named-dirty-categories.md
    │   ├── 003-efflayer-collect-time.md
    │   ├── 004-style-ownership-guards.md
    │   ├── 005-immediate-interactive-rebuild.md
    │   └── 006-zindex-modal-reset.md
    ├── client/
    │   ├── init.lua
    │   ├── demo.lua
    │   ├── api/
    │   │   ├── ui.lua
    │   │   └── context.lua
    │   ├── core/
    │   │   ├── node.lua
    │   │   └── widget.lua
    │   ├── input/
    │   │   ├── dispatcher.lua
    │   │   ├── events.lua
    │   │   └── hit_test.lua
    │   ├── layout/
    │   │   └── layout.lua
    │   ├── render/
    │   │   ├── renderer.lua
    │   │   ├── render_list.lua
    │   │   ├── state.lua
    │   │   ├── effects.lua
    │   │   └── backend_mta.lua
    │   ├── resources/
    │   │   └── manager.lua
    │   ├── animation/
    │   │   ├── animation.lua
    │   │   └── easing.lua
    │   ├── style/
    │   │   └── theme.lua
    │   ├── text/
    │   │   └── text.lua
    │   ├── utils/
    │   │   └── color.lua
    │   └── widgets/
    │       ├── builders.lua
    │       ├── button.lua
    │       ├── checkbox.lua
    │       ├── combobox.lua
    │       ├── contextmenu.lua
    │       ├── edit.lua
    │       ├── gridlist.lua
    │       ├── image.lua
    │       ├── label.lua
    │       ├── panel.lua
    │       ├── popup.lua
    │       ├── progressbar.lua
    │       ├── radiobutton.lua
    │       ├── scrollpanel.lua
    │       ├── slider.lua
    │       ├── tabpanel.lua
    │       ├── toggle.lua
    │       ├── tooltip.lua
    │       └── window.lua
    └── tests/
        ├── run.py
        ├── loader.lua
        ├── test_core.lua
        ├── test_input.lua
        ├── test_layout.lua
        ├── test_render.lua
        ├── test_widgets.lua
        ├── test_advanced.lua
        ├── test_stage7b.lua
        ├── test_stage8.lua
        ├── test_stage9.lua
        ├── test_stage10.lua
        ├── test_stage11.lua
        └── test_stage12.lua

---

## 14. Что переносим / redesign / удаляем

### Переносим (поведение + решения)
- dirty-инвалидация (с читаемыми именами);
- zero-work idle;
- централизованный input dispatcher;
- плоский interactive list для hit-test;
- bubble event model (+ stopPropagation/preventDefault);
- data-driven анимация (единый tick);
- composite-концепция;
- layer-архитектура;
- modal focus lock / input trap;
- popup dismiss-on-outside-click.

### Redesign
- Node: SoA+slot+id → читаемый объект (AoS) + изолированный runtime;
- property system: добавлен property-style, единый mutation layer;
- widget: один файл на виджет, контракт;
- text: measurement/layout/render + font API + cache;
- style/theme: build-time defaults + runtime applyStyle с ownership guards;
- multi-context: createContext();
- layout: anchor/center/stretch/autosize + design resolution;
- opacity: 0..1 float;
- color: string/number/table на уровне свойства.

### Удаляем
- 10+ makeXxxMt фабрик → единый механизм наследования;
- повторяющиеся destroy-override → lifecycle-контракт;
- packed margin/padding bit-math → обычные поля.

---

## 15. Performance target

Архитектура рассчитана на **100–1000+ узлов** без деградации по очевидным
причинам. Приоритеты (по порядку): readability → API quality → extensibility
→ predictable runtime → CPU → memory → GPU.

Idle-кадр = zero work: ни layout, ни render-list, ни hit-test не
пересчитываются без инвалидации.

---

## 16. Review gate (Stage 6 → 7)

После core + renderer + input + layout + базовых виджетов — остановка и
проверка: понятен ли Node, API, lifecycle, rendering, добавление виджета,
читаем ли код. Только после прохождения — advanced widgets.
