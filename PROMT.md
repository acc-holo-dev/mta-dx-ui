# DXUI V3 — MASTER REWRITE PROMPT

## MTA:SA / Lua 5.1 / DirectX 9

# 0. ТВОЯ РОЛЬ

Ты — Principal Software Architect + Senior Lua 5.1 + MTA:SA + DX9 engineer + UI framework architect + performance engineer.

Ты работаешь с существующим проектом:

`github.com/acc-holo-dev/mta-dx-ui`

Твоя задача — не «починить V2».

Твоя задача:

# СОЗДАТЬ DXUI V3 КАК ЦЕЛОСТНЫЙ PRODUCTION-ORIENTED UI ENGINE

с максимально понятным кодом, сильной архитектурой, хорошим API и высокой практической производительностью.

---

# 1. ЖЁСТКИЙ ПОРЯДОК РАБОТЫ

Работать строго в этом порядке:

```text
1. Анализ legacy
2. Проектирование структуры V3
3. Создание структуры файлов
4. Проектирование внутренних контрактов
5. Реализация core
6. Реализация rendering/input/layout/theme
7. Реализация basic widgets
8. Реализация composite widgets
9. Интеграция и полировка
10. Проверка работоспособности
11. Tests / load / performance / diagnostics
12. Documentation / examples / ADR / README
```

## КРИТИЧЕСКОЕ ПРАВИЛО

Пункты 11–12 **не должны отнимать основной рабочий цикл до завершения кода**.

Не начинай писать:

* полноценные tests;
* benchmark suite;
* README;
* examples;
* ADR;
* большие architecture documents;

пока основная V3 implementation не собрана.

Исключение:

`ARCHITECTURE.md`/архитектурная заметка допускается только в минимальном объёме, необходимом для фиксации спорных решений.

---

# 2. SUB-AGENTS

Если среда поддерживает sub-agents/parallel agents:

# ИСПОЛЬЗУЙ ИХ АКТИВНО.

Не дублируй работу одного агента несколькими помощниками бессмысленно.

Разделяй независимые задачи.

Примеры:

```text
Agent A → полный audit legacy
Agent B → MTA/DX9/API research
Agent C → текущий render pipeline analysis
Agent D → theme/style/DGS analysis
Agent E → API/Developer Experience analysis
Agent F → performance bottlenecks
Agent G → предложенный V3 architecture review
```

Главный агент:

* объединяет результаты;
* устраняет противоречия;
* принимает финальные решения;
* определяет source of truth;
* пишет код.

Sub-agent не имеет права самостоятельно определять окончательную архитектуру проекта.

После получения результатов:

```text
collect
→ compare
→ challenge
→ decide
```

---

# 3. FIRST STEP — LEGACY AUDIT

До написания кода изучить весь repository.

Обязательно проверить:

* source;
* widgets;
* core;
* render;
* input;
* layout;
* animation;
* style;
* text;
* resources;
* configuration;
* exports;
* meta.xml;
* examples;
* tests;
* documentation;
* benchmarks;
* legacy workarounds.

Построить:

```text
module
responsibility
dependencies
public API
internal API
hot path
cold path
state
ownership
problems
keep
rewrite
merge
remove
replace
```

Не доверять README слепо.

Source code + проверенное MTA behavior = source of truth.

---

# 4. DGS

Изучить DGS только как functional/style reference.

Особенно:

* theme/style;
* state styling;
* resource-specific styles;
* textures/materials;
* fonts;
* Window;
* CloseButton;
* widget appearance;
* configuration.

НЕ копировать:

* code;
* internal architecture;
* naming;
* hacks.

Использовать только лучшие идеи.

---

# 5. НЕ ДЕЛАЙ MECHANICAL REWRITE

Запрещено:

```text
V2
→ переименовать файлы
→ заменить несколько таблиц
→ перенести код
→ назвать это V3
```

V3 должна переосмыслить:

* Node;
* Widget;
* Parts;
* Theme;
* Layout;
* Input;
* Render;
* Resources;
* Lifecycle;
* Ownership;
* API.

---

# 6. MAIN PRODUCT PHILOSOPHY

# POWERFUL INSIDE.

# OBVIOUS OUTSIDE.

Программист должен думать о:

```text
UI
Node
Widget
Part
Theme
Layout
Event
Animation
Resource
```

а не о:

```text
slot
dirty mask
render command index
batch key
storage column
```

---

# 7. PRIORITIES

В порядке важности:

1. Readability
2. API quality
3. Developer Experience
4. Extensibility
5. Predictability
6. Performance
7. Memory efficiency
8. GPU efficiency

Performance всё равно обязательна.

Не делать readable, но очевидно медленную архитектуру.

---

# 8. PUBLIC ENTRY POINT

Пользователь получает DXUI:

```lua
local ui = exports.dxui:getUI()
```

один раз при инициализации ресурса.

Не вызывать exports в `onClientRender` и других hot paths.

Пользователь не должен знать о Context.

---

# 9. GLOBAL RUNTIME / RESOURCE OWNERSHIP

Runtime:

```text
one global DXUI
```

Ownership:

```text
Resource A → свои nodes
Resource B → свои nodes
Resource C → свои nodes
```

Resource не может произвольно уничтожать чужие UI objects.

При остановке resource:

* его nodes;
* listeners;
* animations;
* owned resources

корректно освобождаются.

---

# 10. NODE MODEL

Node должен выглядеть как обычный Lua object.

Разрешить:

```lua
button.x = 100
button.visible = true
button.color.r = 255
```

и:

```lua
button:setPosition(100, 100)
button:setVisible(true)
button:setColor(...)
```

Это обязательная философия API.

Оба пути используют одну mutation/invalidation system.

---

# 11. VALUE OBJECTS

Поддерживать понятные значения:

```lua
button.color.r
button.color.g

button.position.x
button.position.y

button.size.width
button.size.height
```

при сохранении коротких aliases:

```lua
button.x
button.y
button.width
button.height
```

если это не создаёт чрезмерную сложность.

---

# 12. USER DATA

Node должен поддерживать:

```lua
node.userData = ...
```

без вмешательства framework.

---

# 13. CHILDREN / PARENT

Поддерживать:

```lua
window.children
button.parent = window
```

и соответствующие methods.

Поддерживать оба способа создания:

```lua
window:addChild(button)
```

```lua
window:button(...)
```

если это остаётся понятным.

---

# 14. COMPOSITE WIDGETS

Built-in composite widgets должны использовать реальные Nodes/Widgets там, где это разумно.

Например:

```text
Window
├── Header
│   ├── DragArea
│   ├── Icon
│   ├── Title
│   └── CloseButton
└── Content
```

Parts должны быть доступны:

```lua
window.header
window.header.dragArea
window.header.title
window.header.closeButton
window.content
```

---

# 15. PARTS

Part — настоящий Node/Widget, если он имеет:

* собственную visual state;
* layout;
* input;
* customization;
* replacement value.

Не создавать бессмысленные internal nodes.

---

# 16. PART REPLACEMENT

Разрешить:

```lua
window.closeButton = customButton
```

и:

```lua
window.closeButton.icon = ui.texture(...)
```

.

Ownership replacement должен быть deterministic.

Если part принадлежал Window:

```text
detach
→ destroy according to ownership
→ attach replacement
```

---

# 17. USER CUSTOM CHILDREN

Пользователь должен иметь возможность добавлять собственные children в разрешённые контейнеры:

```lua
window.content:addChild(...)
```

---

# 18. WIDGET ARCHITECTURE

Предпочтение:

```text
BaseNode
   ↓
BaseWidget
   ↓
Widget
```

с понятным Lua metatable/prototype подходом.

Не создавать сложную OO framework.

Новый widget должен быть возможен без изменения kernel.

---

# 19. WIDGET FILES

Каждый существенный widget должен иметь отдельный файл.

Например:

```text
widgets/
    panel.lua
    label.lua
    button.lua
    image.lua
    window.lua
    checkbox.lua
    slider.lua
    edit.lua
    scrollpanel.lua
    ...
```

Не повторять гигантский `ui.lua`.

---

# 20. WIDGET SOURCE RULE

Открыв:

```text
widgets/button.lua
```

разработчик должен быстро понять:

* state;
* properties;
* events;
* parts;
* behavior;
* lifecycle.

Widget не должен требовать чтения renderer internals для понимания basic behavior.

---

# 21. RENDERER

Renderer централизованный.

Widget не должен самостоятельно управлять global DX state.

Renderer отвечает за:

* rendering;
* state;
* batching;
* ordering;
* culling;
* MTA DX interaction.

---

# 22. RENDER REPRESENTATION

Исследовать:

```text
direct rendering
render items
render commands
persistent render list
hybrid
```

.

Выбрать то, что лучше для MTA/Lua target workload.

Не принимать решение заранее ради идеологии.

---

# 23. BATCHING / STATE CACHE

Batching и state caching являются internal optimizations.

Разрешены:

* texture cache;
* shader cache;
* blend state cache;
* render target cache;
* render ordering;
* batching.

Но не делать сложность видимой public API.

---

# 24. INTERNAL OPTIMIZATION

Разрешены:

* arrays;
* packed data;
* SoA;
* AoS;
* hybrid;
* free lists;
* pools;
* numeric IDs;
* bitmasks.

Но public Node model должен оставаться readable.

Оптимизация должна быть изолированной и иметь реальное назначение.

---

# 25. DIRTY SYSTEM

Не фиксировать заранее:

> только bool

или:

> только bitmask.

Выбрать наиболее понятную и достаточно быструю модель.

Разделять при необходимости:

```text
layout
style
render
input
content
```

.

Не выполнять full-tree work при локальном изменении.

---

# 26. ZERO-WORK IDLE

Если UI не меняется:

не выполнять без причины:

* полный layout;
* полный style resolve;
* full render rebuild;
* full hit-test rebuild;
* text measurement;
* expensive resource operations.

---

# 27. SOURCE OF TRUTH

Для каждого значения должна быть одна canonical source.

Derived/cache state должен иметь:

```text
source
cache
invalidation
rebuild
```

---

# 28. LAYOUT

Поддержать классические модели:

* absolute;
* relative;
* anchor;
* center;
* stretch;
* margin;
* padding;
* auto;
* fill.

И flex-like возможности:

* row;
* column;
* gap;
* align;
* justify;
* grow;
* shrink;
* wrap.

---

# 29. HUMAN-READABLE DIMENSIONS

Поддержать понятный API:

```lua
width = 300
width = ui.percent(50)
width = ui.auto()
width = ui.fill()
```

Также можно:

```lua
width = "50%"
```

если parsing выполняется только в cold path и compiled representation используется дальше.

---

# 30. AUTOMATIC RELAYOUT

Layout должен автоматически инвалидироваться после:

* child create;
* child destroy;
* resize;
* parent resize;
* text changes;
* font changes;
* padding/margin changes;
* layout changes.

Не требовать ручной `relayout()` в обычном use case.

---

# 31. SCREEN / DESIGN RESOLUTION

Поддерживать:

* pixels;
* design resolution;
* relative dimensions;
* aspect ratio;
* scaling.

Не заставлять programmer вручную пересчитывать UI под каждое разрешение.

---

# 32. SUPERSAMPLING

Не считать:

> 2x render + downsample

автоматически правильным решением.

Исследовать и при необходимости сделать configurable quality strategy.

---

# 33. TRANSFORM

Если поддерживается:

```text
x
y
scaleX
scaleY
rotation
rotationOrigin
```

то transform должен корректно работать с:

* rendering;
* children;
* input;
* clipping;
* animation;
* layout.

Не оставлять half-working transform.

---

# 34. OPACITY

Любой visual node должен поддерживать opacity.

Не использовать RT только ради обычной opacity, если существует более дешёвый путь.

---

# 35. CLIPPING

Обычный clipping:

# CHEAP RECTANGLE PATH

Advanced:

# MASK PATH

Не строить обычный UI вокруг render targets.

---

# 36. VISUAL CAPABILITIES

Visual features — отдельные capabilities:

* background;
* texture;
* radius;
* border;
* outline;
* mask;
* opacity;
* icon;
* shadow/effect hooks.

Не заставлять каждый widget наследовать весь список.

---

# 37. BLUR

Blur не входит в текущий implementation scope.

Архитектура должна позволять добавить его позже.

---

# 38. TEXT

Text subsystem должна отдельно отвечать за:

* measurement;
* layout;
* rendering;
* caching.

Поддержать:

* multiline;
* wrapping;
* alignment;
* color coding;
* custom fonts;
* autosize;
* clipping;
* ellipsis;
* selection/caret foundation.

---

# 39. INPUT

Central dispatcher.

Не:

```text
one MTA handler per node
```

.

Pipeline:

```text
MTA input
→ DXUI input
→ hit test
→ target
→ event propagation
```

---

# 40. POINTER CAPTURE

Обязательно поддерживать:

```text
mouse down
→ capture
→ movement outside node
→ target still receives movement
→ mouse up
→ release
```

---

# 41. EVENTS

Поддерживать понятный event API:

```lua
button:on("click", function(event)
    ...
end)
```

Event должен иметь полезные данные.

Поддерживать нужные механизмы:

```text
capture
target
bubble
stopPropagation
preventDefault
consume
```

но без browser-DOM монстра.

---

# 42. FOCUS

Central focus system.

Поддерживать:

```text
hovered
focused
pressed
captured
active
```

и keyboard navigation.

---

# 43. EDIT

Architecture должна позволять:

* selection;
* clipboard;
* cursor;
* keyboard;
* multiline;
* placeholder;
* caret;
* readonly;
* max chars;
* focus;
* scrolling.

---

# 44. ANIMATION

Central animation manager.

Не:

* timer per animation;
* coroutine per animation;
* MTA handler per animation.

Поддерживать:

```text
animateTo
properties
timeline
sequence
callback
pause
resume
cancel
chaining
easing
spring/bounce
```

---

# 45. THEME — CENTRAL FEATURE

Theme не является просто:

```text
background
textColor
```

.

Theme управляет:

* colors;
* fonts;
* dimensions;
* spacing;
* radii;
* textures;
* icons;
* states;
* transitions;
* widget parts.

---

# 46. THEME FORMAT

Theme — portable JSON package:

```text
theme/
    theme.json
    textures/
    fonts/
    icons/
```

Theme должна быть возможна как отдельный portable package/resource.

---

# 47. ENGINE SETTINGS

Engine settings — отдельно:

```text
source/client/settings.lua
```

Settings отвечает за:

* engine behavior;
* scaling;
* design resolution;
* render quality;
* defaults;
* error behavior;
* animation defaults;
* resource policy.

Theme отвечает за appearance.

Не смешивать.

---

# 48. THEME TOKENS

Theme должна иметь reusable tokens:

```text
colors
fonts
spacing
sizes
radii
durations
```

и references между ними.

Token resolution выполнять в cold/configuration path.

---

# 49. COMPONENT THEME

Theme structure:

```text
components/
    window
    panel
    button
    label
    image
    checkbox
    radiobutton
    progressbar
    slider
    combobox
    edit
    scrollpanel
    tabpanel
    gridlist
    popup
    contextmenu
    tooltip
```

---

# 50. STATE THEME

States:

```text
normal
hover
pressed
focused
selected
disabled
```

Theme может задавать каждому состоянию:

* background;
* texture;
* color;
* font;
* dimensions;
* outline;
* icon;
* transition.

---

# 51. TRANSITIONS IN THEME

Theme может задавать transition:

```text
duration
easing
```

или явно запрещать transition.

Если transition не указана:

state change может быть instant.

---

# 52. EXPLICIT ANIMATION PRIORITY

Если programmer вызывает:

```lua
button:animate(...)
```

explicit animation имеет приоритет над automatic theme transition.

---

# 53. THEME FALLBACK

Приоритет должен быть deterministic.

Концептуально:

```text
engine defaults
→ global theme
→ resource theme
→ component theme
→ part theme
→ state theme
→ instance override
→ explicit runtime override
```

Необязательные значения наследуются.

---

# 54. SPARSE OVERRIDES

Если programmer меняет:

```lua
button.background = customTexture
```

меняется только background.

Не копировать и не уничтожать всю theme configuration.

---

# 55. LIVE THEME SWITCH

```lua
ui:setTheme(...)
```

должен менять существующий UI.

Не только новые nodes.

Theme switching должен:

```text
load
validate
compile
activate
invalidate affected UI
```

---

# 56. LOCAL PLAYER THEMES

Игрок должен иметь возможность:

* выбрать theme;
* изменить preferences;
* сохранить local settings;
* загрузить их при входе;
* применить theme ко всему DXUI.

Malformed local data:

```text
warning
→ fallback
```

а не crash.

---

# 57. RESOURCE-SPECIFIC THEMES

Поддержать:

```text
global user theme
+
resource theme
+
instance overrides
```

.

Resource A может иметь свой визуальный identity.

---

# 58. THEME FONTS

Theme должна поддерживать custom fonts.

Например:

```json
{
    "fonts": {
        "body": "...",
        "title": "...",
        "mono": "..."
    }
}
```

Font resources должны кэшироваться.

---

# 59. THEME ASSET OWNERSHIP

При смене theme:

* obsolete assets release;
* active assets remain;
* shared resources reuse.

Не держать бесконечно старые themes в памяти.

---

# 60. PART THEMING

Например Window:

```text
Window
├── Header
│   ├── DragArea
│   ├── Icon
│   ├── Title
│   └── CloseButton
└── Content
```

Theme может изменять:

```text
header background
header height
title font
title color
close icon
close button states
content padding
window background
radius
outline
```

То же самое применять к:

* Checkbox;
* Edit;
* Scrollbar;
* ComboBox;
* TabPanel;
* GridList;
* etc.

---

# 61. THEME VS STRUCTURE

Обычная Theme изменяет appearance/configuration.

Она не должна произвольно ломать widget tree.

Если позже понадобится structural skinning:

сделать отдельной capability.

---

# 62. REPOSITORY STRUCTURE

Главная структура:

```text
.
├── source/
│   └── client/
│       ├── api/
│       ├── core/
│       ├── input/
│       ├── layout/
│       ├── render/
│       ├── resources/
│       ├── style/
│       ├── text/
│       ├── animation/
│       ├── widgets/
│       ├── settings.lua
│       └── init.lua
│
├── readme/
│   ├── ai/
│   ├── documents/
│   ├── examples/
│   └── tests/
│
├── meta.xml
└── README.md
```

Разрешается изменить структуру только после аргументированного architecture decision.

---

# 63. REPOSITORY CLEANLINESS

Root должен выглядеть как готовый продукт.

Не держать там:

* roadmap;
* release notes;
* random reports;
* agent scratch files;
* migration junk;
* temporary benchmarks.

AI-specific material → `readme/ai/`.

Human docs → `readme/documents/`.

Examples → `readme/examples/`.

Tests → `readme/tests/`.

---

# 64. IMPLEMENTATION FIRST

После создания structure и contracts:

# ПИСАТЬ КОД.

Не тратить бесконечные ответы на переписывание документации вместо implementation.

---

# 65. REQUIRED CORE ORDER

Реализовать:

```text
1. Runtime
2. Node
3. lifecycle
4. ownership
5. tree
6. properties
7. value objects
8. style foundation
9. layout foundation
10. renderer
11. input
12. parts
13. basic widgets
14. composite widgets
```

---

# 66. BASIC WIDGETS

Сначала:

```text
Panel
Label
Button
Image
Window
```

После стабильного foundation:

```text
Checkbox
RadioButton
ProgressBar
Slider
ScrollPanel
Edit
ComboBox
TabPanel
GridList
Popup
ContextMenu
Modal
Tooltip
```

---

# 67. PERFORMANCE REQUIREMENT

Target workload:

```text
50
100–300
500–1000
1000+
```

.

Не проектировать только под «несколько кнопок».

Но не жертвовать читаемостью ради hypothetical 100000 nodes.

---

# 68. PERFORMANCE ANALYSIS

Для спорных решений анализировать:

```text
Lua VM cost
CPU cost
native MTA cost
GPU cost
memory
allocations
GC
```

.

---

# 69. PERFORMANCE CLAIMS

Разделять:

```text
hypothesis
expected
measured
```

.

Не говорить:

```text
10x faster
zero allocation
zero overhead
```

без evidence.

---

# 70. MTA-SPECIFIC RULE

Перед важной DX9/MTA архитектурой проверить реальный behavior:

* dxDraw;
* textures;
* fonts;
* shaders;
* render targets;
* blend;
* screen;
* client file API;
* resource lifecycle;
* exports.

Не переносить desktop/game-engine assumptions автоматически.

---

# 71. ERROR HANDLING

Development:

```text
clear errors
warnings
validation
```

Production:

```text
predictable
low overhead
safe
```

Destroyed objects не должны приводить к hidden corruption.

---

# 72. NO GIANT MANAGER

Не создавать один manager для:

```text
nodes
render
input
layout
theme
resources
animation
```

.

---

# 73. NO MICRO-MODULE HELL

Не дробить код на бессмысленные tiny modules.

Каждый модуль должен иметь понятную ответственность.

---

# 74. NO MAGIC

Избегать:

* magic numbers;
* mysterious flags;
* hidden ownership;
* implicit destruction;
* undocumented state transitions.

---

# 75. COMMENTS

Комментарии объясняют:

```text
what
why
```

.

Никаких:

```text
M1
M20
§42
ADR-19
```

в implementation code.

---

# 76. DOCUMENTATION TIMING

До завершения implementation писать только то, что необходимо агенту для принятия решений.

После завершения основной V3:

создать/актуализировать:

```text
README.md
readme/documents/
readme/examples/
readme/ai/
```

---

# 77. TEST TIMING

Полный test resource делать ПОСЛЕ основной V3 implementation.

Test resource должен запускаться как отдельный MTA resource и проверять:

* lifecycle;
* ownership;
* nodes;
* layout;
* input;
* rendering behavior;
* themes;
* resources;
* widgets;
* performance;
* load;
* delays;
* memory observations.

---

# 78. FINAL VERIFICATION

После implementation:

```text
code
→ integration
→ runtime verification
→ tests
→ performance
→ cleanup
→ docs
→ examples
```

---

# 79. FIRST RESPONSE FORMAT

Первый ответ после получения prompt:

```text
# DXUI V3 AUDIT

# CURRENT REPOSITORY MAP

# CURRENT ARCHITECTURE

# CURRENT DATA FLOW

# CURRENT RENDER FLOW

# CURRENT INPUT FLOW

# CURRENT RESOURCE OWNERSHIP

# CURRENT THEME SYSTEM

# CURRENT WIDGET COMPOSITION

# CURRENT API

# CURRENT PERFORMANCE RISKS

# CURRENT READABILITY RISKS

# CURRENT ARCHITECTURAL DEBT

# KEEP

# REWRITE

# REMOVE

# MERGE

# REPLACE

# V3 ARCHITECTURE

# V3 FILE TREE

# IMPLEMENTATION ORDER
```

НЕ писать полноценный V3 code на первом ответе.

---

# 80. SECOND RESPONSE

После audit:

создать физическую структуру V3.

Сначала:

```text
source/
readme/ai/
readme/documents/
readme/examples/
readme/tests/
meta.xml
README.md
```

Но не заполнять документацию/примеры/тесты полностью.

Сначала создать и подготовить code architecture.

---

# 81. THIRD RESPONSE

Затем:

# BEGIN IMPLEMENTATION

Не возвращаться постоянно к архитектуре без серьёзной причины.

Если обнаружена фундаментальная ошибка:

```text
stop
state problem
show alternatives
choose
fix
continue
```

---

# 82. SELF-REVIEW AFTER EACH MAJOR PHASE

Проверить:

```text
readability
API
ownership
lifecycle
performance
memory
coupling
extensibility
```

Если код становится хуже для понимания:

упростить.

Если упрощение создаёт серьёзный runtime degradation:

локализовать optimization.

---

# 83. ARCHITECTURE CHANGE RULE

Не менять фундаментальное решение молча.

Каждое существенное изменение:

```text
Old decision
Problem discovered
New decision
Why
Impact
```

Коротко.

---

# 84. FINAL API TARGET

Должно быть естественно написать:

```lua
local ui = exports.dxui:getUI()

local window = ui.window({
    x = 100,
    y = 100,
    width = ui.percent(60),
    height = ui.percent(70),
})

window.header.background = ui.texture("header.png")

window.header.closeButton.icon =
    ui.texture("close.png")

local button = window.content:button({
    text = "Hello"
})

button.color.r = 255
button.visible = true

button:on("click", function(event)
    window:hide()
end)
```

И программист должен понимать этот код без изучения внутреннего engine.

---

# 85. FINAL QUALITY BAR

DXUI V3 должна выглядеть как:

# СЕРЬЁЗНЫЙ СПЕЦИАЛИЗИРОВАННЫЙ UI ENGINE ДЛЯ MTA:SA

а не:

* AI prototype;
* огромный legacy dump;
* DGS clone;
* набор несвязанных widgets;
* low-level rendering framework, случайно написанный на Lua.

---

# 86. THE FINAL RULE

# НЕ ПИШИ КОД РАДИ КОЛИЧЕСТВА КОДА.

Но после завершения architecture:

# НЕ ПРЕВРАЩАЙ ПРОЕКТ В БЕСКОНЕЧНЫЙ AUDIT.

Проект должен двигаться вперёд:

```text
UNDERSTAND
→ DECIDE
→ STRUCTURE
→ IMPLEMENT
→ INTEGRATE
→ VERIFY
→ DOCUMENT
```

Именно в таком порядке.

# GOAL:

## READABLE OUTSIDE.

## ENGINEERED INSIDE.

## FAST ENOUGH TO MATTER.

## SIMPLE ENOUGH TO EXTEND.

## CLEAN ENOUGH TO TRUST.
