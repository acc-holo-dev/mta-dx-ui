# DXUI V2 — Architecture

> **Принцип:** SIMPLE OUTSIDE, ENGINEERED INSIDE.
> Публичный API — обычный объектный Lua. Внутри — контролируемые оптимизации,
> изолированные от пользователя.

Этот документ — результат Stage 0 (аудит legacy) и Stage 1 (архитектурный
redesign). Legacy (`client/`, `docs/adr/`, `tests/`) остаётся reference
implementation: его **поведение** сохраняем, **реализацию** — нет.

---

## 1. Почему redesign, а не rewrite

Legacy достиг функциональной полноты (M20, 357 тестов), но его архитектура
оптимизирована под внутреннее представление данных, а не под человека:

| Проблема legacy | Следствие |
|---|---|
| SoA + slot + id-индирекция | виджеты читают `s.worldX[slot]`, `s.w[slot]` — автор виджета обязан знать SoA |
| Нет property-style API | только `setPosition(...)`, нет `button.x = 100` |
| `ui.lua` = 2929 строк | все 16 виджетов в одном файле |
| Состояние composite на handle (`_parts`, `_win`, `_sp`, `_ed`, `_tg`, `_pb`, `_sl`, `_cb`, `_tabs`, `_grid`) | параллельная система состояния вне Storage, ручной cleanup в каждом destroy |
| 10+ почти одинаковых `makeXxxMt` | дублирование метатабличной логики |
| Нет text engine / font API / style / resource manager / multi-context | функциональные дыры |

V2 решает эти проблемы, **не** выбрасывая то, что legacy сделал правильно:
dirty-инвалидацию, zero-work idle, централизованный input, data-driven
анимацию, RT-clip, composite-концепцию, layer-архитектуру.

---

## 2. Слои

```
PUBLIC API          (ui.*, node.*, context.*)
    ↓
UI OBJECTS          (Node, Widget, composite)
    ↓
UI RUNTIME          (Context: layout / input / render / style / resources)
    ↓
MTA DX              (backend_mta)
```

Зависимости идут только вниз. Core не знает о конкретных виджетах.
Renderer не знает о внутреннем состоянии сложных виджетов.

---

## 3. Node — публичный объект (AoS)

Node — **обычная Lua-таблица**, которую держит пользователь. Это source of
truth состояния узла. Никаких slot/id/SoA в публичном представлении.

```lua
node = {
    id        = <number>,      -- стабильный id (для отладки/событий), не доминирует
    x = 0, y = 0,
    width = 0, height = 0,
    visible = true,
    enabled = true,
    opacity = 1,               -- 0..1 (float), НЕ 0..255
    parent = nil,
    children = {},             -- массив прямых детей
    zIndex = 0,
    layer = <LAYER_BASE>,
    style = nil,               -- имя стиля или таблица
    userData = nil,            -- произвольные данные пользователя
}
```

### 3.1 Property system (единый mutation layer)

Метатаблица Node перехватывает запись через `__newindex` и чтение через
`__index`. **Оба стиля** — property и method — сходятся в один внутренний
слой `node:_set(prop, value)`:

```lua
button.x = 100            -- __newindex -> _set("x", 100)
button:setPosition(100, 0) -- метод -> _set("x", 100) + _set("y", 0)
```

`_set` делает ровно три вещи:
1. валидация значения (в dev-режиме);
2. запись в поле;
3. инвалидация ровно тех подсистем, которые зависят от свойства.

Свойства объявляются **декларативно** (см. §8 Widget contract), поэтому
`_set` не содержит гигантского `if/elseif` — таблица свойств генерирует
getter/setter/invalidation один раз при определении виджета.

### 3.2 Invalidation (читаемые категории)

Вместо `0x091` — именованные категории. Внутри допустим bitmask, но наружу
он никогда не выходит:

```lua
DIRTY_LAYOUT      -- позиция/размер/родитель/якорь/margin/padding
DIRTY_RENDER      -- цвет/текст/текстура/opacity/геометрия
DIRTY_INPUT       -- hit-геометрия/видимость/enabled/z-order
DIRTY_STYLE       -- разрешение стиля
DIRTY_CHILDREN    -- состав детей
DIRTY_VISIBILITY  -- видимость/culling
```

Каждое свойство знает, какие категории оно инвалидирует (объявлено в его
описании). Изменение `x` → `DIRTY_LAYOUT`; изменение `color` → `DIRTY_RENDER`;
изменение `visible` → `DIRTY_VISIBILITY + DIRTY_INPUT + DIRTY_RENDER`.

### 3.3 Lifecycle (явный)

```
created → mounted → updated → hidden → detached → destroyed
```

- **created** — `ui.panel(...)` / `context:create(...)`.
- **mounted** — узел (или его предок) прикреплён к корню контекста.
- **updated** — изменение свойства (через `_set`).
- **hidden** — `visible = false` (узел жив, не рисуется, не хитается).
- **detached** — `parent = nil` (узел жив, вне дерева).
- **destroyed** — `node:destroy()`; рекурсивно сносит детей, снимает
  подписки, освобождает node-owned ресурсы, отменяет анимации.

Ownership: **родитель владеет детьми**. Destroy родителя уничтожает поддерево.
События/ресурсы/анимации узла освобождаются в destroy.

---

## 4. Context

```lua
local hud  = ui.createContext()
local menu = ui.createContext()
```

Каждый context владеет:
- своим корнем (root node);
- своим focus manager;
- своими layers;
- своим lifecycle (beginFrame/render/endFrame).

Глобальный coordinator (один на ресурс) владеет:
- размером экрана / design resolution;
- глобальным input bridge (MTA-события → контексты);
- frame lifecycle (onClientRender);
- общим resource manager.

Контексты изолированы: фокус/слои/дерево одного не влияют на другой.

---

## 5. Rendering

### 5.1 Модель: flat render list (derived cache)

Рендер **не** обходит дерево каждый кадр. Runtime держит **плоский список
render items** — производный кэш, который:

- **перестраивается** при структурной инвалидации (состав детей, видимость,
  z-order, layer, parent);
- **обновляет отдельные записи** при визуальной инвалидации (цвет/текст/
  текстура/opacity/геометрия);
- **не трогается** в idle-кадре (zero work).

```lua
renderItem = {
    node = <node>,          -- обратная ссылка (для отладки/освобождения)
    kind = "rect"|"image"|"text",
    x, y, w, h,
    color, texture, text,
    layer, zIndex,
    clip = <clip region or nil>,
    opacity,
}
```

### 5.2 Pipeline кадра

```
beginFrame
  → update animations        (только активные)
  → process scheduled actions (только отложенные)
  → resolve invalidated layout
  → resolve invalidated style
  → rebuild/update render list (только dirty)
  → sort (только если orderDirty)
  → draw (flat list, batched state)
endFrame
```

Каждый этап **conditional**: если ничего не изменилось, этап пропускается.

### 5.3 Ordering + batching

Сортировка по `(layer, zIndex, kind)` — только при `orderDirty`. Batching по
дорогим state-переходам (texture, blend, RT) — внутренняя оптимизация,
невидимая пользователю. State cache дедуплицирует redundant state changes.

### 5.4 Clipping: cheap vs expensive path

- **Cheap path** — обычный узел без clip: рисуется напрямую.
- **Expensive path** — clip/mask: RT-стек (как legacy RTManager), только для
  узлов, которым это реально нужно.

Mask — отдельный rendering path, не входит в fast path.

### 5.5 Opacity

`opacity` — float 0..1. Дешёвый путь — модуляция альфа-канала цвета.
RT используется только когда opacity требует композиции поддерева (редко).

---

## 6. Input

Централизованный dispatcher (один на context), **не** per-node MTA handlers.

```
MTA events (bootstrap bridge)
  → Context.dispatcher
    → hit test (flat interactive list)
    → target
    → event dispatch (bubble)
```

Состояния: `hovered`, `focused`, `pressed`, `captured`, `active`, `disabled`.

Hit-test использует **плоский список интерактивных узлов** (derived cache,
перестраивается при `DIRTY_INPUT`). Обычный прямоугольный узел — дешёвый
AABB-тест; сложная геометрия — отдельный path.

### 6.1 Event model

`target → bubble` (вверх по parent). `event:stopPropagation()`,
`event:preventDefault()`. Capture-фаза — только если понадобится для
drag/modal (не строим DOM-клон).

### 6.2 Focus

Единый focus manager на context (`focusedNode`). Используется Edit, keyboard,
modal, tab-navigation.

---

## 7. Layout

Подсистема layout вычисляет world-координаты из локальных описаний.
Инвалидируется при изменении position/size/parent/layoutMode/anchor/margin/
padding/content-size.

Поддерживаемые режимы:
- `absolute` — x/y в пикселях;
- `relative` — x/y как доля 0..1 от родителя;
- `anchor` — 9 точек привязки (TL/TC/TR/ML/MC/MR/BL/BC/BR);
- `center` — центрирование в родителе;
- `stretch` — растягивание по осям;
- `margin` / `padding`;
- `autosize` — размер по содержимому.

### 7.1 Design resolution

```lua
ui:setDesignResolution(1920, 1080)
```

Layout учитывает смену разрешения. Supersampling — **configurable**, не
обязательный (исследовать native vs 2x vs RT+downsample; см. ADR позже).

---

## 8. Widget contract

Каждый виджет — отдельный файл `widgets/<name>.lua`. Контракт:

```lua
local Widget = require("core.widget")

local Button = Widget:extend("Button")

Button.properties = {
    text  = { default = "", invalidates = { DIRTY_RENDER } },
    color = { default = "#FFFFFF", invalidates = { DIRTY_RENDER } },
    -- x/y/width/height/visible/... наследуются от Node
}

function Button:render(renderer)
    renderer:rect(self.x, self.y, self.width, self.height, self.color)
    if self.text ~= "" then
        renderer:text(self.text, self.x, self.y, self.width, self.height)
    end
end

function Button:onClick(fn) ... end
```

Новый виджет пишется **без изменения** core/kernel, storage, dispatcher —
только через существующие интерфейсы.

### 8.1 Inheritance (Lua 5.1 prototype)

```
Widget → Node
Button → Widget
```

Простое prototype-наследование через `setmetatable({}, {__index = Parent})`.
Без сложного OO-фреймворка.

### 8.2 Composite widgets

Composite логически — один объект для пользователя. Внутри владеет
скрытыми child-узлами (frame, title bar, close button, content...).

Для каждого composite определено отдельно:
- logical root;
- какие внутренние узлы существуют;
- какие скрыты от пользователя;
- как уничтожается;
- как распространяются события;
- parent/child semantics.

Внутренние узлы — обычные дети (destroy-каскад сносит их сам). Публичный
handle делегирует методы внутренним частям, но пользователь видит один объект.

---

## 9. Style / Theme

```lua
ui.setTheme(theme)
button.style = "primary"
```

Разрешение стиля (вычисляется при `DIRTY_STYLE`, **не** каждый кадр):

```
theme defaults → widget defaults → parent style → local style → state style
```

Control states — first-class: `normal`, `hover`, `pressed`, `focused`,
`selected`, `disabled`.

---

## 10. Resources

Единый Resource Manager управляет: textures, fonts, shaders, render targets.

```lua
local tex  = ui.texture("icons/inventory.png")  -- cached
local font = ui.font("Roboto", 12)              -- cached
```

Ownership:
- **global** — живёт весь ресурс;
- **shared** — refcount, освобождается при нуле ссылок;
- **node-owned** — освобождается в destroy узла.

Destroy корректно освобождает node-owned ресурсы.

---

## 11. Text engine

Самостоятельная подсистема, разделённая на:
- **measurement** — измерение текста (кэшируется);
- **layout** — multiline, wrapping, alignment, vertical alignment, ellipsis;
- **rendering** — вывод через backend.

Measurement cache инвалидируется при изменении text/font/scale/wrap/style.

---

## 12. Animation

Централизованный manager (один tick в beginFrame), **без** per-node таймеров.

```lua
button:animate({ x = 100, opacity = 0 }, 300)
```

Анимация изменяет **реальные свойства** через нормальный mutation layer
(`_set`), а не дублирующие значения. Поддержка: animateTo, property animation,
timeline, sequence, callback, pause/resume/cancel.

---

## 13. Файловая структура

```
dxui-v2/
├── meta.xml
├── README.md
├── ARCHITECTURE.md
├── client/
│   ├── init.lua
│   ├── api/
│   │   ├── ui.lua          -- createContext, setTheme, setDesignResolution, texture, font
│   │   └── context.lua     -- Context
│   ├── core/
│   │   ├── node.lua        -- Node (объект + property system + lifecycle)
│   │   ├── widget.lua      -- Widget base (extend, properties, render contract)
│   │   ├── tree.lua        -- parent/child, mount/detach
│   │   └── runtime.lua     -- frame loop, dirty processing
│   ├── layout/
│   │   ├── layout.lua
│   │   ├── anchors.lua
│   │   └── measurement.lua
│   ├── input/
│   │   ├── dispatcher.lua
│   │   ├── hit_test.lua
│   │   ├── focus.lua
│   │   └── events.lua
│   ├── render/
│   │   ├── renderer.lua    -- public renderer primitives (rect/text/image/line)
│   │   ├── render_list.lua -- flat render list (derived cache)
│   │   ├── state.lua       -- state cache (dedup)
│   │   └── backend_mta.lua
│   ├── resources/
│   │   ├── manager.lua
│   │   ├── fonts.lua
│   │   ├── textures.lua
│   │   └── shaders.lua
│   ├── animation/
│   │   ├── animation.lua
│   │   └── easing.lua
│   ├── style/
│   │   ├── theme.lua
│   │   └── style.lua
│   └── widgets/
│       ├── panel.lua
│       ├── label.lua
│       ├── button.lua
│       ├── image.lua
│       ├── window.lua
│       └── ... (scrollpanel, edit, checkbox, ... — Stage 7)
└── docs/
    └── adr/
```

---

## 14. Что переносим / redesign / удаляем

### Переносим (поведение + решения)
- dirty-инвалидация (с читаемыми именами);
- zero-work idle;
- централизованный input dispatcher;
- плоский interactive list для hit-test;
- bubble event model (+ stopPropagation/preventDefault);
- data-driven анимация (единый tick);
- RT-clip (cheap/expensive path);
- composite-концепция;
- layer-архитектура;
- modal focus lock / input trap;
- popup dismiss-on-outside-click.

### Redesign
- Node: SoA+slot+id → читаемый объект (AoS) + изолированный runtime;
- property system: добавить property-style, единый mutation layer;
- widget: один файл на виджет, контракт, без SoA reach-in;
- composite: `_parts`/`_win`/`_sp` → явная composite-абстракция;
- text: measurement/layout/render + font API + cache;
- style/theme: цепочка разрешения;
- resources: единый manager;
- multi-context: createContext();
- layout: anchor/center/stretch/autosize + design resolution;
- opacity: 0..1 float;
- color: string/number/table на уровне свойства.

### Удаляем
- 10+ `makeXxxMt` фабрик → единый механизм наследования;
- повторяющиеся destroy-override → lifecycle-контракт;
- packed margin/padding bit-math → обычные поля (или изолированно, если измерено);
- Lua-реализация bitor/bitand → читаемые категории (или изолированно);
- monospace-предположения текста (`EDIT_CHAR_W=7`, `#text*7+8`).

### Оставляем в legacy
- тесты (357) как behavior reference;
- benchmark harness;
- ADR как история решений (не обязательное чтение);
- debug/profiler как future expansion points.

---

## 15. Performance target

Архитектура рассчитана на **100–1000+ узлов** без деградации по очевидным
причинам. Приоритеты (по порядку): readability → API quality → extensibility
→ predictable runtime → CPU → memory → GPU.

Idle-кадр = zero work: ни layout, ни style, ни render-list, ни hit-test не
пересчитываются без инвалидации.

---

## 16. Review gate (Stage 6 → 7)

После core + renderer + input + layout + базовых виджетов — остановка и
проверка: понятен ли Node, API, lifecycle, rendering, добавление виджета,
читаем ли код. Только после прохождения — advanced widgets.
